//
//  CustomArchiver.m
//  StorageEngine
//
//  Created by Johannes Schriewer on 16.05.2012.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import "DSTCustomArchiver.h"
@interface DSTCustomUnArchiver () {
    __strong DSTPersistenceContext *context;
}
@end

@implementation DSTCustomUnArchiver
@synthesize context;

- (id)initForReadingWithData:(NSData *)data inContext:(DSTPersistenceContext *)theContext {
    self = [super initForReadingWithData:data];
    if (self) {
        context = theContext;
    }
    return self;
}

- (id)initForReadingWithData:(NSData *)data {
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"You have to supply a context" userInfo:nil];
}

+ (id)unarchiveObjectWithData:(NSData *)data inContext:(DSTPersistenceContext *)context {
	DSTCustomUnArchiver *unarchiver = [[DSTCustomUnArchiver alloc] initForReadingWithData:data inContext:context];
	return [unarchiver decodeObjectForKey:@"root"];
}

@end
