//
//  StorageEngine.h
//  StorageEngine
//
//  Created by Johannes Schriewer on 2012-05-20.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import <sqlite3.h>

#define LogEntry(_msg) [NSString stringWithFormat:@"%s:%d %@", __PRETTY_FUNCTION__, __LINE__, _msg]

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
