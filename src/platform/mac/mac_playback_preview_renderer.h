#pragma once

#include "../../core/ui_interfaces.h"

#import <Foundation/Foundation.h>

#include <memory>

typedef void (^ReaShootMacPlaybackFrameHandler)(const void *pixels, int width, int height, int strideBytes);

@interface ReaShootMacPlaybackPreviewRenderer : NSObject
- (instancetype)initWithFrameHandler:(ReaShootMacPlaybackFrameHandler)frameHandler;
- (void)showPath:(NSString *)path
       itemStart:(double)itemStart
    sourceOffset:(double)sourceOffset
 projectPosition:(double)projectPosition;
- (void)hide;
@end

namespace reashoot::platform::mac {

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler);

} // namespace reashoot::platform::mac
