//
//  DSTTestObject.m
//  StorageEngine
//
//  Created by Johannes Schriewer on 2012-05-20.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import "DSTTestObject.h"

@implementation DSTTestObject
@synthesize unsignedInteger, aFloat, aSize, aString, aPoint, aRect, someValues, someValuesDictionary, customPersistentClass, readonlyValue;

- (NSUInteger)version {
	return 1;
}

- (void)setDefaults {
	unsignedInteger = 123;
	aFloat = 1.23;
	aString = @"String";
	aSize = CGSizeMake(10, 20);
	aPoint = CGPointMake(20, 30);
	aRect = CGRectMake(10, 20, 30, 40);
	someValues = [NSArray arrayWithObjects:@"aString", [NSNumber numberWithInt:123], nil];
	someValuesDictionary = [NSDictionary dictionaryWithObjectsAndKeys:@"abcdefghijklmnopq", @"aString", [NSNumber numberWithInt:123], @"anInteger", nil];
	customPersistentClass = nil;
	readonlyValue = 200;
}

- (NSString *)description {
	return [NSString stringWithFormat:@"%@ = { unsignedInteger = %d, aFloat: %f, aString = '%@', aSize = %@, aPoint = %@, aRect = %@, someValues = %@, someValuesDictionary = %@, customPersistentClass = %p }",
		  [self class], unsignedInteger, aFloat, aString, NSStringFromCGSize(aSize), NSStringFromCGPoint(aPoint), NSStringFromCGRect(aRect), someValues, someValuesDictionary, customPersistentClass];
}

- (void)didLoadFromContext {
	NSLog(@"just loaded this object from disk");
}

@end
