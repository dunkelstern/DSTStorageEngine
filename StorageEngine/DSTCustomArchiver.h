//
//  CustomArchiver.h
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DSTPersistenceContext.h"

@interface DSTCustomUnArchiver : NSKeyedUnarchiver

- (id)initForReadingWithData:(NSData *)data inContext:(DSTPersistenceContext *)context;

+ (id)unarchiveObjectWithData:(NSData *)data inContext:(DSTPersistenceContext *)context;

@property (nonatomic, readonly) DSTPersistenceContext *context;
@end
