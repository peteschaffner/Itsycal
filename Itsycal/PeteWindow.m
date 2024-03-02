//
//  PeteWindow.m
//  Itsycal
//
//  Created by Pete Schaffner on 01/03/2024.
//  Copyright © 2024 mowglii.com. All rights reserved.
//

#import "PeteWindow.h"

static const CGFloat kMinimumSpaceBetweenWindowAndScreenEdge = 10;

@implementation PeteWindow
{
    NSView *_childContentView;
}

- (id)init
{
    self = [super initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    if (self) {
        [self setStyleMask:NSWindowStyleMaskFullSizeContentView | NSWindowStyleMaskNonactivatingPanel | NSWindowStyleMaskUtilityWindow];
        [self setBackgroundColor:NSColor.clearColor];
        [self setLevel:NSMainMenuWindowLevel];
        [self setMovable:NO];
        [self setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    }
    return self;
}

- (BOOL)canBecomeMainWindow
{
    return NO;
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)positionRelativeToRect:(NSRect)rect screenMaxX:(CGFloat)screenMaxX
{
    // Calculate window's top left point.
    // First, center window under status item.
    CGFloat w = NSWidth(self.frame);
    CGFloat x = roundf(NSMidX(rect) - w / 2);
    CGFloat y = NSMinY(rect) - 7;

    // If the calculated x position puts the window too
    // far to the right, shift the window left.
    if (x + w + kMinimumSpaceBetweenWindowAndScreenEdge > screenMaxX) {
        x = screenMaxX - w - kMinimumSpaceBetweenWindowAndScreenEdge;
    }

    // Set the window position.
    [self setFrameTopLeftPoint:NSMakePoint(x, y)];

    [self invalidateShadow];
}

@end
