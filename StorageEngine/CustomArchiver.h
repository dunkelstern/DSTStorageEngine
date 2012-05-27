//
//  CustomArchiver.h
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PersistenceContext.h"

@interface CustomUnArchiver : NSKeyedUnarchiver

- (id)initForReadingWithData:(NSData *)data inContext:(PersistenceContext *)context;

+ (id)unarchiveObjectWithData:(NSData *)data inContext:(PersistenceContext *)context;

@property (nonatomic, readonly) PersistenceContext *context;
@end
