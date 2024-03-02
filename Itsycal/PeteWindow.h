//
//  PeteWindow.h
//  Itsycal
//
//  Created by Pete Schaffner on 01/03/2024.
//  Copyright © 2024 mowglii.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PeteWindow : NSPanel

- (void)positionRelativeToRect:(NSRect)rect screenMaxX:(CGFloat)screenMaxX;

@end

NS_ASSUME_NONNULL_END
