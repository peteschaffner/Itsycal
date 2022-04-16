//
//  OpaquePopoverViewController.m
//  Itsycal
//
//  Created by Peter Schaffner on 16/04/2022.
//  Copyright © 2022 mowglii.com. All rights reserved.
//

#import "OpaquePopoverViewController.h"
#import "Themer.h"

@implementation OpaquePopoverViewController

- (void)viewDidAppear
{
	// Add a colored subview at the bottom the of popover's
	// window's frameView's view hierarchy. This should color
	// the popover including the arrow.
	NSView *frameView = self.view.window.contentView.superview;
	if (!frameView) return;
	if (frameView.subviews.count > 0
		&& [frameView.subviews[0].identifier isEqualToString:@"popoverBackgroundBox"]) return;
	NSBox *backgroundColorView = [[NSBox alloc] initWithFrame:frameView.bounds];
	backgroundColorView.identifier = @"popoverBackgroundBox";
	backgroundColorView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	backgroundColorView.boxType = NSBoxCustom;
	backgroundColorView.borderType = NSNoBorder;
	backgroundColorView.fillColor = Theme.mainBackgroundColor;
	[frameView addSubview:backgroundColorView positioned:NSWindowBelow relativeTo:nil];
}

@end
