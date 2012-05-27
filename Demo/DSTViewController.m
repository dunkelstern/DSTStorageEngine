//
//  DSTViewController.m
//  StorageEngine
//
//  Created by Johannes Schriewer on 2012-05-20.
//  Copyright (c) 2012 Johannes Schriewer. All rights reserved.
//

#import "DSTViewController.h"
#import "StorageEngine.h"
#import "DSTTestObject.h"

@interface DSTViewController ()

@end

@implementation DSTViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	// create a persistence context
	PersistenceContext *persist = [[PersistenceContext alloc] initWithDatabase:@"test.sqlite"];

#if 1
	// instanciate a persistent object
	DSTTestObject *o = [[DSTTestObject alloc] initWithContext:persist];
	[o setDefaults];
	
	NSLog(@"object is %@", ([o isDirty]) ? @"dirty" : @"clean");
	
	// save the object and get the object id in return
	NSInteger pkid = [o save];
	NSLog(@"object is %@", ([o isDirty]) ? @"dirty" : @"clean");

	[o setAFloat:2.45];

	NSLog(@"object is %@", ([o isDirty]) ? @"dirty" : @"clean");
#else
	// fetch object from context
	DSTTestObject *o = [[DSTTestObject alloc] initWithIdentifier:0 fromContext:persist];
	NSLog(@"fetched: %@", o);
#endif
	
	// delete the object again
	// [DSTTestObject deleteObjectFromContext:persist identifier:pkid];
	
	
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
	    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
	} else {
	    return YES;
	}
}

@end
