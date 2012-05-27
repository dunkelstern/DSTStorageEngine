# DSTStorageEngine

Simple Objective-C storage backend based on SQLite 3. Concepts borrowed heavily from CoreData but modified somewhat to match my approach:

* Managed Context is named DSTPersistenceContext
* Managed Object is named DSTPersistentObject
* You may have more than one PersistenceContext
* You may have multiple backing-files (one per context)
* You don't have to register your context on app startup

## How to use

1. Import the header file

        #import "DSTStorageEngine.h"

2. Link your binary against `libsqlite3.dylib` (works like every other framework)
3. Create a context (named `test.sqlite` in your documents directory)

    	PersistenceContext *persist = [[PersistenceContext alloc]
    	                                initWithDatabase:@"test.sqlite"];

4. Create a `DSTPersistenceObject` subclass to contain your model object:

        #import "DSTPersistentObject.h"

        // interface, use as many properties as you like
        @interface TestObject : DSTPersistentObject <DSTPersistentObjectSubclass>

        @property (nonatomic, assign) CGFloat aFloat;
        @property (nonatomic, assign) CGSize aSize;
        @property (nonatomic, strong) NSString *aString;

        // this won't be saved because it's declared readonly
        @property (nonatomic, readonly, assign) NSInteger readonlyValue;

        @end

        // implementation, implement the delegate defined above
        @implementation TestObject
        @synthesize aFloat, aSize, aString;
        
        - (NSUInteger)version {
            // currently we have object version 1,
            // increase this if you make changes to the properties
            return 1;
        }

        - (void)setDefaults {
            aFloat = 0.0;
            aSize = CGSizeZero;
            aString = nil;
        }
        
        - (void)didLoadFromContext {
            // this is called if the object has been successfully loaded from a context
        }
        
        @end

5. Instanciate your object:

        TestObject *obj = [[TestObject alloc] initWithContext:persist];
        [obj setDefaults];

6. Save your object (the save function returns the identifier, but you may access it by calling `[obj identifier]` later too):

        NSInteger identifier = [obj save];
        
    To save all objects that have been added to the context by calling save before:
    
        [[persist registeredObjects] makeObjectsPerformSelector:@selector(save)];
        
7. Your object is stored on disk, all database tables and files will be created automatically, your schema definition is your property layout of your class (there are some limitations but read on).

8. Fetch an object by its identifier:

        TestObject *o = [[TestObject alloc] initWithIdentifier:0 fromContext:persist];

9. Delete an object from a context:

        [TestObject deleteObjectFromContext:persist identifier:0];

10. Delete the complete context:

        [DSTPersistenceContext removeOnDiskRepresentationForDatabase:@"test.sqlite"];

## Limitations

* Your classes have to be key-value-coding compliant
* If you use c-style `struct` types make sure they have a predeterminable length
* Do not use `char *`
* Do not use pointers in any struct or property if it is not a pointer to a subclass of `NSObject`
* All custom classes used as properties have to be `NSCoding` compliant (e.g. have `initWithCoder` and `encodeWithCoder`)
* Do not use c-style arrays as properties (in structs they are ok as long as the length is not variable)


## Todo

* Automatically register DSTPersistentObject Objects that are properties of another DSTPersistentObject
* Allow cascaded deleting of complete DSTPersistenObject trees
* Implement fault objects to allow loading only the part of the tree hierarchy that is accessed
* Recursive saving of object trees
* Detect referencing cycles and bail out if found instead of looping endlessly
