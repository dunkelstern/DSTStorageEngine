//
//  CustomArchiver.m
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import "CustomArchiver.h"
@interface CustomUnArchiver () {
    __strong PersistenceContext *context;
}
@end

@implementation CustomUnArchiver
@synthesize context;

- (id)initForReadingWithData:(NSData *)data inContext:(PersistenceContext *)theContext {
    self = [super initForReadingWithData:data];
    if (self) {
        context = theContext;
    }
    return self;
}

- (id)initForReadingWithData:(NSData *)data {
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"You have to supply a context" userInfo:nil];
}

+ (id)unarchiveObjectWithData:(NSData *)data inContext:(PersistenceContext *)context {
	CustomUnArchiver *unarchiver = [[CustomUnArchiver alloc] initForReadingWithData:data inContext:context];
	return [unarchiver decodeObjectForKey:@"root"];
}

@end
