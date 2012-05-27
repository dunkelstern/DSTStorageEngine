//
//  PersistenceContext.h
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PersistentObject;
@interface PersistenceContext : NSObject

- (PersistenceContext *)initWithDatabase:(NSString *)dbName;
- (NSArray *)registeredObjects;
+ (void)removeOnDiskRepresentationForDatabase:(NSString *)dbName;
@end
