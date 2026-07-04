#pragma once

#include "../../core/platform_interfaces.h"

#import <Foundation/Foundation.h>

#include <memory>

typedef void (^ReaShootMacH264FrameHandler)(const void *pixels, int width, int height, int strideBytes);
typedef void (^ReaShootMacDecoderStatusHandler)(BOOL hardwareAccelerated, const char *system);

@interface ReaShootMacH264FrameDecoder : NSObject
- (instancetype)initWithFrameHandler:(ReaShootMacH264FrameHandler)frameHandler
                decoderStatusHandler:(ReaShootMacDecoderStatusHandler)decoderStatusHandler;
- (void)reset;
- (void)decodeAccessUnit:(NSData *)accessUnit;
@end

namespace reashoot::platform::mac {

std::unique_ptr<core::PreviewRenderer> createH264PreviewRenderer(core::VideoFrameCallback frameHandler,
                                                                 core::DecoderStatusCallback decoderStatusHandler = {});

} // namespace reashoot::platform::mac
