#import "mac_h264_preview_renderer.h"

#include "../../core/h264_annex_b.h"

#import <VideoToolbox/VideoToolbox.h>

#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

@interface ReaShootMacH264FrameDecoder ()
@property(nonatomic, assign) CMVideoFormatDescriptionRef formatDescription;
@property(nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property(nonatomic, copy) ReaShootMacH264FrameHandler frameHandler;
@property(nonatomic, copy) ReaShootMacDecoderStatusHandler decoderStatusHandler;
- (void)handlePixelBuffer:(CVPixelBufferRef)pixelBuffer;
@end

namespace {

using SteadyClock = std::chrono::steady_clock;

struct PreviewDiagnosticMetadata {
  bool valid = false;
  uint64_t sequence = 0;
  uint64_t sourceUnixMicros = 0;
  uint32_t nalTypes = 0;
};

uint64_t wallClockMicros() {
  return static_cast<uint64_t>([[NSDate date] timeIntervalSince1970] * 1'000'000.0);
}

uint64_t readBigEndianU64(const uint8_t *bytes) {
  uint64_t value = 0;
  for (int i = 0; i < 8; ++i) {
    value = (value << 8) | bytes[i];
  }
  return value;
}

PreviewDiagnosticMetadata parseDiagnosticSEI(const uint8_t *bytes, size_t length) {
  PreviewDiagnosticMetadata metadata;
  for (const auto &unit : reashoot::core::splitAnnexB(bytes, length)) {
    if (unit.type < 32) {
      metadata.nalTypes |= (1u << unit.type);
    }
    if (unit.type != 6 || unit.size < 2) {
      continue;
    }
    const uint8_t *nalu = bytes + unit.offset;
    size_t offset = 1;
    int payloadType = 0;
    while (offset < unit.size && nalu[offset] == 0xff) {
      payloadType += 255;
      ++offset;
    }
    if (offset >= unit.size) {
      continue;
    }
    payloadType += nalu[offset++];
    int payloadSize = 0;
    while (offset < unit.size && nalu[offset] == 0xff) {
      payloadSize += 255;
      ++offset;
    }
    if (offset >= unit.size) {
      continue;
    }
    payloadSize += nalu[offset++];
    if (payloadType != 5 || payloadSize < 23) {
      continue;
    }

    std::vector<uint8_t> unescapedPayload;
    unescapedPayload.reserve(static_cast<size_t>(payloadSize));
    int zeroCount = 0;
    size_t cursor = offset;
    while (cursor < unit.size && unescapedPayload.size() < static_cast<size_t>(payloadSize)) {
      const uint8_t value = nalu[cursor++];
      if (zeroCount == 2 && value == 0x03) {
        zeroCount = 0;
        continue;
      }
      unescapedPayload.push_back(value);
      if (value == 0) {
        ++zeroCount;
      } else {
        zeroCount = 0;
      }
    }
    if (unescapedPayload.size() < 23) {
      continue;
    }
    const uint8_t *payload = unescapedPayload.data();
    if (std::memcmp(payload, "RSDIAG1", 7) != 0) {
      continue;
    }
    metadata.valid = true;
    metadata.sequence = readBigEndianU64(payload + 7);
    metadata.sourceUnixMicros = readBigEndianU64(payload + 15);
    return metadata;
  }
  return metadata;
}

void performOnMainRunLoopCommonModes(dispatch_block_t block) {
  if (!block) {
    return;
  }
  if ([NSThread isMainThread]) {
    block();
    return;
  }
  CFRunLoopPerformBlock(CFRunLoopGetMain(), kCFRunLoopCommonModes, block);
  CFRunLoopWakeUp(CFRunLoopGetMain());
}

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

- (instancetype)initWithFrameHandler:(ReaShootMacH264FrameHandler)frameHandler
                decoderStatusHandler:(ReaShootMacDecoderStatusHandler)decoderStatusHandler {
  self = [super init];
  if (self) {
    _frameHandler = [frameHandler copy];
    _decoderStatusHandler = [decoderStatusHandler copy];
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
  if (status != noErr || !self.decompressionSession) {
    return NO;
  }
  VTSessionSetProperty(self.decompressionSession, kVTDecompressionPropertyKey_RealTime, kCFBooleanTrue);
  if (self.decoderStatusHandler) {
    BOOL hardwareAccelerated = NO;
    CFTypeRef usingHardware = nullptr;
    if (VTSessionCopyProperty(self.decompressionSession,
                              kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,
                              kCFAllocatorDefault,
                              &usingHardware) == noErr &&
        usingHardware) {
      if (CFGetTypeID(usingHardware) == CFBooleanGetTypeID()) {
        hardwareAccelerated = CFBooleanGetValue(static_cast<CFBooleanRef>(usingHardware));
      }
      CFRelease(usingHardware);
    }
    self.decoderStatusHandler(hardwareAccelerated, "VideoToolbox");
  }
  return YES;
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
  VTDecompressionSessionWaitForAsynchronousFrames(self.decompressionSession);
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
  handler(immutableFrame.bytes, width, height, static_cast<int>(destinationStride));
}

@end

namespace reashoot::platform::mac {

namespace {

struct DecodeContext {
  PreviewDiagnosticMetadata diagnostic;
  SteadyClock::time_point receiveTime;
  uint64_t receiveWallMicros = 0;
};

struct PendingFrame {
  std::shared_ptr<core::VideoFrame> frame;
  DecodeContext context;
};

class MacH264PreviewRenderer final : public core::PreviewRenderer {
public:
  MacH264PreviewRenderer(core::VideoFrameCallback frameHandler, core::DecoderStatusCallback decoderStatusHandler)
      : frameHandler_(std::move(frameHandler)),
        decodeQueue_(dispatch_queue_create("com.kevinlong.reashoot.h264-preview-decoder", DISPATCH_QUEUE_SERIAL)) {
    decoder_ = [[ReaShootMacH264FrameDecoder alloc] initWithFrameHandler:^(const void *pixels, int width, int height, int strideBytes) {
      if (!frameHandler_ || !pixels || width <= 0 || height <= 0 || strideBytes <= 0) {
        return;
      }
      auto frame = std::make_shared<core::VideoFrame>();
      frame->width = width;
      frame->height = height;
      frame->strideBytes = strideBytes;
      const auto byteCount = static_cast<size_t>(strideBytes) * static_cast<size_t>(height);
      const auto *bytes = static_cast<const uint8_t *>(pixels);
      frame->pixels.assign(bytes, bytes + byteCount);
      DecodeContext context = currentDecodeContext();
      frame->previewAccessUnitNalTypes = context.diagnostic.nalTypes;
      if (context.diagnostic.valid) {
        frame->previewSequence = context.diagnostic.sequence;
      }
      if (context.diagnostic.sourceUnixMicros > 0 && context.receiveWallMicros > context.diagnostic.sourceUnixMicros) {
        frame->previewSourceToReceiveMs =
            static_cast<double>(context.receiveWallMicros - context.diagnostic.sourceUnixMicros) / 1000.0;
      }
      publishFrame(std::move(frame), context);
    } decoderStatusHandler:^(BOOL hardwareAccelerated, const char *system) {
      if (!decoderStatusHandler) {
        return;
      }
      core::DecoderStatus status;
      status.hardwareAccelerated = hardwareAccelerated;
      status.system = system && system[0] ? system : "VideoToolbox";
      decoderStatusHandler(status);
    }];
  }

  void reset() override {
    {
      std::lock_guard<std::mutex> lock(frameMutex_);
      pendingFrame_.reset();
      frameDispatchPending_ = false;
      ++frameGeneration_;
    }
    dispatch_sync(decodeQueue_, ^{
      [decoder_ reset];
    });
  }

  void renderAnnexBAccessUnit(const uint8_t *bytes, size_t length) override {
    if (!bytes || length == 0) {
      return;
    }
    const DecodeContext context = {
        parseDiagnosticSEI(bytes, length),
        SteadyClock::now(),
        wallClockMicros(),
    };
    NSData *data = [NSData dataWithBytes:bytes length:length];
    dispatch_sync(decodeQueue_, ^{
      setCurrentDecodeContext(context);
      [decoder_ decodeAccessUnit:data];
    });
  }

private:
  void setCurrentDecodeContext(const DecodeContext &context) {
    std::lock_guard<std::mutex> lock(contextMutex_);
    currentContext_ = context;
  }

  DecodeContext currentDecodeContext() {
    std::lock_guard<std::mutex> lock(contextMutex_);
    return currentContext_;
  }

  void publishFrame(std::shared_ptr<core::VideoFrame> frame, const DecodeContext &context) {
    if (!frame) {
      return;
    }
    bool shouldSchedule = false;
    uint64_t generation = 0;
    {
      std::lock_guard<std::mutex> lock(frameMutex_);
      pendingFrame_ = std::make_shared<PendingFrame>(PendingFrame{std::move(frame), context});
      generation = frameGeneration_;
      if (!frameDispatchPending_) {
        frameDispatchPending_ = true;
        shouldSchedule = true;
      }
    }
    if (!shouldSchedule) {
      return;
    }
    performOnMainRunLoopCommonModes(^{
      std::shared_ptr<PendingFrame> pendingFrame;
      {
        std::lock_guard<std::mutex> lock(frameMutex_);
        if (generation != frameGeneration_) {
          return;
        }
        pendingFrame = std::move(pendingFrame_);
        pendingFrame_.reset();
        frameDispatchPending_ = false;
      }
      if (pendingFrame && pendingFrame->frame && frameHandler_) {
        const auto now = SteadyClock::now();
        pendingFrame->frame->previewReceiveToEmitMs =
            static_cast<double>(std::chrono::duration_cast<std::chrono::microseconds>(now - pendingFrame->context.receiveTime).count()) /
            1000.0;
        if (pendingFrame->context.diagnostic.sourceUnixMicros > 0) {
          const uint64_t emitWallMicros = wallClockMicros();
          if (emitWallMicros > pendingFrame->context.diagnostic.sourceUnixMicros) {
            pendingFrame->frame->previewSourceToEmitMs =
                static_cast<double>(emitWallMicros - pendingFrame->context.diagnostic.sourceUnixMicros) / 1000.0;
          }
        }
        frameHandler_(*pendingFrame->frame);
      }
    });
  }

  core::VideoFrameCallback frameHandler_;
  __strong ReaShootMacH264FrameDecoder *decoder_ = nil;
  dispatch_queue_t decodeQueue_ = nil;
  std::mutex contextMutex_;
  DecodeContext currentContext_;
  std::mutex frameMutex_;
  std::shared_ptr<PendingFrame> pendingFrame_;
  bool frameDispatchPending_ = false;
  uint64_t frameGeneration_ = 0;
};

} // namespace

std::unique_ptr<core::PreviewRenderer> createH264PreviewRenderer(core::VideoFrameCallback frameHandler,
                                                                 core::DecoderStatusCallback decoderStatusHandler) {
  return std::make_unique<MacH264PreviewRenderer>(std::move(frameHandler), std::move(decoderStatusHandler));
}

} // namespace reashoot::platform::mac
