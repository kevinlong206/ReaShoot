#pragma once

#import <AVFoundation/AVFoundation.h>

@interface ReaShootMacH264PreviewRenderer : NSObject
- (instancetype)initWithLayer:(AVSampleBufferDisplayLayer *)layer;
- (void)reset;
- (void)renderAccessUnit:(NSData *)accessUnit;
@end
