/*
 * Things3.h
 */

#import <AppKit/AppKit.h>
#import <ScriptingBridge/ScriptingBridge.h>


@class Things3Window, Things3Application, Things3List, Things3Area, Things3Contact, Things3Tag, Things3ToDo, Things3Project, Things3SelectedToDo;

enum Things3PrintingErrorHandling {
	Things3PrintingErrorHandlingStandard = 'lwst' /* Standard PostScript error handling */,
	Things3PrintingErrorHandlingDetailed = 'lwdt' /* print a detailed report of PostScript errors */
};
typedef enum Things3PrintingErrorHandling Things3PrintingErrorHandling;

enum Things3Status {
	Things3StatusOpen = 'tdio' /* To do is open. */,
	Things3StatusCompleted = 'tdcm' /* To do has been completed. */,
	Things3StatusCanceled = 'tdcl' /* To do has been canceled. */
};
typedef enum Things3Status Things3Status;

@protocol Things3GenericMethods

- (void) close;  // Close a window.
- (void) printWithProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) delete;  // Delete an object.
- (SBObject *) duplicateTo:(SBObject *)to withProperties:(NSDictionary *)withProperties;  // Copy object(s) and put the copies at a new location.
- (void) show;  // Show Things item in the UI
- (void) moveTo:(Things3List *)to;  // Move a to do to a different list.
- (void) scheduleFor:(NSDate *)for_;  // Schedules a Things to do

@end



/*
 * Standard Suite
 */

// A window.
@interface Things3Window : SBObject <Things3GenericMethods>

@property (copy, readonly) NSString *name;  // The full title of the window.
- (NSInteger) id;  // The unique identifier of the window.
@property NSInteger index;  // The index of the window, ordered front to back.
@property NSRect bounds;  // The bounding rectangle of the window.
@property (readonly) BOOL closeable;  // Whether the window has a close box.
@property (readonly) BOOL minimizable;  // Whether the window can be minimized.
@property BOOL minimized;  // Whether the window is currently minimized.
@property (readonly) BOOL resizable;  // Whether the window can be resized.
@property BOOL visible;  // Whether the window is currently visible.
@property (readonly) BOOL zoomable;  // Whether the window can be zoomed.
@property BOOL zoomed;  // Whether the window is currently zoomed.


@end



/*
 * Things Suite
 */

// The application's top-level scripting object.
@interface Things3Application : SBApplication

- (SBElementArray<Things3Window *> *) windows;
- (SBElementArray<Things3List *> *) lists;
- (SBElementArray<Things3ToDo *> *) toDos;
- (SBElementArray<Things3Project *> *) projects;
- (SBElementArray<Things3Area *> *) areas;
- (SBElementArray<Things3Contact *> *) contacts;
- (SBElementArray<Things3Tag *> *) tags;
- (SBElementArray<Things3SelectedToDo *> *) selectedToDos;

@property (copy, readonly) NSString *name;  // The name of the application.
@property (readonly) BOOL frontmost;  // Is this the frontmost (active) application?
@property (copy, readonly) NSString *version;  // The version of the application.

- (void) print:(id)x withProperties:(NSDictionary *)withProperties printDialog:(BOOL)printDialog;  // Print a document.
- (void) quit;  // Quit the application.
- (BOOL) exists:(id)x;  // Verify if an object exists.
- (void) showQuickEntryPanelWithAutofill:(BOOL)withAutofill withProperties:(NSDictionary *)withProperties;  // Show Things Quick Entry panel
- (void) logCompletedNow;  // Log completed items now
- (void) emptyTrash;  // Empty Things trash
- (Things3Contact *) addContactNamed:(NSString *)x;  // Add a contact to Things
- (Things3ToDo *) parseQuicksilverInput:(NSString *)x;  // Add new Things to do from input in Quicksilver syntax

@end

// Represents a Things list.
@interface Things3List : SBObject <Things3GenericMethods>

- (SBElementArray<Things3ToDo *> *) toDos;

- (NSString *) id;  // The unique identifier of the list.
@property (copy) NSString *name;  // Name of the list


@end

// Represents a Things area of responsibility.
@interface Things3Area : Things3List

- (SBElementArray<Things3ToDo *> *) toDos;
- (SBElementArray<Things3Tag *> *) tags;

@property (copy) NSString *tagNames;  // Tag names separated by comma
@property BOOL collapsed;  // Is this area collapsed?


@end

// Represents a Things contact.
@interface Things3Contact : Things3List

- (SBElementArray<Things3ToDo *> *) toDos;


@end

// Represents a Things tag.
@interface Things3Tag : SBObject <Things3GenericMethods>

- (SBElementArray<Things3Tag *> *) tags;
- (SBElementArray<Things3ToDo *> *) toDos;

- (NSString *) id;  // The unique identifier of the tag.
@property (copy) NSString *name;  // Name of the tag
@property (copy) NSString *keyboardShortcut;  // Keyboard shortcut for the tag
@property (copy) Things3Tag *parentTag;  // Parent tag


@end

// Represents a Things to do.
@interface Things3ToDo : SBObject <Things3GenericMethods>

- (SBElementArray<Things3Tag *> *) tags;

- (NSString *) id;  // The unique identifier of the to do.
@property (copy) NSString *name;  // Name of the to do
@property (copy) NSDate *creationDate;  // Creation date of the to do
@property (copy) NSDate *modificationDate;  // Modification date of the to do
@property (copy) NSDate *dueDate;  // Due date of the to do
@property (copy, readonly) NSDate *activationDate;  // Activation date of the scheduled to do
@property (copy) NSDate *completionDate;  // Completion date of the to do
@property (copy) NSDate *cancellationDate;  // Cancellation date of the to do
@property Things3Status status;  // Status of the to do
@property (copy) NSString *tagNames;  // Tag names separated by comma
@property (copy) NSString *notes;  // Notes of the to do
@property (copy) Things3Project *project;  // Project the to do belongs to
@property (copy) Things3Area *area;  // Area the to do belongs to
@property (copy) Things3Contact *contact;  // Contact the to do is assigned to

- (void) edit;  // Edit Things to do

@end

// Represents a Things project.
@interface Things3Project : Things3ToDo

- (SBElementArray<Things3ToDo *> *) toDos;


@end

// Represents a to do selected in Things UI.
@interface Things3SelectedToDo : Things3ToDo


@end

