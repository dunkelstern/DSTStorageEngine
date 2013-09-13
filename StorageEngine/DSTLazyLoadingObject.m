//
//  DSTLazyLoadingObject.m
//  mps
//
//  Created by Johannes Schriewer on 01.02.2013.
//  Copyright (c) 2013 planetmutlu. All rights reserved.
//

#import "DSTLazyLoadingObject.h"
#import "DSTStorageEngine.h"
#import "DSTStorageEngine_Internal.h"
#import "DSTCustomArchiver.h"

@interface DSTLazyLoadingObject () {
    DSTPersistentObject *proxiedObject;
    Class realClass;
    NSInteger identifier;
    __weak DSTPersistenceContext *context;
    id parent;
}
@end

@implementation DSTLazyLoadingObject

- (DSTLazyLoadingObject *)initWithClass:(Class)class coder:(NSCoder *)coder {
    realClass = class;
    DSTCustomUnArchiver *decoder = (DSTCustomUnArchiver *)coder;
    identifier = [decoder decodeIntegerForKey:@"identifier"];
    context = [decoder context];
    if (![context objectExists:identifier inTable:[realClass tableName]]) {
        return nil;
    }
    proxiedObject = nil;
    parent = [decoder parent];
    [context registerLazyObject:self];
    return self;
}

+ (BOOL)respondsToSelector:(SEL)aSelector {
    return [DSTPersistentObject respondsToSelector:aSelector];
}

- (NSString *)debugDescription {
    if (proxiedObject) {
        return [proxiedObject debugDescription];
    } else {
        return [NSString stringWithFormat:@"<DSTLazyLoadingObject %p> Faulted object for %@ class", self, realClass];
    }
}

- (NSString *)description {
    if (proxiedObject) {
        return [proxiedObject description];
    } else {
        return [NSString stringWithFormat:@"<DSTLazyLoadingObject %p>", self];
    }
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    if (!proxiedObject) {
        proxiedObject = [self loadProxiedObject];
    }
    [invocation setTarget:proxiedObject];
    [invocation invoke];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    if (!proxiedObject) {
        proxiedObject = [self loadProxiedObject];
    }
    return [proxiedObject methodSignatureForSelector:sel];
}

- (Class)class {
    if (proxiedObject) {
        return [proxiedObject class];
    }
    return realClass;
}

- (BOOL)isKindOfClass:(Class)aClass {
    return [realClass isSubclassOfClass:aClass];
}

- (BOOL)isMemberOfClass:(Class)aClass {
    return aClass == realClass;
}

- (Class)superclass {
    return [realClass superclass];
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [realClass respondsToSelector:aSelector];
}

#pragma mark - Special Logic to speed up saves

- (void)save {
    if(proxiedObject) {
        [proxiedObject save];
    }
}

- (void)invalidate {
    if (proxiedObject) {
        [proxiedObject invalidate];
    }
    [context deRegisterLazyObject:self];
    parent = nil;
    proxiedObject = nil;
    context = nil;
}

- (NSString *)tableName {
    return [realClass tableName];
}

- (NSInteger)identifier {
    return identifier;
}

- (id)parent {
    return parent;
}

#pragma mark - Internal

- (id)loadProxiedObject {
    DSTPersistentObject *obj = [(DSTPersistentObject *)[realClass alloc] initWithIdentifier:identifier fromContext:context];
    [obj awakeAfterUsingCoder:nil];
    if ([realClass respondsToSelector:@selector(parentAttribute)]) {
        [obj setValue:parent forKey:[realClass parentAttribute]];
    }
    [context registerObject:obj];
    return obj;
}

@end
