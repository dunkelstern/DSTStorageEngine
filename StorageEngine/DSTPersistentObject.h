/*
 *  DSTPersistentObject.h
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

#import <Foundation/Foundation.h>
#import "DSTPersistenceContext.h"

@protocol DSTPersistentObjectSubclass <NSObject, NSCoding>
- (void)setDefaults;
- (NSUInteger)version;

@optional
- (void)didLoadFromContext;
@end

@interface DSTPersistentObject : NSObject <NSCoding, DSTPersistentObjectSubclass> {
    DSTPersistenceContext *context;
}

+ (void)deleteObjectFromContext:(DSTPersistenceContext *)context identifier:(NSInteger)identifier;

- (DSTPersistentObject *)initWithContext:(DSTPersistenceContext *)context;
- (DSTPersistentObject *)initWithIdentifier:(NSInteger)identifier fromContext:(DSTPersistenceContext *)context;
- (void)markAsChanged; // "dirtify" object e.g. if something in an mutable array changed
- (NSInteger)save; // returns new ID if saved first or current ID if updated
- (void)backgroundSave;

@property (nonatomic, readonly) NSInteger identifier;
@property (nonatomic, readonly, getter = isDirty) BOOL dirty;
@property (nonatomic, readonly) DSTPersistenceContext *context;

- (NSString *)tableName;
+ (NSString *)tableName;

@end
