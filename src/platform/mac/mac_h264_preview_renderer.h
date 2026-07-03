#pragma once

#import <AVFoundation/AVFoundation.h>

typedef void (^ReaShootMacH264FrameHandler)(const void *pixels, int width, int height, int strideBytes);

@interface ReaShootMacH264PreviewRenderer : NSObject
- (instancetype)initWithLayer:(AVSampleBufferDisplayLayer *)layer;
- (void)reset;
- (void)renderAccessUnit:(NSData *)accessUnit;
@end

@interface ReaShootMacH264FrameDecoder : NSObject
- (instancetype)initWithFrameHandler:(ReaShootMacH264FrameHandler)frameHandler;
- (void)reset;
- (void)decodeAccessUnit:(NSData *)accessUnit;
@end
