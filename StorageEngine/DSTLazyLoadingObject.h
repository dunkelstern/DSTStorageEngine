//
//  DSTLazyLoadingObject.h
//  mps
//
//  Created by Johannes Schriewer on 01.02.2013.
//  Copyright (c) 2013 planetmutlu. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DSTLazyLoadingObject : NSProxy
- (DSTLazyLoadingObject *)initWithClass:(Class)class coder:(NSCoder *)coder;
- (NSString *)tableName;
- (NSInteger)identifier;
- (void)invalidate;
- (id)parent;
@end
