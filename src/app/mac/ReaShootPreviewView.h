#pragma once

#import <Cocoa/Cocoa.h>

#include <cstdint>
#include <vector>

@interface ReaShootPreviewView : NSView
- (void)setFramePixels:(std::vector<uint8_t>)pixels width:(int)width height:(int)height stride:(int)stride;
- (void)setDisplaySizeWithWidth:(int)width height:(int)height;
- (void)clearFrameWithMessage:(NSString *)message;
- (void)setEmptyMessage:(NSString *)message;
@end
