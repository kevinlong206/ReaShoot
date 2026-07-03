#pragma once

#import <Foundation/Foundation.h>

typedef void (^ReaShootMacH264FrameHandler)(const void *pixels, int width, int height, int strideBytes);

@interface ReaShootMacH264FrameDecoder : NSObject
- (instancetype)initWithFrameHandler:(ReaShootMacH264FrameHandler)frameHandler;
- (void)reset;
- (void)decodeAccessUnit:(NSData *)accessUnit;
@end
