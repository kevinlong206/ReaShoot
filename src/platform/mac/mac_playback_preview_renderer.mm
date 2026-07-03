#import "mac_playback_preview_renderer.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>

#include <cmath>
#include <cstring>
#include <memory>
#include <vector>

@interface ReaShootMacPlaybackPreviewRenderer ()
@property(nonatomic, strong) AVAssetImageGenerator *imageGenerator;
@property(nonatomic, copy) NSString *activePath;
@property(nonatomic, assign) double lastRenderedSourceTime;
@property(nonatomic, copy) ReaShootMacPlaybackFrameHandler frameHandler;
@property(nonatomic, assign) BOOL visible;
@end

namespace reashoot::platform::mac {

namespace {

class MacPlaybackPreview final : public core::PlaybackPreview {
public:
  explicit MacPlaybackPreview(core::VideoFrameCallback frameHandler) {
    renderer_ = [[ReaShootMacPlaybackPreviewRenderer alloc] initWithFrameHandler:^(const void *pixels, int width, int height, int strideBytes) {
      if (!frameHandler || !pixels || width <= 0 || height <= 0 || strideBytes <= 0) {
        return;
      }
      core::VideoFrame frame;
      frame.width = width;
      frame.height = height;
      frame.strideBytes = strideBytes;
      const auto byteCount = static_cast<size_t>(strideBytes) * static_cast<size_t>(height);
      const auto *bytes = static_cast<const uint8_t *>(pixels);
      frame.pixels.assign(bytes, bytes + byteCount);
      frameHandler(frame);
    }];
  }

  void showMedia(const std::string &path, double itemStart, double sourceOffset, double projectPosition) override {
    [renderer_ showPath:[NSString stringWithUTF8String:path.c_str()]
              itemStart:itemStart
           sourceOffset:sourceOffset
        projectPosition:projectPosition];
  }

  void hide() override { [renderer_ hide]; }

private:
  __strong ReaShootMacPlaybackPreviewRenderer *renderer_ = nil;
};

} // namespace

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler) {
  return std::make_unique<MacPlaybackPreview>(std::move(frameHandler));
}

} // namespace reashoot::platform::mac

@implementation ReaShootMacPlaybackPreviewRenderer

- (instancetype)initWithFrameHandler:(ReaShootMacPlaybackFrameHandler)frameHandler {
  self = [super init];
  if (self) {
    _frameHandler = [frameHandler copy];
    _lastRenderedSourceTime = -1.0;
  }
  return self;
}

- (void)showPath:(NSString *)path
       itemStart:(double)itemStart
    sourceOffset:(double)sourceOffset
 projectPosition:(double)projectPosition {
  if (path.length == 0 || !self.frameHandler) {
    return;
  }

  const BOOL switchedSource = !self.imageGenerator || ![self.activePath isEqualToString:path];
  if (switchedSource) {
    self.activePath = path;
    AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:path]];
    self.imageGenerator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    self.imageGenerator.appliesPreferredTrackTransform = YES;
    self.imageGenerator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.02, 600);
    self.imageGenerator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.02, 600);
    self.lastRenderedSourceTime = -1.0;
  }

  const double sourceTime = projectPosition - itemStart + sourceOffset;
  if (!switchedSource && self.visible && self.lastRenderedSourceTime >= 0.0 &&
      std::fabs(sourceTime - self.lastRenderedSourceTime) < (1.0 / 40.0)) {
    return;
  }

  CMTime requestedTime = CMTimeMakeWithSeconds(sourceTime > 0.0 ? sourceTime : 0.0, 600);
  NSError *error = nil;
  CGImageRef image = [self.imageGenerator copyCGImageAtTime:requestedTime actualTime:nullptr error:&error];
  if (!image) {
    return;
  }

  const size_t width = CGImageGetWidth(image);
  const size_t height = CGImageGetHeight(image);
  const size_t stride = width * 4u;
  NSMutableData *frameData = [NSMutableData dataWithLength:height * stride];
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate(frameData.mutableBytes,
                                               width,
                                               height,
                                               8,
                                               stride,
                                               colorSpace,
                                               kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGColorSpaceRelease(colorSpace);
  if (!context) {
    CGImageRelease(image);
    return;
  }
  CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
  CGContextRelease(context);
  CGImageRelease(image);

  NSData *immutableFrame = [frameData copy];
  ReaShootMacPlaybackFrameHandler handler = self.frameHandler;
  handler(immutableFrame.bytes, static_cast<int>(width), static_cast<int>(height), static_cast<int>(stride));
  self.lastRenderedSourceTime = sourceTime;
  self.visible = YES;
}

- (void)hide {
  self.visible = NO;
  self.lastRenderedSourceTime = -1.0;
}

@end
