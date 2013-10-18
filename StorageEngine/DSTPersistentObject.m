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

#import <dispatch/dispatch.h>

// TODO: Automatically register PersistentObject Objects that are properties of another PersistentObject
// TODO: Allow cascaded deleting of complete PersistenObject trees
// TODO: Recursive saving of object trees
// TODO: Detect referencing cycles and bail out if found instead of looping endlessly

#define mustOverride() @throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"You must override %@ in a subclass", NSStringFromSelector(_cmd)] userInfo:nil]

#import <objc/runtime.h>
#import <objc/message.h>

#import "DSTPersistentObject.h"
#import "DSTCustomArchiver.h"
#import "DSTStorageEngine_Internal.h"
#import "DSTLazyLoadingObject.h"

@interface DSTPersistentObject () {
    NSInteger identifier;
	BOOL dirty;
    BOOL observer;
    NSMutableDictionary *props;
}

// db table creation, only called if table not available
- (void)createTable;

// saving functions
- (NSDictionary *)serialize;
- (NSDictionary *)prepareSubTables;
- (void)processSubTables:(NSDictionary *)actions;

// loading functions
- (BOOL)loadFromContext;
@end

@implementation DSTPersistentObject
@synthesize identifier;
@synthesize dirty;

#pragma mark - Setup

+ (DSTPersistenceContext *)checkMigrationWithContext:(DSTPersistenceContext *)context {
    // check version
    __block NSInteger version;
    dispatch_sync(context.dispatchQueue, ^{
        version = [context versionForTable:[self tableName]];
    });
    if (version < 0) return context;

    // migrate if neccessary
    if ([self version] != version) {
        DSTPersistenceContext *fromContext;
        DSTPersistenceContext *toContext;

        BOOL migrationStart = NO;
        if (![context migrationFromContext]) {
            fromContext = [[DSTPersistenceContext alloc] initWithDatabase:[context databaseFile] readonly:YES];
            [fromContext setLazyLoadingEnabled:NO];
            [context setMigrationFromContext:toContext];

            migrationStart = YES;

            toContext = [DSTPersistenceContext duplicateContextInTemporaryFile:context];
            [context setMigrationToContext:toContext];
        } else {
            fromContext = [context migrationFromContext];
            toContext = [context migrationToContext];
        }

        if ([toContext versionForTable:[self tableName]] != [self version]) {
            [fromContext setMigrationFromContext:fromContext];
            [fromContext setMigrationToContext:toContext];
            NSArray *pkids = [fromContext pkidsForTable:[self tableName]];
            for (NSNumber *pkid in pkids) {
                DSTPersistentObject *obj = (DSTPersistentObject *)[[[self class] alloc] initForMigrationWithIdentifier:[pkid integerValue] forContext:fromContext];

                // drop table at first run and recreate
                if (pkids[0] == pkid) {
                    [obj setContext:toContext];
                    [toContext deleteTable:[self tableName]];
                    [obj createTable];
                    [toContext beginTransaction];
                }

                // save all loaded objects in new context and deregister them from old context
                NSSet *regObjs = [fromContext registeredObjects];
                for (DSTPersistentObject *o in regObjs) {
                    [o setContext:toContext];
                    [toContext registerObject:o];
                    [fromContext deRegisterObject:o];
                }

                // migrate and save
                [obj migrateFromVersion:version additionalData:nil];
                for (DSTPersistentObject *o in regObjs) {
                    [o markAsChanged];
                    [o save];
                }
            }
        } else {
            DebugLog(@"Migration for %@ already done.", [self class]);
        }

        if (migrationStart) {
            [toContext endTransaction];
            [DSTPersistenceContext exchangeContext:context fromTemporaryContext:toContext];
            [context setMigrationFromContext:nil];
            [context setMigrationToContext:nil];
        }
        return toContext;
    }
    return context;
}

- (DSTPersistentObject *)initForMigrationWithIdentifier:(NSInteger)theIdentifier forContext:(DSTPersistenceContext *)theContext {
	if (![theContext tableExists:[self tableName]]) {
		return nil; // bail out
	}

    self = [super init];
    if (self) {
        _context = theContext;
		identifier = theIdentifier;

        if (![self loadFromContext]) {
            return nil;
        }
        [_context registerObject:self];

        dirty = YES;
    }
    return self;	
}

- (DSTPersistentObject *)initWithContext:(DSTPersistenceContext *)theContext {
    if ([theContext isReadonly]) {
		FailLog(@"Database is read only!");
		return nil;
    }

    self = [super init];
    if (self) {
        _context = theContext;
		identifier = -1;
		dirty = YES;
		[self addObserver:self
			   forKeyPath:@"dirty"
				  options:0
				  context:nil];
		observer = YES;

		// save ourselves
        __block BOOL tableExists = NO;
        dispatch_sync(_context.dispatchQueue, ^{
            tableExists = [_context tableExists:[self tableName]];
        });

        if (!tableExists) {
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
		identifier = theIdentifier;

        DSTPersistenceContext *migrationContext = [[self class] checkMigrationWithContext:theContext];
        if (theContext != migrationContext) {
            _context = migrationContext;
        } else {
            _context = theContext;
        }

        if (![self loadFromContext]) {
            return nil;
        }
        _context = theContext;
        [_context registerObject:self];

        if (theContext != migrationContext) {
            dirty = YES;
        } else {
            dirty = NO;
        }
		[self addObserver:self
			   forKeyPath:@"dirty"
				  options:0
				  context:nil];
		observer = YES;

		[self didLoadFromContext];
    }
    return self;	
}

- (void)invalidate {
    [_context deRegisterObject:self];
    _context = nil;
}

- (void)dealloc {
    if (observer) {
        [self removeObserver:self forKeyPath:@"dirty"];
    }
}

+ (NSSet *)keyPathsForValuesAffectingDirty {
	return [NSSet setWithArray:[[[self class] recursiveFetchProperties] allKeys]];
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

    if (archiver.context.lazyLoadingEnabled) {
        return self;
    }
    identifier = [archiver decodeIntegerForKey:@"identifier"];
    
	self = [self initWithIdentifier:identifier fromContext:[archiver context]];
    if (self) {
        _context = [archiver context];
        [_context registerObject:self];
        if ([self.class respondsToSelector:@selector(parentAttribute)]) {
            [self setValue:[archiver parent] forKey:[self.class parentAttribute]];
        }
    }
    return self;
}

- (id)awakeAfterUsingCoder:(NSCoder *)aDecoder {
    DSTCustomUnArchiver *archiver = (DSTCustomUnArchiver *)aDecoder;
    if (archiver.context.lazyLoadingEnabled) {
        DSTLazyLoadingObject *lazy = [[DSTLazyLoadingObject alloc] initWithClass:self.class coder:aDecoder];
        return (DSTPersistentObject *)lazy;
    } else {
        return [super awakeAfterUsingCoder:aDecoder];
    }
}

- (void)encodeWithCoder:(NSCoder *)coder {
    if (identifier < 0) {
        dirty = YES;
        [self save];
        
    }
    [coder encodeInteger:identifier forKey:@"identifier"];
}

- (id)valueForUndefinedKey:(NSString *)key {
    Log(@"WARNING: class %@, undefined key %@", [self class], key);
    return nil;
}

#pragma mark - Internal API
- (NSUInteger)version {
	return [[self class] version];
}

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
            if ([self valueForKey:propertyName]) {
                [propertiesSQL setObject:[NSKeyedArchiver archivedDataWithRootObject:[self valueForKey:propertyName]] forKey:propertyName];
            }
		} else if ([propertyType hasPrefix:@"{"]) {
			// here we have to handle structs, we currently can only do those that have NSValue support
			[propertiesSQL setObject:[self valueForKey:propertyName] forKey:propertyName];
		} else {
			Log(@"Could not encode type %@, so will not try to", propertyType);
		}
	}
	return propertiesSQL;
}

- (NSDictionary *)prepareSubTables {
    NSDictionary *properties = [self fetchAllProperties];
    NSMutableArray *remove = [NSMutableArray array];
    NSMutableArray *insert = [NSMutableArray array];

	// remove all objects for this from subtables
	// and insert new objects into subtables
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];

		// now parse property types into classes
		if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];

			// remove old entries
            [remove addObject:@{ @"subtable"   : subTableName,
                                 @"where"      : @"objectID",
                                 @"identifier" : @(identifier) }];

			NSArray *array = [self valueForKey:propertyName];

			NSUInteger i = 0;
			for (id obj in array) {
				NSData *data = [NSKeyedArchiver archivedDataWithRootObject:obj];
                [insert addObject:@{ @"subtable" : subTableName,
                                     @"values"   : @{
                                        @"objectID"  : @((NSInteger)identifier),
                                        @"sortOrder" : @(i),
                                        @"data"      : data }
                                    }];
				i++;
			}
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];

			// remove old entries
            [remove addObject:@{ @"subtable" : subTableName,
                                 @"where"    : @"objectID",
                                 @"identifier" : @(identifier) }];

			NSDictionary *dict = [self valueForKey:propertyName];

			for (NSString *key in [dict allKeys]) {
				id obj = [dict objectForKey:key];
				NSData *data = [NSKeyedArchiver archivedDataWithRootObject:obj];
                [insert addObject:@{ @"subtable" : subTableName,
                                     @"values"   : @{
                                        @"objectID" : @((NSInteger)identifier),
                                        @"key"      : key,
                                        @"data"     : data }
                                     }];
			}
		}
	}

    return @{
        @"remove" : remove,
        @"insert" : insert
    };
}

- (void)processSubTables:(NSDictionary *)actions {
    if ([_context isReadonly]) {
		FailLog(@"Database is read only!");
		return;
    }

    for (NSDictionary *remove in actions[@"remove"]) {
        dispatch_async(_context.dispatchQueue, ^{
            [_context deleteFromTable:remove[@"subtable"] where:remove[@"where"] isNumber:[remove[@"identifier"] integerValue]];
        });
    }

    for (NSDictionary *insert in actions[@"insert"]) {
        dispatch_async(_context.dispatchQueue, ^{
            NSDictionary *values = insert[@"values"];
            // fix -1 identifier if object is saved the first time
            if ([values[@"objectID"] integerValue] < 0) {
                values = [values mutableCopy];
                [(NSMutableDictionary *)values setObject:@((NSInteger)identifier) forKey:@"objectID"];
            }
            [_context insertObjectInto:insert[@"subtable"] values:values];
        });
    }

    
}

- (BOOL)loadFromContext {
    __block NSDictionary *data;
    dispatch_sync(_context.dispatchQueue, ^{
        data = [_context fetchFromTable:[self tableName] pkid:identifier];
    });
    if (!data) {
        return NO;
    }
	NSDictionary *properties = [self fetchAllProperties];
	
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];
		
		// now parse property types into classes
		if (([propertyType hasPrefix:@"f"]) || ([propertyType hasPrefix:@"s"]) || ([propertyType hasPrefix:@"d"])) {
			// float
            if (([data objectForKey:[propertyName lowercaseString]]) && (![[data objectForKey:[propertyName lowercaseString]] isKindOfClass:[NSNull class]])) {
                [self setValue:[data objectForKey:[propertyName lowercaseString]] forKey:propertyName];
            } else {
                [self setValue:@(0.0) forKey:propertyName];
            }
		} else if (([propertyType hasPrefix:@"I"]) || ([propertyType hasPrefix:@"i"]) || ([propertyType hasPrefix:@"l"]) || ([propertyType hasPrefix:@"L"]) || ([propertyType hasPrefix:@"c"]) || ([propertyType hasPrefix:@"C"]) || ([propertyType hasPrefix:@"B"]) || ([propertyType hasPrefix:@"q"]) || ([propertyType hasPrefix:@"Q"])) {
			// some form of integer
            if (([data objectForKey:[propertyName lowercaseString]]) && (![[data objectForKey:[propertyName lowercaseString]] isKindOfClass:[NSNull class]])) {
                [self setValue:[data objectForKey:[propertyName lowercaseString]] forKey:propertyName];
            } else {
                [self setValue:@(0) forKey:propertyName];
            }
		} else if (([propertyType hasPrefix:@"@\"NSString"]) || ([propertyType hasPrefix:@"@\"NSMutableString"])) {
			// string
			if ([data objectForKey:[propertyName lowercaseString]]) {
				if ([[data objectForKey:[propertyName lowercaseString]] isKindOfClass:[NSNull class]]) {
					[self setValue:nil forKey:propertyName];
				} else {
                    if ([propertyType hasPrefix:@"@\"NSMutable"]) {
                        [self setValue:[[data objectForKey:[propertyName lowercaseString]] mutableCopy] forKey:propertyName];
                    } else {
                        [self setValue:[data objectForKey:[propertyName lowercaseString]] forKey:propertyName];
                    }
				}
			}
		} else if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];

            __block NSArray *array;
            dispatch_sync(_context.dispatchQueue, ^{
                array = [_context fetchFromTable:subTableName where:@"objectID" isNumber:identifier];
            });
			NSSortDescriptor *sorter = [[NSSortDescriptor alloc] initWithKey:@"sortorder" ascending:YES];
			array = [array sortedArrayUsingDescriptors:@[sorter]];
			
			NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:[array count]];
			for (NSDictionary *data in array) {
				NSData *content = [data objectForKey:@"data"];
                if ((content) && (![content isKindOfClass:[NSNull class]])) {
                    id unarchived = [DSTCustomUnArchiver unarchiveObjectWithData:content inContext:_context parent:self];
                    if (unarchived) {
                        [result addObject:unarchived];
                    }
                }
			}
            if ([propertyType hasPrefix:@"@\"NSMutable"]) {
                [self setValue:[NSMutableArray arrayWithArray:result] forKey:propertyName];                
            } else {
                [self setValue:[NSArray arrayWithArray:result] forKey:propertyName];
            }
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];

            __block NSArray *array;
            dispatch_sync(_context.dispatchQueue, ^{
                array = [_context fetchFromTable:subTableName where:@"objectID" isNumber:identifier];
            });
			NSMutableDictionary *result = [[NSMutableDictionary alloc] initWithCapacity:[array count]];
			for (NSDictionary *data in array) {
				NSData *content = [data objectForKey:@"data"];
				NSString *key = [data objectForKey:@"key"];
                if ((content) && (![content isKindOfClass:[NSNull class]])) {
                    [result setObject:[DSTCustomUnArchiver unarchiveObjectWithData:content inContext:_context parent:self] forKey:key];
                }
			}
            if ([propertyType hasPrefix:@"@\"NSMutable"]) {
                [self setValue:[NSMutableDictionary dictionaryWithDictionary:result] forKey:propertyName];
            } else {
                [self setValue:[NSDictionary dictionaryWithDictionary:result] forKey:propertyName];
            }
		} else if ([propertyType hasPrefix:@"@"]) {
			// an object besides of string, array or dictionary (NSKeyedArchiver used to encode)
            if (![[data objectForKey:[propertyName lowercaseString]] isKindOfClass:[NSNull class]]) {
                [self setValue:[DSTCustomUnArchiver unarchiveObjectWithData:[data objectForKey:[propertyName lowercaseString]] inContext:_context parent:self] forKey:propertyName];
            } else {
                [self setValue:nil forKey:propertyName];
            }
		} else if ([propertyType hasPrefix:@"{"]) {
			// here we have to handle structs, we currently can only do those that have NSValue support
            if (([data objectForKey:[propertyName lowercaseString]]) && (![[data objectForKey:[propertyName lowercaseString]] isKindOfClass:[NSNull class]])) {
                [self setValue:[DSTCustomUnArchiver unarchiveObjectWithData:[data objectForKey:[propertyName lowercaseString]] inContext:_context parent:self] forKey:propertyName];
            }
		} else {
			Log(@"Could not decode type %@, so will not try to", propertyType);
		}
	}
    dirty = NO;
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
    if ([_context isReadonly]) {
		FailLog(@"Database is read only!");
		return;
    }

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
			NSDictionary *columns = @{@"objectID" : @"INTEGER", // foreign key
									  @"sortOrder": @"INTEGER",
									  @"data"     : @"BLOB"};
            dispatch_async(_context.dispatchQueue, ^{
                [_context createTable:subTableName columns:columns version:[self version]];
            });
			[propertiesSQL setObject:@"INTEGER" forKey:propertyName];
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			NSDictionary *columns = @{@"objectID": @"INTEGER", // foreign key
									  @"key"     : @"TEXT",
									  @"data"    : @"BLOB"};
            dispatch_async(_context.dispatchQueue, ^{
                [_context createTable:subTableName columns:columns version:[self version]];
            });
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

    dispatch_async(_context.dispatchQueue, ^{
        [_context createTable:[self tableName] columns:propertiesSQL version:[self version]];
    });
}

- (NSMutableDictionary *)fetchAllProperties {
	if (!props) {
		props = [[self class] recursiveFetchProperties];
	}
	return props;
}

+ (NSMutableDictionary *)recursiveFetchProperties {
	NSMutableDictionary *properties;
    NSArray *exclude = [self backReferencingProperties];

	if ([self superclass] != [NSObject class]) {
		properties = (NSMutableDictionary *)[[self superclass] recursiveFetchProperties];
    } else {
		properties = [NSMutableDictionary dictionary];
    }
	
	unsigned int propertyCount;
	
	objc_property_t *propList = class_copyPropertyList([self class], &propertyCount);

	for (NSUInteger i = 0; i < propertyCount; i++) {
		objc_property_t property = propList[i];
		
		NSString *propertyName = @(property_getName(property));

        // do not add backReferencingProperties
        BOOL skip = NO;
        for (NSString *property in exclude) {
            if ([propertyName isEqualToString:property]) {
                skip = YES;
            }
        }
        if (skip) continue;

		NSString *attributes = @(property_getAttributes(property));

		// readonly properties are not saved as it is assumed they will be generated on the fly
        // weak properties are not saved as it is assumed they backreference to the parent object
		if (([attributes rangeOfString:@",R,"].location == NSNotFound) &&
            ([attributes rangeOfString:@",W,"].location == NSNotFound)) {
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

+ (NSArray *)backReferencingProperties {
    return @[ @"context" ];
}

+ (void)removeObjectFromAssociatedSubTables:(NSInteger)identifier context:(DSTPersistenceContext *)context {
    if ([context isReadonly]) {
		FailLog(@"Database is read only!");
		return;
    }
	NSDictionary *properties = [[self class] recursiveFetchProperties];
	
	// remove all objects for this from subtables
	for (NSString *propertyName in properties) {
		NSString *propertyType = [properties objectForKey:propertyName];
		
		// now parse property types into classes
		if (([propertyType hasPrefix:@"@\"NSArray"]) || ([propertyType hasPrefix:@"@\"NSMutableArray"])) {
			// some array
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];
			
			// remove entries
            dispatch_async(context.dispatchQueue, ^{
                [context deleteFromTable:subTableName where:@"objectID" isNumber:identifier];
            });
		} else if (([propertyType hasPrefix:@"@\"NSDictionary"]) || ([propertyType hasPrefix:@"@\"NSMutableDictionary"])) {
			// some dictionary
			NSString *subTableName = [NSString stringWithFormat:@"%@_%@", [self tableName], propertyName];

			// remove entries
            dispatch_async(context.dispatchQueue, ^{
                [context deleteFromTable:subTableName where:@"objectID" isNumber:identifier];
            });
		}
	}
}

#pragma mark - Shared API

+ (void)deleteObjectFromContext:(DSTPersistenceContext *)context identifier:(NSInteger)identifier {
    if ([context isReadonly]) {
		FailLog(@"Database is read only!");
		return;
    }
    [[self class] removeObjectFromAssociatedSubTables:identifier context:context];
    dispatch_async(context.dispatchQueue, ^{
        [context deleteFromTable:[self tableName] pkid:identifier];
    });
}

- (NSInteger)identifier {
    if (identifier < 0) {
        return [self save];
    } else {
        return identifier;
    }
}

- (NSInteger)save {
    if ([_context isReadonly]) {
		FailLog(@"Database is read only!");
		return -1;
    }

    @synchronized(self) {
        if ((!dirty) && !(identifier < 0)) {
            return identifier;
        }

        // serialize all values of this object before returning
        NSDictionary *data = [self serialize];
        NSDictionary *subtableActions = [self prepareSubTables];

        // execute the query itself in a background thread
        if (identifier < 0) {
            dispatch_sync(_context.dispatchQueue, ^{
                identifier = [_context insertObjectInto:[self tableName] values:data];
                [_context registerObject:self];
            });
        }

        dispatch_sync(_context.dispatchQueue, ^{
            [_context updateTable:[self tableName] pkid:identifier values:data];
            [self processSubTables:subtableActions];
            dirty = NO;
        });

        return identifier;
    }
}

- (void)backgroundSave {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self save];
    });
}

- (void)markAsChanged {
    dirty = YES;
}

#pragma mark - Abstract API
- (void)setDefaults {
    IMP myImp = [DSTPersistentObject instanceMethodForSelector:@selector(setDefaults)];
    IMP classImp = [[self class] instanceMethodForSelector:@selector(setDefaults)];
    if (myImp == classImp) {
        mustOverride();
    }
}

- (void)didLoadFromContext {
	// do nothing, convenience for subclasses
}

@end
