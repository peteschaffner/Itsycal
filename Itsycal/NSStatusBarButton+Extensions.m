//
//  NSStatusBarButton+Extensions.m
//  Itsycal
//
//  Created by Pete Schaffner on 02/03/2024.
//  Copyright © 2024 mowglii.com. All rights reserved.
//

#import "NSStatusBarButton+Extensions.h"
#import "ViewController.h"

@implementation NSStatusBarButton (HighlightState)

/*
 // This allows the status item to remain highlighted while the window is open.
 // By overriding the `mouseDown` method, we can handle highlighting in our window
 // controller. It's a solution that requires tight coupling, but it's better than removing
 // the action and using a local event monitor (which would break holding command to reposition the item)
 //
 // Reference: https://stackoverflow.com/a/74498437
 extension NSStatusBarButton {

 public override func mouseDown(with event: NSEvent) {
 if event.modifierFlags.contains(.control) {
 self.rightMouseDown(with: event)
 return
 }

 if let appDelegate = self.target as? AppDelegate {
 appDelegate.toggleUI(self)
 }
 }

 }
 */

// This allows the status item to remain highlighted while the window is open.
// By overriding the `mouseDown` method, we can handle highlighting in "ViewController"
// It's a solution that requires tight coupling, but it's better than removing the action
// and using a local event monitor (which would break holding command to reposition the item)
//
// Reference: https://stackoverflow.com/a/74498437

- (void)mouseDown:(NSEvent *)event
{
    if ((event.modifierFlags & NSEventModifierFlagControl) != 0) {
        [self rightMouseDown:event];
        return;
    }

    ViewController *viewController = (ViewController*)self.target;
    if ([self.target isKindOfClass:[ViewController class]]) {
        [viewController statusItemClicked:self];
    }

}

@end
