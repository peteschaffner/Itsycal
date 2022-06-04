//
//  EventViewController.h
//  Itsycal
//
//  Created by Sanjay Madan on 2/25/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "OpaquePopoverViewController.h"
#import "EventCenter.h"

@class EventCenter;

@interface EventViewController : OpaquePopoverViewController <NSTextFieldDelegate, NSTextViewDelegate>

@property (nonatomic, weak) EventCenter *ec;
@property (nonatomic, weak) NSPopover *enclosingPopover;
@property (nonatomic, weak) NSCalendar *cal;
@property (nonatomic) NSDate *calSelectedDate;
@property (nullable, nonatomic) NSString *eventTitleString;
@property (nullable, nonatomic) NSString *locationString;
@property (nullable, nonatomic) NSString *calendarIdentifier;
@property (nullable, nonatomic) NSString *eventId;
@property (nullable, nonatomic) NSDate *startDateValue;
@property (nullable, nonatomic) NSDate *endDateValue;
@property (nonatomic) BOOL allDay;
@property (nullable, nonatomic) EKRecurrenceRule *recurrenceRule;
@property (nullable, nonatomic) EKAlarm *alert;

@end
