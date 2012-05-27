//
//  DSTTestObject.h
//  StorageEngine
//
//  Created by Johannes Schriewer on 2012-05-20.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import "DSTPersistentObject.h"

@interface DSTTestObject : DSTPersistentObject <PersistentObjectSubclass>

@property (nonatomic, assign) CGFloat aFloat;
@property (nonatomic, assign) CGSize aSize;
@property (nonatomic, assign) CGPoint aPoint;
@property (nonatomic, strong) NSString *aString;
@property (nonatomic, assign) CGRect aRect;
@property (nonatomic, strong) DSTTestObject *customPersistentClass;
@property (nonatomic, assign) NSUInteger unsignedInteger;

@property (nonatomic, strong) NSArray *someValues;
@property (nonatomic, strong) NSDictionary *someValuesDictionary;

@property (nonatomic, readonly, assign) NSInteger readonlyValue;

@end
