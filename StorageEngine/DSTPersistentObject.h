//
//  PersistenceObject.h
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DSTPersistenceContext.h"

@protocol PersistentObjectSubclass <NSObject, NSCoding>
- (void)setDefaults;
- (NSUInteger)version;

@optional
- (void)didLoadFromContext;
@end

@interface DSTPersistentObject : NSObject <NSCoding, PersistentObjectSubclass> {
    __strong DSTPersistenceContext *context;
}

+ (void)deleteObjectFromContext:(DSTPersistenceContext *)context identifier:(NSInteger)identifier;

- (DSTPersistentObject *)initWithContext:(DSTPersistenceContext *)context;
- (DSTPersistentObject *)initWithIdentifier:(NSInteger)identifier fromContext:(DSTPersistenceContext *)context;
- (NSInteger)save; // returns new ID if saved first or current ID if updated

@property (nonatomic, readonly) NSInteger identifier;
@property (nonatomic, readonly, getter = isDirty) BOOL dirty;
@end
