//
//  ViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/4/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import <os/log.h>
#import <AudioToolbox/AudioToolbox.h>
#import "ViewController.h"
#import "Itsycal.h"
#import "PeteWindow.h"
#import "DatePickerVC.h"
#import "SBCalendar.h"
#import "EventViewController.h"
#import "PrefsVC.h"
#import "PrefsGeneralVC.h"
#import "PrefsAppearanceVC.h"
#import "PrefsAboutVC.h"
#import "MoButton.h"
#import "MoVFLHelper.h"
#import "MoUtils.h"
#import "Sparkle/SUUpdater.h"
#import "Things3.h"

@implementation ViewController
{
    EventCenter   *_ec;
    MoCalendar    *_moCal;
    NSCalendar    *_nsCal;
    NSStatusItem  *_statusItem;
    MoButton      *_btnAdd, *_btnCal, *_btnOpt, *_btnPin;
    NSWindowController    *_prefsWC;
    AgendaViewController  *_agendaVC;
    NSDateFormatter       *_iconDateFormatter;
    NSTimeInterval         _inactiveTime;
    NSDictionary          *_filteredEventsForDate;
    NSTimer   *_timer;
    NSString  *_clockFormat;
    BOOL       _clockUsesSeconds;
    BOOL       _clockUsesTime;
    BOOL       _shouldShowMeetingIndicator;
    NSRect     _screenFrame;
    NSPopover *_newEventPopover;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kShowEventDays];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMenuBarIconType];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kShowMonthInIcon];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kShowDayOfWeekInIcon];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kShowDaysWithNoEventsInAgenda];
    [[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kClockFormat];
}

#pragma mark -
#pragma mark View lifecycle

- (void)loadView
{
    // View controller content view
    NSView *v = [NSView new];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.wantsLayer = YES;
    v.layer.cornerRadius = 16;
    v.layer.cornerCurve = kCACornerCurveContinuous;

    NSVisualEffectView *ev = [NSVisualEffectView new];
    ev.frame = v.bounds;
    ev.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    ev.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    ev.material = NSVisualEffectMaterialPopover;
    ev.state = NSVisualEffectStateActive;

    [v addSubview:ev];

    NSView *innerStroke = [NSView new];
    innerStroke.frame = v.bounds;
    innerStroke.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    innerStroke.wantsLayer = YES;
    innerStroke.layer.borderColor = [NSColor.whiteColor colorWithAlphaComponent:0.2].CGColor;
    innerStroke.layer.borderWidth = 1;
    innerStroke.layer.cornerRadius = v.layer.cornerRadius;
    innerStroke.layer.cornerCurve = v.layer.cornerCurve;

    [v addSubview:innerStroke];

    // MoCalendar
    _moCal = [MoCalendar new];
    _moCal.delegate = self;
    _moCal.target = self;
    _moCal.doubleAction = @selector(addCalendarEvent:);
    [v addSubview:_moCal];

    // Convenience function to config buttons.
    MoButton* (^btn)(NSString*, NSString*, NSString*, SEL) = ^MoButton* (NSString *imageName, NSString *tip, NSString *key, SEL action) {
        MoButton *btn = [MoButton new];
        [btn setTarget:self];
        [btn setAction:action];
        [btn setToolTip:tip];
        [btn setImage:[NSImage imageNamed:imageName]];
        [btn setAlternateImage:NULL];
        [btn setKeyEquivalent:key];
        [btn setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
        [btn setContentTintColor:NSColor.secondaryLabelColor];
        [v addSubview:btn];
        return btn;
    };

    // Add event, Calendar.app, and Options buttons
    _btnAdd = btn(@"btnAdd", NSLocalizedString(@"New Event   ⌘N", @""), @"n", @selector(addCalendarEvent:));
    _btnCal = btn(@"btnCal", NSLocalizedString(@"Open Calendar   ⌘O", @""), @"o", @selector(showCalendarApp:));
    _btnOpt = btn(@"btnOpt", NSLocalizedString(@"Options", @""), @"", @selector(showOptionsMenu:));
    _btnPin = btn(@"btnPin", NSLocalizedString(@"Pin Itsycal   P", @""), @"p", @selector(pin:));
    _btnPin.keyEquivalentModifierMask = 0;
    [_btnPin setButtonType:NSButtonTypeToggle];
    
    // Agenda
    _agendaVC = [AgendaViewController new];
    _agendaVC.delegate = self;
    _agendaVC.identifier = @"AgendaVC";
    NSView *agenda = _agendaVC.view;
    [v addSubview:agenda];

    // Constraints
    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:v metrics:nil views:NSDictionaryOfVariableBindings(_moCal, _btnAdd, _btnCal, _btnOpt, _btnPin, agenda)];
    [vfl :@"H:|-9-[_moCal]-9-|"];
    [vfl :@"H:|[agenda]|"];
    [vfl :@"H:|-8-[_btnAdd]-(>=0)-[_btnPin]-6-[_btnCal]-6-[_btnOpt]-8-|" :NSLayoutFormatAlignAllCenterY];
    [vfl :@"V:|-16-[_moCal]-6-[agenda]-6-[_btnOpt(22)]-8-|"];

    self.view = v;
}

- (void)viewDidLoad
{
    // The order of the statements is important! Subsequent statments
    // depend on previous ones.
    
    _iconDateFormatter = [NSDateFormatter new];
    _iconDateFormatter.formattingContext = NSFormattingContextStandalone;
    _iconDateFormatter.calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601];
    _inactiveTime = 0;

    // Calendar is 'autoupdating' so it handles timezone changes properly.
    _nsCal = [NSCalendar autoupdatingCurrentCalendar];
    _agendaVC.nsCal = _nsCal;
    
    MoDate today = [self todayDate];
    _moCal.todayDate = today;
    _moCal.selectedDate = today;
    
    [self createStatusItem];
    
    _ec = [[EventCenter alloc] initWithCalendar:_nsCal delegate:self];
    
    TooltipViewController *tooltipVC = [TooltipViewController new];
    tooltipVC.tooltipDelegate = self;
    _moCal.tooltipVC = tooltipVC;

    [self updateTimer];
    
    // Now that everything else is set up, we file for notifications.
    // Some of the notification handlers rely on stuff we just set up.
    [self fileNotifications];

    [_moCal bind:@"showWeeks" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowWeeks] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"showEventDots" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowEventDots] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"useColoredDots" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kUseColoredDots] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"highlightedDOWs" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kHighlightedDOWs] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"weekStartDOW" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kWeekStartDOW] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_moCal bind:@"doNotDrawOutlineAroundCurrentMonth" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kDoNotDrawOutlineAroundCurrentMonth] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];
    [_agendaVC bind:@"showLocation" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:kShowLocation] options:@{NSContinuouslyUpdatesValueBindingOption: @(YES)}];

    // A very ugly and questionable hack. Maybe it doesn't work. It
    // shouldn't work. But I think it might. Somehow prevents(?!?)
    // defaults from temporarily changing to NULL and then reverting
    // back after the first access. The bug seems random and hard to
    // replicate so I don't know if (or why) this works. The idea is
    // a bogus first access will prevent the bug from happening when
    // the user changes defaults the first time.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:@"WakeUpUserDefaults"];
    [defaults synchronize];
    [defaults removeObjectForKey:@"WakeUpUserDefaults"];
    [defaults synchronize];
}

- (void)viewWillAppear
{
    [super viewWillAppear];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _btnPin.state = [defaults boolForKey:kPinItsycal] ? NSControlStateValueOn : NSControlStateValueOff;
    [self updatePinColor];
    _moCal.showWeeks = [defaults boolForKey:kShowWeeks];
    _moCal.doNotDrawOutlineAroundCurrentMonth = [defaults boolForKey:kDoNotDrawOutlineAroundCurrentMonth];

    [self.itsycalWindow makeFirstResponder:_moCal];
}

#pragma mark -
#pragma mark Keyboard & button actions

- (void)keyDown:(NSEvent *)theEvent
{
    NSString *charsIgnoringModifiers = [theEvent charactersIgnoringModifiers];
    if (charsIgnoringModifiers.length != 1) return;
    NSUInteger flags = [theEvent modifierFlags];
    BOOL noFlags = !(flags & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl));
    BOOL cmdFlag = (flags & NSEventModifierFlagCommand) &&  !(flags & (NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl));
    BOOL cmdOptFlag = (flags & NSEventModifierFlagCommand) && (flags & NSEventModifierFlagOption) &&  !(flags & (NSEventModifierFlagShift | NSEventModifierFlagControl));
    BOOL cmdShiftFlag = (flags & NSEventModifierFlagCommand) && (flags & NSEventModifierFlagShift) &&  !(flags & (NSEventModifierFlagOption | NSEventModifierFlagControl));
    unichar keyChar = [charsIgnoringModifiers characterAtIndex:0];
    
    if (keyChar == 'w' && noFlags) {
        [[NSUserDefaults standardUserDefaults] setBool:!_moCal.showWeeks forKey:kShowWeeks];
    }
    else if (keyChar == '.' && noFlags) {
        [[NSUserDefaults standardUserDefaults] setBool:!_agendaVC.showLocation forKey:kShowLocation];
    }
    else if (keyChar == ',' && cmdFlag) {
        [self showPrefs:self];
    }
    else if (keyChar == 'T' && cmdShiftFlag) {
        [self showDatePickerPopover:self];
    }
    else if (keyChar == 'r' && cmdOptFlag) {
        [_ec refresh];
    }
    else if (keyChar == 'j' && cmdFlag) {
        if (![_agendaVC clickFirstActiveZoomButton]) NSBeep();
    }
    else {
        [super keyDown:theEvent];
    }
}

- (void)addCalendarEvent:(id)sender
{
    // Close popover if it's already showing
    if (_newEventPopover.shown) {
        [_newEventPopover close];
        // If sender is _moCal, we are here because
        //  the user double-clicked on a date. We want
        //  to open the popover at that date. If the
        //  popover is already open, we close it and
        //  then re-open it at the double-clicked date.
        // If sender is NOT _moCal, we are here because
        //  the user clicked the New Event button. This
        //  is a toggle button, so if the popover is
        //  already open, we close it and return.
        if (sender != _moCal) return;
    }
    
    // Was prefs window open in the past and then hidden when
    // app became inactive? This prevents it from reappearing.
    [self.prefsWC close];
    
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    
    if (_ec.calendarAccessGranted == NO) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = NSLocalizedString(@"Calendar access was denied.", @"");
        alert.informativeText = NSLocalizedString(@"Itsycal is more useful when you allow it to add events to your calendars. You can change this setting in System Settings › Security & Privacy › Privacy.", @"");
        [alert runModal];
        return;
    }
    
    // Confirm that there are calendars which can be modified.
    BOOL atLeastOneModifiableCalendar = NO;
    for (id obj in [_ec sourcesAndCalendars]) {
        if ([obj isKindOfClass:[CalendarInfo class]] && 
            ((CalendarInfo *)obj).calendar.allowsContentModifications) {
            atLeastOneModifiableCalendar = YES;
            break;
        }
    }
    if (atLeastOneModifiableCalendar == NO) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = NSLocalizedString(@"There are no modifiable calendars.", @"");
        alert.informativeText = NSLocalizedString(@"Itsycal cannot create a new event unless there is at least one calendar you have permission to modify.", @"");
        [alert runModal];
        return;
    }

    if (!_newEventPopover) {
        _newEventPopover = [NSPopover new];
        _newEventPopover.animates = NO;
        _newEventPopover.delegate = self;
    }
    EventViewController *eventVC = [EventViewController new];
    eventVC.ec = _ec;
    eventVC.enclosingPopover = _newEventPopover;
    eventVC.cal = _nsCal;
    eventVC.title = @"";
    eventVC.calSelectedDate = MakeNSDateWithDate(_moCal.selectedDate, _nsCal);
    
    _newEventPopover.contentViewController = eventVC;
    _newEventPopover.appearance = NSApp.effectiveAppearance;
    [_newEventPopover showRelativeToRect:_btnAdd.bounds ofView:_btnAdd preferredEdge:NSRectEdgeMinX];
}

- (void)showCalendarApp:(id)sender
{
    [self showCalendarAppAtDate:MakeNSDateWithDate(_moCal.selectedDate, _nsCal) dayView:NO];
}

- (void)showCalendarAppAtDate:(NSDate *)date dayView:(BOOL)dayView
{
    // Determine the default calendar app.
    // See: support.busymac.com/help/21535-busycal-url-handler
    
    CFStringRef strRef = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, CFSTR("ics"), kUTTypeData);
    CFStringRef bundleID = LSCopyDefaultRoleHandlerForContentType(strRef, kLSRolesEditor);
    CFRelease(strRef);
    NSString *defaultCalendarAppBundleID = CFBridgingRelease(bundleID);
    
    // Use URL scheme to open BusyCal or Fantastical2 on the
    // date selected in our calendar.
    
    if ([defaultCalendarAppBundleID isEqualToString:@"com.busymac.busycal2"] ||
        [defaultCalendarAppBundleID isEqualToString:@"com.busymac.busycal3"]) {
        [self showCalendarAppWithURLScheme:@"busycalevent://date" date:date];
        return;
    }
    else if ([defaultCalendarAppBundleID isEqualToString:@"com.flexibits.fantastical2.mac"]) {
        [self showCalendarAppWithURLScheme:@"x-fantastical2://show/calendar" date:date];
        return;
    }
    
    // Use the Scripting Bridge to open Calendar.app on the
    // date selected in our calendar.
    
    SBCalendarApplication *calendarApp = [SBApplication applicationWithBundleIdentifier:@"com.apple.iCal"];
    if (calendarApp == nil) {
        NSString *message = NSLocalizedString(@"The Calendar application could not be found.", @"Alert box message when we fail to launch the Calendar application");
        NSAlert *alert = [NSAlert new];
        alert.messageText = message;
        alert.alertStyle = NSAlertStyleCritical;
        [alert runModal];
        return;
    }

    // HACK: Navigate Calendar.app to `date` AFTER A DELAY. Since around
    // macOS 14.5, Calendar.app seems to remember the previous date it was set
    // to and automatically reverts to it after activation. By waiting, we
    // allow Calendar.app to revert and then we navigate properly to `date`.
    [calendarApp activate]; // bring to foreground
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [calendarApp activate]; // bring to foreground
        if (dayView) [calendarApp switchViewTo:SBCalendarCALViewTypeForScriptingDayView];
        [calendarApp viewCalendarAt:date];
    });
}

- (void)showCalendarAppWithURLScheme:(NSString *)urlScheme date:(NSDate *)date
{
    // url is of the form: urlScheme/yyyy-MM-dd
    // For example: x-fantastical2://show/calendar/2011-05-22
    NSDateComponents *comp = [_nsCal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    NSString *url = [NSString stringWithFormat:@"%@/%04zd-%02zd-%02zd", urlScheme, comp.year, comp.month, comp.day];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
}

- (void)showOptionsMenu:(id)sender
{
    NSMenu *optMenu = [[NSMenu alloc] initWithTitle:@"Options Menu"];
    NSInteger i = 0;
    NSString *prefsString = NSLocalizedString(@"Preferences…", @"");
    if (@available(macOS 13.0, *)) {
        prefsString = NSLocalizedString(@"Settings…", @"");
    }

    [optMenu insertItemWithTitle:NSLocalizedString(@"About Itsycal", @"") action:@selector(showAbout:) keyEquivalent:@"" atIndex:i++];
    [optMenu insertItemWithTitle:NSLocalizedString(@"Check for Updates…", @"") action:@selector(checkForUpdates:) keyEquivalent:@"" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:NSLocalizedString(@"Go to Date…", @"") action:@selector(showDatePickerPopover:) keyEquivalent:@"T" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:prefsString action:@selector(showPrefs:) keyEquivalent:@"," atIndex:i++];
    [optMenu insertItemWithTitle:NSLocalizedString(@"Date & Time…", @"") action:@selector(openDateAndTimePrefs:) keyEquivalent:@"" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:NSLocalizedString(@"Help…", @"") action:@selector(navigateToHelp:) keyEquivalent:@"" atIndex:i++];
    [optMenu insertItem:[NSMenuItem separatorItem] atIndex:i++];
    [optMenu insertItemWithTitle:NSLocalizedString(@"Quit Itsycal", @"") action:@selector(terminate:) keyEquivalent:@"q" atIndex:i++];
    NSPoint pt = NSOffsetRect(_btnOpt.frame, -5, -10).origin;
    [optMenu popUpMenuPositioningItem:nil atLocation:pt inView:self.view];
}

- (void)pin:(id)sender
{
    BOOL pin = _btnPin.state == NSControlStateValueOn;
    [[NSUserDefaults standardUserDefaults] setBool:pin forKey:kPinItsycal];
    [self updatePinColor];
}

- (void)updatePinColor
{
    BOOL pin = _btnPin.state == NSControlStateValueOn;
    [_btnPin setContentTintColor:pin ? NSColor.controlAccentColor : NSColor.secondaryLabelColor];
}

- (NSWindowController *)prefsWC
{
    if (!_prefsWC) {
        // VCs for each tab in prefs panel.
        PrefsGeneralVC *prefsGeneralVC = [PrefsGeneralVC new];
        PrefsAppearanceVC *prefsAppearanceVC = [PrefsAppearanceVC new];
        PrefsAboutVC *prefsAboutVC = [PrefsAboutVC new];
        prefsGeneralVC.ec = _ec;
        prefsGeneralVC.title = NSLocalizedString(@"General", @"General prefs tab label");
        prefsAppearanceVC.title = NSLocalizedString(@"Appearance", @"Appearance prefs tab label");
        prefsAboutVC.title = NSLocalizedString(@"About", @"About prefs tab label");
        // prefsVC is the container VC the tab VCs.
        PrefsVC *prefsVC = [PrefsVC new];
        prefsVC.childViewControllers = @[prefsGeneralVC, prefsAppearanceVC, prefsAboutVC];
        // Create prefs WC.
        NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSZeroRect styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];
        _prefsWC = [[NSWindowController alloc] initWithWindow:panel];
        _prefsWC.contentViewController = prefsVC;
        _prefsWC.window.contentView.wantsLayer = YES;
        [_prefsWC.window center];
    }
    return _prefsWC;
}

- (PrefsVC *)prefsVC
{
    return (PrefsVC *)self.prefsWC.contentViewController;
}

- (void)showAbout:(id)sender
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [_newEventPopover close];
    [self.prefsVC showAbout];
    [self.prefsWC showWindow:self];
}

- (void)showPrefs:(id)sender
{
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [_newEventPopover close];
    [self.prefsVC showPrefs];
    [self.prefsWC showWindow:self];
}

- (void)checkForUpdates:(id)sender
{
    [[SUUpdater sharedUpdater] checkForUpdates:self];
}

- (void)openDateAndTimePrefs:(id)sender
{
    NSURL *url = nil;
    
    if (@available(macOS 13, *)) {
        url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.Date-Time-Settings.extension"];
    } else {
        NSString *path = @"/System/Library/PreferencePanes/DateAndTime.prefPane";
        url = [NSURL fileURLWithPath:path];
    }
    
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)navigateToHelp:(id)sender
{
    NSURL *url = [NSURL URLWithString:@"https://www.mowglii.com/itsycal/help.html"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)showDatePickerPopover:(id)sender
{
    NSView *positionView = [[NSView alloc] initWithFrame:NSMakeRect(NSWidth(self.view.frame)/2 - 5, NSHeight(self.view.frame) - 70, 10, 10)];
    [self.view addSubview:positionView positioned:NSWindowBelow relativeTo:nil];

    NSPopover *datePickerPopover = [NSPopover new];

    DatePickerVC *vc = [[DatePickerVC alloc] initWithMoCal:_moCal nsCal:_nsCal];
    vc.enclosingPopover = datePickerPopover;

    datePickerPopover.contentViewController = vc;
    datePickerPopover.behavior = NSPopoverBehaviorTransient;
    datePickerPopover.appearance = NSApp.effectiveAppearance;
    [datePickerPopover showRelativeToRect:positionView.bounds ofView:positionView preferredEdge:NSRectEdgeMinY];

    // Move the positioning view to trick the popover to hide it's arrow.
    // https://nyrra33.com/2018/08/08/a-small-trick-to-hide-nspopovers-arrow/
    positionView.frame = NSMakeRect(0, -200, 10, 10);
}

#pragma mark -
#pragma mark Menubar item

- (void)createStatusItem
{
    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    _statusItem.button.target = self;
    _statusItem.button.action = @selector(statusItemClicked:);
    [_statusItem.button sendActionOn:NSEventMaskLeftMouseDown];
    [(NSButtonCell *)_statusItem.button.cell setHighlightsBy:NSNoCellMask];

    // Remember item position in menubar. (@pskowronek (Github))
    [_statusItem setAutosaveName:@"ItsycalStatusItem"];

    [self clockFormatDidChange];
    [self updateMenubarIcon];
    [self positionItsycalWindow];

    // Notification for when status item view moves
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusItemMoved:) name:NSWindowDidMoveNotification object:_statusItem.button.window];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(statusItemMoved:) name:NSWindowDidResizeNotification object:_statusItem.button.window];
}

- (void)updateStatusItemFont
{
    static NSFontDescriptor *origFontDesc = nil;
    static NSFontDescriptor *monoFontDesc = nil;
    // Use monospaced font if user sets custom clock format that
    // uses seconds so the status item doesn't move distractingly
    // every second. It still moves each minute if showing time.
    // We modify the default font with a font descriptor instead
    // of using +monospacedDigitSystemFontOfSize:weight: because
    // we get slightly darker looking ':' characters this way.
    if (_clockUsesSeconds) {
        if (!monoFontDesc) {
            origFontDesc = [_statusItem.button.font fontDescriptor];
            monoFontDesc = [origFontDesc fontDescriptorByAddingAttributes:@{NSFontFeatureSettingsAttribute: @[@{NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType), NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}]}];
        }
        _statusItem.button.font = [NSFont fontWithDescriptor:monoFontDesc size:0];
    }
    else if (origFontDesc) {
        _statusItem.button.font = [NSFont fontWithDescriptor:origFontDesc size:0];
    }
}

- (void)removeStatusItem
{
    if (_statusItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidMoveNotification object:_statusItem.button.window];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSWindowDidResizeNotification object:_statusItem.button.window];
        // Let 10.12+ remember item position and remove item when app is terminated.
        // If we remove item ourselves, autosavename is deleted from user defaults.
        // (@pskowronek (Github))
        // DO NOT do this:
        //   [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
        //   _statusItem = nil;
    }
}

- (NSString *)iconText
{
    NSString *iconText;
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kShowMonthInIcon] || [[NSUserDefaults standardUserDefaults] boolForKey:kShowDayOfWeekInIcon]) {
        NSMutableString *template = @"d".mutableCopy;
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kShowMonthInIcon]) {
            [template appendString:@"MMM"];
        }
        if ([[NSUserDefaults standardUserDefaults] boolForKey:kShowDayOfWeekInIcon]) {
            [template appendString:@"EEE"];
        }
        [_iconDateFormatter setDateFormat:[NSDateFormatter dateFormatFromTemplate:template options:0 locale:[NSLocale currentLocale]]];
        iconText = [_iconDateFormatter stringFromDate:[NSDate new]];
    } else {
        iconText = [NSString stringWithFormat:@"%zd", _moCal.todayDate.day];
    }
    
    if (iconText == nil) {
        iconText = @"!!";
    }
    return iconText;
}

- (void)updateMenubarIcon
{
    NSString *accessibilityTitle = @"Itsycal";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL hideIcon = [defaults boolForKey:kHideIcon];
    if (hideIcon) {
        if ([defaults boolForKey:kShowMeetingIndicator] && _shouldShowMeetingIndicator) {
            NSImage *meetIndicator = [NSImage imageNamed:@"meetSolid"];
            meetIndicator.template = YES;
            _statusItem.button.image = meetIndicator;
            _statusItem.button.imagePosition = NSImageLeft;
        }
        else {
            _statusItem.button.image = nil;
            _statusItem.button.imagePosition = NSNoImage;
        }
    }
    else {
        NSString *iconText = [self iconText];
        accessibilityTitle = [accessibilityTitle stringByAppendingFormat:@", %@", iconText];
        _statusItem.button.image = [self iconImageForText:iconText];
        _statusItem.button.imagePosition = _clockFormat ? NSImageLeft : NSImageOnly;
    }
    if (_clockFormat) {
        [_iconDateFormatter setDateFormat:_clockFormat];
        // After updating the Xcode Deployment Target to macOS 10.14 from
        // macOS 10.12, the button title renders slightly higher than it should
        // on Mojave and slightly lower than it should on Catalina.
        // As a workaround, instead of setting the title with an NSString,
        // provide an NSAttributedString with a baseline offset.
        CGFloat scaleFactor = NSScreen.mainScreen.backingScaleFactor ?: 2.0;
        CGFloat baselineOffset = -1.0 / scaleFactor;
        if (@available(macOS 10.15, *)) {
            baselineOffset = 0.5;
        }
        if (@available(macOS 11, *)) {
            baselineOffset = 0;
        }
        if ([defaults objectForKey:kBaselineOffset]) {
            baselineOffset = [defaults floatForKey:kBaselineOffset];
            baselineOffset = MIN(2.0, MAX(-2.0, baselineOffset));
        }
        NSString *buttonText = [_iconDateFormatter stringFromDate:[NSDate new]];
        accessibilityTitle = [accessibilityTitle stringByAppendingFormat:@", %@", buttonText];
        if (!hideIcon) {
            // Prepend a space to _clockFormat text to separate it from icon.
            buttonText = [@" " stringByAppendingString:buttonText];
        }
        _statusItem.button.attributedTitle = [[NSAttributedString alloc] initWithString:buttonText attributes:@{NSBaselineOffsetAttributeName: @(baselineOffset)}];
    }
    _statusItem.button.accessibilityTitle = accessibilityTitle;
    [self adjustStatusItemWidthIfNecessary];
}

- (void)adjustStatusItemWidthIfNecessary
{
    // Set a fixed width for _statusItem if it uses a clock format
    // but doesn't show seconds. This prevents the _statusItem from
    // slightly shifting in the menubar when time changes due to the
    // different widths of digits in the proportional font.
    static NSStatusBarButton *dummyButton = nil;
    if (_clockFormat && !_clockUsesSeconds) {
        if (!dummyButton) {
            NSFontDescriptor *monoFontDesc = [[_statusItem.button.font fontDescriptor] fontDescriptorByAddingAttributes:@{NSFontFeatureSettingsAttribute: @[@{NSFontFeatureTypeIdentifierKey: @(kNumberSpacingType), NSFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}]}];
            dummyButton = [NSStatusBarButton new];
            dummyButton.font = [NSFont fontWithDescriptor:monoFontDesc size:0];
        }
        // Same logic as -updateMenubarIcon to set up dummyButton
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:kHideIcon]) {
            if ([defaults boolForKey:kShowMeetingIndicator] && _shouldShowMeetingIndicator) {
                dummyButton.image = [NSImage imageNamed:@"meetSolid"];
                dummyButton.imagePosition = NSImageLeft;
            }
            else {
                dummyButton.image = nil;
                dummyButton.imagePosition = NSNoImage;
            }
        }
        else {
            dummyButton.image = _statusItem.button.image;
            dummyButton.imagePosition = _clockFormat ? NSImageLeft : NSImageOnly;
        }
        dummyButton.title = _statusItem.button.title;
        [dummyButton sizeToFit];
        _statusItem.length = NSWidth(dummyButton.frame) + 2;
        if (@available(macOS 11, *)) {
            _statusItem.length = NSWidth(dummyButton.frame) - 8;
        }
        //os_log(OS_LOG_DEFAULT, "[%@] %@ --> %.0f, %.0f", [self iconText], _statusItem.button.title,
        //      _statusItem.button.frame.size.width, _statusItem.button.image.size.width);
    }
    else {
        _statusItem.length = NSVariableStatusItemLength;
        //os_log(OS_LOG_DEFAULT, "VARIABLE LENGTH ITEM");
    }
}

- (NSImage *)iconImageForText:(NSString *)text
{
    if (text == nil) text = @"!";

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSInteger menuBarIconType = [defaults integerForKey:kMenuBarIconType];
    if (menuBarIconType == 2) {
        return [NSImage imageNamed:@"menubaricon2"];
    }
    if (menuBarIconType == 3) {
        return [NSImage imageNamed:@"menubaricon3"];
    }

    // Does user want outline icon or solid icon?
    BOOL outline = menuBarIconType == 1;

    // Should we show the virtual meeting indicator?
    BOOL meeting = [defaults boolForKey:kShowMeetingIndicator] && _shouldShowMeetingIndicator;

    // Return cached icon if one is available.
    NSString *iconName = [NSString stringWithFormat:@"%@ %@ %@", text, outline ? @"outline" : @"solid", meeting ? @"meeting" : @"nomeeting"];
    NSImage *iconImage = [NSImage imageNamed:iconName];
    if (iconImage != nil) return iconImage;

    // Measure text width
    CGFloat fontSize = 11.5;
    NSFont *font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightBold];
    CGRect textRect = [[[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: font}] boundingRectWithSize:CGSizeMake(999, 999) options:0 context:nil];

    // Icon width is at least 17 pts with 4 pt inside margins.
    CGFloat meetingWidth = meeting ? 18 : 0;
    CGFloat width = MAX(4 + meetingWidth + ceilf(NSWidth(textRect)) + 4, 17);
    CGFloat height = 16;
    iconImage = [NSImage imageWithSize:NSMakeSize(width, height) flipped:NO drawingHandler:^BOOL (NSRect rect) {
        
        CGFloat meetingOffset = meeting ? 9 : 0;
        
        // Draw meeting indicator if necessary;
        if (meeting) {
            NSString *imageName = outline ? @"meetSolid" : @"meetOutline";
            [[NSImage imageNamed:imageName] drawAtPoint:NSMakePoint(3, 0) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
        }

        // Draw text.
        if (outline) CGContextSetShouldSmoothFonts(NSGraphicsContext.currentContext.CGContext, false);
        NSFontWeight fontWeight = outline ? NSFontWeightSemibold : NSFontWeightBold;
        NSMutableParagraphStyle *pstyle = [NSMutableParagraphStyle new];
        pstyle.alignment = NSTextAlignmentCenter;
        [text drawInRect:NSOffsetRect(rect, meetingOffset, -1) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:fontSize weight:fontWeight], NSParagraphStyleAttributeName: pstyle}];
        
        // Draw rounded rect.
        [NSColor.blackColor set];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext.currentContext setCompositingOperation:NSCompositingOperationXOR];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3] fill];
        if (outline) [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 1, 1) xRadius:2 yRadius:2] fill];
        [NSGraphicsContext restoreGraphicsState];

        return YES;
    }];
    [iconImage setTemplate:YES];
    [iconImage setName:iconName];
    return iconImage;
}

- (void)positionItsycalWindow
{
    NSRect statusItemFrame = [_statusItem.button.window convertRectToScreen:_statusItem.button.frame];

    // Hack alert:
    // MacOS 11 does not report the correct frame for _statusItem.button
    // if its length is adjusted (see -adjustStatusItemWidthIfNecessary).
    // As a result, this method positions the window *uncentered* below
    // the status item. Adjust the frame with a value empirically
    // determined to make the window appear centered.
    if (@available(macOS 11.0, *)) {
        if (_statusItem.length != NSVariableStatusItemLength) {
            statusItemFrame.size.width += 15;
        }
    }
    
    // Hack alert:
    // Which screen is the status item on? I'd like to just use
    // _statusItem.button.window.screen, but that property is nil
    // when the user is working with a full screen app: the menu
    // bar is hidden and so the status item is offscreen.
    // Alternatively, I'd like to use [NSScreen mainscreen], but
    // that method seems to give the wrong answer when the user
    // is working on an external monitor with a full screen app.
    // So... I iterate over all the screens and see which one
    // contains the statusItem's origin. I adjust the origin
    // down a bit to account for the case where the menu bar is
    // hidden (as it is when an app is in fullscreen mode) as
    // the system *currently* places the status item just above
    // its screen. This isn't documented behavior and so might
    // not work in the future.
    NSScreen *statusItemScreen = [NSScreen mainScreen];
    NSPoint testPoint = statusItemFrame.origin;
    testPoint.y -= 100;
    for (NSScreen *screen in [NSScreen screens]) {
        if (NSPointInRect(testPoint, screen.frame)) {
            statusItemScreen = screen;
            break;
        }
    }
    _screenFrame = statusItemScreen.frame;
    CGFloat screenMaxX = NSMaxX(statusItemScreen.frame);

    // Constrain the menu item's frame to be no higher than the top
    // of the screen. For some reason, when an app is in fullscreen
    // mode sometimes the menu item frame is reported to be *above*
    // the top of the screen. The result is that the calendar is
    // shown clipped at the top. Prevent that by constraining the
    // top of the menu item to be at most the top of the screen.
    statusItemFrame.origin.y = MIN(statusItemFrame.origin.y, NSMaxY(statusItemScreen.frame));
    
    // So that agenda height can adjust to fit screen if needed.
    [_agendaVC.view setNeedsLayout:YES];

    [self.itsycalWindow positionRelativeToRect:statusItemFrame screenMaxX:screenMaxX];
}

- (void)statusItemMoved:(NSNotification *)note
{
    // Reposition itsycalWindow so that it remains
    // centered under _statusItemView.
    //
    // We do the repositioning after a slight delay to account
    // for the following scenario:
    //  - The user has more than one screen.
    //  - Itsycal is visible on one of them.
    //  - The user clicks the menu item on the other screen.
    //
    // In this scenario, this method will be called because the
    // user's click "moved" the status item window from one screen
    // to another. If we repositioned the window immediately, it
    // would be placed on the active screen and the logic in
    // -statusItemClicked: would not be able to know that the click
    // occurred in a different screen from the one where Itsycal
    // was showing. The result would be Itsycal flashing in the
    // new screen (because of this method's repositioning) and then
    // hiding because that's the logic that would execute in the
    // -statusItemClicked: method. The delay let's -menuItemClicked:
    // handle this scenario first.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self positionItsycalWindow];
    });
}

- (void)statusItemClicked:(id)sender
{
    // If there are multiple screens and Itsycal is showing
    // on one and the user clicks the menu item on another,
    // instead of a regular toggle, we want Itsycal to hide
    // from it's old screen and show in the new one.
    // To distinguish screens, we used to use the screen address,
    // but with macOS Big Sur, that is not reliable. Instead,
    // we now use the screen's frame.
    if (!NSEqualRects(self.itsycalWindow.screen.frame, NSScreen.mainScreen.frame)) {
        if ([self.itsycalWindow occlusionState] & NSWindowOcclusionStateVisible) {
            // The slight delay before showing the window in the new
            // position is to allow -windowDidResignKey: to execute
            // first so that it doesn't hide the window we are
            // trying to show.
            [self.itsycalWindow orderOut:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self showItsycalWindow];
            });
            return;
        }
    }
    if ([self.itsycalWindow occlusionState] & NSWindowOcclusionStateVisible) {
        [self hideItsycalWindow];
    }
    else {
        [self showItsycalWindow];
    }
}

#pragma mark -
#pragma mark Window management

- (PeteWindow *)itsycalWindow
{
    return (PeteWindow *)self.view.window;
}

- (void)showItsycalWindow
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateAgenda];
    });

    [[NSApplication sharedApplication] unhideWithoutActivation];
    [self positionItsycalWindow];
    [self.itsycalWindow makeKeyAndOrderFront:self];
    [self.itsycalWindow makeFirstResponder:_moCal];
    [_statusItem.button setHighlighted:YES];
    _inactiveTime = 0;
}

- (void)hideItsycalWindow
{
    if (!_newEventPopover.shown) {
        [self.itsycalWindow orderOut:self];
        [_newEventPopover close];
        [_statusItem.button setHighlighted:NO];
        _inactiveTime = MonotonicClockTime();
    }
}

- (void)cancel:(id)sender
{
    // User pressed 'esc'.
    [self hideItsycalWindow];
}

- (void)windowDidResize:(NSNotification *)notification
{
    [self positionItsycalWindow];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    if (_btnPin.state == NSControlStateValueOff) {
        [self hideItsycalWindow];
    }
}

- (void)windowDidChangeOcclusionState:(NSNotification *)notification
{
    // We have to do this because of the fancy window drawing
    [self.itsycalWindow invalidateShadow];
}

- (void)popoverDidClose:(NSNotification *)notification
{
    if (notification.object == _newEventPopover) {
        _newEventPopover = nil;
    }
}

- (void)keyboardShortcutActivated
{
    // The user hit the keyboard shortcut. This is the same
    // as if the user had clicked the menubar icon.
    [self statusItemClicked:self];
}

- (void)dateURLReceived:(NSDate *)showDate
{
    // We received a URL asking us to show a specific date.
    MoDate selectedDate = MakeDateWithNSDate(showDate, _nsCal);
    _moCal.selectedDate = selectedDate;
    
    // Only "click" the status item if the itsycal window isn't already visible.
    // Otherwise, it would just close.
    if (!([self.itsycalWindow occlusionState] & NSWindowOcclusionStateVisible)) {
        [self statusItemClicked:self];
    }

}

#pragma mark -
#pragma mark AgendaDelegate

- (void)agendaHoveredOverRow:(NSInteger)row
{
    if (row == -1) {
        [_moCal unhighlightCells];
    }
    else if([_agendaVC.events[row] isKindOfClass:EventInfo.class]) {
        EventInfo *info = _agendaVC.events[row];
        MoDate startDate = MakeDateWithNSDate(info.event.startDate, _nsCal);
        MoDate endDate   = MakeDateWithNSDate(info.event.endDate,   _nsCal);
        // Fixup for endDates that are at midnight
        if ([info.event.endDate compare:[_nsCal startOfDayForDate:info.event.endDate]] == NSOrderedSame) {
            endDate = AddDaysToDate(-1, endDate);
        }
        [_moCal highlightCellsFromDate:startDate toDate:endDate withColor:info.event.calendar.color];
    }
}

- (void)agendaWantsToDeleteEvent:(EKEvent *)event
{
    // Was prefs window open in the past and then hidden when
    // app became inactive? This prevents it from reappearing.
    [self.prefsWC close];
    
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    
    // Make a string showing the event title and duration.
    static NSDateIntervalFormatter *durationFormatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        durationFormatter = [NSDateIntervalFormatter new];
        durationFormatter.dateStyle = NSDateIntervalFormatterMediumStyle;
    });
    NSDate *endDate = event.endDate;
    if (event.isAllDay) {
        // EKEvent allDay events go from 12 AM to 12 AM. So, a one-day event
        // will just barely span two days. For example, a one-day event on Aug 4
        // results in a duration of Aug 4-5. By subtracting some time, we get the
        // duration in days we would expect.
        endDate = [_nsCal dateByAddingUnit:NSCalendarUnitHour value:-4 toDate:event.endDate options:0];
        durationFormatter.timeStyle = NSDateIntervalFormatterNoStyle;
    }
    else {
        durationFormatter.timeStyle = NSDateIntervalFormatterShortStyle;
    }
    durationFormatter.timeStyle = event.isAllDay ? NSDateIntervalFormatterNoStyle : NSDateIntervalFormatterShortStyle;
    NSString *title = event.title == nil ? @"" : event.title;
    NSString *duration = [durationFormatter stringFromDate:event.startDate toDate:endDate];
    NSString *eventString = [NSString stringWithFormat:@"%@\n%@", title, duration];

    BOOL eventRepeats = event.hasRecurrenceRules;
    
    // Ask the user to confirm they want to delete this event (or future events).
    NSAlert *alert = [NSAlert new];
    if (eventRepeats == YES) {
        alert.messageText = NSLocalizedString(@"You're deleting an event.", @"");
        alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", eventString, NSLocalizedString(@"Do you want to delete this and all future occurrences of this event, or only the selected occurrence?", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Delete Only This Event", @"")];
        [alert addButtonWithTitle:NSLocalizedString(@"Delete All Future Events", @"")];
    }
    else {
        alert.messageText = NSLocalizedString(@"Are you sure you want to delete this event?", @"");
        alert.informativeText = eventString;
        [alert addButtonWithTitle:NSLocalizedString(@"Delete This Event", @"")];
    }
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
    NSModalResponse response = [alert runModal];
    
    // Return if the user chose 'Cancel'.
    if ((eventRepeats == YES && response == NSAlertThirdButtonReturn) ||
        (eventRepeats == NO && response == NSAlertSecondButtonReturn)) {
        return;
    }
    
    // Delete this event (or future events).
    NSError *error = NULL;
    EKSpan span = (eventRepeats && response == NSAlertSecondButtonReturn) ? EKSpanFutureEvents : EKSpanThisEvent;
    BOOL result = [_ec removeEvent:event span:span error:&error];
    if (result == NO && error != nil) {
        [[NSAlert alertWithError:error] runModal];
    }
}

- (void)agendaShowCalendarAppAtDate:(NSDate *)date
{
    [self showCalendarAppAtDate:date dayView:YES];
}

- (CGFloat)agendaMaxPossibleHeight
{
    return NSHeight(_screenFrame) - NSHeight(_moCal.frame) - 140;
}

#pragma mark -
#pragma mark MoCalendarDelegate

- (void)calendarUpdated:(MoCalendar *)cal
{
    // Attempt to reload cached events. If this works,
    // the display will update fast. Then fetch.
    [_moCal reloadData];
    [_ec fetchEvents];
}

- (void)calendarSelectionChanged:(MoCalendar *)cal
{
    [self updateAgenda];
}

- (NSArray<NSColor *> *)dotColorsForDate:(MoDate)date useColor:(BOOL)useColor
{
    NSArray<EventInfo *> *events = [self eventsForDate:date];
    if (!events || events.count == 0) return nil;
    if (!useColor) return @[];
    NSMutableOrderedSet *colors = [NSMutableOrderedSet new];
    for (EventInfo *eventInfo in events) {
        [colors addObject:eventInfo.event.calendar.color];
        if (colors.count == 3) break;
    }
    switch (colors.count) {
        case 1: return @[colors[0]];
        case 2: return @[colors[0], colors[1]];
        case 3: return @[colors[0], colors[1], colors[2]];
        default: return nil;
    }
}

#pragma mark - Events

- (NSArray *)eventsForDate:(MoDate)date
{
    NSDate *nsDate = MakeNSDateWithDate(date, _nsCal);
    return _filteredEventsForDate[nsDate];
}

- (NSArray *)todosForToday
{
    Things3Application *thingsApp = [SBApplication applicationWithBundleIdentifier:@"com.culturedcode.ThingsMac"];
    Things3List *todayList = [thingsApp.lists objectWithName:@"Today"];
    NSArray *todos = [todayList.toDos get];
    return [todos filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"status == %d", Things3StatusOpen]];
}

- (NSArray *)datesAndEventsForDate:(MoDate)date days:(NSInteger)days
{
    NSMutableArray *datesAndEvents = [NSMutableArray new];
    MoDate endDate = AddDaysToDate(days, date);
    while (CompareDates(date, endDate) < 0) {
        NSDate *nsDate = MakeNSDateWithDate(date, _nsCal);
        NSArray *events = _filteredEventsForDate[nsDate];
        NSArray *todos = [self todosForToday];
        
        if (events != nil) {
            [nsDate setHasNoEvents:NO];
            [datesAndEvents addObject:nsDate];
            [datesAndEvents addObjectsFromArray:events];
        }
        else {
            [nsDate setHasNoEvents:YES];
            if ([[NSUserDefaults standardUserDefaults] boolForKey:kShowDaysWithNoEventsInAgenda]) {
                // If the user wants to show days with no events in the agenda,
                // we need the objects we add to `datesAndEvents` to be
                // annotated so AgendaViewController can handle them
                // appropriately. For the date, we set an associated object.
                // For the event we give it a new EventInfo. Importantly, the
                // EventInfo's `event` property will be nil and we will use
                // this fact in AgendaViewController.
                [datesAndEvents addObject:nsDate];
                [datesAndEvents addObject:[EventInfo new]];
            }
        }
        
        if (CompareDates(date, [self todayDate]) == 0 && todos.count != 0) {
            if ([nsDate hasNoEvents]) {
                [nsDate setHasNoEvents:NO];
                [datesAndEvents addObject:nsDate];
            }
            
            [datesAndEvents addObjectsFromArray:todos];
        }
        
        date = AddDaysToDate(1, date);
    }
    return datesAndEvents;
}

#pragma mark -
#pragma mark EventCenterDelegate

- (void)eventCenterEventsChanged
{
    //os_log(OS_LOG_DEFAULT, "%s", __FUNCTION__);
    _filteredEventsForDate = [_ec filteredEventsForDate];
    [_moCal reloadData];
    [self updateAgenda];
}

- (MoDate)fetchStartDate
{
    return _moCal.firstDate;
}

- (MoDate)fetchEndDate
{
    return AddDaysToDate([self daysToShowInAgenda], _moCal.lastDate);
}

#pragma mark -
#pragma mark Agenda

- (NSInteger)daysToShowInAgenda
{
    NSInteger days = [[NSUserDefaults standardUserDefaults] integerForKey:kShowEventDays];
    days = MIN(MAX(days, 0), 9); // days is in range 0..9
    // days == 8 really means 14; 9 really means 31
    if (days == 8) days = 14; else if (days == 9) days = 31;
    return days;
}

- (void)updateAgenda
{
    NSInteger days = [self daysToShowInAgenda];
    _agendaVC.events = [self datesAndEventsForDate:_moCal.selectedDate days:days];
    [_agendaVC reloadData];
    [self showMeetingIndicatorIfNecessary];
}

#pragma mark -
#pragma mark Time

- (MoDate)todayDate
{
    NSDateComponents *c = [_nsCal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[NSDate new]];
    return MakeDate(c.year, c.month-1, c.day);
}

- (void)resetCalendarToToday
{
    MoDate today = [self todayDate];
    _moCal.todayDate = today;
    _moCal.selectedDate = today;
}

- (void)showMeetingIndicatorIfNecessary
{
    BOOL show = NO;
    NSArray *todayEvents = [self eventsForDate:[self todayDate]];
    for (EventInfo *info in todayEvents) {
        // Show meeting indicator 15 minutes prior to event start until end.
        NSDate *fifteenMinutesPrior = [_nsCal dateByAddingUnit:NSCalendarUnitSecond value:-(15 * 60 + 30) toDate:info.event.startDate options:0];
        if (info.zoomURL && !info.event.isAllDay
            && [fifteenMinutesPrior compare:NSDate.date] == NSOrderedAscending
            && [NSDate.date compare:info.event.endDate] == NSOrderedAscending) {
            show = YES;
            break;
        }
    }
    if (_shouldShowMeetingIndicator != show) {
        _shouldShowMeetingIndicator = show;
        [self updateMenubarIcon];
    }
}

- (float)volumeRelativeToSystemVolumeWithCap:(float)cap
{
    // https://stackoverflow.com/a/8953438/111418
    AudioDeviceID deviceID;
    UInt32 dataSize = sizeof(deviceID);
    AudioObjectPropertyAddress propertyAddress;
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    propertyAddress.mScope    = kAudioObjectPropertyScopeGlobal;
    propertyAddress.mElement  = kAudioObjectPropertyElementMaster;

    OSStatus result = AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0, NULL, &dataSize, &deviceID);

    if (kAudioHardwareNoError != result) return cap;
    
    propertyAddress.mSelector = kAudioDevicePropertyVolumeScalar;
    propertyAddress.mScope    = kAudioDevicePropertyScopeOutput;
    propertyAddress.mElement  = 1; // Channel 0  is master, if available

    if (!AudioObjectHasProperty(deviceID, &propertyAddress)) return cap;

    Float32 volume;
    dataSize = sizeof(volume);

    result = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, NULL, &dataSize, &volume);

    if (kAudioHardwareNoError != result) return cap;
    
    return (volume >= cap) ? cap / volume : 1;
}

- (void)updateTimer
{
    NSDateComponents *components = [_nsCal components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond fromDate:[NSDate new]];

    // Should we beep-beep on the hour? If so, cap the volume relative to the
    // system volume so it's not too loud.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:kBeepBeepOnTheHour]
        && components.minute == 0
        && components.second == 0) {
        NSSound *beepbeep = [NSSound soundNamed:@"beep"];
        // See if the user has put their own beep.mp3 in our Application
        // Support folder. The user-supplied sound is in a folder named for
        // our bundle identifier.
        NSURL *beepURL = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        if (beepURL) {
            NSString *bundleID = NSBundle.mainBundle.bundleIdentifier;
            beepURL = [beepURL URLByAppendingPathComponent:bundleID isDirectory:YES];
            beepURL = [beepURL URLByAppendingPathComponent:@"beep.mp3" isDirectory:NO];
            if ([NSFileManager.defaultManager fileExistsAtPath:beepURL.path isDirectory:NULL]) {
                beepbeep = [[NSSound alloc] initWithContentsOfURL:beepURL byReference:NO];
            }
        }
        [beepbeep setVolume:[self volumeRelativeToSystemVolumeWithCap:0.12]];
        [beepbeep play];
    }

    // Set up _timer to fire on next minute or second.
    if (_clockUsesSeconds) {
        components.second += 1;
    }
    else {
        components.minute += 1;
        components.second = 0;
    }
    NSDate *fireDate = [_nsCal dateFromComponents:components];
    // Set new fireDate a quarter second late in the hope that it
    // avoids the edge case when we fall back at the end of Daylight
    // Savings time. Some users reported either the seconds timer
    // getting stuck in a loop and pinning CPU at 100% or the minute
    // timer not firing until the fallback hour has ended.
    fireDate = [fireDate dateByAddingTimeInterval:0.25];
    [_timer invalidate];
    _timer = [[NSTimer alloc] initWithFireDate:fireDate interval:0 target:self selector:@selector(updateTimer) userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    
    // Check if past events should be dimmed each minute.
    // Also check if we should show the meeting indicator.
    static NSTimeInterval dimEventsTime = 0;
    NSTimeInterval currentTime = MonotonicClockTime();
    NSTimeInterval elapsedTime = currentTime - dimEventsTime;
    if (elapsedTime > 60 || fabs(elapsedTime - 60) < 0.5) {
        [_agendaVC dimEventsIfNecessary];
        dimEventsTime = currentTime;
        [self showMeetingIndicatorIfNecessary];
    }
    // Reset calendar to today after 10 minutes of inactivity.
    elapsedTime = currentTime - _inactiveTime;
    if (_inactiveTime && (elapsedTime > 600 || fabs(elapsedTime - 600) < 0.5)) {
        [self resetCalendarToToday];
        _inactiveTime = 0;
    }
    // Update clock if necessary.
    if (_clockUsesTime) [self updateMenubarIcon];
}

#pragma mark -
#pragma mark Custom clock format

- (void)clockFormatDidChange
{
    NSString *format = [[NSUserDefaults standardUserDefaults] stringForKey:kClockFormat];

    // -observeValueForKeyPath:ofObject:change:context: sends
    // redundant change notifications ever since binding prefs
    // textfield to kClockFormat. If clock format hasn't changed,
    // ignore this redundant change notification.
    if ((format == nil && _clockFormat == nil) ||
        [format isEqualToString:_clockFormat]) {
        return;
    }

    // Did the user set a custom clock format string?
    if (format != nil && ![format isEqualToString:@""]) {
        [self processFormatForTimeAndSecondsSpecifiers:format];
        _clockFormat = format;
    }
    else {
        _clockUsesTime = NO;
        _clockUsesSeconds = NO;
        _clockFormat = nil;
        _statusItem.button.title = @"";
    }
    [self updateStatusItemFont];
    [self updateMenubarIcon];
    [self updateTimer];
}

- (void)processFormatForTimeAndSecondsSpecifiers:(NSString *)format
{
    // A time specifier is one of the following: a, H, h, K, k, j, m, s.
    // The seconds specifier is an s-character. Does format contain
    // a time specifier or s that isn't inside a quoted string? a quoted
    // string is delimited by single-quote chars.

    NSString *timeSpecifiers = @"aHhKkjms";
    
    __block BOOL timeSpecifierFound = NO;
    __block BOOL secondsSpecifierFound = NO;
    __block BOOL insideQuotedString = NO;

    // First, remove adjacent pairs of single-quotes. They
    // represent single-quote literals. Removing them makes
    // parsing for quoted strings much easier.
    NSString *fmt = [format stringByReplacingOccurrencesOfString:@"''" withString:@""];

    // Iterate through fmt looking for an s that isn't in a quoted string.
    [fmt enumerateSubstringsInRange: NSMakeRange(0, [fmt length]) options: NSStringEnumerationByComposedCharacterSequences usingBlock: ^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {

        // Did we find an s that isn't inside a quoted string?
        if (insideQuotedString == NO && [substring isEqualToString:@"s"]) {
            secondsSpecifierFound = YES;
            timeSpecifierFound = YES;
            *stop = YES;
        }
        // Did we find a time specifier that isn't inside a quoted string?
        else if (insideQuotedString == NO && [timeSpecifiers containsString:substring]) {
            timeSpecifierFound = YES;
        }
        // Are we inside a quoted string? They are delimited with single-quotes.
        else if ([substring isEqualToString:@"'"]) {
            insideQuotedString = !insideQuotedString;
        }
    }];
    _clockUsesTime = timeSpecifierFound;
    _clockUsesSeconds = secondsSpecifierFound;
}

#pragma mark -
#pragma mark Notifications

- (void)fileNotifications
{
    // Day changed notification
    [[NSNotificationCenter defaultCenter] addObserverForName:NSCalendarDayChangedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [self resetCalendarToToday];
        [self updateMenubarIcon];
        [self updateTimer];
    }];
    
    // Timezone changed notification
    [[NSNotificationCenter defaultCenter] addObserverForName:NSSystemTimeZoneDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [self updateMenubarIcon];
        [self updateTimer];
        [self->_ec refetchAll];
    }];
    
    // Locale notifications
    [[NSNotificationCenter defaultCenter] addObserverForName:NSCurrentLocaleDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [self updateMenubarIcon];
        [self updateTimer];
        [self updateAgenda]; // 12/24 hr time change in sys prefs
    }];
    
    // System clock notification
    [[NSNotificationCenter defaultCenter] addObserverForName:NSSystemClockDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [self updateMenubarIcon];
        [self updateTimer];
        [self->_ec refetchAll];
    }];

    // Wake from sleep notification
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidWakeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        [self updateMenubarIcon];
        [self updateTimer];
    }];

    // Observe NSUserDefaults for preference changes
    for (NSString *keyPath in @[kShowEventDays, kMenuBarIconType, kShowMonthInIcon, kShowDayOfWeekInIcon, kShowDaysWithNoEventsInAgenda, kShowMeetingIndicator, kHideIcon, kBaselineOffset, kClockFormat]) {
        [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:NULL];
    }
}

#pragma mark -
#pragma mark NSUserDefaults observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:kShowEventDays] ||
        [keyPath isEqualToString:kShowDaysWithNoEventsInAgenda]) {
        [self updateAgenda];
    }
    else if ([keyPath isEqualToString:kMenuBarIconType] ||
             [keyPath isEqualToString:kShowMonthInIcon] ||
             [keyPath isEqualToString:kShowDayOfWeekInIcon] ||
             [keyPath isEqualToString:kShowMeetingIndicator] ||
             [keyPath isEqualToString:kHideIcon] ||
             [keyPath isEqualToString:kBaselineOffset]) {
        [self updateMenubarIcon];
    }
    else if ([keyPath isEqualToString:kClockFormat]) {
        [self clockFormatDidChange];
    }
}

@end
