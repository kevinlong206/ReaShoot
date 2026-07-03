#import "mac_h264_preview_renderer.h"

#include "../../core/h264_annex_b.h"

@interface ReaShootMacH264PreviewRenderer ()
@property(nonatomic, weak) AVSampleBufferDisplayLayer *layer;
@property(nonatomic, assign) CMVideoFormatDescriptionRef formatDescription;
@end

@implementation ReaShootMacH264PreviewRenderer

- (instancetype)initWithLayer:(AVSampleBufferDisplayLayer *)layer {
  self = [super init];
  if (self) {
    _layer = layer;
  }
  return self;
}

- (void)dealloc {
  [self reset];
}

- (void)reset {
  if (self.formatDescription) {
    CFRelease(self.formatDescription);
    self.formatDescription = nil;
  }
  [self.layer flushAndRemoveImage];
}

- (void)renderAccessUnit:(NSData *)accessUnit {
  if (accessUnit.length < 5 || !self.layer) {
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
      if (self.formatDescription) {
        CFRelease(self.formatDescription);
      }
      self.formatDescription = formatDescription;
    }
  }

  if (!self.formatDescription || sampleData.length == 0) {
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

  CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
  if (attachments && CFArrayGetCount(attachments) > 0) {
    CFMutableDictionaryRef attachment = static_cast<CFMutableDictionaryRef>(const_cast<void *>(CFArrayGetValueAtIndex(attachments, 0)));
    CFDictionarySetValue(attachment, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
  }
  if (self.layer.status == AVQueuedSampleBufferRenderingStatusFailed) {
    [self.layer flush];
  }
  [self.layer enqueueSampleBuffer:sampleBuffer];
  CFRelease(sampleBuffer);
}

@end
