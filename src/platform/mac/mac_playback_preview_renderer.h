#pragma once

#import <Cocoa/Cocoa.h>

@interface ReaShootMacPlaybackPreviewRenderer : NSObject
- (instancetype)initWithContainerView:(NSView *)containerView;
- (void)showPath:(NSString *)path
       itemStart:(double)itemStart
    sourceOffset:(double)sourceOffset
 projectPosition:(double)projectPosition;
- (void)hide;
@end
