/*
 *  DSTPersistentObject.m
 *  DSTPersistentObject
 *
 *  Created by Johannes Schriewer on 2011-04-27
 *  Copyright (c) 2011 Johannes Schriewer.
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *
 *  - Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  - Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 *  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 *  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
 *  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
 *  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 *  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 *  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 *  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 *  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

// TODO: Automatically register PersistentObject Objects that are properties of another PersistentObject
// TODO: Allow cascaded deleting of complete PersistenObject trees
// TODO: implement fault objects to allow loading only the part of the tree hierarchy that is accessed
// TODO: Recursive saving of object trees
// TODO: Detect referencing cycles and bail out if found instead of looping endlessly

#define mustOverride() @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)] userInfo:nil]

#import <objc/runtime.h>
#import <objc/message.h>

#import "DSTPersistentObject.h"
#import "DSTCustomArchiver.h"
#import "DSTStorageEngine_Internal.h"


@interface DSTPersistentObject () {
    NSInteger identifier;
	BOOL dirty;
    BOOL observer;
    __strong NSMutableDictionary *props;
}

// db table creation, only called if table not available
- (void)createTable;

// saving functions
- (NSDictionary *)serialize;
- (void)saveSubTables;

// loading functions
- (BOOL)loadFromContext;
@end

@implementation DSTPersistentObject
@synthesize identifier;
@synthesize dirty;

#pragma mark - Setup
- (DSTPersistentObject *)initWithContext:(DSTPersistenceContext *)theContext {
    self = [super init];
    if (self) {
        context = theContext;
		identifier = -1;
		dirty = YES;
		[self addObserver:self
			   forKeyPath:@"dirty"
				  options:0
				  context:nil];
		observer = YES;
        
		// save ourselves
		if (![context tableExists:[self tableName]]) {
			[self createTable];
		}
        [self setDefaults];
	}
    return self;
}

- (DSTPersistentObject *)initWithIdentifier:(NSInteger)theIdentifier fromContext:(DSTPersistenceContext *)theContext {
	if (![theContext tableExists:[self tableName]]) {
		return nil; // bail out
	}

    self = [super init];
    if (self) {
        context = theContext;
		identifier = theIdentifier;
		if (![self loadFromContext]) {
            return nil;
        }
		[context registerObject:self];
		dirty = NO;
		[self addObserver:self
			   forKeyPath:@"dirty"
				  options:0
				  context:nil];
		observer = YES;

		[self didLoadFromContext];
    }
    return self;	
}


- (void)dealloc {
    if (observer) {
        [self removeObserver:self forKeyPath:@"dirty"];
    }
    [context deRegisterObject:self];
}

+ (NSSet *)keyPathsForValuesAffectingDirty {
	NSMutableArray *properties = [[self class] recursiveFetchPropertyNames];
    NSString *remove = nil;
    for (NSString *p in properties) {
        if ([p isEqualToString:@"dirty"]) {
            remove = p;
        }
    }
    if (remove) {
        [properties removeObject:remove];
    }
    
	return [NSSet setWithArray:properties];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([keyPath isEqualToString:@"dirty"]) {
		dirty = YES;
	}
}

#pragma mark - NSCoding
- (DSTPersistentObject *)initWithCoder:(NSCoder *)coder {
    if (![coder isKindOfClass:[DSTCustomUnArchiver class]]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"PersistentObject can only be unarchived by CustomArchiver" userInfo:nil];
    }
    DSTCustomUnArchiver *archiver = (DSTCustomUnArchiver *)coder;
    
    identifier = [archiver decodeIntegerForKey:@"identifier"];
    
	self = [[[self class] alloc] initWithIdentifier:identifier fromContext:[archiver context]];
    if (self) {
        context = [archiver context];
        [context registerObject:self];        
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:identifier forKey:@"identifier"];
}

- (id)valueForUndefinedKey:(NSString *)key {
    Log(@"WARNING: class %@, undefined key %@", [self class], key);
    return nil;
}

#pragma mark - Internal API

- (NSDictionary *)serialize {
	NSDictionary *properties = [self fetchAllProperties];
	
	NSMutableDictionary *propertiesSQL = [[NSMutableDictionary alloc] initWithCapacity:[properties count]];
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];
		
		// now parse property types into classes
		if (([propertyType hasPrefix:@"f"]) || ([propertyType hasPrefix:@"s"]) || ([propertyType hasPrefix:@"d"])) {
			// float
			[propertiesSQL setObject:[self valueForKey:propertyName] forKey:propertyName];
		} else if (([propertyType hasPrefix:@"I"]) || ([propertyType hasPrefix:@"i"]) || ([propertyType hasPrefix:@"l"]) || ([propertyType hasPrefix:@"L"]) || ([propertyType hasPrefix:@"c"]) || ([propertyType hasPrefix:@"C"]) || ([propertyType hasPrefix:@"B"]) || ([propertyType hasPrefix:@"q"]) || ([propertyType hasPrefix:@"Q"])) {
			// some form of integer
			[propertiesSQL setObject:[self valueForKey:propertyName] forKey:propertyName];
		} else if (([propertyType hasPrefix:@"@\"NSString"]) || ([propertyType hasPrefix:@"@\"NSMutableString"])) {
			// some form of string
			if ([self valueForKey:propertyName] != nil) {
				[propertiesSQL setObject:[self valueForKey:propertyName] forKey:propertyName];
			}
		} else if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array			
			// will be saved in saveSubTables
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			// will be saved in saveSubTables
		} else if ([propertyType hasPrefix:@"@"]) {
			// an object besides of string, array or dictionary (NSKeyedArchiver used to encode)
			[propertiesSQL setObject:[NSKeyedArchiver archivedDataWithRootObject:[self valueForKey:propertyName]] forKey:propertyName];			
		} else if ([propertyType hasPrefix:@"{"]) {
			// here we have to handle structs, we currently can only do those that have NSValue support
			[propertiesSQL setObject:[self valueForKey:propertyName] forKey:propertyName];
		} else {
			Log(@"Could not encode type %@, so will not try to", propertyType);
		}
	}
	return propertiesSQL;
}

- (void)saveSubTables {
	NSDictionary *properties = [self fetchAllProperties];
	
	// remove all objects for this from subtables
	// and insert new objects into subtables
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];
		
		// now parse property types into classes
		if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];

			// remove old entries
			[context deleteFromTable:subTableName where:@"objectID" isNumber:identifier];
			
			NSArray *array = [self valueForKey:propertyName];
			
			NSArray *fields = [NSArray arrayWithObjects:@"objectID", @"sortOrder", @"data", nil];
			NSUInteger i = 0;
			for (id obj in array) {
				NSData *data = [NSKeyedArchiver archivedDataWithRootObject:obj];
				NSArray *values = [NSArray arrayWithObjects:
								   [NSNumber numberWithUnsignedInteger:identifier],
								   [NSNumber numberWithUnsignedInteger:i],
								   data, nil];
				[context insertObjectInto:subTableName values:[NSDictionary dictionaryWithObjects:values forKeys:fields]];
				i++;
			}
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			
			// remove old entries
			[context deleteFromTable:subTableName where:@"objectID" isNumber:identifier];
			
			NSDictionary *dict = [self valueForKey:propertyName];

			NSArray *fields = [NSArray arrayWithObjects:@"objectID", @"key", @"data", nil];
			for (NSString *key in [dict allKeys]) {
				id obj = [dict objectForKey:key];
				NSData *data = [NSKeyedArchiver archivedDataWithRootObject:obj];
				NSArray *values = [NSArray arrayWithObjects:
								   [NSNumber numberWithUnsignedInteger:identifier],
								   key, data, nil];
				[context insertObjectInto:subTableName values:[NSDictionary dictionaryWithObjects:values forKeys:fields]];
			}
		}
	}
}

- (BOOL)loadFromContext {
	NSDictionary *data = [context fetchFromTable:[self tableName] pkid:identifier];
    if (!data) {
        return NO;
    }
	NSDictionary *properties = [self fetchAllProperties];
	
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];
		
		// now parse property types into classes
		if (([propertyType hasPrefix:@"f"]) || ([propertyType hasPrefix:@"s"]) || ([propertyType hasPrefix:@"d"])) {
			// float
			[self setValue:[data objectForKey:[propertyName lowercaseString]] forKey:propertyName];
		} else if (([propertyType hasPrefix:@"I"]) || ([propertyType hasPrefix:@"i"]) || ([propertyType hasPrefix:@"l"]) || ([propertyType hasPrefix:@"L"]) || ([propertyType hasPrefix:@"c"]) || ([propertyType hasPrefix:@"C"]) || ([propertyType hasPrefix:@"B"]) || ([propertyType hasPrefix:@"q"]) || ([propertyType hasPrefix:@"Q"])) {
			// some form of integer
			[self setValue:[data objectForKey:[propertyName lowercaseString]] forKey:propertyName];
		} else if (([propertyType hasPrefix:@"@\"NSString"]) || ([propertyType hasPrefix:@"@\"NSMutableString"])) {
			// some form of string
			if ([data objectForKey:[propertyName lowercaseString]]) {
				if ([[data objectForKey:[propertyName lowercaseString]] isKindOfClass:[NSNull class]]) {
					[self setValue:nil forKey:propertyName];
				} else {
					[self setValue:[data objectForKey:[propertyName lowercaseString]] forKey:propertyName];
				}
			}
		} else if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];

			NSArray *array = [context fetchFromTable:subTableName where:@"objectID" isNumber:identifier];
			NSSortDescriptor *sorter = [[NSSortDescriptor alloc] initWithKey:@"sortorder" ascending:YES];
			array = [array sortedArrayUsingDescriptors:[NSArray arrayWithObject:sorter]];
			
			NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:[array count]];
			for (NSDictionary *data in array) {
				NSData *content = [data objectForKey:@"data"];
				[result addObject:[DSTCustomUnArchiver unarchiveObjectWithData:content inContext:context]];
			}
			[self setValue:[NSArray arrayWithArray:result] forKey:propertyName];
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			
			NSArray *array = [context fetchFromTable:subTableName where:@"objectID" isNumber:identifier];
			
			NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:[array count]];
			for (NSDictionary *data in array) {
				NSData *content = [data objectForKey:@"data"];
				NSString *key = [data objectForKey:@"key"];
				[result setObject:[DSTCustomUnArchiver unarchiveObjectWithData:content inContext:context] forKey:key];
			}
			[self setValue:[NSDictionary dictionaryWithDictionary:result] forKey:propertyName];
		} else if ([propertyType hasPrefix:@"@"]) {
			// an object besides of string, array or dictionary (NSKeyedArchiver used to encode)
			[self setValue:[DSTCustomUnArchiver unarchiveObjectWithData:[data objectForKey:[propertyName lowercaseString]] inContext:context] forKey:propertyName];
		} else if ([propertyType hasPrefix:@"{"]) {
			// here we have to handle structs, we currently can only do those that have NSValue support
			[self setValue:[DSTCustomUnArchiver unarchiveObjectWithData:[data objectForKey:[propertyName lowercaseString]] inContext:context] forKey:propertyName];
		} else {
			Log(@"Could not decode type %@, so will not try to", propertyType);
		}
	}
    return YES;
}

#pragma mark - Private
- (NSString *)tableName {
	return [NSString stringWithFormat:@"%@", [self class]];
}

+ (NSString *)tableName {
	return [NSString stringWithFormat:@"%@", [self class]];
}

- (void)createTable {
	NSDictionary *properties = [self fetchAllProperties];
	
	NSMutableDictionary *propertiesSQL = [[NSMutableDictionary alloc] initWithCapacity:[properties count]];
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];
		
		// now parse property types into classes
		if (([propertyType hasPrefix:@"f"]) || ([propertyType hasPrefix:@"s"]) || ([propertyType hasPrefix:@"d"])) {
			// float
			[propertiesSQL setObject:@"REAL" forKey:propertyName];
		} else if (([propertyType hasPrefix:@"I"]) || ([propertyType hasPrefix:@"i"]) || ([propertyType hasPrefix:@"l"]) || ([propertyType hasPrefix:@"L"]) || ([propertyType hasPrefix:@"c"]) || ([propertyType hasPrefix:@"C"]) || ([propertyType hasPrefix:@"B"]) || ([propertyType hasPrefix:@"q"]) || ([propertyType hasPrefix:@"Q"])) {
			// some form of integer
			[propertiesSQL setObject:@"INTEGER" forKey:propertyName];
		} else if (([propertyType hasPrefix:@"@\"NSString"]) || ([propertyType hasPrefix:@"@\"NSMutableString"])) {
			// some form of string
			[propertiesSQL setObject:@"TEXT" forKey:propertyName];
		} else if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			NSDictionary *columns = [NSDictionary dictionaryWithObjectsAndKeys:
									 @"INTEGER", @"objectID", // foreign key
									 @"INTEGER", @"sortOrder",
									 @"BLOB", @"data",
									 nil];
			[context createTable:subTableName columns:columns version:[self version]];
			[propertiesSQL setObject:@"INTEGER" forKey:propertyName];
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			NSDictionary *columns = [NSDictionary dictionaryWithObjectsAndKeys:
									 @"INTEGER", @"objectID", // foreign key
									 @"TEXT", @"key",
									 @"BLOB", @"data",
									 nil];
			[context createTable:subTableName columns:columns version:[self version]];
			[propertiesSQL setObject:@"INTEGER" forKey:propertyName];
		} else if ([propertyType hasPrefix:@"@"]) {
			// an object besides of string, array or dictionary (NSKeyedArchiver used to encode)
			[propertiesSQL setObject:@"BLOB" forKey:propertyName];			
		} else if ([propertyType hasPrefix:@"{"]) {
			// here we have to handle structs, we currently can only do those that have NSValue support
			[propertiesSQL setObject:@"BLOB" forKey:propertyName];
		} else {
			Log(@"Could not encode type %@, so will not try to", propertyType);
		}
	}
	
	[context createTable:[self tableName] columns:propertiesSQL version:[self version]];
}

- (NSMutableDictionary *)fetchAllProperties {
	if (!props) {
		props = [[self class] recursiveFetchProperties];
	}
	return props;
}

+ (NSMutableDictionary *)recursiveFetchProperties {
	NSMutableDictionary *properties;
	
	if ([self superclass] != [NSObject class])
		properties = (NSMutableDictionary *)[[self superclass] recursiveFetchProperties];
	else
		properties = [NSMutableDictionary dictionary];
	
	NSUInteger propertyCount;
	
	objc_property_t *propList = class_copyPropertyList([self class], &propertyCount);

	for (NSUInteger i = 0; i < propertyCount; i++) {
		objc_property_t property = propList[i];
		
		NSString *propertyName = [NSString stringWithUTF8String:property_getName(property)];
		NSString *attributes = [NSString stringWithUTF8String: property_getAttributes(property)];

		// readonly properties are not saved as it is assumed they will be generated on the fly
		if ([attributes rangeOfString:@",R,"].location == NSNotFound) {
			NSArray *parts = [attributes componentsSeparatedByString:@","];
			if (parts != nil) {
				if ([parts count] > 0) {
					// Remove the leading 'T'
					NSString *propertyType = [[parts objectAtIndex:0] substringFromIndex:1];
					[properties setObject:propertyType forKey:propertyName];
				}
			}
		}
	}
	
	free(propList);
	return properties;
}

+ (NSMutableArray *)recursiveFetchPropertyNames {
    NSMutableArray *properties;
	
	if ([self superclass] != [NSObject class])
		properties = (NSMutableArray *)[[self superclass] recursiveFetchPropertyNames];
	else
		properties = [NSMutableArray array];
	
	NSUInteger propertyCount;
	
	objc_property_t *propList = class_copyPropertyList([self class], &propertyCount);
    
	for (NSUInteger i = 0; i < propertyCount; i++) {
		objc_property_t property = propList[i];
		
		NSString *propertyName = [NSString stringWithUTF8String:property_getName(property)];
        [properties addObject:propertyName];
	}
	
	free(propList);
	return properties;
}

+ (void)removeObjectFromAssociatedSubTables:(NSInteger)identifier context:(DSTPersistenceContext *)context {
	NSDictionary *properties = [[self class] recursiveFetchProperties];
	
	// remove all objects for this from subtables
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];
		
		// now parse property types into classes
		if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			
			// remove entries
			[context deleteFromTable:subTableName where:@"objectID" isNumber:identifier];
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			
			// remove entries
			[context deleteFromTable:subTableName where:@"objectID" isNumber:identifier];
		}
	}
}

#pragma mark - Shared API

+ (void)deleteObjectFromContext:(DSTPersistenceContext *)context identifier:(NSInteger)identifier {
	[[self class] removeObjectFromAssociatedSubTables:identifier context:context];
	[context deleteFromTable:[self tableName] pkid:identifier];
}

- (NSInteger)save {
	if (!dirty) {
		return identifier;
	}
	
	NSDictionary *data = [self serialize];
	if (identifier < 0) {
		identifier = [context insertObjectInto:[self tableName] values:data];
		[context registerObject:self];
		[self saveSubTables];
	} else {
		[context updateTable:[self tableName] pkid:identifier values:data];
		[self saveSubTables];
	}
	dirty = NO;
	
	return identifier;
}

#pragma mark - Abstract API
- (void)setDefaults {
    mustOverride();
}

- (NSUInteger)version {
	mustOverride();
	return 0;
}

- (void)didLoadFromContext {
	// do nothing, convenience for subclasses
}

@end
