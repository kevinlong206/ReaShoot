#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include "mac_media_audio_reader.h"

#include <algorithm>
#include <cmath>

namespace reashoot::platform::mac {
namespace {

NSString *stringFromStd(const std::string &value) {
  return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

class MacMediaAudioReader final : public core::MediaAudioReader {
public:
  std::vector<double> readMonoSamples(const std::string &path, double sourceStart, double duration, int sampleRate) override {
    if (path.empty() || duration <= 0.0 || sampleRate <= 0) {
      return {};
    }

    NSURL *url = [NSURL fileURLWithPath:stringFromStd(path)];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *audioTrack = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!audioTrack) {
      return {};
    }

    NSError *error = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    if (!reader || error) {
      return {};
    }

    NSDictionary *settings = @{
      AVFormatIDKey: @(kAudioFormatLinearPCM),
      AVSampleRateKey: @(sampleRate),
      AVNumberOfChannelsKey: @1,
      AVLinearPCMIsFloatKey: @YES,
      AVLinearPCMBitDepthKey: @32,
      AVLinearPCMIsNonInterleavedKey: @NO,
      AVLinearPCMIsBigEndianKey: @NO
    };
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:settings];
    if (![reader canAddOutput:output]) {
      return {};
    }
    [reader addOutput:output];
    reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds((std::max)(0.0, sourceStart), 600),
                                       CMTimeMakeWithSeconds(duration, 600));
    if (![reader startReading]) {
      return {};
    }

    std::vector<double> samples;
    samples.reserve(static_cast<size_t>(std::ceil(duration * sampleRate)));
    while (reader.status == AVAssetReaderStatusReading) {
      CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
      if (!sampleBuffer) {
        break;
      }

      CMBlockBufferRef blockBuffer = nullptr;
      AudioBufferList audioBufferList = {};
      OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
          sampleBuffer,
          nullptr,
          &audioBufferList,
          sizeof(audioBufferList),
          nullptr,
          nullptr,
          kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
          &blockBuffer);
      if (status == noErr && audioBufferList.mNumberBuffers > 0 && audioBufferList.mBuffers[0].mData) {
        const int frameCount = static_cast<int>(CMSampleBufferGetNumSamples(sampleBuffer));
        const float *buffer = reinterpret_cast<const float *>(audioBufferList.mBuffers[0].mData);
        for (int index = 0; index < frameCount; ++index) {
          samples.push_back(static_cast<double>(buffer[index]));
        }
      }
      if (blockBuffer) {
        CFRelease(blockBuffer);
      }
      CFRelease(sampleBuffer);
    }

    return samples;
  }
};

} // namespace

std::unique_ptr<core::MediaAudioReader> createMediaAudioReader() {
  return std::make_unique<MacMediaAudioReader>();
}

} // namespace reashoot::platform::mac
