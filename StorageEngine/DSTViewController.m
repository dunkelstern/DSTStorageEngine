//
//  DSTViewController.m
//  StorageEngine
//
//  Created by Johannes Schriewer on 2012-05-20.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "DSTViewController.h"

@interface DSTViewController ()

@end

@implementation DSTViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
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
