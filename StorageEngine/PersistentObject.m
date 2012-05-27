//
//  PersistenceObject.m
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//


// TODO: Automatically register PersistentObject Objects that are properties of another PersistentObject
// TODO: Allow cascaded deleting of complete PersistenObject trees
// TODO: implement fault objects to allow loading only the part of the tree hierarchy that is accessed
// TODO: Recursive saving of object trees
// TODO: Detect referencing cycles and bail out if found instead of looping endlessly

#define mustOverride() @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)] userInfo:nil]

#import <objc/runtime.h>
#import <objc/message.h>

#import "PersistentObject.h"
#import "CustomArchiver.h"
#import "StorageEngine_Internal.h"


@interface PersistentObject () {
    NSInteger identifier;
	BOOL dirty;
}

// db table creation, only called if table not available
- (void)createTable;

// saving functions
- (NSDictionary *)serialize;
- (void)saveSubTables;

// loading functions
- (void)loadFromContext;
@end

@implementation PersistentObject
@synthesize identifier;
@synthesize dirty;

#pragma mark - Setup
- (PersistentObject *)initWithContext:(PersistenceContext *)theContext {
    self = [super init];
    if (self) {
        context = theContext;
		identifier = -1;
		dirty = YES;
		[self addObserver:self
			   forKeyPath:@"dirty"
				  options:0
				  context:nil];
		
		// save ourselves
		if (![context tableExists:[self tableName]]) {
			[self createTable];
		}
	}
    return self;
}

- (PersistentObject *)initWithIdentifier:(NSInteger)theIdentifier fromContext:(PersistenceContext *)theContext {
	if (![theContext tableExists:[self tableName]]) {
		return nil; // bail out
	}

    self = [super init];
    if (self) {
        context = theContext;
		identifier = theIdentifier;
		[self loadFromContext];
		[context registerObject:self];
		dirty = NO;
		[self addObserver:self
			   forKeyPath:@"dirty"
				  options:0
				  context:nil];

		[self didLoadFromContext];
    }
    return self;	
}


- (void)dealloc {
	[self removeObserver:self forKeyPath:@"dirty"];
    [context deRegisterObject:self];
}

+ (NSSet *)keyPathsForValuesAffectingDirty {
	NSDictionary *properties = [[self class] fetchAllProperties];
	return [NSSet setWithArray:[properties allKeys]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if ([keyPath isEqualToString:@"dirty"]) {
		dirty = YES;
	}
}

#pragma mark - NSCoding
- (PersistentObject *)initWithCoder:(NSCoder *)coder {
    if (![coder isKindOfClass:[CustomUnArchiver class]]) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"PersistentObject can only be unarchived by CustomArchiver" userInfo:nil];
    }
    CustomUnArchiver *archiver = (CustomUnArchiver *)coder;
    
	self = [[[self class] alloc] initWithIdentifier:[[archiver valueForKey:@"identifier"] integerValue] fromContext:[archiver context]];
    if (self) {
        context = [archiver context];
        [context registerObject:self];
        
        identifier = [[coder valueForKey:@"identifier"] integerValue];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:[NSNumber numberWithInteger:identifier] forKey:@"identifier"];
}

#pragma mark - Internal API

- (NSDictionary *)serialize {
	NSDictionary *properties = [[self class] fetchAllProperties];
	
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
	NSDictionary *properties = [[self class] fetchAllProperties];
	
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

- (void)loadFromContext {
	NSDictionary *data = [context fetchFromTable:[self tableName] pkid:identifier];
	NSDictionary *properties = [[self class] fetchAllProperties];
	
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
				[result addObject:[CustomUnArchiver unarchiveObjectWithData:content inContext:context]];
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
				[result setObject:[CustomUnArchiver unarchiveObjectWithData:content inContext:context] forKey:key];
			}
			[self setValue:[NSDictionary dictionaryWithDictionary:result] forKey:propertyName];
		} else if ([propertyType hasPrefix:@"@"]) {
			// an object besides of string, array or dictionary (NSKeyedArchiver used to encode)
			[self setValue:[CustomUnArchiver unarchiveObjectWithData:[data objectForKey:[propertyName lowercaseString]] inContext:context] forKey:propertyName];
		} else if ([propertyType hasPrefix:@"{"]) {
			// here we have to handle structs, we currently can only do those that have NSValue support
			[self setValue:[CustomUnArchiver unarchiveObjectWithData:[data objectForKey:[propertyName lowercaseString]] inContext:context] forKey:propertyName];
		} else {
			Log(@"Could not decode type %@, so will not try to", propertyType);
		}
	}
}

#pragma mark - Private
- (NSString *)tableName {
	return [NSString stringWithFormat:@"%@", [self class]];
}

+ (NSString *)tableName {
	return [NSString stringWithFormat:@"%@", [self class]];
}

- (void)createTable {
	NSDictionary *properties = [[self class] fetchAllProperties];
	
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

+ (NSMutableDictionary *)fetchAllProperties {
	static NSMutableDictionary *props = nil;
	if (!props) {
		props = [[self class] recursiveFetchProperties];
	}
	return props;
}

+ (NSMutableDictionary *)recursiveFetchProperties {
	NSMutableDictionary *properties;
	
	if ([self superclass] != [NSObject class])
		properties = (NSMutableDictionary *)[[self superclass] fetchAllProperties];
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

+ (void)removeObjectFromAssociatedSubTables:(NSInteger)identifier context:(PersistenceContext *)context {
	NSDictionary *properties = [[self class] fetchAllProperties];
	
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

+ (void)deleteObjectFromContext:(PersistenceContext *)context identifier:(NSInteger)identifier {
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
