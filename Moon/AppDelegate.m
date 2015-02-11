//
//  AppDelegate.m
//  Itsycal2
//
//  Created by Sanjay Madan on 2/4/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "AppDelegate.h"
#import "Itsycal.h"
#import "ItsycalWindow.h"
#import "ViewController.h"
#import "MASShortcutBinder.h"
#import "MASShortcutMonitor.h"

@implementation AppDelegate
{
    NSWindowController  *_wc;
    ViewController      *_vc;
}

+ (void)initialize
{
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        kPinItsycal:   @(NO),
        kShowWeeks:    @(NO),
        kWeekStartDOW: @0 // Sun=0, Mon=1,... (MoCalendar.h)
    }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Register keyboard shortcut.
    [[MASShortcutBinder sharedBinder] bindShortcutWithDefaultsKey:kKeyboardShortcut toAction:^{
         [_vc keyboardShortcutActivated];
     }];
    
    _vc = [ViewController new];
    _wc = [[NSWindowController alloc] initWithWindow:[ItsycalWindow  new]];
    _wc.contentViewController = _vc;
    _wc.window.delegate = _vc;
    [_wc showWindow:nil];
    
    [self loadMenuExtra];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [self removeMenuExtra];
    [[MASShortcutMonitor sharedMonitor] unregisterAllShortcuts];
}

#pragma mark -
#pragma mark MenuExtra

// Adapted from MenuMeters source.
// www.ragingmenace.com/software/menumeters/

// Routines to handle adding and remove menu extras in HIServices (from ASM source)
int CoreMenuExtraGetMenuExtra(CFStringRef identifier, void *menuExtra);
int CoreMenuExtraAddMenuExtra(CFURLRef path, int position, int whoCares, int whoCares2, int whoCares3, int whoCares4);
int CoreMenuExtraRemoveMenuExtra(void *menuExtra, int whoCares);

// How long to wait for Extras to add once CoreMenuExtraAddMenuExtra returns?
static const int kWaitForExtraLoadMicroSec     = 10000000;
static const int kWaitForExtraLoadStepMicroSec = 250000;

- (void)loadMenuExtra
{
    if ([self isMenuExtraLoaded]) {
        NSLog(@"Menuextra is already loaded!");
        return;
    }
    
    NSURL *menuCrackerURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"MenuCracker" ofType:@"menu"]];
    NSURL *menuExtraURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"ItsycalExtra" ofType:@"menu"]];
    
    // Load the crack. With MenuCracker 2.x multiple loads are allowed, so
    // we don't care if someone else has the MenuCracker 2.x bundle loaded.
    // Plus, since MC 2.x does dodgy things with the load we can't actually
    // find out if its loaded.
    CoreMenuExtraAddMenuExtra((__bridge CFURLRef)menuCrackerURL, 0, 0, 0, 0, 0);
    
    // Load actual request
    CoreMenuExtraAddMenuExtra((__bridge CFURLRef)menuExtraURL, 0, 0, 0, 0, 0);
    
    // Wait for the item to load.
    int microSlept = 0;
    while (![self isMenuExtraLoaded] && (microSlept < kWaitForExtraLoadMicroSec)) {
        microSlept += kWaitForExtraLoadStepMicroSec;
        usleep(kWaitForExtraLoadStepMicroSec);
    }
    
    // Try again if needed.
    if (![self isMenuExtraLoaded]) {
        microSlept = 0;
        CoreMenuExtraAddMenuExtra((__bridge CFURLRef)menuExtraURL, 0, 0, 0, 0, 0);
        while (![self isMenuExtraLoaded] && (microSlept < kWaitForExtraLoadMicroSec)) {
            microSlept += kWaitForExtraLoadStepMicroSec;
            usleep(kWaitForExtraLoadStepMicroSec);
        }
    }
    
    // At this point, either the MenuExtra is loaded or it isn't.
    // If not, Itsycal will run as a normal NSStatusItem app.
}

- (BOOL)isMenuExtraLoaded
{
    void *anExtra = NULL;
    if (!CoreMenuExtraGetMenuExtra((__bridge CFStringRef)kItsycalExtraBundleID, &anExtra) && anExtra) {
        return YES;
    }
    return NO;
}

- (void)removeMenuExtra
{
    void *anExtra = NULL;
    if (!CoreMenuExtraGetMenuExtra((__bridge CFStringRef)kItsycalExtraBundleID, &anExtra) && anExtra) {
        CoreMenuExtraRemoveMenuExtra(anExtra, 0);
    }
}

@end