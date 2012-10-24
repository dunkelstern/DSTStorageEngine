/*
 *  DSTStorageEngine_Internal.h
 *  DSTStorageEngine
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

#import <sqlite3.h>

#define LogEntry(_msg) [NSString stringWithFormat:@"%s:%d %@", __PRETTY_FUNCTION__, __LINE__, _msg]

#ifdef Log
    #undef Log
#endif

#ifdef DebugLog
    #undef DebugLog
#endif

#ifdef FailLog
    #undef FailLog
#endif

#if 0
	#define DebugLog(_msg, ...) NSLog(LogEntry(_msg), __VA_ARGS__)
	#define FailLog(_msg, ...) @throw [NSException exceptionWithName:NSInvalidArgumentException reason:_msg userInfo:nil]
	#define Log(_msg, ...) NSLog(LogEntry(_msg), __VA_ARGS__)
#else
	#define DebugLog(_msg, ...)  while (0); /* do nothing */
	#define FailLog(_msg, ...) NSLog(LogEntry(_msg), ##__VA_ARGS__)
	#define Log(_msg, ...) NSLog(LogEntry(_msg), __VA_ARGS__)
#endif

@interface DSTPersistenceContext () {
    NSMutableArray *registeredObjects;
	NSMutableArray *tables;
	sqlite3 *dbHandle;
    BOOL transactionRunning;
}
- (void)registerObject:(DSTPersistentObject *)object;
- (void)deRegisterObject:(DSTPersistentObject *)object;

- (BOOL)tableExists:(NSString *)name;
- (BOOL)createTable:(NSString *)name columns:(NSDictionary *)columns version:(NSUInteger)version;
- (void)updateTable:(NSString *)name pkid:(NSUInteger)pkid values:(NSDictionary *)values;
- (NSUInteger)insertObjectInto:(NSString *)name values:(NSDictionary *)values;
- (void)deleteFromTable:(NSString *)name pkid:(NSUInteger)pkid;
- (void)deleteFromTable:(NSString *)name where:(NSString *)fieldName isNumber:(NSUInteger)number;

- (NSDictionary *)fetchFromTable:(NSString *)name pkid:(NSUInteger)pkid;
- (NSArray *)fetchFromTable:(NSString *)name where:(NSString *)fieldName isNumber:(NSUInteger)number;
@end
