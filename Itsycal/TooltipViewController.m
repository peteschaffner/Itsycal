//
//  TooltipViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/17/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "TooltipViewController.h"
#import "Themer.h"

@implementation TooltipViewController

- (void)viewDidLoad
{
    [super viewDidLoad];


    self.view.wantsLayer = YES;
    self.view.layer.cornerRadius = 6;
    self.view.layer.cornerCurve = kCACornerCurveContinuous;

    NSVisualEffectView *ev = [NSVisualEffectView new];
    ev.frame = self.view.bounds;
    ev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    ev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    ev.material = NSVisualEffectMaterialPopover;
    ev.state = NSVisualEffectStateActive;

    [self.view addSubview:ev positioned:NSWindowBelow relativeTo:NULL];

    NSView *innerStroke = [NSView new];
    innerStroke.frame = self.view.bounds;
    innerStroke.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    innerStroke.wantsLayer = YES;
    innerStroke.layer.borderColor = [NSColor.whiteColor colorWithAlphaComponent:0.2].CGColor;
    innerStroke.layer.borderWidth = 1;
    innerStroke.layer.cornerRadius = self.view.layer.cornerRadius;
    innerStroke.layer.cornerCurve = self.view.layer.cornerCurve;

    [self.view addSubview:innerStroke];
}

- (BOOL)toolTipForDate:(MoDate)date
{
    self.tv.enableHover = NO;
    self.tv.enclosingScrollView.hasVerticalScroller = NO; // in case user has System Prefs set to always show scroller
    self.events = [self.tooltipDelegate eventsForDate:date];
    if (self.events) {
        [self reloadData];
        return YES;
    }
    return NO;
}

@end
