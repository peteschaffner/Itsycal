//
//  MoButton.m
//  
//
//  Created by Sanjay Madan on 2/11/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "MoButton.h"

@implementation MoButton
{
	CALayer *_hoverLayer;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.bordered = NO;
        self.imagePosition = NSImageOnly;
        [self setButtonType:NSButtonTypeMomentaryChange];
		self.wantsLayer = YES;
		_hoverLayer = [CALayer new];
		_hoverLayer.frame = self.bounds;
		_hoverLayer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_hoverLayer.cornerRadius = 4;
		_hoverLayer.cornerCurve = kCACornerCurveContinuous;
		[self.layer addSublayer:_hoverLayer];
    }
    return self;
}

- (CGSize)intrinsicContentSize
{
    return self.image.size;
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    [self evaluateHover];
}

- (void)setActionBlock:(void (^)(void))actionBlock
{
    if (actionBlock) {
        _actionBlock = [actionBlock copy];
        self.target = self;
        self.action = @selector(doActionBlock:);
    }
    else {
        _actionBlock = nil;
        self.target = nil;
        self.action = NULL;
    }
}

- (void)doActionBlock:(id)sender
{
    self.actionBlock();
}

- (void)updateTrackingAreas
{
    for (NSTrackingArea *area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }
    NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:self.bounds options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways) owner:self userInfo:nil];
    [self addTrackingArea:area];
    [self evaluateHover];
    [super updateTrackingAreas];
}

- (void)evaluateHover
{
    NSPoint mouseLocation = [self.window mouseLocationOutsideOfEventStream];
    mouseLocation = [self convertPoint:mouseLocation fromView:nil];
    if (NSPointInRect(mouseLocation, self.bounds)) {
        [self showHoverEffect:YES];
    } else {
        [self showHoverEffect:NO];
    }
}

- (void)mouseEntered:(NSEvent *)event
{
    [self showHoverEffect:YES];
}

- (void)mouseExited:(NSEvent *)event
{
    [self showHoverEffect:NO];
}

- (void)showHoverEffect:(BOOL)show
{
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        context.duration = 0.15;
		_hoverLayer.opacity = show && self.enabled ? 0.08 : 0;
    }];
}

- (void)updateLayer
{
	_hoverLayer.backgroundColor = NSColor.labelColor.CGColor;
}

@end
