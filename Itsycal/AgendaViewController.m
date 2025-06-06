//
//  AgendaViewController.m
//  Itsycal
//
//  Created by Sanjay Madan on 2/18/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import "Itsycal.h"
#import "AgendaViewController.h"
#import "EventCenter.h"
#import "MoButton.h"
#import "MoVFLHelper.h"
#import "Themer.h"
#import "Sizer.h"
#import "Things3.h"

static NSString *kColumnIdentifier    = @"Column";
static NSString *kDateCellIdentifier  = @"DateCell";
static NSString *kEventCellIdentifier = @"EventCell";
static NSString *kTodoCellIdentifier = @"TodoCell";

@interface ThemedScroller : NSScroller
@end

@interface AgendaRowView : NSTableRowView
@property (nonatomic) BOOL isHovered;
@end

@interface AgendaDateCell : NSView
@property (nonatomic) NSTextField *dayTextField;
@property (nonatomic) NSTextField *DOWTextField;
@property (nonatomic, weak) NSDate *date;
@end

@interface AgendaTodoCell : NSView
@property (nonatomic) NSTextField *title;
@property (nonatomic) NSButton *btnEvent;
@end

@interface AgendaEventCell : NSView
@property (nonatomic) NSGridView *grid;
@property (nonatomic) NSTextField *titleTextField;
@property (nonatomic) NSTextField *locationTextField;
@property (nonatomic) NSTextField *durationTextField;
@property (nonatomic) MoButton *btnVideo;
@property (nonatomic, weak) EventInfo *eventInfo;
@property (nonatomic) BOOL dim;
@end

@interface AgendaPopoverVC : NSViewController
@property (nonatomic, weak) NSCalendar *nsCal;
@property (nonatomic) NSButton *btnDelete;
@property (nonatomic) NSButton *btnShowCalApp;
- (void)populateWithEventInfo:(EventInfo *)info;
- (void)scrollToTopAndFlashScrollers;
- (NSSize)size;
@end

#pragma mark -
#pragma mark AgendaViewController

// =========================================================================
// AgendaViewController
// =========================================================================

@implementation AgendaViewController
{
    NSPopover *_popover;
    CGFloat _windowTopMargin;
}

- (void)loadView
{
    // Create some vertical padding inside the tooltip windows
    if ([NSStringFromClass([self class]) isEqualToString:@"TooltipViewController"]) {
        _windowTopMargin = 8.0;
    } else {
        _windowTopMargin = 0.0;
    }

    // View controller content view
    NSView *v = [NSView new];

    // Calendars table view
    _tv = [MoTableView new];
    _tv.target = self;
    _tv.action = @selector(showPopover:);
    _tv.doubleAction = @selector(showCalendarApp:);
    _tv.menu = [NSMenu new];
    _tv.menu.delegate = self;
    _tv.headerView = nil;
    _tv.allowsColumnResizing = NO;
    _tv.intercellSpacing = NSMakeSize(0, 0);
    _tv.backgroundColor = NSColor.clearColor;
    _tv.floatsGroupRows = NO;
    _tv.refusesFirstResponder = YES;
    _tv.dataSource = self;
    _tv.delegate = self;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 110000
    if (@available(macOS 11.0, *)) {
        _tv.style = NSTableViewStylePlain;
    }
#endif
    [_tv addTableColumn:[[NSTableColumn alloc] initWithIdentifier:kColumnIdentifier]];
    
    // Calendars enclosing scrollview
    NSScrollView *tvContainer = [NSScrollView new];
    tvContainer.translatesAutoresizingMaskIntoConstraints = NO;
    tvContainer.drawsBackground = NO;
    tvContainer.hasVerticalScroller = YES;
    tvContainer.documentView = _tv;
    tvContainer.verticalScroller = [ThemedScroller new];
    
    [v addSubview:tvContainer];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[tv]|" options:0 metrics:nil views:@{@"tv": tvContainer}]];
    [v addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-(m)-[tv]|" options:0 metrics:@{ @"m" : @(_windowTopMargin) } views:@{@"tv": tvContainer}]];

    self.view = v;
}

- (void)viewWillAppear
{
    [super viewWillAppear];
    [self reloadData];
}

- (void)viewDidLayout
{
    // Calculate height of view based on _tv row heights.
    // We set the view's height using preferredContentSize.
    NSInteger rows = [_tv numberOfRows];
    CGFloat height = 0;
    for (NSInteger row = 0; row < rows; ++row) {
        height += [self tableView:_tv heightOfRow:row];
    }
    if ([self.identifier isEqualToString:@"AgendaVC"]) {
        // Limit height so everything fits on the screen.
        height = MIN(height, [self.delegate agendaMaxPossibleHeight]);
    }
    // If height is 0, we make it 0.001 which is effectively the
    // same dimension. When preferredContentSize is zero, it is
    // ignored, so we use a non-zero value that has the same
    // effect. Without this, the size won't shrink to zero when
    // transitioning from an agenda with events to one without.
    height = MAX(height, 0.001);

    // 😭😭😭 Hack alert!
    // On macOS Sonoma 14.3.1, window drawing (specifically the drawing done
    // in `ItsycalWindow` `-drawRect:`) is corrupted when:
    //   1. There are many events making the agenda too big to fit on-screen.
    //   2. The user has 2 monitors and switches to the smaller one.
    // I have no idea why setting `preferredContentSize` via a call to
    // `-performSelectorOnMainThread:withObject:waitUntilDone` works while
    // simply setting it here as we used to do no longer does.
    NSSize prefSize = NSMakeSize(NSWidth(_tv.frame), height + _windowTopMargin * 2);
    NSValue *value = [NSValue valueWithSize:prefSize];
    [self performSelectorOnMainThread:@selector(setPreferredContentSizeHack:) 
                           withObject:value waitUntilDone:NO];
}

- (void)setPreferredContentSizeHack:(NSValue *)value
{
    // See -viewDidLayout for why this is done here.
    self.preferredContentSize = value.sizeValue;
}

- (void)updateViewConstraints
{
    // Tell _tv that row heights need to be recalculated.
    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [_tv numberOfRows])];
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0];
    [_tv noteHeightOfRowsWithIndexesChanged:indexSet];
    [NSAnimationContext endGrouping];
    [super updateViewConstraints];
}

- (void)setShowLocation:(BOOL)showLocation
{
    if (_showLocation != showLocation) {
        _showLocation = showLocation;
        [self reloadData];
    }
}

- (void)reloadData
{
    [_tv reloadData];
    [_tv scrollRowToVisible:0];
    [[_tv enclosingScrollView] flashScrollers];
    [self.view setNeedsLayout:YES];
    [_popover close];
}

#pragma mark -
#pragma mark TableView context menu

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    // Invoked just before menu is to be displayed.
    // Show a context menu ONLY for non-group rows.
    [menu removeAllItems];
    if (_tv.clickedRow < 0 || [self tableView:_tv isGroupRow:_tv.clickedRow] ||
        [self tableView:_tv isEmptyEventRow:_tv.clickedRow]) return;
    [menu addItemWithTitle:NSLocalizedString(@"Open in Calendar", nil) action:@selector(showCalendarApp:) keyEquivalent:@""];
    [menu addItemWithTitle:NSLocalizedString(@"Copy", nil) action:@selector(copyEventToPasteboard:) keyEquivalent:@""];
    EventInfo *info = self.events[_tv.clickedRow];
    if (info.event.calendar.allowsContentModifications) {
        NSMenuItem *item =[menu addItemWithTitle:NSLocalizedString(@"Delete", nil) action:@selector(deleteEvent:) keyEquivalent:@""];
        item.tag = _tv.clickedRow;
    }
}

#pragma mark -
#pragma mark Copy

- (void)copyEventToPasteboard:(id)sender
{
    if (_tv.clickedRow < 0 || [self tableView:_tv isGroupRow:_tv.clickedRow]) return;
    static NSDateIntervalFormatter *intervalFormatter = nil;
    if (intervalFormatter == nil) {
        intervalFormatter = [NSDateIntervalFormatter new];
        intervalFormatter.dateStyle = NSDateIntervalFormatterMediumStyle;
    }
    
    AgendaEventCell *cell = [_tv viewAtColumn:0 row:_tv.clickedRow makeIfNecessary:NO];
    
    if (cell == nil) return; // should not happen
    
    intervalFormatter.timeZone  = [NSTimeZone localTimeZone];
    // All-day events don't show time.
    intervalFormatter.timeStyle = cell.eventInfo.event.isAllDay
        ? NSDateIntervalFormatterNoStyle
        : NSDateIntervalFormatterShortStyle;
    // All-day events technically end at the start of the day after
    // their end date. So display endDate as one less.
    NSDate *endDate = cell.eventInfo.event.isAllDay
        ? [self.nsCal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:cell.eventInfo.event.endDate options:0]
        : cell.eventInfo.event.endDate;
    if (@available(macOS 13.0, *)) {
        // macOS 13 changed All-day events' end date from 12 AM of
        // day after last day of event to 11:59:59 PM of last day.
        endDate = cell.eventInfo.event.endDate;
    }
    // Interval formatter just prints single date when from == to.
    NSString *duration = [intervalFormatter stringFromDate:cell.eventInfo.event.startDate toDate:endDate];
    // If the locale is English and we are in 12 hour time,
    // remove :00 from the time. Effect is 3:00 PM -> 3 PM.
    if ([[[NSLocale currentLocale] localeIdentifier] hasPrefix:@"en"]) {
        if ([duration containsString:@"AM"] || [duration containsString:@"PM"] ||
            [duration containsString:@"am"] || [duration containsString:@"pm"]) {
            duration = [duration stringByReplacingOccurrencesOfString:@":00" withString:@""];
        }
    }
    NSString *eventText = [NSString stringWithFormat:@"%@\n%@\n%@%@",
                           cell.titleTextField.stringValue,
                           duration,
                           cell.locationTextField.stringValue,
                           cell.locationTextField.stringValue.length > 0 ? @"\n" : @""];
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] writeObjects:@[eventText]];
}

#pragma mark -
#pragma mark TableView click actions

- (void)showPopoverForRow:(NSInteger)row
{
    if (row == -1 || [self tableView:_tv isGroupRow:row] ||
        [self tableView:_tv isEmptyEventRow:row]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        self->_popover = [NSPopover new];
        self->_popover.contentViewController = [AgendaPopoverVC new];
        self->_popover.behavior = NSPopoverBehaviorTransient;
        self->_popover.animates = NO;
    });
    
    AgendaEventCell *cell = [_tv viewAtColumn:0 row:row makeIfNecessary:NO];
    
    if (!cell) return; // should never happen
    
    AgendaPopoverVC *popoverVC = (AgendaPopoverVC *)_popover.contentViewController;
    [popoverVC setNsCal:self.nsCal];
    [popoverVC populateWithEventInfo:cell.eventInfo];
    
    if (cell.eventInfo.event.calendar.allowsContentModifications) {
        popoverVC.btnDelete.tag = row;
        popoverVC.btnDelete.target = self;
        popoverVC.btnDelete.action = @selector(deleteEvent:);
        unichar backspaceKey = NSBackspaceCharacter;
        popoverVC.btnDelete.keyEquivalent = [NSString stringWithCharacters:&backspaceKey length:1];
    }
    
    NSRect positionRect = NSInsetRect([_tv rectOfRow:row], 8, 0);
    [_popover setAppearance:NSApp.effectiveAppearance];
    [_popover showRelativeToRect:positionRect ofView:_tv preferredEdge:NSRectEdgeMinX];
    [_popover setContentSize:popoverVC.size];
    [popoverVC scrollToTopAndFlashScrollers];
    
    // Prevent popoverVC's _note from eating key presses (like esc and delete).
    [popoverVC.view.window makeFirstResponder:popoverVC.btnDelete];
}

- (void)showPopover:(id)sender
{
    if (_tv.clickedRow == -1 || [self tableView:_tv isGroupRow:_tv.clickedRow]) return;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        self->_popover = [NSPopover new];
        self->_popover.contentViewController = [AgendaPopoverVC new];
        self->_popover.behavior = NSPopoverBehaviorTransient;
        self->_popover.animates = NO;
    });

    AgendaEventCell *cell = [_tv viewAtColumn:0 row:_tv.clickedRow makeIfNecessary:NO];

    if (!cell) return; // should never happen

    AgendaPopoverVC *popoverVC = (AgendaPopoverVC *)_popover.contentViewController;
    [popoverVC setNsCal:self.nsCal];
    [popoverVC populateWithEventInfo:cell.eventInfo];

    if (cell.eventInfo.event.calendar.allowsContentModifications) {
        popoverVC.btnDelete.tag = _tv.clickedRow;
        popoverVC.btnDelete.target = self;
        popoverVC.btnDelete.action = @selector(deleteEvent:);
        unichar backspaceKey = NSBackspaceCharacter;
        popoverVC.btnDelete.keyEquivalent = [NSString stringWithCharacters:&backspaceKey length:1];
    }

    popoverVC.btnShowCalApp.tag = [_tv rowForView:cell];
    popoverVC.btnShowCalApp.target = self;
    popoverVC.btnShowCalApp.action = @selector(showCalendarApp:);

    NSRect positionRect = NSInsetRect([_tv rectOfRow:_tv.clickedRow], 8, 0);
    [_popover setAppearance:NSApp.effectiveAppearance];
    [_popover showRelativeToRect:positionRect ofView:_tv preferredEdge:NSRectEdgeMinX];
    [_popover setContentSize:popoverVC.size];
    [popoverVC scrollToTopAndFlashScrollers];

    // Prevent popoverVC's _note from eating key presses (like esc and delete).
    [popoverVC.view.window makeFirstResponder:popoverVC.btnDelete];
}

- (void)showCalendarApp:(id)sender
{
    NSInteger row = -1;
    if ([sender isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)sender;
        row = button.tag;
    } else if (_tv.clickedRow != -1 || ![self tableView:_tv isGroupRow:_tv.clickedRow]) {
        row = _tv.clickedRow;
    } else return;

    // Open Calendar.app with the given event selected.
    EKEvent *event = ((EventInfo *)self.events[row]).event;
    NSString *eventID = event.calendarItemIdentifier;
    NSString *path;
    if (event.hasRecurrenceRules) {
        NSDate *safeStartDate = event.startDate ? event.startDate : NSDate.distantFuture;
        NSLocale *locale;
        NSTimeZone *timeZone;
        NSDateFormatter *dateFormatter = [NSDateFormatter new];
        dateFormatter.dateFormat = @"yyyyMMdd'T'HHmmss'Z'";
        if (event.isAllDay) {
            locale = NSLocale.currentLocale;
            timeZone = NSTimeZone.localTimeZone;
        } else {
            locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        }
        dateFormatter.locale = locale;
        dateFormatter.timeZone = timeZone;
        NSString *formattedDate = [dateFormatter stringFromDate:safeStartDate];

        path = [NSString stringWithFormat:@"ical://ekevent/%@/%@?method=show&options=more", formattedDate, eventID];
    } else {
        path = [NSString stringWithFormat:@"ical://ekevent/%@?method=show&options=more", eventID];
    }

    NSURL *url = [NSURL URLWithString:path];
    dispatch_async(dispatch_get_global_queue(NSOperationQualityOfServiceUserInitiated, 0), ^{
        [NSWorkspace.sharedWorkspace openURL:url];
    });

    return;
}

- (void)showThingsApp:(id)sender
{
    if ([sender isKindOfClass:[NSButton class]]) {
        NSButton *btn = sender;
        Things3ToDo *todo = ((Things3ToDo *)self.events[btn.tag]);
        [todo edit];
    }
}

#pragma mark -
#pragma mark TableView delegate/datasource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return self.events == nil ? 0 : self.events.count;
}

- (NSTableRowView *)tableView:(MoTableView *)tableView rowViewForRow:(NSInteger)row
{
    AgendaRowView *rowView = [_tv makeViewWithIdentifier:@"RowView" owner:self];
    if (rowView == nil) {
        rowView = [AgendaRowView new];
        rowView.identifier = @"RowView";
    }
    rowView.isHovered = tableView.hoverRow == row;
    return rowView;
}

- (NSView *)tableView:(MoTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSView *v = nil;
    id obj = self.events[row];
    
    if ([obj isKindOfClass:[NSDate class]]) {
        AgendaDateCell *cell = [_tv makeViewWithIdentifier:kDateCellIdentifier owner:self];
        if (cell == nil) cell = [AgendaDateCell new];
        cell.date = obj;
        cell.dayTextField.stringValue = [self dayStringForDate:obj];
        cell.DOWTextField.stringValue = [self DOWStringForDate:obj];
        cell.dayTextField.textColor = Theme.agendaDayTextColor;
        cell.DOWTextField.textColor = Theme.agendaDOWTextColor;
        if ([(NSDate*)obj hasNoEvents]) {
            cell.dayTextField.textColor = NSColor.tertiaryLabelColor;
            cell.DOWTextField.textColor = NSColor.tertiaryLabelColor;
        }
        v = cell;
    }
    else if ([obj isKindOfClass:SBObject.class]) {
        Things3ToDo *todo = obj;
        NSString *title = todo.name;
        AgendaTodoCell *cell = [_tv makeViewWithIdentifier:kTodoCellIdentifier owner:self];
        if (cell == nil) cell = [AgendaTodoCell new];

        if (title) {
            cell.title.stringValue = todo.name;
            cell.btnEvent.target = self;
            cell.btnEvent.action = @selector(showThingsApp:);
            cell.btnEvent.tag = row;
        }

        v = cell;
    }
    else {
        EventInfo *info = obj;
        AgendaEventCell *cell = [_tv makeViewWithIdentifier:kEventCellIdentifier owner:self];
        if (!cell) cell = [AgendaEventCell new];
        [self populateEventCell:cell withInfo:info];
        v = cell;
    }
    return v;
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    // Keep a cell around for measuring event cell height.
    static AgendaDateCell *dateCell = nil;
    static AgendaEventCell *eventCell = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        eventCell = [AgendaEventCell new];
        dateCell = [AgendaDateCell new];
        dateCell.frame = NSMakeRect(0, 0, NSWidth(self->_tv.frame), 999); // only width is important here
        dateCell.dayTextField.integerValue = 21;
    });
    
    CGFloat height = dateCell.fittingSize.height;
    id obj = self.events[row];
    if ([obj isKindOfClass:[EventInfo class]]) {
        eventCell.frame = NSMakeRect(0, 0, NSWidth(_tv.frame), 999); // only width is important here
        [self populateEventCell:eventCell withInfo:obj];
        height = eventCell.fittingSize.height;
    }
    return height;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
    return [self.events[row] isKindOfClass:[NSDate class]];
}

- (BOOL)tableView:(NSTableView *)tableView isEmptyEventRow:(NSInteger)row
{
    id obj = self.events[row];
    return ([obj isKindOfClass:[EventInfo class]] &&
            ((EventInfo *)obj).event == nil);
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return NO; // disable selection
}

- (void)tableView:(MoTableView *)tableView didHoverOverRow:(NSInteger)hoveredRow
{
    BOOL showPopoverOnHover = [[NSUserDefaults standardUserDefaults] boolForKey:kShowEventPopoverOnHover];
    if (hoveredRow == -1 || [self tableView:_tv isGroupRow:hoveredRow] ||
        [self tableView:_tv isEmptyEventRow:hoveredRow]) {
        if (showPopoverOnHover && hoveredRow != -1) {
            [_popover close];
        }
        hoveredRow = -1;
    }
    for (NSInteger row = 0; row < [_tv numberOfRows]; row++) {
        if (![self tableView:_tv isGroupRow:row]) {
            BOOL isEmptyEventRow = [self tableView:_tv isEmptyEventRow:row];
            BOOL isHovered = (row == hoveredRow && !isEmptyEventRow);
            AgendaRowView *rowView = [_tv rowViewAtRow:row makeIfNecessary:NO];
            rowView.isHovered = isHovered;
            if (showPopoverOnHover && isHovered) {
                [self showPopoverForRow:hoveredRow];
            }
        }
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(agendaHoveredOverRow:)]) {
        [self.delegate agendaHoveredOverRow:hoveredRow];
    }
}

#pragma mark -
#pragma mark Delete event

- (void)deleteEvent:(id)sender
{
    NSInteger row = -1;
    if ([sender isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)sender;
        // The delete button disappears(?!?!) after being clicked (macOS 11).
        // It's actually still there. You can click it. But it isn't drawn.
        // This bizarre buggy behavior seems to affect borderless buttons.
        // So we insanely toggle bordered on/off to make sure the button shows.
        button.bordered = YES;
        button.bordered = NO;
        row = button.tag;
    } else if ([sender isKindOfClass:[NSMenuItem class]]) {
        row = [(NSMenuItem *)sender tag];
    }
    if (row < 0) return;
    if (self.delegate && [self.delegate respondsToSelector:@selector(agendaWantsToDeleteEvent:)]) {
        EventInfo *info = self.events[row];
        [self.delegate agendaWantsToDeleteEvent:info.event];
    }
}

#pragma mark -
#pragma mark Format Agenda Strings

- (NSString *)dayStringForDate:(NSDate *)date
{
    static NSDateFormatter *dateFormatter = nil;
    if (dateFormatter == nil) {
        dateFormatter = [NSDateFormatter new];
    }
    dateFormatter.timeZone = [NSTimeZone localTimeZone];
    [dateFormatter setLocalizedDateFormatFromTemplate:@"dMMM"];
    return [dateFormatter stringFromDate:date];
}

- (NSString *)DOWStringForDate:(NSDate *)date
{
    static NSDateFormatter *dateFormatter = nil;
    if (dateFormatter == nil) {
        dateFormatter = [NSDateFormatter new];
    }
    dateFormatter.timeZone = [NSTimeZone localTimeZone];
    if ([self.nsCal isDateInToday:date] || [self.nsCal isDateInTomorrow:date]) {
        dateFormatter.doesRelativeDateFormatting = YES;
        dateFormatter.dateStyle = NSDateFormatterMediumStyle;
        dateFormatter.timeStyle = NSDateFormatterNoStyle;
    }
    else {
        dateFormatter.doesRelativeDateFormatting = NO;
        [dateFormatter setLocalizedDateFormatFromTemplate:@"EEEE"];
    }
    return [dateFormatter stringFromDate:date];
}

- (void)populateEventCell:(AgendaEventCell *)cell withInfo:(EventInfo *)info
{
    static NSDateFormatter *timeFormatter = nil;
    static NSDateIntervalFormatter *intervalFormatter = nil;
    if (timeFormatter == nil) {
        timeFormatter = [NSDateFormatter new];
        timeFormatter.dateStyle = NSDateFormatterNoStyle;
        timeFormatter.timeStyle = NSDateFormatterShortStyle;
    }
    if (intervalFormatter == nil) {
        intervalFormatter = [NSDateIntervalFormatter new];
        intervalFormatter.dateStyle = NSDateIntervalFormatterNoStyle;
        intervalFormatter.timeStyle = NSDateIntervalFormatterShortStyle;
    }

    // There are no events on this date.
    if (!info.event) {
        cell.eventInfo = nil;
        cell.dim = YES;
        cell.titleTextField.stringValue = NSLocalizedString(@"", @"");
        cell.titleTextField.textColor = NSColor.tertiaryLabelColor;
        [cell.grid rowAtIndex:1].hidden = YES; // hide location row
        [cell.grid rowAtIndex:2].hidden = YES; // hide duration row
        cell.btnVideo.enabled = NO;
        cell.btnVideo.hidden = YES;
        return;
    }

    NSString *title = @"";
    NSString *location = @"";
    NSString *duration = @"";
    timeFormatter.timeZone  = [NSTimeZone localTimeZone];
    intervalFormatter.timeZone = nil; // Force tz update on macOS 10.13
    intervalFormatter.timeZone  = [NSTimeZone localTimeZone];
    // Needed to pick up 12/24 hr time system preference change:
    intervalFormatter.locale = [NSLocale currentLocale];
    
    cell.eventInfo = info;

    if (info && info.event) {
        if (info.event.title) {
            // If title has newlines or stretches of whitespace, compress
            // them into a single space.
            title = [[info.event.title componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@" "];
        }
        if (info.event.location) location = info.event.location;
    }
    
    // Hide location row IF !self.showLocation OR there's no location string.
    [cell.grid rowAtIndex:1].hidden = (!self.showLocation || location.length == 0);
    
    // Hide duration row for all day events.
    [cell.grid rowAtIndex:2].hidden = info.isAllDay;
    
    if (info.isAllDay == NO) {
        if (info.isStartDate == YES) {
            if (info.event.startDate != nil) {
                duration = [timeFormatter stringFromDate:info.event.startDate];
            }
        }
        else if (info.isEndDate == YES) {
            if (info.event.endDate != nil) {
                NSString *ends = NSLocalizedString(@"ends", @"Spanning event ends");
                duration = [NSString stringWithFormat:@"%@ %@", ends, [timeFormatter stringFromDate:info.event.endDate]];
            }
        }
        else {
            if (info.event.startDate != nil && info.event.endDate != nil) {
                duration = [intervalFormatter stringFromDate:info.event.startDate toDate:info.event.endDate];
            }
        }
        // If the locale is English and we are in 12 hour time,
        // remove :00 from the time. Effect is 3:00 PM -> 3 PM.
        if ([[[NSLocale currentLocale] localeIdentifier] hasPrefix:@"en"]) {
            if ([[timeFormatter dateFormat] rangeOfString:@"a"].location != NSNotFound) {
                duration = [duration stringByReplacingOccurrencesOfString:@":00" withString:@""];
            }
        }
    }

    // Virtual meeting button.
    cell.btnVideo.enabled = NO;
    cell.btnVideo.hidden = info.zoomURL ? NO : YES;
    cell.btnVideo.actionBlock = nil;
    cell.btnVideo.contentTintColor = nil;

    cell.titleTextField.stringValue = title;
    cell.titleTextField.textColor = Theme.agendaEventTextColor;
    cell.locationTextField.stringValue = location;
    cell.locationTextField.textColor = Theme.agendaEventDateTextColor;
    cell.durationTextField.stringValue = duration;
    cell.durationTextField.textColor = Theme.agendaEventDateTextColor;

    // If event's endDate is today and is past, dim event.
    cell.dim = NO;
    if (!info.isStartDate && !info.isAllDay
        && [self.nsCal isDateInToday:info.event.endDate]
        && [NSDate.date compare:info.event.endDate] == NSOrderedDescending) {
        cell.titleTextField.textColor = Theme.agendaEventDateTextColor;
        cell.dim = YES;
    }
    
    // Enable the zoom button 15 minutes prior to event start until end.
    // If the user prefers, button can remain enabled indefinitely.
    NSDate *fifteenMinutesPrior = [self.nsCal dateByAddingUnit:NSCalendarUnitSecond value:-(15 * 60 + 30) toDate:info.event.startDate options:0];
    if (info.zoomURL && !info.event.isAllDay
        && [fifteenMinutesPrior compare:NSDate.date] == NSOrderedAscending
        && ([NSDate.date compare:info.event.endDate] == NSOrderedAscending
            || [NSUserDefaults.standardUserDefaults boolForKey:kEnableMeetingButtonIndefinitely])) {
        cell.btnVideo.enabled = YES;
        cell.btnVideo.contentTintColor = Theme.todayCellColor;
        cell.btnVideo.actionBlock = ^{
            [NSWorkspace.sharedWorkspace openURL:info.zoomURL];
        };
    }
}

#pragma mark -
#pragma mark Dim past events

- (void)dimEventsIfNecessary
{
    // If the user has the window showing, reload the agenda cells.
    // This will redraw the events, dimming if necessary.
    // This also enables/disables zoom buttons if necessary
    // depending on whether a virtual meeting is in progress.
    if (self.view.window.isVisible) {
        [_tv reloadData];
    }
}

#pragma mark -
#pragma mark Click first active Zoom button

- (BOOL)clickFirstActiveZoomButton
{
    for (NSInteger row = 0; row < _tv.numberOfRows; row++) {
        NSView *view = [_tv viewAtColumn:0 row:row makeIfNecessary:NO];
        if ([view isKindOfClass:[AgendaEventCell class]]) {
            AgendaEventCell *cell = (AgendaEventCell *)view;
            if (cell.btnVideo.enabled) {
                [cell.btnVideo performClick:self];
                return YES;
            }
        }
    }
    return NO;
}

@end

#pragma mark -
#pragma mark ThemedScroller

// =========================================================================
// ThemedScroller
// =========================================================================

@implementation ThemedScroller

+ (BOOL)isCompatibleWithOverlayScrollers {
    return self == [ThemedScroller class];
}

- (void)drawKnobSlotInRect:(NSRect)slotRect highlight:(BOOL)flag
{
    [Theme.mainBackgroundColor set];
    NSRectFill(slotRect);
}

@end

#pragma mark -
#pragma mark Agenda Row View

// =========================================================================
// AgendaRowView
// =========================================================================

@implementation AgendaRowView

- (void)drawBackgroundInRect:(NSRect)dirtyRect {
    if (self.isHovered) {
        [Theme.agendaHoverColor set];
        NSRect rect = NSInsetRect(self.bounds, 8, 1);
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5] fill];
    }
}

- (void)setIsHovered:(BOOL)isHovered {
    if (_isHovered != isHovered) {
        _isHovered = isHovered;
        [self setNeedsDisplay:YES];
    }
}

@end

#pragma mark -
#pragma mark Agenda Date and Event cells

// =========================================================================
// AgendaDateCell
// =========================================================================

@implementation AgendaDateCell

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.identifier = kDateCellIdentifier;
        _dayTextField = [NSTextField labelWithString:@""];
        _dayTextField.translatesAutoresizingMaskIntoConstraints = NO;
        _dayTextField.font = [NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightSemibold];
        _dayTextField.textColor = Theme.agendaDayTextColor;
        [_dayTextField setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
        
        _DOWTextField = [NSTextField labelWithString:@""];
        _DOWTextField.translatesAutoresizingMaskIntoConstraints = NO;
        _DOWTextField.font = [NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightSemibold];
        _DOWTextField.textColor = Theme.agendaDOWTextColor;

        [self addSubview:_dayTextField];
        [self addSubview:_DOWTextField];
        MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:self metrics:nil views:NSDictionaryOfVariableBindings(_dayTextField, _DOWTextField)];
        [vfl :@"H:|-10-[_DOWTextField]-(>=4)-[_dayTextField]-10-|" :NSLayoutFormatAlignAllLastBaseline];
        [vfl :@"V:|-6-[_dayTextField]-1-|"];
        
        REGISTER_FOR_SIZE_CHANGE;
    }
    return self;
}

- (void)sizeChanged:(id)sender
{
    _dayTextField.font = [NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightSemibold];
    _DOWTextField.font = [NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightSemibold];
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Must be opaque so rows can scroll under it.
    [Theme.mainBackgroundColor set];
    NSRectFillUsingOperation(self.bounds, NSCompositingOperationSourceOver);
    NSRect r = NSMakeRect(10, self.bounds.size.height - 4, self.bounds.size.width - 20, 1);
    [Theme.agendaDividerColor set];
    NSRectFillUsingOperation(r, NSCompositingOperationSourceOver);
}

@end

// =========================================================================
// AgendaTodoCell
// =========================================================================

@implementation AgendaTodoCell {
    NSLayoutConstraint *_leadingConstraint;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.identifier = kTodoCellIdentifier;

        _title = [NSTextField labelWithString:@""];
        _title.translatesAutoresizingMaskIntoConstraints = NO;
        _title.font = [NSFont systemFontOfSize:SizePref.fontSize];
        _title.lineBreakMode = NSLineBreakByWordWrapping;
        _title.cell.truncatesLastVisibleLine = YES;
        _title.maximumNumberOfLines = 1;

        [self addSubview:_title];

        CGFloat leadingConstant = SizePref.agendaEventLeadingMargin;
        _leadingConstraint = [_title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:leadingConstant];
        _leadingConstraint.active = YES;
        [_title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-11].active = YES;
        [_title.centerYAnchor constraintEqualToAnchor:self.centerYAnchor].active = YES;

        // This button handles opening the todo popover.
        _btnEvent = [NSButton new];
        _btnEvent.title = @"";
        _btnEvent.bordered = 0;
        _btnEvent.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self addSubview:_btnEvent];

        REGISTER_FOR_SIZE_CHANGE;
    }
    return self;
}

- (void)sizeChanged:(id)sender
{
    _leadingConstraint.constant = SizePref.agendaEventLeadingMargin;
    _title.font = [NSFont systemFontOfSize:SizePref.fontSize];
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Draw colored dot. Dot is elongated for all-day events.
    // Stroke for tentative and pending events, otherwise fill.
    CGFloat x = 10.75;
    CGFloat yOffset = SizePref.fontSize + 2.75;
    CGFloat dotWidthX = SizePref.agendaDotWidth + 0.5;
    CGFloat dotWidthY = dotWidthX;
    CGFloat radius = 1.5;
    NSColor *dotColor = [NSColor colorWithRed:0.424 green:0.604 blue:0.933 alpha:1.0];
    [dotColor set];
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, NSHeight(self.bounds) - yOffset, dotWidthX, dotWidthY) xRadius:radius yRadius:radius];
    p.lineWidth = 1.4;
    [p stroke];
}

@end

// =========================================================================
// AgendaEventCell
// =========================================================================

@implementation AgendaEventCell {
    NSLayoutConstraint *_gridLeadingConstraint;
}

- (instancetype)init
{
    // Convenience function for making labels.
    NSTextField* (^label)(void) = ^NSTextField* () {
        NSTextField *lbl = [NSTextField labelWithString:@""];
        lbl.font = [NSFont systemFontOfSize:SizePref.fontSize];
        lbl.lineBreakMode = NSLineBreakByWordWrapping;
        lbl.cell.truncatesLastVisibleLine = YES;
        return lbl;
    };
    self = [super init];
    if (self) {
        self.identifier = kEventCellIdentifier;
        _titleTextField = label();
        _titleTextField.maximumNumberOfLines = 1;
        _locationTextField = label();
        _locationTextField.maximumNumberOfLines = 2;
        _durationTextField = label();
        
        _btnVideo = [MoButton new];
        _btnVideo.bordered = 0;
        _btnVideo.image = [NSImage imageNamed:SizePref.videoImageName];
        _btnVideo.image.template = YES;
        
        /*
         Outer box = self
         Middle box = grid
         Innermost box = durationGrid
         a = _gridLeadingConstraint
         +------------------------------------------+
         |     |                                    |
         |     3                                    |
         |     |                                    |
         |   +---------------------------------+    |
         |-a-|[titleTextField]                 |-11-|
         |   |[locationTextField]              |    |
         |   |+-------------------------------+|    |
         |   ||[durationTextField], [btnVideo]||    |
         |   |+-------------------------------+|    |
         |   +---------------------------------+    |
         |     |                                    |
         |     3                                    |
         |     |                                    |
         +------------------------------------------+
         */
        
        NSGridView *durationGrid = [NSGridView gridViewWithViews:@[@[_durationTextField, _btnVideo]]];
        durationGrid.rowSpacing = 0;
        [durationGrid setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        
        _grid = [NSGridView gridViewWithViews:@[@[_titleTextField],
                                                @[_locationTextField],
                                                @[durationGrid]]];
        _grid.translatesAutoresizingMaskIntoConstraints = NO;
        _grid.rowSpacing = 0;
        [self addSubview:_grid];
        
        MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:self metrics:nil views:NSDictionaryOfVariableBindings(_grid)];
        [vfl :@"H:[_grid]-11-|"];
        [vfl :@"V:|-3-[_grid]-3-|"];
        
        CGFloat leadingConstant = SizePref.agendaEventLeadingMargin;
        _gridLeadingConstraint = [_grid.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:leadingConstant];
        _gridLeadingConstraint.active = YES;
        
        [_btnVideo.centerYAnchor constraintEqualToAnchor:_durationTextField.centerYAnchor].active = YES;
        
        REGISTER_FOR_SIZE_CHANGE;
    }
    return self;
}

- (void)sizeChanged:(id)sender
{
    _gridLeadingConstraint.constant = SizePref.agendaEventLeadingMargin;
    _btnVideo.image = [NSImage imageNamed:SizePref.videoImageName];
    _btnVideo.image.template = YES;
    _titleTextField.font = [NSFont systemFontOfSize:SizePref.fontSize];
    _locationTextField.font = [NSFont systemFontOfSize:SizePref.fontSize];
    _durationTextField.font = [NSFont systemFontOfSize:SizePref.fontSize];
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    // Setting preferredMaxLayoutWidth allows us to calculate height
    // after word-wrapping.
    // margins = leading + trailing margins
    CGFloat margins = _gridLeadingConstraint.constant + 5;
    _titleTextField.preferredMaxLayoutWidth = NSWidth(frame) - margins;
    _locationTextField.preferredMaxLayoutWidth = NSWidth(frame) - margins;
    _durationTextField.preferredMaxLayoutWidth = NSWidth(frame) - margins;
}

- (void)setDim:(BOOL)dim {
    if (_dim != dim) {
        _dim = dim;
        [self setNeedsDisplay:YES];
    }
}

- (NSImage *)pendingPatternImage
{
    static NSImage *patternImage = nil;
    if (!patternImage) {
        patternImage = [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
            [Theme.pendingBackgroundColor set];
            NSBezierPath *p = [NSBezierPath new];
            [p moveToPoint:NSMakePoint(-2, 2)];
            [p lineToPoint:NSMakePoint(6, 10)];
            [p moveToPoint:NSMakePoint(10, 6)];
            [p lineToPoint:NSMakePoint(2, -2)];
            [p setLineWidth:3];
            [p stroke];
            return YES;
        }];
    }
    return patternImage;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // There are no events on this date. Draw a dash.
    if (!self.eventInfo) {
        [NSColor.tertiaryLabelColor set];
        CGFloat diameter = SizePref.agendaDotWidth/3.0;
        CGFloat y = (NSHeight(self.bounds) - diameter)/2.0;
        NSRect rect = NSMakeRect(11, y, diameter * 3.0, diameter);
        CGFloat radius = diameter/2.0;
        [[NSBezierPath bezierPathWithRoundedRect:rect
                                         xRadius:radius
                                         yRadius:radius] fill];
        return;
    }

    // Draw a pattern background for events that are pending
    // participation acceptance. Inset and radius match the
    // hover values in AgendaRowView -drawBackgroundInRect:.
    BOOL isTentative = [[self.eventInfo.event valueForKey:@"participationStatus"] integerValue] == EKParticipantStatusTentative;
    BOOL isPending = [[self.eventInfo.event valueForKey:@"participationStatus"] integerValue] == EKParticipantStatusPending;
    if (self.eventInfo.event.hasAttendees && isPending) {
        [[NSColor colorWithPatternImage:[self pendingPatternImage]] set];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 8, 1) xRadius:5 yRadius:5] fill];
    }
    // Draw colored dot. Dot is elongated for all-day events.
    // Stroke for tentative and pending events, otherwise fill.
    CGFloat alpha = self.dim ? 0.5 : 1;
    CGFloat x = 11;
    CGFloat yOffset = SizePref.fontSize + 2;
    CGFloat dotWidthX = SizePref.agendaDotWidth;
    CGFloat dotWidthY = dotWidthX;
    CGFloat radius = dotWidthX / 2.0;
    NSColor *dotColor = self.eventInfo.event.calendar.color;
    if (self.eventInfo.isAllDay) {
        x += 1;
        yOffset += 2;
        dotWidthX -= 2;
        dotWidthY += 4;
        radius -= 1;
    }
    [[dotColor colorWithAlphaComponent:alpha] set];
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, NSHeight(self.bounds) - yOffset, dotWidthX, dotWidthY) xRadius:radius yRadius:radius];
    if (self.eventInfo.event.hasAttendees && (isTentative || isPending)) {
        p.lineWidth = 1.5;
        [p stroke];
    } else {
        [p fill];
    }
}

@end

#pragma mark -
#pragma mark AgendaPopoverVC

// =========================================================================
// AgendaPopoverVC
// =========================================================================

#define POPOVER_TEXT_WIDTH 280

@implementation AgendaPopoverVC
{
    NSGridView  *_grid;
    NSTextField *_title;
    NSTextField *_duration;
    NSTextField *_recurrence;
    NSTextView *_location;
    NSTextView *_note;
    NSTextView *_URL;
    NSStackView *_attendees;
    NSScrollView *_scrollView;
    NSDataDetector *_linkDetector;
    NSRegularExpression *_hiddenLinksRegex;
    NSRegularExpression *_messageLinksRegex;
    NSLayoutConstraint *_locHeight;
    NSLayoutConstraint *_noteHeight;
    NSLayoutConstraint *_URLHeight;
}

- (instancetype)init
{
    // Convenience functions.
    NSTextField* (^label)(void) = ^NSTextField* {
        NSTextField *lbl = [NSTextField wrappingLabelWithString:@""];
        lbl.drawsBackground = NO;
        lbl.textColor = Theme.currentMonthTextColor;
        [lbl setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        return lbl;
    };
    NSBox* (^separator)(void) = ^NSBox* {
        // Need a big width for separator to show up reliably in NSGridView.
        NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 999, 1)];
        separator.boxType = NSBoxSeparator;
        return separator;
    };
    NSTextView* (^textview)(void) = ^NSTextView* {
        NSTextView *txtview = [NSTextView new];
        txtview.editable = NO;
        txtview.selectable = YES;
        txtview.drawsBackground = NO;
        txtview.textContainer.lineFragmentPadding = 0;
        txtview.textContainer.size = NSMakeSize(POPOVER_TEXT_WIDTH, FLT_MAX);
        return txtview;
    };
    self = [super init];
    if (self) {
        _title = label();
        _duration = label();
        _recurrence = label();

        _location = textview();
        _note = textview();
        _URL = textview();

        _btnDelete = [NSButton new];
        _btnDelete.title = @"⌫";
        _btnDelete.focusRingType = NSFocusRingTypeNone;
        _btnDelete.bordered = NO;
        _btnDelete.contentTintColor = NSColor.secondaryLabelColor;

        _btnShowCalApp = [NSButton new];
        _btnShowCalApp.bordered = NO;
        _btnShowCalApp.imagePosition = NSImageOnly;
        _btnShowCalApp.image = [[NSImage imageWithSystemSymbolName:@"arrow.right.circle" accessibilityDescription:NULL] imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightSemibold]];
        _btnShowCalApp.focusRingType = NSFocusRingTypeNone;

        NSView *titleHolder = [NSView new];
        [titleHolder addSubview:_title];
        [titleHolder addSubview:_btnDelete];
        [titleHolder addSubview:_btnShowCalApp];
        MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:titleHolder metrics:nil views:NSDictionaryOfVariableBindings(_title, _btnShowCalApp, _btnDelete)];
        [vfl :@"H:|[_title]-2-[_btnShowCalApp]-(>=10)-[_btnDelete]|" :NSLayoutFormatAlignAllCenterY];
        [vfl :@"V:|[_title]|"];
        [titleHolder.widthAnchor constraintEqualToConstant:POPOVER_TEXT_WIDTH].active = YES;
        
        _attendees = [NSStackView new];
        _attendees.orientation = NSUserInterfaceLayoutOrientationVertical;
        _attendees.alignment = NSLayoutAttributeLeft;
        _attendees.spacing = 4;
        _attendees.detachesHiddenViews = NO;
        [_attendees setClippingResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
        
        _grid = [NSGridView gridViewWithViews:@[@[titleHolder],  // row 0
                                                @[_location],    // 1
                                                @[separator()],  // 2
                                                @[_duration],    // 3
                                                @[_recurrence],  // 4
                                                @[separator()],  // 5
                                                @[_attendees],   // 6
                                                @[separator()],  // 7
                                                @[_note],        // 8
                                                @[_URL]]];       // 9
        _grid.rowSpacing = 8;
        _grid.translatesAutoresizingMaskIntoConstraints = NO;
        [_grid cellForView:_btnDelete].xPlacement = NSGridCellPlacementCenter;
        [_grid columnAtIndex:0].width = POPOVER_TEXT_WIDTH;
        [_grid columnAtIndex:0].leadingPadding  = 10;
        [_grid columnAtIndex:0].trailingPadding = 14;

        _scrollView = [NSScrollView new];
        _scrollView.drawsBackground = NO;
        _scrollView.hasVerticalScroller = YES;
        _scrollView.documentView = _grid;

        _linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
        _hiddenLinksRegex = [NSRegularExpression regularExpressionWithPattern:@"<((https?|rdar):\\/\\/[^\\s]+)>" options:NSRegularExpressionCaseInsensitive error:NULL];
        _messageLinksRegex = [NSRegularExpression regularExpressionWithPattern:@"message:%3\\S+" options:NSRegularExpressionCaseInsensitive error:NULL];
        
        _locHeight = [_location.heightAnchor constraintEqualToConstant:100];
        _locHeight.active = YES;
        _noteHeight = [_note.heightAnchor constraintEqualToConstant:100];
        _noteHeight.active = YES;
        _URLHeight = [_URL.heightAnchor constraintEqualToConstant:100];
        _URLHeight.active = YES;
    }
    return self;
}

- (void)loadView
{
    NSView *view = [NSView new];
    [view addSubview:_scrollView];
    MoVFLHelper *vfl = [[MoVFLHelper alloc] initWithSuperview:view metrics:nil views:NSDictionaryOfVariableBindings(_scrollView)];
    [vfl :@"H:|[_scrollView]|"];
    [vfl :@"V:|-8-[_scrollView]-8-|"];
    self.view = view;
}

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
    backgroundColorView.borderWidth = 0;
    backgroundColorView.fillColor = Theme.mainBackgroundColor;
    [frameView addSubview:backgroundColorView positioned:NSWindowBelow relativeTo:nil];
}

- (NSSize)size
{
    // See -loadView. Vertial padding top+bottom = 16.
    return NSMakeSize(_grid.fittingSize.width, _grid.fittingSize.height + 16);
}

- (void)scrollToTopAndFlashScrollers
{
    NSView *docView = _scrollView.documentView;
    [docView scrollPoint:NSMakePoint(0, NSHeight(docView.bounds))];
    [_scrollView flashScrollers];
}

- (void)populateWithEventInfo:(EventInfo *)info
{
    static NSDateIntervalFormatter *intervalFormatter = nil;
    if (intervalFormatter == nil) {
        intervalFormatter = [NSDateIntervalFormatter new];
        intervalFormatter.dateStyle = NSDateIntervalFormatterMediumStyle;
    }
    NSString *title = @"";
    NSString *duration = @"";
    NSString *recurrence = @"";
    intervalFormatter.timeZone  = [NSTimeZone localTimeZone];
    
    if (info && info.event) {
        if (info.event.title) title = info.event.title;
    }
    
    // Hide location row IF there's no location string.
    [_grid rowAtIndex:1].hidden = !info.event.location;
    
    // Hide recurrence row IF there's no recurrence rule.
    [_grid rowAtIndex:4].hidden = !info.event.hasRecurrenceRules;
    
    // Hide attendees row and separator above it IF there are no attendees.
    [_grid rowAtIndex:5].hidden = !info.event.hasAttendees;
    [_grid rowAtIndex:6].hidden = !info.event.hasAttendees;

    // Hide note row and separator row above it IF there's no note AND no URL.
    [_grid rowAtIndex:7].hidden = !info.event.hasNotes && !info.event.URL;
    [_grid rowAtIndex:8].hidden = !info.event.hasNotes;
    
    // Hide URL row IF there's no URL.
    [_grid rowAtIndex:9].hidden = !info.event.URL;

    // Hide delete button IF event doesn't allow modification.
    _btnDelete.hidden = !info.event.calendar.allowsContentModifications;

    // All-day events don't show time.
    intervalFormatter.timeStyle = info.event.isAllDay
        ? NSDateIntervalFormatterNoStyle
        : NSDateIntervalFormatterShortStyle;
    // All-day events technically end at the start of the day after
    // their end date. So display endDate as one less.
    NSDate *endDate = info.event.isAllDay
        ? [self.nsCal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:info.event.endDate options:0]
        : info.event.endDate;
    if (@available(macOS 13.0, *)) {
        // macOS 13 changed All-day events' end date from 12 AM of
        // day after last day of event to 11:59:59 PM of last day.
        endDate = info.event.endDate;
    }
    // Interval formatter just prints single date when from == to.
    duration = [intervalFormatter stringFromDate:info.event.startDate toDate:endDate];
    // If the locale is English and we are in 12 hour time,
    // remove :00 from the time. Effect is 3:00 PM -> 3 PM.
    if ([[[NSLocale currentLocale] localeIdentifier] hasPrefix:@"en"]) {
        if ([duration containsString:@"AM"] || [duration containsString:@"PM"] ||
            [duration containsString:@"am"] || [duration containsString:@"pm"]) {
            duration = [duration stringByReplacingOccurrencesOfString:@":00" withString:@""];
        }
    }
    // If the event is not All-day and the start and end dates are
    // different, put them on different lines.
    // The – is U+2013 (en-dash) and the space is U+2009 (thin space)
    if (!info.event.isAllDay) {
        NSDateComponents *start = [intervalFormatter.calendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:info.event.startDate];
        NSDateComponents *end = [intervalFormatter.calendar components:NSCalendarUnitMonth | NSCalendarUnitDay fromDate:info.event.endDate];
        if (start.day != end.day || start.month != end.month) {
            duration = [duration stringByReplacingOccurrencesOfString:@"– " withString:@"–\n"];
        }
    }
    // Recurrence.
    if (info.event.hasRecurrenceRules) {
        recurrence = [NSString stringWithFormat:@"%@ ", NSLocalizedString(@"Repeat:", nil)];
        EKRecurrenceRule *rule = info.event.recurrenceRules.firstObject;
        NSString *frequency = @"✓";
        switch (rule.frequency) {
            case EKRecurrenceFrequencyDaily:
                frequency = rule.interval == 1
                    ? NSLocalizedString(@"Every Day", nil)
                    : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Days", nil), rule.interval];
                break;
            case EKRecurrenceFrequencyWeekly:
                frequency = rule.interval == 1
                    ? NSLocalizedString(@"Every Week", nil)
                    : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Weeks", nil), rule.interval];
                break;
            case EKRecurrenceFrequencyMonthly:
                frequency = rule.interval == 1
                    ? NSLocalizedString(@"Every Month", nil)
                    : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Months", nil), rule.interval];
                break;
            case EKRecurrenceFrequencyYearly:
                frequency = rule.interval == 1
                    ? NSLocalizedString(@"Every Year", nil)
                    : [NSString stringWithFormat:NSLocalizedString(@"Every %zd Years", nil), rule.interval];
                break;
            default:
                break;
        }
        recurrence = [recurrence stringByAppendingString:frequency];
        if (rule.recurrenceEnd) {
            if (rule.recurrenceEnd.endDate) {
                intervalFormatter.timeStyle = NSDateIntervalFormatterNoStyle;
                NSString *endRecurrence = [NSString stringWithFormat:@"\n%@ %@", NSLocalizedString(@"End Repeat:", nil), [intervalFormatter stringFromDate:rule.recurrenceEnd.endDate toDate:rule.recurrenceEnd.endDate]];
                recurrence = [recurrence stringByAppendingString:endRecurrence];
            }
            if (rule.recurrenceEnd.occurrenceCount) {
                NSString *endRecurrence = [NSString stringWithFormat:@"\n%@ ×%zd", NSLocalizedString(@"End Repeat:", nil), rule.recurrenceEnd.occurrenceCount];
                recurrence = [recurrence stringByAppendingString:endRecurrence];
            }
        }
    }
    
    // Location
    if (info.event.location) {
        NSString *trimmedLoc = [info.event.location stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmedLoc isEqualToString:@""]) {
            [_grid rowAtIndex:1].hidden = YES;
        }
        else {
            [self populateTextView:_location withString:trimmedLoc heightConstraint:_locHeight];
        }
    }
    
    // Attendees
    if (info.event.hasAttendees) {
        
        // Block returns YES if participant is the event's organizer.
        BOOL (^ParticipantIsOrganizer)(EKParticipant*, EKParticipant*) = ^BOOL(EKParticipant *participant, EKParticipant *organizer) {
            // https://stackoverflow.com/a/17222036/111418
            return [participant.URL.resourceSpecifier isEqualToString:organizer.URL.resourceSpecifier];
        };
        
        // Sometimes info.event.organizer isn't in info.event.attendees.
        // Make an array of participants that definitely has the organizer.
        NSMutableArray<EKParticipant *> *participants = [NSMutableArray new];
        if (info.event.organizer) {
            [participants addObject:info.event.organizer];
        }
        for (EKParticipant *p in info.event.attendees) {
            // Don't double-add the organizer.
            if (!ParticipantIsOrganizer(p, info.event.organizer)) {
                [participants addObject:p];
            }
        }
        // Sort participants with organizer first, then accepted, pending, declined.
        NSArray<EKParticipant *> *sortedParticipants = [participants sortedArrayUsingComparator:^NSComparisonResult(EKParticipant * p1, EKParticipant *p2) {
            if (ParticipantIsOrganizer(p1, info.event.organizer)) return NSOrderedAscending;
            if (ParticipantIsOrganizer(p2, info.event.organizer)) return NSOrderedDescending;
            if (p1.participantStatus == EKParticipantStatusAccepted) return NSOrderedAscending;
            if (p2.participantStatus == EKParticipantStatusAccepted) return NSOrderedDescending;
            if (p1.participantStatus == EKParticipantStatusPending) return NSOrderedAscending;
            if (p2.participantStatus == EKParticipantStatusPending) return NSOrderedDescending;
            return NSOrderedDescending;
        }];
        NSMutableArray<NSStackView *> *attendeesArray = [NSMutableArray new];
        for (EKParticipant *participant in sortedParticipants) {
            NSString *orgIcon = ParticipantIsOrganizer(participant, info.event.organizer) ? @"•" : @"";
            NSString *statusIcon = @"􀁜"; // questionmark.circle (Requires SF fonts to see)
            NSColor *textColor = Theme.agendaEventDateTextColor;
            if (participant.participantStatus == EKParticipantStatusAccepted) {
                statusIcon = @"􀁢"; // checkmark.circle (Requires SF fonts to see)
                textColor = Theme.agendaEventTextColor;
            }
            if (participant.participantStatus == EKParticipantStatusDeclined) {
                statusIcon = @"􀁐"; // x.circle (Requires SF fonts to see)
                textColor = Theme.agendaEventTextColor;
            }

            // Status icons are in the embedded font Mow.otf, CANNOT compress.
            NSTextField *statusLabel = [NSTextField labelWithString:statusIcon];
            statusLabel.textColor = textColor;
            statusLabel.font = [NSFont fontWithName:@"Mow" size:SizePref.fontSize];
            [statusLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

            // EKParticipant name and URL.resourceSpecifier (email addr)
            // are nullable (why?...). Make sure we don't try to create
            // a label with a null string.
            NSString *participantString = participant.name;
            if (!participantString) {
                participantString = participant.URL.resourceSpecifier; // email addr
                if (!participantString) participantString = @"***";
            }

            // Participant uses system font, CAN compress.
            NSTextField *participantLabel = [NSTextField labelWithString:participantString];
            participantLabel.selectable = YES;
            participantLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            participantLabel.textColor = textColor;
            participantLabel.font = [NSFont systemFontOfSize:SizePref.fontSize];
            [participantLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

            // Organizer icon uses system font, CANNOT compress.
            NSTextField *organizerLabel = [NSTextField labelWithString:orgIcon];
            organizerLabel.textColor = textColor;
            organizerLabel.font = [NSFont systemFontOfSize:SizePref.fontSize];
            [organizerLabel setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];

            // Horizontally stack status icon, participant, organizer indicator.
            NSStackView *attendee = [NSStackView stackViewWithViews:@[statusLabel, participantLabel, organizerLabel]];
            attendee.alignment = NSLayoutAttributeBaseline;
            attendee.detachesHiddenViews = NO;
            [attendee setHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
            [attendee setClippingResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
            [attendeesArray addObject:attendee];
        }
        // Vertically stack attendees.
        [_attendees setViews:attendeesArray inGravity:NSStackViewGravityBottom];
    }

    // Notes
    if (info.event.hasNotes) {
        NSString *trimmedNotes = [info.event.notes stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmedNotes isEqualToString:@""]) {
            // Hide note row and separator row above it, provided no URL.
            [_grid rowAtIndex:7].hidden = !info.event.URL;
            [_grid rowAtIndex:8].hidden = YES;
        }
        else {
            [self populateTextView:_note withString:trimmedNotes heightConstraint:_noteHeight];
        }
    }

    // URL
    if (info.event.URL) {
        // HACK: append a space at end of URL to force correct height calc. Without
        // this, height is sometimes wrong on first display.
        NSString *absURL = [NSString stringWithFormat:@"%@ ", info.event.URL.absoluteString];
        [self populateTextView:_URL withString:absURL heightConstraint:_URLHeight];
    }
    
    _title.stringValue = title;
    _duration.stringValue = duration;
    _recurrence.stringValue = recurrence;
    
    _title.font = [NSFont systemFontOfSize:SizePref.fontSize weight:NSFontWeightSemibold];
    _duration.font = [NSFont systemFontOfSize:SizePref.fontSize];
    _recurrence.font = _duration.font;
    _btnDelete.font  = [NSFont systemFontOfSize:SizePref.fontSize+3];

    _title.textColor = Theme.agendaEventTextColor;
    _duration.textColor = Theme.agendaEventTextColor;
    _recurrence.textColor = Theme.agendaEventTextColor;
}

- (void)populateTextView:(NSTextView *)textView withString:(NSString *)string heightConstraint:(NSLayoutConstraint *)constraint
{
    // We will detect mail message URLs with _messageLinksRegex. These URLs
    // link directly to specific messages. They may contain fragments that look
    // like standard URLs that are picked up by _linkDetector. In order to avoid
    // conflicts, we keep an array of NSRanges for matched message URLs. When
    // we go to match standard URLs, we will only match those whose NSRanges
    // don't intersect (overlap) with message URLs.
    NSMutableArray *messageLinkRanges = [NSMutableArray new];
    
    // Ugly hack to deal with Microsoft's insane habit of putting links
    // in angle brackets, making them invisible when rendereed as HTML.
    string = [_hiddenLinksRegex stringByReplacingMatchesInString:string options:kNilOptions range:NSMakeRange(0, string.length) withTemplate:@"&lt;$1&gt;"];

    string = [string stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
    NSData *htmlData = [string dataUsingEncoding:NSUnicodeStringEncoding];
    NSMutableAttributedString *attrString = [[NSMutableAttributedString alloc] initWithHTML:htmlData documentAttributes:nil];
    
    [attrString addAttribute:NSFontAttributeName value:[NSFont systemFontOfSize:SizePref.fontSize] range:NSMakeRange(0, attrString.length)];
    [attrString addAttribute:NSForegroundColorAttributeName value:Theme.agendaEventTextColor range:NSMakeRange(0, attrString.length)];
    [_messageLinksRegex enumerateMatchesInString:attrString.string options:kNilOptions range:NSMakeRange(0, attrString.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        NSString *link = [string substringWithRange:result.range];
        [attrString addAttribute:NSLinkAttributeName value:link range:result.range];
        [messageLinkRanges addObject:[NSValue valueWithRange:result.range]];
    }];
    [_linkDetector enumerateMatchesInString:attrString.string options:kNilOptions range:NSMakeRange(0, attrString.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        // Make sure result.range doesn't intersect (overlap) with the
        // range of a message URL matched by _messageLinksRegex.
        BOOL resultOverlapsAMessageLink = NO;
        for (NSValue *val in messageLinkRanges) {
            NSRange intersection = NSIntersectionRange(val.rangeValue, result.range);
            if (intersection.length != 0) {
                resultOverlapsAMessageLink = YES;
                break;
            }
        }
        if (!resultOverlapsAMessageLink) {
            [attrString addAttribute:NSLinkAttributeName value:result.URL.absoluteString range:result.range];
        }
    }];
    textView.textStorage.attributedString = attrString;
    [self setHeightConstraint:constraint forTextView:textView];
}

- (void)setHeightConstraint:(NSLayoutConstraint *)constraint forTextView:(NSTextView *)textView
{
    // Force layout and then calculate text height.
    // stackoverflow.com/a/44969138/111418
    (void) [textView.layoutManager glyphRangeForTextContainer:textView.textContainer];
    NSRect textRect = [textView.layoutManager usedRectForTextContainer:textView.textContainer];
    constraint.constant = textRect.size.height;
}

@end
