/*
 *  DSTPersistenceContext.m
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

#import "DSTPersistenceContext.h"

// Class extensions are in this file
#import "DSTStorageEngine_Internal.h"

@implementation DSTPersistenceContext

- (DSTPersistenceContext *)initWithDatabase:(NSString *)dbName {
    self = [super init];
    if (self) {
        registeredObjects = [[NSMutableArray alloc] init];
		dbHandle = NULL;

        _dispatchQueue = dispatch_queue_create("de.dunkelstern.dstpersistencecontext", DISPATCH_QUEUE_SERIAL);

        if ([dbName hasPrefix:@"/"]) {
            // absolute path
            _databaseFile = dbName;
        } else {
            // relative to document dir
            _databaseFile = [[[[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] objectAtIndex:0] URLByAppendingPathComponent:dbName] absoluteString];
        }
		int result = sqlite3_open([_databaseFile UTF8String], &dbHandle);
		if (result) {
			FailLog(@"Could not open database: %s", sqlite3_errmsg(dbHandle));
			sqlite3_close(dbHandle);
			dbHandle = NULL;
			return nil;
		}

		char *errmsg = NULL;
		if (sqlite3_exec(dbHandle, "PRAGMA encoding = \"UTF-8\"",  NULL, NULL, &errmsg) != SQLITE_OK) {
			FailLog(@"Could not set encoding to UTF-8: %s", errmsg);
			sqlite3_free(errmsg);
			sqlite3_close(dbHandle);
			dbHandle = NULL;
			return nil;
		}
		
		if (sqlite3_exec(dbHandle, "PRAGMA auto_vacuum=0",  NULL, NULL, &errmsg) != SQLITE_OK) {
			FailLog(@"Could not set auto vaccum: %s", errmsg);
			sqlite3_free(errmsg);
			sqlite3_close(dbHandle);
			dbHandle = NULL;
			return nil;
		}

		if (sqlite3_exec(dbHandle, "PRAGMA journal_mode=MEMORY",  NULL, NULL, &errmsg) != SQLITE_OK) {
			FailLog(@"Could not set journal mode: %s", errmsg);
			sqlite3_free(errmsg);
			sqlite3_close(dbHandle);
			dbHandle = NULL;
			return nil;
		}

		if (sqlite3_exec(dbHandle, "PRAGMA temp_store=2",  NULL, NULL, &errmsg) != SQLITE_OK) {
			FailLog(@"Could not set temporary store mode: %s", errmsg);
			sqlite3_free(errmsg);
			sqlite3_close(dbHandle);
			dbHandle = NULL;
			return nil;
		}

		tables = [[NSMutableArray alloc] initWithCapacity:1];
		[self fetchTables];

		if (![self tableExists:@"storageengine_versions"]) {
			if (sqlite3_exec(dbHandle, "CREATE TABLE storageengine_versions ( tablename TEXT, version INTEGER )",  NULL, NULL, &errmsg) != SQLITE_OK) {
				FailLog(@"Could not create versioning table: %s", errmsg);
				sqlite3_free(errmsg);
				sqlite3_close(dbHandle);
				return nil;
			}
			[self fetchTables];
		}
    }
    return self;
}

- (void)dealloc {
    dispatch_sync(self.dispatchQueue, ^{
        if (dbHandle) {
            if (transactionRunning) [self endTransaction];
            sqlite3_close(dbHandle);
        }
    });
    dispatch_release(_dispatchQueue);
}

#pragma mark - API
- (void)optimize {
    dispatch_async(self.dispatchQueue, ^{
        if (transactionRunning) [self endTransaction];
        char *errmsg = NULL;
        if (sqlite3_exec(dbHandle, "VACUUM",  NULL, NULL, &errmsg) != SQLITE_OK) {
            FailLog(@"Could not optimize database: %s", errmsg);
        }
    });
}

- (void)beginTransaction {
    dispatch_async(self.dispatchQueue, ^{
        char *errmsg = NULL;
        if (transactionRunning) return;
        if (sqlite3_exec(dbHandle, "BEGIN TRANSACTION",  NULL, NULL, &errmsg) != SQLITE_OK) {
            FailLog(@"Could not begin database transaction: %s", errmsg);
        } else {
            transactionRunning = YES;
        }
    });
}

- (void)endTransaction {
    dispatch_async(self.dispatchQueue, ^{
        if (!transactionRunning) return;

        char *errmsg = NULL;
        if (sqlite3_exec(dbHandle, "END TRANSACTION",  NULL, NULL, &errmsg) != SQLITE_OK) {
            FailLog(@"Could not end database transaction: %s", errmsg);
        } else {
            transactionRunning = NO;
        }
    });
}

- (NSArray *)registeredObjects {
    return [NSArray arrayWithArray:registeredObjects];
}

+ (void)removeOnDiskRepresentationForDatabase:(NSString *)dbName {
	NSFileManager *fm = [NSFileManager defaultManager];
	NSURL *databaseFile = [[[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] objectAtIndex:0] URLByAppendingPathComponent:dbName];
	NSError *error = nil;
	[fm removeItemAtURL:databaseFile error:&error];
	if (error) {
		Log(@"Could not remove database file: %@", error);
	}
}

#pragma mark - Internal API
- (BOOL)tableExists:(NSString *)name {
	NSString *lowerCaseName = [name lowercaseString];
	for (NSString *tableName in tables) {
		if ([tableName isEqualToString:lowerCaseName]) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)createTable:(NSString *)name columns:(NSDictionary *)columns version:(NSUInteger)version {
	if ([self tableExists:name]) {
		FailLog(@"Table %@ exists already", name);
		return NO;
	}
	
	NSMutableString *query = [[NSMutableString alloc] init];
	
	// build query
	[query appendFormat:@"CREATE TABLE %@ ( id INTEGER PRIMARY KEY, ", [name lowercaseString]];
	for (NSString *columnName in [columns allKeys]) {
		Class type = [columns objectForKey:columnName];
		[query appendFormat:@"%@ %@,", [columnName lowercaseString], type];
	}
	[query deleteCharactersInRange:NSMakeRange([query length]-1, 1)];
	[query appendFormat:@");"];
	
	// execute query
	char *errmsg = NULL;
	if (sqlite3_exec(dbHandle, [query UTF8String],  NULL, NULL, &errmsg) != SQLITE_OK) {
		FailLog(@"Could not create table: %s", errmsg);
		sqlite3_free(errmsg);
		return NO;
	}
	
	// insert into version table
	NSString *versionQuery = [NSString stringWithFormat:@"INSERT INTO storageengine_versions ( tablename, version ) VALUES ( \"%@\", %u )", [name lowercaseString], version];
	if (sqlite3_exec(dbHandle, [versionQuery UTF8String],  NULL, NULL, &errmsg) != SQLITE_OK) {
		FailLog(@"Could insert version string: %s", errmsg);
		sqlite3_free(errmsg);
		sqlite3_exec(dbHandle, [[NSString stringWithFormat:@"DROP TABLE %@", name] UTF8String], NULL, NULL, &errmsg);
		return NO;
	}
	
	[self fetchTables];
	return YES;
}

- (NSUInteger)insertObjectInto:(NSString *)name values:(NSDictionary *)values {	
	sqlite3_stmt *stmt = NULL;
	
	// build insert query
	NSMutableString *query = [[NSMutableString alloc] init];
	[query appendFormat:@"INSERT INTO %@ ( ", [name lowercaseString]];
	for(NSString *key in values) {
		[query appendFormat:@"%@,", [key lowercaseString]];
	}
	[query deleteCharactersInRange:NSMakeRange([query length]-1, 1)];
	[query appendFormat:@" ) VALUES ( "];
	for(NSString *key in values) {
		[query appendFormat:@":%@,", [key lowercaseString]];
	}
	[query deleteCharactersInRange:NSMakeRange([query length]-1, 1)];
	[query appendFormat:@" );"];
	
	// execute
	DebugLog(@"Query: %@", query);
	if (sqlite3_prepare_v2(dbHandle, [query UTF8String], strlen([query UTF8String]), &stmt, NULL) != SQLITE_OK) {
		Log(@"Could not prepare insert statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return NSUIntegerMax;
	}
	[self fillStatement:stmt values:values];
	
	int result = sqlite3_step(stmt);
	if (result != SQLITE_DONE) {
		Log(@"Could not execute insert statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return NSUIntegerMax;
	}
	sqlite3_finalize(stmt);
	
	return sqlite3_last_insert_rowid(dbHandle);
}

- (void)deleteFromTable:(NSString *)name pkid:(NSUInteger)pkid {
	sqlite3_stmt *stmt = NULL;

	// prepare statement
	NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE id = :pkindex", [name lowercaseString]];
	DebugLog(@"Query: %@", sql);
	if (sqlite3_prepare_v2(dbHandle, [sql UTF8String], strlen([sql UTF8String]), &stmt, NULL) != SQLITE_OK) {
		Log(@"Could not prepare delete statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return;
	}
	int parameterIndex = sqlite3_bind_parameter_index(stmt, ":pkindex");
	sqlite3_bind_int(stmt, parameterIndex, pkid);

	// execute statement
	if (sqlite3_step(stmt) != SQLITE_DONE) {
		Log(@"Could not execute delete statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return;
	}
	sqlite3_finalize(stmt);
}

- (void)deleteFromTable:(NSString *)name where:(NSString *)fieldName isNumber:(NSUInteger)number {
	sqlite3_stmt *stmt = NULL;
	NSString *fieldPlaceholder = [NSString stringWithFormat:@":%@", [fieldName lowercaseString]];
	
	// prepare statement
	NSString *sql = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = %@", [name lowercaseString], [fieldName lowercaseString], fieldPlaceholder];
	DebugLog(@"Query: %@", sql);
	if (sqlite3_prepare_v2(dbHandle, [sql UTF8String], strlen([sql UTF8String]), &stmt, NULL) != SQLITE_OK) {
		Log(@"Could not prepare delete statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return;
	}
	int parameterIndex = sqlite3_bind_parameter_index(stmt, [fieldPlaceholder UTF8String]);
	sqlite3_bind_int(stmt, parameterIndex, number);
	
	// execute statement
	if (sqlite3_step(stmt) != SQLITE_DONE) {
		Log(@"Could not execute delete statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return;
	}
	sqlite3_finalize(stmt);	
}

- (void)updateTable:(NSString *)name pkid:(NSUInteger)pkid values:(NSDictionary *)values {
	NSMutableString *query = [[NSMutableString alloc] init];
	[query appendFormat:@"UPDATE %@ SET ", [name lowercaseString]];
	for(NSString *key in values) {
		[query appendFormat:@"%@ = :%@,", [key lowercaseString], [key lowercaseString]];
	}
	[query deleteCharactersInRange:NSMakeRange([query length]-1, 1)];
	[query appendFormat:@" WHERE id = %u;", pkid];
	
	DebugLog(@"Query: %@", query);
	sqlite3_stmt *stmt = NULL;
	if (sqlite3_prepare_v2(dbHandle, [query UTF8String], strlen([query UTF8String]), &stmt, NULL) != SQLITE_OK) {
		Log(@"Could not prepare update statement: %s", sqlite3_errmsg(dbHandle));
		return;
	}
	[self fillStatement:stmt values:values];
	
	int result = sqlite3_step(stmt);
	if (result != SQLITE_DONE) {
		Log(@"Could not execute update statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return;
	}
	sqlite3_finalize(stmt);
}


- (NSDictionary *)fetchFromTable:(NSString *)name pkid:(NSUInteger)pkid {
	sqlite3_stmt *stmt = NULL;

	// fetch from table
	NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE id = :pkid", [name lowercaseString]];
	DebugLog(@"Query: %@", sql);
	if (sqlite3_prepare_v2(dbHandle, [sql UTF8String], strlen([sql UTF8String]), &stmt, NULL) != SQLITE_OK) {
		Log(@"Could not prepare fetch statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return nil;
	}
	int parameterIndex = sqlite3_bind_parameter_index(stmt, ":pkid");
	sqlite3_bind_int(stmt, parameterIndex, pkid);
	if (sqlite3_step(stmt) != SQLITE_ROW) {
		Log(@"Could not execute fetch statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return nil;
	}
	
	NSDictionary *result = [self convertResultToDictionary:stmt];
	sqlite3_finalize(stmt);
	return result;
}

- (NSArray *)fetchFromTable:(NSString *)name where:(NSString *)fieldName isNumber:(NSUInteger)number {
	sqlite3_stmt *stmt = NULL;
	NSString *fieldPlaceholder = [NSString stringWithFormat:@":%@", [fieldName lowercaseString]];

	// fetch from table
	NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@ = %@", [name lowercaseString], [fieldName lowercaseString], fieldPlaceholder];
	DebugLog(@"Query: %@", sql);
	if (sqlite3_prepare_v2(dbHandle, [sql UTF8String], strlen([sql UTF8String]), &stmt, NULL) != SQLITE_OK) {
		Log(@"Could not prepare fetch statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return nil;
	}
	int parameterIndex = sqlite3_bind_parameter_index(stmt, [fieldPlaceholder UTF8String]);
	sqlite3_bind_int(stmt, parameterIndex, number);
	
	NSMutableArray *data = [[NSMutableArray alloc] init];
	int sqlResult = SQLITE_OK;
	while ((sqlResult = sqlite3_step(stmt)) == SQLITE_ROW) {
		[data addObject:[self convertResultToDictionary:stmt]];
	}
	
	if (sqlResult != SQLITE_DONE) {
		Log(@"Could not execute fetch statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return nil;
	}
	
	sqlite3_finalize(stmt);
	return [NSArray arrayWithArray:data];	
}

- (void)registerObject:(DSTPersistentObject *)object {
    [registeredObjects addObject:object];
}

- (void)deRegisterObject:(DSTPersistentObject *)object {
    [registeredObjects removeObject:object];
}

#pragma mark - Private API
- (void)fetchTables {
	sqlite3_stmt *stmt = NULL;
	
	[tables removeAllObjects];
	
	// fetch table list
	char *sql = "SELECT name FROM SQLITE_MASTER WHERE type = 'table'";
	DebugLog(@"Query: %s", sql);
	if (sqlite3_prepare_v2(dbHandle, sql, strlen(sql), &stmt, NULL) != SQLITE_OK) {
		Log(@"Could prepare fetchTables statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return;
	}

	int sqlResult = SQLITE_OK;
	while ((sqlResult = sqlite3_step(stmt)) == SQLITE_ROW) {
		[tables addObject:@((const char *)sqlite3_column_text(stmt, 0))];
	}
	
	if (sqlResult != SQLITE_DONE) {
		Log(@"Could execute fetchTables statement: %s", sqlite3_errmsg(dbHandle));
		sqlite3_finalize(stmt);
		return;		
	}
	sqlite3_finalize(stmt);
}

- (void)fillStatement:(sqlite3_stmt *)stmt values:(NSDictionary *)values {
	for(NSString *key in values) {
		id value = [values objectForKey:key];
		NSString *placeholder = [NSString stringWithFormat:@":%@", [key lowercaseString]];
		int parameterIndex = sqlite3_bind_parameter_index(stmt, [placeholder UTF8String]);
		int result = 0;
		
		if ([value isKindOfClass:[NSString class]]) {
			result = sqlite3_bind_text(stmt, parameterIndex, [value UTF8String], strlen([value UTF8String]), SQLITE_TRANSIENT);
		} else if ([value isKindOfClass:[NSNumber class]]) {
			result = sqlite3_bind_double(stmt, parameterIndex, [value doubleValue]);
		} else if ([value isKindOfClass:[NSData class]]) {
			result = sqlite3_bind_blob(stmt, parameterIndex, [value bytes], [value length], SQLITE_TRANSIENT);
		} else if ([value isKindOfClass:[NSValue class]]) {
			NSData *data = [NSKeyedArchiver archivedDataWithRootObject:value];
			result = sqlite3_bind_blob(stmt, parameterIndex, [data bytes], [data length], SQLITE_TRANSIENT);
		} else {
			FailLog(@"Could not determine data type for %@", key);
		}
		
		if (result != SQLITE_OK) {
			Log(@"binding of %@ (index: %d) failed: %s", key, parameterIndex, sqlite3_errmsg(dbHandle));
		}
	}
}

- (NSDictionary *)convertResultToDictionary:(sqlite3_stmt *)stmt {
	NSMutableDictionary	*data = [[NSMutableDictionary alloc] initWithCapacity:sqlite3_column_count(stmt)];
	for (int i = 0; i < sqlite3_column_count(stmt); i++) {
		NSString *key = @(sqlite3_column_name(stmt, i));
		id obj;
		
		switch (sqlite3_column_type(stmt, i)) {
			case SQLITE_INTEGER:
				obj = @(sqlite3_column_int(stmt,i));
				break;
			case SQLITE_FLOAT:
				obj = @(sqlite3_column_double(stmt,i));
				break;
			case SQLITE_BLOB:
				obj = [NSData dataWithBytes:sqlite3_column_blob(stmt, i) length:sqlite3_column_bytes(stmt, i)];
				break;
			case SQLITE_NULL:
				obj = [NSNull null];
				break;
			case SQLITE_TEXT:
				obj = @((const char *)sqlite3_column_text(stmt, i));
				break;
			default:
				Log(@"Unknown column type %d", sqlite3_column_type(stmt, i));
				obj = [NSNull null];
				break;
		}
		[data setObject:obj forKey:key];
	}
	return [NSDictionary dictionaryWithDictionary:data];
}
@end
