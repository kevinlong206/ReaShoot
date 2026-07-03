#pragma once

#import <Foundation/Foundation.h>

typedef void (^ReaShootMacPlaybackFrameHandler)(const void *pixels, int width, int height, int strideBytes);

@interface ReaShootMacPlaybackPreviewRenderer : NSObject
- (instancetype)initWithFrameHandler:(ReaShootMacPlaybackFrameHandler)frameHandler;
- (void)showPath:(NSString *)path
       itemStart:(double)itemStart
    sourceOffset:(double)sourceOffset
 projectPosition:(double)projectPosition;
- (void)hide;
@end
