/*
 *  DSTCustomArchiver.m
 *  DSTCustomArchiver
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

#import "DSTCustomArchiver.h"

@implementation DSTCustomUnArchiver

- (id)initForReadingWithData:(NSData *)data inContext:(DSTPersistenceContext *)theContext parent:(id)parent {
    self = [super initForReadingWithData:data];
    if (self) {
        _context = theContext;
        _parent = parent;
    }
    return self;
}

- (id)initForReadingWithData:(NSData *)data {
    @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"You have to supply a context" userInfo:nil];
}

+ (id)unarchiveObjectWithData:(NSData *)data inContext:(DSTPersistenceContext *)context parent:(id)parent {
	DSTCustomUnArchiver *unarchiver = [[DSTCustomUnArchiver alloc] initForReadingWithData:data inContext:context parent:parent];
	return [unarchiver decodeObjectForKey:@"root"];
}

@end
