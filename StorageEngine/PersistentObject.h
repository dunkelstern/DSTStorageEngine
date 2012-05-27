//
//  PersistenceObject.h
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PersistenceContext.h"

@protocol PersistentObjectSubclass <NSObject, NSCoding>
- (void)setDefaults;
- (NSUInteger)version;

@optional
- (void)didLoadFromContext;
@end

@interface PersistentObject : NSObject <NSCoding, PersistentObjectSubclass> {
    __strong PersistenceContext *context;
}

+ (void)deleteObjectFromContext:(PersistenceContext *)context identifier:(NSInteger)identifier;

- (PersistentObject *)initWithContext:(PersistenceContext *)context;
- (PersistentObject *)initWithIdentifier:(NSInteger)identifier fromContext:(PersistenceContext *)context;
- (NSInteger)save; // returns new ID if saved first or current ID if updated

@property (nonatomic, readonly) NSInteger identifier;
@property (nonatomic, readonly, getter = isDirty) BOOL dirty;
@end
