#import "mac_h264_preview_renderer.h"

#include "../../core/h264_annex_b.h"

#import <VideoToolbox/VideoToolbox.h>

#include <cstring>
#include <memory>
#include <utility>
#include <vector>

@interface ReaShootMacH264FrameDecoder ()
@property(nonatomic, assign) CMVideoFormatDescriptionRef formatDescription;
@property(nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property(nonatomic, copy) ReaShootMacH264FrameHandler frameHandler;
- (void)handlePixelBuffer:(CVPixelBufferRef)pixelBuffer;
@end

namespace {

void ReaShootMacH264FrameDecoderOutputCallback(void *refCon,
                                               void *sourceFrameRefCon,
                                               OSStatus status,
                                               VTDecodeInfoFlags infoFlags,
                                               CVImageBufferRef imageBuffer,
                                               CMTime presentationTimeStamp,
                                               CMTime presentationDuration) {
  (void)sourceFrameRefCon;
  (void)infoFlags;
  (void)presentationTimeStamp;
  (void)presentationDuration;
  if (status != noErr || !imageBuffer) {
    return;
  }
  ReaShootMacH264FrameDecoder *decoder = (__bridge ReaShootMacH264FrameDecoder *)refCon;
  [decoder handlePixelBuffer:static_cast<CVPixelBufferRef>(imageBuffer)];
}

} // namespace

@implementation ReaShootMacH264FrameDecoder

- (instancetype)initWithFrameHandler:(ReaShootMacH264FrameHandler)frameHandler {
  self = [super init];
  if (self) {
    _frameHandler = [frameHandler copy];
  }
  return self;
}

- (void)dealloc {
  [self reset];
}

- (void)reset {
  if (self.decompressionSession) {
    VTDecompressionSessionInvalidate(self.decompressionSession);
    CFRelease(self.decompressionSession);
    self.decompressionSession = nil;
  }
  if (self.formatDescription) {
    CFRelease(self.formatDescription);
    self.formatDescription = nil;
  }
}

- (BOOL)ensureDecompressionSession {
  if (self.decompressionSession) {
    return YES;
  }
  if (!self.formatDescription) {
    return NO;
  }

  NSDictionary *attributes = @{
    (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
  };
  VTDecompressionOutputCallbackRecord callback = {
      ReaShootMacH264FrameDecoderOutputCallback,
      (__bridge void *)self,
  };
  OSStatus status = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                 self.formatDescription,
                                                 nullptr,
                                                 (__bridge CFDictionaryRef)attributes,
                                                 &callback,
                                                 &_decompressionSession);
  return status == noErr && self.decompressionSession;
}

- (void)decodeAccessUnit:(NSData *)accessUnit {
  if (accessUnit.length < 5) {
    return;
  }

  const uint8_t *bytes = static_cast<const uint8_t *>(accessUnit.bytes);
  const NSUInteger length = accessUnit.length;
  std::vector<reashoot::core::H264NalUnit> ranges = reashoot::core::splitAnnexB(bytes, length);

  NSData *sps = nil;
  NSData *pps = nil;
  NSMutableData *sampleData = [NSMutableData data];
  for (const auto &range : ranges) {
    const NSUInteger naluStart = range.offset;
    const NSUInteger naluLength = range.size;
    if (naluLength == 0) {
      continue;
    }
    const uint8_t naluType = range.type;
    NSData *nalu = [NSData dataWithBytes:bytes + naluStart length:naluLength];
    if (naluType == 7) {
      sps = nalu;
      continue;
    }
    if (naluType == 8) {
      pps = nalu;
      continue;
    }
    uint32_t bigEndianLength = CFSwapInt32HostToBig(static_cast<uint32_t>(naluLength));
    [sampleData appendBytes:&bigEndianLength length:sizeof(bigEndianLength)];
    [sampleData appendData:nalu];
  }

  if (sps && pps) {
    const uint8_t *parameterSetPointers[2] = {
        static_cast<const uint8_t *>(sps.bytes),
        static_cast<const uint8_t *>(pps.bytes),
    };
    const size_t parameterSetSizes[2] = {sps.length, pps.length};
    CMVideoFormatDescriptionRef formatDescription = nil;
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(kCFAllocatorDefault,
                                                                          2,
                                                                          parameterSetPointers,
                                                                          parameterSetSizes,
                                                                          4,
                                                                          &formatDescription);
    if (status == noErr && formatDescription) {
      if (self.decompressionSession) {
        VTDecompressionSessionInvalidate(self.decompressionSession);
        CFRelease(self.decompressionSession);
        self.decompressionSession = nil;
      }
      if (self.formatDescription) {
        CFRelease(self.formatDescription);
      }
      self.formatDescription = formatDescription;
    }
  }

  if (sampleData.length == 0 || ![self ensureDecompressionSession]) {
    return;
  }

  CMBlockBufferRef blockBuffer = nil;
  OSStatus blockStatus = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                            nullptr,
                                                            sampleData.length,
                                                            kCFAllocatorDefault,
                                                            nullptr,
                                                            0,
                                                            sampleData.length,
                                                            0,
                                                            &blockBuffer);
  if (blockStatus != noErr || !blockBuffer) {
    return;
  }
  blockStatus = CMBlockBufferReplaceDataBytes(sampleData.bytes, blockBuffer, 0, sampleData.length);
  if (blockStatus != noErr) {
    CFRelease(blockBuffer);
    return;
  }

  CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
  const size_t sampleSize = sampleData.length;
  CMSampleBufferRef sampleBuffer = nil;
  OSStatus sampleStatus = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                                    blockBuffer,
                                                    self.formatDescription,
                                                    1,
                                                    1,
                                                    &timing,
                                                    1,
                                                    &sampleSize,
                                                    &sampleBuffer);
  CFRelease(blockBuffer);
  if (sampleStatus != noErr || !sampleBuffer) {
    return;
  }

  VTDecompressionSessionDecodeFrame(self.decompressionSession, sampleBuffer, 0, nullptr, nullptr);
  CFRelease(sampleBuffer);
}

- (void)handlePixelBuffer:(CVPixelBufferRef)pixelBuffer {
  if (!self.frameHandler || !pixelBuffer) {
    return;
  }
  if (CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
    return;
  }
  const int width = static_cast<int>(CVPixelBufferGetWidth(pixelBuffer));
  const int height = static_cast<int>(CVPixelBufferGetHeight(pixelBuffer));
  const size_t sourceStride = CVPixelBufferGetBytesPerRow(pixelBuffer);
  const void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  if (width <= 0 || height <= 0 || !baseAddress || sourceStride < static_cast<size_t>(width) * 4) {
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return;
  }

  NSMutableData *frameData = [NSMutableData dataWithLength:static_cast<NSUInteger>(width) * static_cast<NSUInteger>(height) * 4u];
  uint8_t *destination = static_cast<uint8_t *>(frameData.mutableBytes);
  const auto *source = static_cast<const uint8_t *>(baseAddress);
  const size_t destinationStride = static_cast<size_t>(width) * 4u;
  for (int y = 0; y < height; ++y) {
    memcpy(destination + static_cast<size_t>(y) * destinationStride, source + static_cast<size_t>(y) * sourceStride, destinationStride);
  }
  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  NSData *immutableFrame = [frameData copy];
  ReaShootMacH264FrameHandler handler = self.frameHandler;
  dispatch_async(dispatch_get_main_queue(), ^{
    handler(immutableFrame.bytes, width, height, static_cast<int>(destinationStride));
  });
}

@end

namespace reashoot::platform::mac {

namespace {

class MacH264PreviewRenderer final : public core::PreviewRenderer {
public:
  explicit MacH264PreviewRenderer(core::VideoFrameCallback frameHandler) {
    decoder_ = [[ReaShootMacH264FrameDecoder alloc] initWithFrameHandler:^(const void *pixels, int width, int height, int strideBytes) {
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

  void reset() override { [decoder_ reset]; }

  void renderAnnexBAccessUnit(const uint8_t *bytes, size_t length) override {
    if (!bytes || length == 0) {
      return;
    }
    NSData *data = [NSData dataWithBytes:bytes length:length];
    [decoder_ decodeAccessUnit:data];
  }

private:
  __strong ReaShootMacH264FrameDecoder *decoder_ = nil;
};

} // namespace

std::unique_ptr<core::PreviewRenderer> createH264PreviewRenderer(core::VideoFrameCallback frameHandler) {
  return std::make_unique<MacH264PreviewRenderer>(std::move(frameHandler));
}

} // namespace reashoot::platform::mac
