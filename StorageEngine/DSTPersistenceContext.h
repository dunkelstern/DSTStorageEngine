/*
 *  DSTPersistenceContext.h
 *  DSTPersistenceContext
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
#import <Foundation/Foundation.h>

@class DSTPersistentObject;
@interface DSTPersistenceContext : NSObject

@property (nonatomic, assign) dispatch_queue_t dispatchQueue;
@property (nonatomic, strong, readonly) NSString *databaseFile;
@property (nonatomic, assign, readonly, getter = isReadonly) BOOL readonly;
@property (nonatomic, assign) BOOL lazyLoadingEnabled;

- (DSTPersistenceContext *)initWithDatabase:(NSString *)dbName;
- (DSTPersistenceContext *)initWithDatabase:(NSString *)dbName readonly:(BOOL)readonly;
- (NSSet *)registeredObjects;
- (void)optimize;
- (void)beginTransaction;
- (void)endTransaction;

+ (void)removeOnDiskRepresentationForDatabase:(NSString *)dbName;
@end
