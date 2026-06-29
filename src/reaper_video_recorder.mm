#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>
#import <LiveKitWebRTC/RTCConfiguration.h>
#import <LiveKitWebRTC/RTCDataChannel.h>
#import <LiveKitWebRTC/RTCDefaultVideoDecoderFactory.h>
#import <LiveKitWebRTC/RTCIceCandidate.h>
#import <LiveKitWebRTC/RTCMediaConstraints.h>
#import <LiveKitWebRTC/RTCMediaStream.h>
#import <LiveKitWebRTC/RTCMediaStreamTrack.h>
#import <LiveKitWebRTC/RTCMTLVideoView.h>
#import <LiveKitWebRTC/RTCPeerConnection.h>
#import <LiveKitWebRTC/RTCPeerConnectionFactory.h>
#import <LiveKitWebRTC/RTCRtpReceiver.h>
#import <LiveKitWebRTC/RTCRtpTransceiver.h>
#import <LiveKitWebRTC/RTCSessionDescription.h>
#import <LiveKitWebRTC/RTCVideoTrack.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <limits>
#include <memory>
#include <string>
#include <vector>

#define REAPERAPI_IMPLEMENT
#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_AddMediaItemToTrack
#define REAPERAPI_WANT_AddTakeToMediaItem
#define REAPERAPI_WANT_CountMediaItems
#define REAPERAPI_WANT_CountSelectedMediaItems
#define REAPERAPI_WANT_CountTracks
#define REAPERAPI_WANT_CountTrackMediaItems
#define REAPERAPI_WANT_CreateTakeAudioAccessor
#define REAPERAPI_WANT_DestroyAudioAccessor
#define REAPERAPI_WANT_DockWindowActivate
#define REAPERAPI_WANT_DockWindowAddEx
#define REAPERAPI_WANT_DockWindowRefreshForHWND
#define REAPERAPI_WANT_DockWindowRemove
#define REAPERAPI_WANT_EnumProjects
#define REAPERAPI_WANT_GetActiveTake
#define REAPERAPI_WANT_GetAudioAccessorSamples
#define REAPERAPI_WANT_GetCursorPositionEx
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_GetSet_LoopTimeRange2
#define REAPERAPI_WANT_GetMediaItemInfo_Value
#define REAPERAPI_WANT_GetMediaItem
#define REAPERAPI_WANT_GetMediaItemTake_Source
#define REAPERAPI_WANT_GetMediaItemTake_Peaks
#define REAPERAPI_WANT_GetMediaItemTakeInfo_Value
#define REAPERAPI_WANT_GetMediaItemTrack
#define REAPERAPI_WANT_GetSelectedMediaItem
#define REAPERAPI_WANT_GetMediaSourceLength
#define REAPERAPI_WANT_GetMediaSourceFileName
#define REAPERAPI_WANT_GetPlayPositionEx
#define REAPERAPI_WANT_GetPlayStateEx
#define REAPERAPI_WANT_GetProjectPathEx
#define REAPERAPI_WANT_GetResourcePath
#define REAPERAPI_WANT_GetSetMediaTrackInfo_String
#define REAPERAPI_WANT_GetTrack
#define REAPERAPI_WANT_GetTrackMediaItem
#define REAPERAPI_WANT_GetTrackName
#define REAPERAPI_WANT_InsertTrackAtIndex
#define REAPERAPI_WANT_IsMediaItemSelected
#define REAPERAPI_WANT_PCM_Source_BuildPeaks
#define REAPERAPI_WANT_PCM_Source_CreateFromFile
#define REAPERAPI_WANT_PCM_Source_GetPeaks
#define REAPERAPI_WANT_RefreshToolbar2
#define REAPERAPI_WANT_SetExtState
#define REAPERAPI_WANT_SetMediaItemInfo_Value
#define REAPERAPI_WANT_SetMediaItemSelected
#define REAPERAPI_WANT_SetMediaItemTake_Source
#define REAPERAPI_WANT_SetMediaTrackInfo_Value
#define REAPERAPI_WANT_ShowMessageBox
#define REAPERAPI_WANT_UpdateArrange
#define REAPERAPI_WANT_UpdateTimeline
#define REAPERAPI_WANT_ValidatePtr2
#include "reaper_plugin_functions.h"

namespace {

constexpr const char *kExtStateSection = "klong_reaper_video_recorder";
constexpr const char *kFollowEnabledKey = "follow_enabled";
constexpr const char *kPreviewFloatingKey = "preview_floating";
constexpr const char *kSelectedDeviceKey = "selected_device_unique_id";
constexpr const char *kSourceKindKey = "source_kind";
constexpr const char *kIPhoneHostKey = "iphone_host";
constexpr const char *kIPhoneControlPortKey = "iphone_control_port";
constexpr const char *kIPhoneHttpPortKey = "iphone_http_port";
constexpr const char *kIPhoneTokenKey = "iphone_token";
constexpr const char *kIPhoneResolutionKey = "iphone_resolution";
constexpr const char *kIPhoneFPSKey = "iphone_fps";
constexpr const char *kIPhoneOrientationKey = "iphone_orientation";
constexpr const char *kIPhoneAspectKey = "iphone_aspect";
constexpr const char *kIPhoneLensKey = "iphone_lens";
constexpr const char *kIPhoneZoomKey = "iphone_zoom";
constexpr const char *kIPhoneLookKey = "iphone_look";
constexpr const char *kDockIdent = "klong_reaper_video_recorder_preview";
constexpr const char *kVideoTrackName = "Video Recorder";
constexpr const char *kRepoHelperPath = "/Users/klong/reaper_video_recorder/build/video-sync-mac";
constexpr const char *kDefaultIPhoneHost = "kevin-long-iphone.local";
constexpr int kRecordBit = 4;
constexpr double kAlignmentPeakRate = 200.0;
constexpr double kAlignmentFinePeakRate = 1000.0;
constexpr int kAlignmentSampleRate = 48000;
constexpr double kAlignmentMaxDuration = 120.0;
constexpr double kAlignmentFineMaxDuration = 30.0;
constexpr double kAlignmentFineSearchSeconds = 0.20;
constexpr double kAlignmentSampleRefineDuration = 1.0;
constexpr double kAlignmentSampleRefineSearchSeconds = 0.030;
constexpr double kAlignmentSearchSeconds = 5.0;
constexpr double kAlignmentMinimumScore = 0.15;
constexpr int kAlignmentRetryLimit = 15;

reaper_plugin_info_t *g_reaper = nullptr;
int g_videoEnabledCommand = 0;
int g_showPreviewCommand = 0;
int g_floatPreviewCommand = 0;
int g_alignSelectedCommand = 0;
int g_toggleFollowCommand = 0;
int g_previousPlayState = 0;
bool g_videoEnabled = false;
bool g_followEnabled = true;
bool g_previewFloating = true;
bool g_activeTransportRecording = false;
bool g_pendingInsert = false;
bool g_pendingAlignment = false;
bool g_useIPhoneSource = false;
std::string g_selectedDeviceUniqueID;
std::string g_iPhoneHost;
std::string g_iPhoneControlPort = "8787";
std::string g_iPhoneHttpPort = "8788";
std::string g_iPhoneToken;
std::string g_iPhoneResolution = "4K";
std::string g_iPhoneFPS = "30";
std::string g_iPhoneOrientation = "portrait";
std::string g_iPhoneAspect = "9:16";
std::string g_iPhoneLens = "wide";
std::string g_iPhoneZoom = "1.0";
std::string g_iPhoneLook = "natural";
std::string g_pendingInsertPath;
std::string g_lastAlignmentStatus;
double g_pendingInsertPosition = 0.0;
ReaProject *g_recordProject = nullptr;
ReaProject *g_pendingAlignmentProject = nullptr;
MediaTrack *g_pendingAlignmentTrack = nullptr;
MediaItem *g_pendingAlignmentItem = nullptr;
double g_recordStartPosition = 0.0;
int g_pendingAlignmentAttempts = 0;
std::time_t g_nextAlignmentAttemptTime = 0;

struct PlaybackVideo {
  bool found = false;
  std::string path;
  double itemStart = 0.0;
  double itemEnd = 0.0;
  double sourceOffset = 0.0;
};

struct AlignmentResult {
  bool aligned = false;
  double correction = 0.0;
  double score = 0.0;
  int videoSamples = 0;
  int videoPeaks = 0;
  int candidateReferences = 0;
  int usableReferences = 0;
  std::string videoDebug;
};

struct TransientPeak {
  int index = 0;
  double value = 0.0;
};

struct AlignmentWindow {
  bool active = false;
  double start = 0.0;
  double end = 0.0;
};

bool hasPathExtension(const std::string &path, const std::string &extension) {
  return path.size() >= extension.size() &&
         std::equal(extension.rbegin(), extension.rend(), path.rbegin(), [](char a, char b) {
           return std::tolower(static_cast<unsigned char>(a)) == std::tolower(static_cast<unsigned char>(b));
         });
}

bool isVideoPath(const std::string &path) {
  return hasPathExtension(path, ".mov") || hasPathExtension(path, ".mp4") || hasPathExtension(path, ".m4v");
}

void showError(const std::string &message) {
  if (ShowMessageBox) {
    ShowMessageBox(message.c_str(), "REAPER Video Recorder", 0);
  }
}

ReaProject *currentProject() {
  char projectFile[4096] = {};
  if (EnumProjects) {
    if (ReaProject *project = EnumProjects(-1, projectFile, sizeof(projectFile))) {
      return project;
    }
  }
  return nullptr;
}

std::string directoryName(const std::string &path) {
  const std::string::size_type slash = path.find_last_of('/');
  if (slash == std::string::npos) {
    return {};
  }
  return path.substr(0, slash);
}

std::string baseNameWithoutExtension(const std::string &path) {
  std::string name = path;
  const std::string::size_type slash = name.find_last_of('/');
  if (slash != std::string::npos) {
    name = name.substr(slash + 1);
  }
  const std::string::size_type dot = name.find_last_of('.');
  if (dot != std::string::npos) {
    name = name.substr(0, dot);
  }
  if (name.empty()) {
    return "unsaved_project";
  }
  for (char &ch : name) {
    const bool safe = (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') ||
                      (ch >= '0' && ch <= '9') || ch == '-' || ch == '_';
    if (!safe) {
      ch = '_';
    }
  }
  return name;
}

std::string timestampString() {
  std::time_t now = std::time(nullptr);
  std::tm localTime = {};
  localtime_r(&now, &localTime);
  char buffer[32] = {};
  std::strftime(buffer, sizeof(buffer), "%Y%m%d_%H%M%S", &localTime);
  return buffer;
}

std::string captureOutputPath(ReaProject *project) {
  char projectPath[4096] = {};
  char projectFile[4096] = {};
  std::string outputRoot;
  std::string projectName = "unsaved_project";

  if (GetProjectPathEx && project) {
    GetProjectPathEx(project, projectPath, sizeof(projectPath));
  }
  if (projectPath[0] != '\0') {
    outputRoot = projectPath;
  }

  if (EnumProjects) {
    EnumProjects(-1, projectFile, sizeof(projectFile));
    if (projectFile[0] != '\0') {
      projectName = baseNameWithoutExtension(projectFile);
      if (outputRoot.empty()) {
        outputRoot = directoryName(projectFile);
      }
    }
  }

  if (outputRoot.empty() && GetResourcePath) {
    outputRoot = GetResourcePath();
  }
  if (outputRoot.empty()) {
    outputRoot = NSHomeDirectory().UTF8String;
  }

  return outputRoot + "/Video Recordings/" + projectName + "_" + timestampString() + ".mov";
}

MediaTrack *findVideoTrack(ReaProject *project) {
  if (!CountTracks || !GetTrack || !GetTrackName) {
    return nullptr;
  }

  const int trackCount = CountTracks(project);
  for (int i = 0; i < trackCount; ++i) {
    MediaTrack *track = GetTrack(project, i);
    if (!track) {
      continue;
    }

    char name[256] = {};
    if (GetTrackName(track, name, sizeof(name)) && std::string(name) == kVideoTrackName) {
      return track;
    }
  }

  return nullptr;
}

MediaTrack *findOrCreateVideoTrack(ReaProject *project) {
  if (!InsertTrackAtIndex || !GetSetMediaTrackInfo_String || !CountTracks || !GetTrack) {
    return nullptr;
  }

  if (MediaTrack *track = findVideoTrack(project)) {
    return track;
  }

  const int trackCount = CountTracks(project);
  InsertTrackAtIndex(trackCount, true);
  MediaTrack *track = GetTrack(project, trackCount);
  if (track) {
    char name[] = "Video Recorder";
    GetSetMediaTrackInfo_String(track, "P_NAME", name, true);
  }
  return track;
}

void disableReaperAudioRecording(MediaTrack *track) {
  if (!track || !SetMediaTrackInfo_Value) {
    return;
  }
  SetMediaTrackInfo_Value(track, "I_RECARM", 0.0);
  SetMediaTrackInfo_Value(track, "I_RECINPUT", -1.0);
  SetMediaTrackInfo_Value(track, "I_RECMODE", 2.0);
  SetMediaTrackInfo_Value(track, "I_RECMON", 0.0);
  SetMediaTrackInfo_Value(track, "I_RECMONITEMS", 0.0);
  SetMediaTrackInfo_Value(track, "B_AUTO_RECARM", 0.0);
}

MediaTrack *ensureVideoTrackReady(ReaProject *project, bool useFreeItemPositioning) {
  MediaTrack *track = findOrCreateVideoTrack(project);
  if (!track) {
    return nullptr;
  }
  disableReaperAudioRecording(track);
  if (SetMediaTrackInfo_Value) {
    SetMediaTrackInfo_Value(track, "I_FREEMODE", useFreeItemPositioning ? 1.0 : 0.0);
  }
  if (UpdateTimeline) {
    UpdateTimeline();
  }
  if (UpdateArrange) {
    UpdateArrange();
  }
  return track;
}

PlaybackVideo findPlaybackVideoAtPosition(ReaProject *project, double position) {
  PlaybackVideo result;
  if (!project || !CountTrackMediaItems || !GetTrackMediaItem || !GetMediaItemInfo_Value ||
      !GetActiveTake || !GetMediaItemTake_Source || !GetMediaSourceFileName) {
    return result;
  }

  MediaTrack *track = findVideoTrack(project);
  if (!track) {
    return result;
  }

  const int itemCount = CountTrackMediaItems(track);
  for (int i = 0; i < itemCount; ++i) {
    MediaItem *item = GetTrackMediaItem(track, i);
    if (!item) {
      continue;
    }

    const double itemStart = GetMediaItemInfo_Value(item, "D_POSITION");
    const double itemLength = GetMediaItemInfo_Value(item, "D_LENGTH");
    const double itemEnd = itemStart + itemLength;
    if (position < itemStart || position >= itemEnd) {
      continue;
    }

    MediaItem_Take *take = GetActiveTake(item);
    PCM_source *source = take ? GetMediaItemTake_Source(take) : nullptr;
    if (!source) {
      continue;
    }

    char filePath[4096] = {};
    GetMediaSourceFileName(source, filePath, sizeof(filePath));
    if (filePath[0] == '\0') {
      continue;
    }
    if (!isVideoPath(filePath)) {
      continue;
    }

    result.found = true;
    result.path = filePath;
    result.itemStart = itemStart;
    result.itemEnd = itemEnd;
    result.sourceOffset = GetMediaItemTakeInfo_Value ? GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") : 0.0;
    return result;
  }

  return result;
}

MediaItem *insertMediaItem(MediaTrack *track,
                           const std::string &path,
                           double position,
                           double laneY,
                           double laneHeight,
                           const char *description,
                           std::string &error) {
  PCM_source *source = PCM_Source_CreateFromFile(path.c_str());
  if (!source) {
    error = std::string("Recording finished, but REAPER could not open the ") + description + " file:\n" + path;
    return nullptr;
  }

  MediaItem *item = AddMediaItemToTrack(track);
  MediaItem_Take *take = item ? AddTakeToMediaItem(item) : nullptr;
  if (!item || !take || !SetMediaItemTake_Source(take, source)) {
    error = std::string("Recording finished, but REAPER could not create a ") + description + " media item.";
    return nullptr;
  }

  bool lengthIsQN = false;
  const double length = GetMediaSourceLength(source, &lengthIsQN);
  SetMediaItemInfo_Value(item, "D_POSITION", position);
  if (!lengthIsQN && length > 0.0) {
    SetMediaItemInfo_Value(item, "D_LENGTH", length);
  }
  SetMediaItemInfo_Value(item, "B_LOOPSRC", 0.0);
  SetMediaItemInfo_Value(item, "F_FREEMODE_Y", laneY);
  SetMediaItemInfo_Value(item, "F_FREEMODE_H", laneHeight);
  if (SetMediaItemSelected) {
    SetMediaItemSelected(item, true);
  }
  if (PCM_Source_BuildPeaks) {
    int remaining = PCM_Source_BuildPeaks(source, 0);
    while (remaining > 0) {
      remaining = PCM_Source_BuildPeaks(source, 1);
    }
    PCM_Source_BuildPeaks(source, 2);
  }
  return item;
}

std::vector<double> normalizedEnvelope(std::vector<double> envelope) {
  if (envelope.empty()) {
    return {};
  }
  double mean = 0.0;
  for (double value : envelope) {
    mean += value;
  }
  mean /= static_cast<double>(envelope.size());

  double energy = 0.0;
  for (double &value : envelope) {
    value -= mean;
    energy += value * value;
  }
  if (energy <= 1e-9) {
    return {};
  }
  return envelope;
}

std::vector<double> shapeEnvelope(std::vector<double> envelope, double peakRate) {
  if (envelope.empty()) {
    return {};
  }

  for (double &value : envelope) {
    value = std::log1p((std::max)(0.0, value) * 24.0);
  }

  const int radius = (std::max)(1, static_cast<int>(std::llround((peakRate >= kAlignmentFinePeakRate ? 0.015 : 0.25) * peakRate)));
  std::vector<double> smoothed(envelope.size(), 0.0);
  double sum = 0.0;
  int count = 0;
  int left = 0;
  int right = -1;
  for (int i = 0; i < static_cast<int>(envelope.size()); ++i) {
    const int targetRight = (std::min)(static_cast<int>(envelope.size()) - 1, i + radius);
    while (right < targetRight) {
      ++right;
      sum += envelope[static_cast<size_t>(right)];
      ++count;
    }
    const int targetLeft = (std::max)(0, i - radius);
    while (left < targetLeft) {
      sum -= envelope[static_cast<size_t>(left)];
      --count;
      ++left;
    }
    smoothed[static_cast<size_t>(i)] = count > 0 ? sum / static_cast<double>(count) : 0.0;
  }

  return normalizedEnvelope(std::move(smoothed));
}

std::vector<double> transientEnvelope(const std::vector<double> &rawEnvelope) {
  if (rawEnvelope.empty()) {
    return {};
  }
  std::vector<double> onset(rawEnvelope.size(), 0.0);
  double slowEnvelope = rawEnvelope.front();
  for (size_t i = 1; i < rawEnvelope.size(); ++i) {
    const double previousSlow = slowEnvelope;
    slowEnvelope = (0.90 * slowEnvelope) + (0.10 * rawEnvelope[i]);
    onset[i] = (std::max)(0.0, rawEnvelope[i] - previousSlow);
  }
  return normalizedEnvelope(std::move(onset));
}

double takeSourceOffset(MediaItem_Take *take) {
  if (!take || !GetMediaItemTakeInfo_Value) {
    return 0.0;
  }
  const double offset = GetMediaItemTakeInfo_Value(take, "D_STARTOFFS");
  return std::isfinite(offset) && offset > 0.0 ? offset : 0.0;
}

double takePlayRate(MediaItem_Take *take) {
  if (!take || !GetMediaItemTakeInfo_Value) {
    return 1.0;
  }
  const double rate = GetMediaItemTakeInfo_Value(take, "D_PLAYRATE");
  return std::isfinite(rate) && rate > 0.0 ? rate : 1.0;
}

bool takeSourcePath(MediaItem_Take *take, std::string &path) {
  if (!take || !GetMediaItemTake_Source || !GetMediaSourceFileName) {
    return false;
  }
  PCM_source *source = GetMediaItemTake_Source(take);
  if (!source) {
    return false;
  }
  char filePath[4096] = {};
  GetMediaSourceFileName(source, filePath, sizeof(filePath));
  if (filePath[0] == '\0') {
    return false;
  }
  path = filePath;
  return true;
}

bool pathLooksLikeMovie(const std::string &path) {
  return hasPathExtension(path, ".mov") || hasPathExtension(path, ".mp4") || hasPathExtension(path, ".m4v");
}

std::vector<double> envelopeFromPeakBuffer(const std::vector<double> &peaks, int returnedSamples, double peakRate) {
  std::vector<double> envelope(static_cast<size_t>(returnedSamples));
  for (int i = 0; i < returnedSamples; ++i) {
    const double value = (std::max)(std::fabs(peaks[static_cast<size_t>(i)]),
                                    std::fabs(peaks[static_cast<size_t>(returnedSamples + i)]));
    envelope[static_cast<size_t>(i)] = value;
  }

  return shapeEnvelope(std::move(envelope), peakRate);
}

std::vector<double> movieAudioEnvelope(const std::string &path, double sourceStart, double duration, double peakRate, int &sampleCountOut, std::string *debug) {
  sampleCountOut = 0;
  if (path.empty() || duration <= 0.0) {
    if (debug) {
      *debug = "movie fallback skipped: empty path or duration";
    }
    return {};
  }

  NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
  NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
  AVAssetTrack *audioTrack = audioTracks.firstObject;
  if (!audioTrack) {
    if (debug) {
      *debug = "movie fallback failed: no audio track in " + path;
    }
    return {};
  }

  NSError *error = nil;
  AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
  if (!reader || error) {
    if (debug) {
      NSString *message = error.localizedDescription ?: @"unknown reader error";
      *debug = "movie fallback failed: " + std::string(message.UTF8String ?: "reader error");
    }
    return {};
  }

  NSDictionary *settings = @{
    AVFormatIDKey: @(kAudioFormatLinearPCM),
    AVLinearPCMIsFloatKey: @YES,
    AVLinearPCMBitDepthKey: @32,
    AVLinearPCMIsNonInterleavedKey: @NO,
    AVLinearPCMIsBigEndianKey: @NO
  };
  AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack outputSettings:settings];
  output.alwaysCopiesSampleData = NO;
  if (![reader canAddOutput:output]) {
    if (debug) {
      *debug = "movie fallback failed: cannot add audio reader output";
    }
    return {};
  }
  [reader addOutput:output];
  reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds((std::max)(0.0, sourceStart), 600),
                                     CMTimeMakeWithSeconds(duration, 600));

  if (![reader startReading]) {
    if (debug) {
      NSString *message = reader.error.localizedDescription ?: @"unknown start error";
      *debug = "movie fallback failed: " + std::string(message.UTF8String ?: "start error");
    }
    return {};
  }

  const int bucketCount = (std::max)(1, static_cast<int>(std::floor(duration * peakRate)));
  std::vector<double> envelope(static_cast<size_t>(bucketCount), 0.0);
  int observedBuckets = 0;
  int64_t decodedFrames = 0;

  while (reader.status == AVAssetReaderStatusReading) {
    CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
    if (!sampleBuffer) {
      break;
    }

    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    const AudioStreamBasicDescription *format =
        formatDescription ? CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) : nullptr;
    const int frameCount = static_cast<int>(CMSampleBufferGetNumSamples(sampleBuffer));
    size_t audioBufferListSize = 0;
    CMBlockBufferRef retainedBlockBuffer = nullptr;
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
        sampleBuffer,
        &audioBufferListSize,
        nullptr,
        0,
        nullptr,
        nullptr,
        kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
        nullptr);

    std::unique_ptr<uint8_t[]> audioBufferListStorage;
    AudioBufferList *audioBufferList = nullptr;
    if (status == noErr && audioBufferListSize > 0) {
      audioBufferListStorage.reset(new uint8_t[audioBufferListSize]);
      audioBufferList = reinterpret_cast<AudioBufferList *>(audioBufferListStorage.get());
      status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
          sampleBuffer,
          nullptr,
          audioBufferList,
          audioBufferListSize,
          nullptr,
          nullptr,
          kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
          &retainedBlockBuffer);
    }

    if (status == noErr && audioBufferList && format && frameCount > 0) {
      const double sampleRate = format->mSampleRate > 0.0 ? format->mSampleRate : 48000.0;
      for (int frame = 0; frame < frameCount; ++frame) {
        const int bucket = static_cast<int>(std::floor(((static_cast<double>(decodedFrames) + static_cast<double>(frame)) / sampleRate) * peakRate));
        if (bucket < 0 || bucket >= bucketCount) {
          continue;
        }
        double peak = 0.0;
        for (UInt32 bufferIndex = 0; bufferIndex < audioBufferList->mNumberBuffers; ++bufferIndex) {
          const AudioBuffer &audioBuffer = audioBufferList->mBuffers[bufferIndex];
          if (!audioBuffer.mData || audioBuffer.mNumberChannels == 0) {
            continue;
          }
          const float *samples = reinterpret_cast<const float *>(audioBuffer.mData);
          const UInt32 channelCount = audioBuffer.mNumberChannels;
          for (UInt32 channel = 0; channel < channelCount; ++channel) {
            const size_t sampleIndex = audioBufferList->mNumberBuffers == 1
                                           ? (static_cast<size_t>(frame) * channelCount) + channel
                                           : static_cast<size_t>(frame);
            peak = (std::max)(peak, std::fabs(static_cast<double>(samples[sampleIndex])));
          }
        }
        envelope[static_cast<size_t>(bucket)] = (std::max)(envelope[static_cast<size_t>(bucket)], peak);
        observedBuckets = (std::max)(observedBuckets, bucket + 1);
      }
      decodedFrames += frameCount;
    } else if (debug && debug->empty()) {
      char message[160] = {};
      std::snprintf(message,
                    sizeof(message),
                    "movie fallback buffer failed: status %d, format %s, frames %d",
                    static_cast<int>(status),
                    format ? "yes" : "no",
                    frameCount);
      *debug = message;
    }

    if (retainedBlockBuffer) {
      CFRelease(retainedBlockBuffer);
    }
    CFRelease(sampleBuffer);
  }

  if (observedBuckets <= 0) {
    if (debug && debug->empty()) {
      NSString *message = reader.error.localizedDescription ?: @"no decoded audio buckets";
      *debug = "movie fallback failed: " + std::string(message.UTF8String ?: "no decoded audio buckets");
    }
    return {};
  }
  if (observedBuckets < static_cast<int>(envelope.size())) {
    envelope.resize(static_cast<size_t>(observedBuckets));
  }

  envelope = shapeEnvelope(std::move(envelope), peakRate);
  if (envelope.empty()) {
    return {};
  }
  sampleCountOut = static_cast<int>(envelope.size());
  return envelope;
}

std::vector<double> takeEnvelope(MediaItem_Take *take, double sourceStart, double duration, int &sampleCountOut, std::string *debug = nullptr, double peakRate = kAlignmentPeakRate) {
  sampleCountOut = 0;
  if (!take || duration <= 0.0) {
    return {};
  }

  const int sampleCount = (std::max)(1, static_cast<int>(std::floor(duration * peakRate)));
  std::vector<double> peaks(static_cast<size_t>(sampleCount) * 2);
  int returnedSamples = 0;
  if (PCM_Source_GetPeaks && GetMediaItemTake_Source) {
    if (PCM_source *source = GetMediaItemTake_Source(take)) {
      const int result = PCM_Source_GetPeaks(source,
                                             peakRate,
                                             sourceStart,
                                             1,
                                             sampleCount,
                                             0,
                                             peaks.data());
      returnedSamples = result & 0xfffff;
    }
  }

  std::vector<double> envelope = returnedSamples > 0 ? envelopeFromPeakBuffer(peaks, returnedSamples, peakRate) : std::vector<double>{};
  if (envelope.empty() && GetMediaItemTake_Peaks) {
    std::fill(peaks.begin(), peaks.end(), 0.0);
    const int result = GetMediaItemTake_Peaks(take,
                                              peakRate,
                                              sourceStart,
                                              1,
                                              sampleCount,
                                              0,
                                              peaks.data());
    returnedSamples = result & 0xfffff;
    envelope = returnedSamples > 0 ? envelopeFromPeakBuffer(peaks, returnedSamples, peakRate) : std::vector<double>{};
  }

  if (envelope.empty()) {
    std::string path;
    if (takeSourcePath(take, path) && pathLooksLikeMovie(path)) {
      std::string movieDebug;
      std::vector<double> movieEnvelope = movieAudioEnvelope(path, sourceStart, duration, peakRate, sampleCountOut, &movieDebug);
      if (!movieEnvelope.empty()) {
        return movieEnvelope;
      }
      if (debug) {
        if (!movieDebug.empty()) {
          *debug = movieDebug;
        } else {
          char message[180] = {};
          std::snprintf(message,
                        sizeof(message),
                        "movie fallback produced no audio after %d silent REAPER peak samples",
                        returnedSamples);
          *debug = message;
        }
      }
      return {};
    }
    if (debug) {
      if (path.empty()) {
        *debug = returnedSamples > 0
                     ? "REAPER peak APIs returned silent samples and source path is empty"
                     : "take/source peak APIs returned no samples and source path is empty";
      } else {
        *debug = returnedSamples > 0
                     ? "REAPER peak APIs returned silent samples for non-movie source: " + path
                     : "take/source peak APIs returned no samples for non-movie source: " + path;
      }
    }
    return {};
  }
  sampleCountOut = returnedSamples;
  return envelope;
}

double normalizedCorrelationAtLag(const std::vector<double> &video,
                                  const std::vector<double> &reference,
                                  int lagSamples,
                                  int minimumOverlapSamples = static_cast<int>(kAlignmentPeakRate)) {
  int videoStart = 0;
  int referenceStart = lagSamples;
  int count = static_cast<int>(video.size());
  if (referenceStart < 0) {
    videoStart = -referenceStart;
    referenceStart = 0;
    count -= videoStart;
  }
  count = (std::min)(count, static_cast<int>(reference.size()) - referenceStart);
  if (count < minimumOverlapSamples) {
    return -std::numeric_limits<double>::infinity();
  }

  double dot = 0.0;
  double videoEnergy = 0.0;
  double referenceEnergy = 0.0;
  for (int i = 0; i < count; ++i) {
    const double videoValue = video[static_cast<size_t>(videoStart + i)];
    const double referenceValue = reference[static_cast<size_t>(referenceStart + i)];
    dot += videoValue * referenceValue;
    videoEnergy += videoValue * videoValue;
    referenceEnergy += referenceValue * referenceValue;
  }
  if (videoEnergy <= 1e-9 || referenceEnergy <= 1e-9) {
    return -std::numeric_limits<double>::infinity();
  }
  return dot / std::sqrt(videoEnergy * referenceEnergy);
}

std::vector<double> normalizedSampleShape(std::vector<double> samples) {
  if (samples.empty()) {
    return {};
  }

  for (double &sample : samples) {
    sample = std::sqrt(std::fabs(sample));
  }

  const int radius = (std::max)(1, static_cast<int>(std::llround(0.0015 * kAlignmentSampleRate)));
  std::vector<double> smoothed(samples.size(), 0.0);
  double sum = 0.0;
  int count = 0;
  int left = 0;
  int right = -1;
  for (int i = 0; i < static_cast<int>(samples.size()); ++i) {
    const int targetRight = (std::min)(static_cast<int>(samples.size()) - 1, i + radius);
    while (right < targetRight) {
      ++right;
      sum += samples[static_cast<size_t>(right)];
      ++count;
    }
    const int targetLeft = (std::max)(0, i - radius);
    while (left < targetLeft) {
      sum -= samples[static_cast<size_t>(left)];
      --count;
      ++left;
    }
    smoothed[static_cast<size_t>(i)] = count > 0 ? sum / static_cast<double>(count) : 0.0;
  }

  return normalizedEnvelope(std::move(smoothed));
}

std::vector<double> movieAudioSamples(const std::string &path, double sourceStart, double duration) {
  if (path.empty() || duration <= 0.0) {
    return {};
  }

  NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
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
    AVSampleRateKey: @(kAlignmentSampleRate),
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
  samples.reserve(static_cast<size_t>(std::ceil(duration * kAlignmentSampleRate)));
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
      for (int i = 0; i < frameCount; ++i) {
        samples.push_back(static_cast<double>(buffer[i]));
      }
    }
    if (blockBuffer) {
      CFRelease(blockBuffer);
    }
    CFRelease(sampleBuffer);
  }

  return samples;
}

std::vector<double> takeAudioAccessorSamples(MediaItem_Take *take, double projectStart, double duration) {
  if (!take || !CreateTakeAudioAccessor || !GetAudioAccessorSamples || !DestroyAudioAccessor || duration <= 0.0) {
    return {};
  }

  const int sampleCount = static_cast<int>(std::ceil(duration * kAlignmentSampleRate));
  if (sampleCount <= 0) {
    return {};
  }
  std::vector<double> samples(static_cast<size_t>(sampleCount), 0.0);
  AudioAccessor *accessor = CreateTakeAudioAccessor(take);
  if (!accessor) {
    return {};
  }
  const int result = GetAudioAccessorSamples(accessor,
                                             kAlignmentSampleRate,
                                             1,
                                             projectStart,
                                             sampleCount,
                                             samples.data());
  DestroyAudioAccessor(accessor);
  if (result <= 0) {
    return {};
  }
  return samples;
}

bool sampleAccurateRefine(MediaItem_Take *videoTake,
                          MediaItem_Take *referenceTake,
                          double videoSourceStart,
                          double videoDuration,
                          double referencePosition,
                          double referenceLength,
                          double coarseSegmentPosition,
                          double analysisOffset,
                          double &refinedPosition,
                          double &refinedScore) {
  std::string videoPath;
  if (!takeSourcePath(videoTake, videoPath) || !pathLooksLikeMovie(videoPath)) {
    return false;
  }

  const double search = kAlignmentSampleRefineSearchSeconds;
  const double duration = (std::min)(videoDuration, kAlignmentSampleRefineDuration);
  const double referenceOffset = coarseSegmentPosition - referencePosition;
  const double referenceWindowOffset = (std::max)(0.0, referenceOffset - search);
  const double referenceWindowProjectPosition = referencePosition + referenceWindowOffset;
  const double referenceDuration = (std::min)(referenceLength - referenceWindowOffset, duration + (2.0 * search));
  if (referenceDuration <= duration * 0.5) {
    return false;
  }

  std::vector<double> videoSamples = normalizedSampleShape(movieAudioSamples(videoPath, videoSourceStart, duration));
  std::vector<double> referenceSamples = normalizedSampleShape(
      takeAudioAccessorSamples(referenceTake, referenceWindowProjectPosition, referenceDuration));
  if (videoSamples.empty() || referenceSamples.empty()) {
    return false;
  }

  const int expectedLag = static_cast<int>(std::llround((coarseSegmentPosition - referenceWindowProjectPosition) * kAlignmentSampleRate));
  const int searchSamples = static_cast<int>(std::llround(search * kAlignmentSampleRate));
  const int minLag = (std::max)(0, expectedLag - searchSamples);
  const int maxLag = (std::min)(static_cast<int>(referenceSamples.size()) - static_cast<int>(videoSamples.size()),
                                expectedLag + searchSamples);
  if (minLag > maxLag) {
    return false;
  }

  const int minimumOverlapSamples = static_cast<int>(std::llround(0.25 * kAlignmentSampleRate));
  double bestScore = -std::numeric_limits<double>::infinity();
  int bestLag = expectedLag;
  for (int lag = minLag; lag <= maxLag; ++lag) {
    const double score = normalizedCorrelationAtLag(videoSamples, referenceSamples, lag, minimumOverlapSamples);
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  if (!std::isfinite(bestScore)) {
    return false;
  }

  refinedPosition = referenceWindowProjectPosition + (static_cast<double>(bestLag) / kAlignmentSampleRate) - analysisOffset;
  refinedScore = bestScore;
  return true;
}

std::vector<TransientPeak> strongestTransientPeaks(const std::vector<double> &signal) {
  std::vector<TransientPeak> peaks;
  if (signal.size() < 3) {
    return peaks;
  }

  double maxValue = 0.0;
  for (double value : signal) {
    maxValue = (std::max)(maxValue, value);
  }
  if (maxValue <= 0.0) {
    return peaks;
  }

  const double threshold = maxValue * 0.35;
  const int minDistance = static_cast<int>(std::llround(0.08 * kAlignmentPeakRate));
  for (int i = 1; i < static_cast<int>(signal.size()) - 1; ++i) {
    const double value = signal[static_cast<size_t>(i)];
    if (value < threshold || value < signal[static_cast<size_t>(i - 1)] || value < signal[static_cast<size_t>(i + 1)]) {
      continue;
    }
    bool merged = false;
    for (TransientPeak &peak : peaks) {
      if (std::abs(peak.index - i) <= minDistance) {
        if (value > peak.value) {
          peak.index = i;
          peak.value = value;
        }
        merged = true;
        break;
      }
    }
    if (!merged) {
      peaks.push_back({i, value});
    }
  }

  std::sort(peaks.begin(), peaks.end(), [](const TransientPeak &a, const TransientPeak &b) {
    return a.value > b.value;
  });
  if (peaks.size() > 32) {
    peaks.resize(32);
  }
  return peaks;
}

bool refineAlignment(MediaItem_Take *videoTake,
                     MediaItem_Take *referenceTake,
                     double videoSourceStart,
                     double videoDuration,
                     double referencePosition,
                     double referenceLength,
                     double coarseSegmentPosition,
                     double analysisOffset,
                     double &refinedPosition,
                     double &refinedScore) {
  videoDuration = (std::min)(videoDuration, kAlignmentFineMaxDuration);
  const double referenceOffset = coarseSegmentPosition - referencePosition;
  const double referenceWindowOffset = (std::max)(0.0, referenceOffset - kAlignmentFineSearchSeconds);
  const double referenceWindowProjectPosition = referencePosition + referenceWindowOffset;
  const double referenceWindowDuration =
      (std::min)(referenceLength - referenceWindowOffset, videoDuration + (2.0 * kAlignmentFineSearchSeconds));
  if (!videoTake || !referenceTake || videoDuration <= 0.0 || referenceWindowDuration <= 0.0) {
    return false;
  }

  int videoSampleCount = 0;
  std::vector<double> videoEnvelope =
      takeEnvelope(videoTake, videoSourceStart, videoDuration, videoSampleCount, nullptr, kAlignmentFinePeakRate);
  if (videoEnvelope.empty()) {
    return false;
  }

  int referenceSampleCount = 0;
  std::vector<double> referenceEnvelope =
      takeEnvelope(referenceTake,
                   takeSourceOffset(referenceTake) + (referenceWindowOffset * takePlayRate(referenceTake)),
                   referenceWindowDuration,
                   referenceSampleCount,
                   nullptr,
                   kAlignmentFinePeakRate);
  if (referenceEnvelope.empty()) {
    return false;
  }

  const int expectedLagSamples =
      static_cast<int>(std::llround((coarseSegmentPosition - referenceWindowProjectPosition) * kAlignmentFinePeakRate));
  const int searchSamples = static_cast<int>(std::llround(kAlignmentFineSearchSeconds * kAlignmentFinePeakRate));
  const int minLag = (std::max)(-videoSampleCount + 1, expectedLagSamples - searchSamples);
  const int maxLag = (std::min)(referenceSampleCount - 1, expectedLagSamples + searchSamples);
  if (minLag > maxLag) {
    return false;
  }

  const int minimumOverlapSamples = static_cast<int>(std::llround(0.25 * kAlignmentFinePeakRate));
  double bestScore = -std::numeric_limits<double>::infinity();
  int bestLag = expectedLagSamples;
  std::vector<double> lagScores(static_cast<size_t>(maxLag - minLag + 1), -std::numeric_limits<double>::infinity());
  for (int lag = minLag; lag <= maxLag; ++lag) {
    const double score = normalizedCorrelationAtLag(videoEnvelope, referenceEnvelope, lag, minimumOverlapSamples);
    lagScores[static_cast<size_t>(lag - minLag)] = score;
    if (score > bestScore) {
      bestScore = score;
      bestLag = lag;
    }
  }
  if (!std::isfinite(bestScore)) {
    return false;
  }

  double weightedLag = static_cast<double>(bestLag);
  double weightSum = 0.0;
  double lagSum = 0.0;
  const double neighborhoodThreshold = bestScore - 0.02;
  const int neighborhoodSamples = static_cast<int>(std::llround(0.025 * kAlignmentFinePeakRate));
  const int neighborhoodStart = (std::max)(minLag, bestLag - neighborhoodSamples);
  const int neighborhoodEnd = (std::min)(maxLag, bestLag + neighborhoodSamples);
  for (int lag = neighborhoodStart; lag <= neighborhoodEnd; ++lag) {
    const double score = lagScores[static_cast<size_t>(lag - minLag)];
    if (!std::isfinite(score) || score < neighborhoodThreshold) {
      continue;
    }
    const double weight = score - neighborhoodThreshold;
    lagSum += static_cast<double>(lag) * weight;
    weightSum += weight;
  }
  if (weightSum > 1e-9) {
    weightedLag = lagSum / weightSum;
  }

  refinedPosition = referenceWindowProjectPosition + (weightedLag / kAlignmentFinePeakRate) - analysisOffset;
  refinedScore = bestScore;
  return true;
}

bool mediaItemInList(MediaItem *item, const std::vector<MediaItem *> *items) {
  if (!items) {
    return true;
  }
  return std::find(items->begin(), items->end(), item) != items->end();
}

MediaItem *firstOverlappingReferenceItem(ReaProject *project, MediaTrack *videoTrack, MediaItem *videoItem) {
  if (!project || !videoTrack || !videoItem || !CountTracks || !GetTrack || !CountTrackMediaItems ||
      !GetTrackMediaItem || !GetMediaItemInfo_Value) {
    return nullptr;
  }

  const double videoPosition = GetMediaItemInfo_Value(videoItem, "D_POSITION");
  const double videoLength = GetMediaItemInfo_Value(videoItem, "D_LENGTH");
  const double videoEnd = videoPosition + (videoLength > 0.0 ? videoLength : 0.0);
  const int trackCount = CountTracks(project);
  for (int trackIndex = 0; trackIndex < trackCount; ++trackIndex) {
    MediaTrack *track = GetTrack(project, trackIndex);
    if (!track || track == videoTrack) {
      continue;
    }

    const int itemCount = CountTrackMediaItems(track);
    for (int itemIndex = 0; itemIndex < itemCount; ++itemIndex) {
      MediaItem *item = GetTrackMediaItem(track, itemIndex);
      if (!item) {
        continue;
      }
      const double itemPosition = GetMediaItemInfo_Value(item, "D_POSITION");
      const double itemLength = GetMediaItemInfo_Value(item, "D_LENGTH");
      const double itemEnd = itemPosition + (itemLength > 0.0 ? itemLength : 0.0);
      if (itemLength > 0.0 && itemPosition <= videoEnd && itemEnd >= videoPosition) {
        return item;
      }
    }
  }

  return nullptr;
}

AlignmentResult alignVideoItemToReference(ReaProject *project,
                                          MediaTrack *videoTrack,
                                          MediaItem *videoItem,
                                          const std::vector<MediaItem *> *referenceItems = nullptr,
                                          AlignmentWindow analysisWindow = {}) {
  AlignmentResult result;
  if (!project || !videoTrack || !videoItem || !CountMediaItems || !GetMediaItem ||
      !GetMediaItemTrack || !GetActiveTake || !GetMediaItemInfo_Value || !SetMediaItemInfo_Value) {
    return result;
  }

  MediaItem_Take *videoTake = GetActiveTake(videoItem);
  const double videoPosition = GetMediaItemInfo_Value(videoItem, "D_POSITION");
  const double videoLength = GetMediaItemInfo_Value(videoItem, "D_LENGTH");
  if (!videoTake || videoLength <= 0.0) {
    return result;
  }

  const double videoEnd = videoPosition + videoLength;
  double analysisProjectStart = videoPosition;
  double videoAnalysisDuration = (std::min)(videoLength, kAlignmentMaxDuration);
  if (analysisWindow.active) {
    analysisProjectStart = (std::max)(videoPosition, analysisWindow.start);
    const double analysisProjectEnd = (std::min)(videoEnd, analysisWindow.end);
    videoAnalysisDuration = analysisProjectEnd - analysisProjectStart;
    if (videoAnalysisDuration <= 0.0) {
      result.videoDebug = "time selection does not overlap selected video item";
      return result;
    }
    videoAnalysisDuration = (std::min)(videoAnalysisDuration, kAlignmentMaxDuration);
  }
  const double analysisOffset = analysisProjectStart - videoPosition;
  const double videoSourceStart = takeSourceOffset(videoTake) + (analysisOffset * takePlayRate(videoTake));

  int videoSampleCount = 0;
  std::string videoDebug;
  std::vector<double> videoEnvelope =
      takeEnvelope(videoTake, videoSourceStart, videoAnalysisDuration, videoSampleCount, &videoDebug);
  result.videoSamples = videoSampleCount;
  result.videoDebug = videoDebug;
  if (videoEnvelope.empty()) {
    return result;
  }
  result.videoPeaks = static_cast<int>(strongestTransientPeaks(transientEnvelope(videoEnvelope)).size());

  const int itemCount = CountMediaItems(project);
  double bestScore = -std::numeric_limits<double>::infinity();
  double bestPosition = videoPosition;
  std::vector<MediaItem *> defaultReferenceItems;
  if (!referenceItems) {
    if (MediaItem *referenceItem = firstOverlappingReferenceItem(project, videoTrack, videoItem)) {
      defaultReferenceItems.push_back(referenceItem);
    }
    referenceItems = &defaultReferenceItems;
  }

  for (int i = 0; i < itemCount; ++i) {
    MediaItem *referenceItem = GetMediaItem(project, i);
    if (!referenceItem || referenceItem == videoItem || GetMediaItemTrack(referenceItem) == videoTrack) {
      continue;
    }
    if (!mediaItemInList(referenceItem, referenceItems)) {
      continue;
    }

    MediaItem_Take *referenceTake = GetActiveTake(referenceItem);
    if (!referenceTake) {
      continue;
    }
    result.candidateReferences += 1;

    const double referencePosition = GetMediaItemInfo_Value(referenceItem, "D_POSITION");
    const double referenceLength = GetMediaItemInfo_Value(referenceItem, "D_LENGTH");
    const double expectedLag = analysisProjectStart - referencePosition;
    if (referenceLength <= 0.0 ||
        expectedLag < -kAlignmentSearchSeconds ||
        expectedLag > referenceLength + kAlignmentSearchSeconds) {
      continue;
    }

    const double referenceWindowOffset = (std::max)(0.0, expectedLag - kAlignmentSearchSeconds);
    const double referenceWindowProjectPosition = referencePosition + referenceWindowOffset;
    const double referenceWindowDuration =
        (std::min)(referenceLength - referenceWindowOffset, videoAnalysisDuration + (2.0 * kAlignmentSearchSeconds));
    if (referenceWindowDuration <= 0.0) {
      continue;
    }

    int referenceSampleCount = 0;
    std::vector<double> referenceEnvelope =
        takeEnvelope(referenceTake,
                     takeSourceOffset(referenceTake) + (referenceWindowOffset * takePlayRate(referenceTake)),
                     referenceWindowDuration,
                     referenceSampleCount);
    if (referenceEnvelope.empty()) {
      continue;
    }
    result.usableReferences += 1;
    const int expectedLagSamples = static_cast<int>(std::llround((analysisProjectStart - referenceWindowProjectPosition) * kAlignmentPeakRate));
    const int searchSamples = static_cast<int>(std::llround(kAlignmentSearchSeconds * kAlignmentPeakRate));
    const int minLag = (std::max)(-videoSampleCount + 1, expectedLagSamples - searchSamples);
    const int maxLag = (std::min)(referenceSampleCount - 1, expectedLagSamples + searchSamples);
    if (minLag > maxLag) {
      continue;
    }

    double referenceBestScore = -std::numeric_limits<double>::infinity();
    double referenceBestPosition = videoPosition;
    for (int lag = minLag; lag <= maxLag; ++lag) {
      const double score = normalizedCorrelationAtLag(videoEnvelope, referenceEnvelope, lag);
      if (score > referenceBestScore) {
        referenceBestScore = score;
        referenceBestPosition = referenceWindowProjectPosition + (static_cast<double>(lag) / kAlignmentPeakRate) - analysisOffset;
      }
    }

    if (referenceBestScore > bestScore) {
      double refinedPosition = referenceBestPosition;
      double refinedScore = referenceBestScore;
      if (refineAlignment(videoTake,
                          referenceTake,
                          videoSourceStart,
                          videoAnalysisDuration,
                          referencePosition,
                          referenceLength,
                          referenceBestPosition + analysisOffset,
                          analysisOffset,
                          refinedPosition,
                          refinedScore)) {
        double samplePosition = refinedPosition;
        double sampleScore = refinedScore;
        if (sampleAccurateRefine(videoTake,
                                 referenceTake,
                                 videoSourceStart,
                                 videoAnalysisDuration,
                                 referencePosition,
                                 referenceLength,
                                 refinedPosition + analysisOffset,
                                 analysisOffset,
                                 samplePosition,
                                 sampleScore)) {
          refinedPosition = samplePosition;
          refinedScore = sampleScore;
        }
        bestPosition = refinedPosition;
        bestScore = refinedScore;
      } else {
        bestPosition = referenceBestPosition;
        bestScore = referenceBestScore;
      }
    }
  }

  if (std::isfinite(bestScore)) {
    result.score = bestScore;
  }
  if (std::isfinite(bestScore) && bestScore >= kAlignmentMinimumScore) {
    result.aligned = true;
    result.correction = bestPosition - videoPosition;
    SetMediaItemInfo_Value(videoItem, "D_POSITION", bestPosition);
    if (UpdateArrange) {
      UpdateArrange();
    }
    if (UpdateTimeline) {
      UpdateTimeline();
    }
  }

  return result;
}

std::string alignmentStatusText(const AlignmentResult &alignment) {
  if (alignment.aligned) {
    const double correctionMs = alignment.correction * 1000.0;
    char message[160] = {};
    std::snprintf(message,
                  sizeof(message),
                  "Recorded to Video Recorder track; aligned %.0f ms (score %.2f)",
                  correctionMs,
                  alignment.score);
    return message;
  }
  char message[200] = {};
  if (alignment.videoSamples <= 0) {
    if (!alignment.videoDebug.empty()) {
      std::snprintf(message, sizeof(message), "No alignment match: %s", alignment.videoDebug.c_str());
    } else {
      std::snprintf(message, sizeof(message), "No alignment match: no audio peaks in video item");
    }
  } else if (alignment.candidateReferences <= 0) {
    std::snprintf(message, sizeof(message), "No alignment match: no nearby reference items");
  } else if (alignment.usableReferences <= 0) {
    std::snprintf(message,
                  sizeof(message),
                  "No alignment match: no reference peaks (%d candidates)",
                  alignment.candidateReferences);
  } else if (std::isfinite(alignment.score)) {
    std::snprintf(message,
                  sizeof(message),
                  "No alignment match: best score %.2f below %.2f (%d refs)",
                  alignment.score,
                  kAlignmentMinimumScore,
                  alignment.usableReferences);
  } else {
    std::snprintf(message,
                  sizeof(message),
                  "No alignment match: %d video peaks, %d refs",
                  alignment.videoPeaks,
                  alignment.usableReferences);
  }
  return message;
}

void clearPendingAlignment() {
  g_pendingAlignment = false;
  g_pendingAlignmentProject = nullptr;
  g_pendingAlignmentTrack = nullptr;
  g_pendingAlignmentItem = nullptr;
  g_pendingAlignmentAttempts = 0;
  g_nextAlignmentAttemptTime = 0;
}

void queuePendingAlignment(ReaProject *project, MediaTrack *track, MediaItem *item) {
  g_pendingAlignment = project && track && item;
  g_pendingAlignmentProject = project;
  g_pendingAlignmentTrack = track;
  g_pendingAlignmentItem = item;
  g_pendingAlignmentAttempts = 0;
  g_nextAlignmentAttemptTime = std::time(nullptr) + 1;
}

bool insertRecordedMedia(const std::string &path, double position, bool fromIPhone, std::string &error) {
  ReaProject *project = g_recordProject ? g_recordProject : currentProject();
  if (!project) {
    error = "Recording finished, but there is no active REAPER project to insert into:\n" + path;
    return false;
  }

  if (!PCM_Source_CreateFromFile || !AddMediaItemToTrack || !AddTakeToMediaItem ||
      !SetMediaItemTake_Source || !SetMediaItemInfo_Value || !GetMediaSourceLength) {
    error = "Recording finished, but required REAPER media insertion APIs are unavailable.";
    return false;
  }

  MediaTrack *track = ensureVideoTrackReady(project, false);
  if (!track) {
    error = "Recording finished, but REAPER could not create or find the Video Recorder track.";
    return false;
  }

  MediaItem *videoItem = insertMediaItem(track,
                                         path,
                                         position,
                                         0.0,
                                         1.0,
                                         "video",
                                         error);
  if (!videoItem) {
    return false;
  }

  (void)fromIPhone;
  AlignmentResult alignment = alignVideoItemToReference(project, track, videoItem);
  if (alignment.aligned) {
    clearPendingAlignment();
    g_lastAlignmentStatus = alignmentStatusText(alignment);
  } else {
    queuePendingAlignment(project, track, videoItem);
    g_lastAlignmentStatus = "Recorded to Video Recorder track; aligning audio";
  }

  if (UpdateArrange) {
    UpdateArrange();
  }
  if (UpdateTimeline) {
    UpdateTimeline();
  }

  return true;
}

void updateFollowStatusText();
void refreshToolbarState();
void stopTransportRecording();

std::string followStatusText() {
  if (!g_videoEnabled) {
    return "Video disabled";
  }
  return std::string("Video enabled; transport follow ") + (g_followEnabled ? "on" : "off");
}

void setFollowEnabled(bool enabled) {
  g_followEnabled = enabled;
  if (SetExtState) {
    SetExtState(kExtStateSection, kFollowEnabledKey, enabled ? "1" : "0", true);
  }
  updateFollowStatusText();
  refreshToolbarState();
}

void setVideoEnabled(bool enabled);

} // namespace

@interface KlongVideoRecorder : NSObject <AVCaptureFileOutputRecordingDelegate, NSURLSessionDataDelegate, LKRTCPeerConnectionDelegate>
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, copy) NSString *activePlaybackPath;
@property(nonatomic, assign) CFTimeInterval lastPlaybackSeekHostTime;
@property(nonatomic, strong) NSView *dockView;
@property(nonatomic, strong) NSView *previewView;
@property(nonatomic, strong) NSWindow *floatingPreviewWindow;
@property(nonatomic, strong) NSPopUpButton *sourcePopup;
@property(nonatomic, strong) NSPopUpButton *devicePopup;
@property(nonatomic, strong) NSPopUpButton *formatDiagnosticPopup;
@property(nonatomic, strong) NSButton *iPhoneSetupButton;
@property(nonatomic, strong) NSWindow *iPhoneSetupWindow;
@property(nonatomic, strong) NSTextField *iPhoneHostField;
@property(nonatomic, strong) NSTextField *iPhoneTokenField;
@property(nonatomic, strong) NSTextField *iPhonePairingCodeField;
@property(nonatomic, strong) NSButton *iPhoneDiscoverButton;
@property(nonatomic, strong) NSButton *iPhonePairButton;
@property(nonatomic, strong) NSButton *iPhoneTestButton;
@property(nonatomic, strong) NSTextField *iPhoneSetupHostField;
@property(nonatomic, strong) NSTextField *iPhoneSetupTokenField;
@property(nonatomic, strong) NSTextField *iPhoneSetupPairingCodeField;
@property(nonatomic, strong) NSButton *iPhoneSetupDiscoverButton;
@property(nonatomic, strong) NSButton *iPhoneSetupPairButton;
@property(nonatomic, strong) NSButton *iPhoneSetupTestButton;
@property(nonatomic, strong) NSPopUpButton *iPhoneResolutionPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneFPSPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneOrientationPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneAspectPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneLensPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneZoomPopup;
@property(nonatomic, strong) NSPopUpButton *iPhoneLookPopup;
@property(nonatomic, strong) NSTextField *formatLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSImageView *remotePreviewView;
@property(nonatomic, strong) LKRTCMTLVideoView *webRTCPreviewView;
@property(nonatomic, strong) LKRTCPeerConnectionFactory *webRTCPeerConnectionFactory;
@property(nonatomic, strong) LKRTCPeerConnection *webRTCPeerConnection;
@property(nonatomic, strong) LKRTCVideoTrack *webRTCVideoTrack;
@property(nonatomic, strong) NSMutableArray<LKRTCIceCandidate *> *webRTCLocalIceCandidates;
@property(nonatomic, strong) NSURLSession *remotePreviewSession;
@property(nonatomic, strong) NSURLSessionDataTask *remotePreviewTask;
@property(nonatomic, strong) NSMutableData *remotePreviewBuffer;
@property(nonatomic, strong) NSOperationQueue *remotePreviewQueue;
@property(nonatomic, assign) BOOL remotePreviewDecoding;
@property(nonatomic, assign) BOOL remotePreviewStreaming;
@property(nonatomic, assign) NSUInteger remotePreviewFramesReceived;
@property(nonatomic, assign) NSUInteger remotePreviewFramesDisplayed;
@property(nonatomic, assign) NSUInteger remotePreviewFramesDropped;
@property(nonatomic, assign) NSUInteger remotePreviewFramesDisplayedAtLastUpdate;
@property(nonatomic, assign) CFTimeInterval remotePreviewLastDisplayTime;
@property(nonatomic, assign) CFTimeInterval remotePreviewLastStatusTime;
@property(nonatomic, assign) BOOL remotePreviewUsingSnapshotFallback;
@property(nonatomic, assign) BOOL iPhonePreviewProfileConfiguring;
@property(nonatomic, assign) BOOL webRTCPreviewStarting;
@property(nonatomic, assign) BOOL webRTCPreviewActive;
@property(nonatomic, assign) BOOL webRTCPreviewFailed;
@property(nonatomic, copy) NSString *webRTCPreviewFallbackReason;
@property(nonatomic, strong) dispatch_semaphore_t webRTCIceGatheringSemaphore;
@property(nonatomic, copy) void (^startCompletion)(void);
@property(nonatomic, copy) void (^stopCompletion)(NSString *path, NSError *error);
@property(nonatomic, copy) NSString *activeOutputPath;
@property(nonatomic, copy) NSString *activeRemoteDownloadDirectory;
@property(nonatomic, copy) NSString *audioDeviceName;
@property(nonatomic, copy) NSString *captureQualityLabel;
@property(nonatomic, assign) BOOL docked;
@property(nonatomic, assign) BOOL floatingPreview;
@property(nonatomic, assign) BOOL hasAudioInput;
@property(nonatomic, assign) BOOL recordingVisualState;
@property(nonatomic, assign) BOOL showingPlayback;
@property(nonatomic, assign) BOOL remoteRecording;
@end

@implementation KlongVideoRecorder

- (instancetype)init {
  self = [super init];
  if (self) {
    _floatingPreview = g_previewFloating;
  }
  return self;
}

- (void)showPreview {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (g_useIPhoneSource) {
      [self ensureDockView];
      [self showLivePreview];
      if (self.floatingPreview) {
        [self showFloatingPreview];
      } else {
        [self showDockedPreview];
      }
      [self setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
      return;
    }
    [self ensureCaptureAccessThenRun:^{
      NSError *error = nil;
      if (![self ensureSession:&error]) {
        showError(error.localizedDescription.UTF8String ?: "Unable to initialize camera session.");
        return;
      }
      [self ensureDockView];
      if (self.floatingPreview) {
        [self showFloatingPreview];
      } else {
        [self showDockedPreview];
      }
      [self setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
    }];
  });
}

- (void)togglePreview {
  if (self.floatingPreview && self.floatingPreviewWindow.visible) {
    [self hideFloatingPreview];
  } else if (self.docked) {
    [self hideDockedPreview];
  } else {
    [self showPreview];
  }
}

- (void)togglePreviewDockMode {
  [self ensureDockView];
  self.floatingPreview = !self.floatingPreview;
  g_previewFloating = self.floatingPreview;
  if (SetExtState) {
    SetExtState(kExtStateSection, kPreviewFloatingKey, g_previewFloating ? "1" : "0", true);
  }
  if (self.floatingPreview) {
    [self hideDockedPreview];
    [self showFloatingPreview];
    [self setStatus:@"Preview floating"];
  } else {
    [self hideFloatingPreview];
    [self showDockedPreview];
    [self setStatus:@"Preview docked"];
  }
}

- (BOOL)isRecording {
  if (g_useIPhoneSource) {
    return self.remoteRecording;
  }
  return self.movieOutput.isRecording;
}

- (NSString *)videoSyncHelperPath {
  NSString *installedPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/REAPER/UserPlugins/video-sync-mac"];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:installedPath]) {
    return installedPath;
  }
  NSString *repoPath = [NSString stringWithUTF8String:kRepoHelperPath];
  if ([[NSFileManager defaultManager] isExecutableFileAtPath:repoPath]) {
    return repoPath;
  }
  return installedPath;
}

- (NSArray<NSString *> *)videoSyncArgumentsForCommand:(NSString *)command extraArguments:(NSArray<NSString *> *)extraArguments {
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:command];
  if (![command isEqualToString:@"discover"]) {
    [arguments addObjectsFromArray:@[
      @"--host",
      [NSString stringWithUTF8String:g_iPhoneHost.c_str()],
      @"--port",
      [NSString stringWithUTF8String:g_iPhoneControlPort.c_str()]
    ]];
  }
  [arguments addObjectsFromArray:extraArguments ?: @[]];
  return arguments;
}

- (NSString *)runVideoSyncCommand:(NSString *)command
                   extraArguments:(NSArray<NSString *> *)extraArguments
                           error:(NSError **)error {
  NSTask *task = [[NSTask alloc] init];
  NSString *helperPath = [self videoSyncHelperPath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
    if (error) {
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                  code:19
                              userInfo:@{NSLocalizedDescriptionKey: @"The bundled video-sync-mac helper is missing. Run make install again."}];
    }
    return nil;
  }
  task.executableURL = [NSURL fileURLWithPath:helperPath];
  task.arguments = [self videoSyncArgumentsForCommand:command extraArguments:extraArguments];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    if (error) {
      *error = launchError;
    }
    return nil;
  }
  [task waitUntilExit];
  NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
  if (task.terminationStatus != 0) {
    if (error) {
      NSString *message = output.length > 0 ? output : @"video-sync-mac failed.";
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                  code:20
                              userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return nil;
  }
  return output;
}

- (void)runVideoSyncCommandAsync:(NSString *)command
                  extraArguments:(NSArray<NSString *> *)extraArguments
                      completion:(void (^)(NSString *output, NSError *error))completion {
  [self runVideoSyncCommandAsync:command extraArguments:extraArguments outputHandler:nil completion:completion];
}

- (void)runVideoSyncCommandAsync:(NSString *)command
                  extraArguments:(NSArray<NSString *> *)extraArguments
                   outputHandler:(void (^)(NSString *line))outputHandler
                      completion:(void (^)(NSString *output, NSError *error))completion {
  NSString *helperPath = [self videoSyncHelperPath];
  if (![[NSFileManager defaultManager] isExecutableFileAtPath:helperPath]) {
    NSError *missingError = [NSError errorWithDomain:@"KlongVideoRecorder"
                                                code:19
                                            userInfo:@{NSLocalizedDescriptionKey: @"The bundled video-sync-mac helper is missing. Run make install again."}];
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(nil, missingError);
    });
    return;
  }

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:helperPath];
  task.arguments = [self videoSyncArgumentsForCommand:command extraArguments:extraArguments];
  NSPipe *pipe = [NSPipe pipe];
  task.standardOutput = pipe;
  task.standardError = pipe;
  NSFileHandle *readHandle = pipe.fileHandleForReading;
  NSMutableData *outputData = [NSMutableData data];
  NSMutableString *pendingLine = [NSMutableString string];
  void (^consumeData)(NSData *) = ^(NSData *data) {
    if (data.length == 0) {
      return;
    }
    @synchronized (outputData) {
      [outputData appendData:data];
    }
    if (!outputHandler) {
      return;
    }
    NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSArray<NSString *> *parts = [chunk componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSUInteger i = 0; i < parts.count; ++i) {
      NSString *part = parts[i];
      if (i == 0) {
        [pendingLine appendString:part];
      } else {
        NSString *line = [pendingLine copy];
        [pendingLine setString:part];
        if (line.length > 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            outputHandler(line);
          });
        }
      }
    }
  };
  readHandle.readabilityHandler = ^(NSFileHandle *handle) {
    NSData *data = handle.availableData;
    consumeData(data);
  };
  task.terminationHandler = ^(NSTask *finishedTask) {
    readHandle.readabilityHandler = nil;
    consumeData([readHandle readDataToEndOfFile]);
    if (outputHandler && pendingLine.length > 0) {
      NSString *line = [pendingLine copy];
      [pendingLine setString:@""];
      dispatch_async(dispatch_get_main_queue(), ^{
        outputHandler(line);
      });
    }
    NSData *data = nil;
    @synchronized (outputData) {
      data = [outputData copy];
    }
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    NSError *commandError = nil;
    if (finishedTask.terminationStatus != 0) {
      NSString *message = output.length > 0 ? output : @"video-sync-mac failed.";
      commandError = [NSError errorWithDomain:@"KlongVideoRecorder"
                                        code:21
                                    userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(output, commandError);
    });
  };

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(nil, launchError);
    });
  }
}

- (BOOL)startIPhoneRecordingWithSuggestedPath:(const std::string &)path
                             startCompletion:(void (^)(void))startCompletion
                                        error:(NSError **)error {
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    if (error) {
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                  code:22
                              userInfo:@{NSLocalizedDescriptionKey: @"Set the iPhone host and pairing token before recording."}];
    }
    return NO;
  }

  NSArray<NSString *> *configureArguments = @[
    @"--token",
    [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
    @"--resolution",
    [NSString stringWithUTF8String:g_iPhoneResolution.c_str()],
    @"--fps",
    [NSString stringWithUTF8String:g_iPhoneFPS.c_str()],
    @"--orientation",
    [NSString stringWithUTF8String:g_iPhoneOrientation.c_str()],
    @"--aspect",
    [NSString stringWithUTF8String:g_iPhoneAspect.c_str()],
    @"--lens",
    [NSString stringWithUTF8String:g_iPhoneLens.c_str()],
    @"--zoom",
    [NSString stringWithUTF8String:g_iPhoneZoom.c_str()],
    @"--look",
    [NSString stringWithUTF8String:g_iPhoneLook.c_str()]
  ];
  if (![self runVideoSyncCommand:@"configure" extraArguments:configureArguments error:error]) {
    return NO;
  }

  NSString *outputPath = [NSString stringWithUTF8String:path.c_str()];
  NSString *directory = [outputPath stringByDeletingLastPathComponent];
  NSError *directoryError = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&directoryError]) {
    if (error) {
      *error = directoryError;
    }
    return NO;
  }

  NSString *sessionID = [NSString stringWithFormat:@"reaper-%s", timestampString().c_str()];
  NSArray<NSString *> *arguments = @[
    @"--token",
    [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
    @"--session",
    sessionID
  ];
  if (![self runVideoSyncCommand:@"start" extraArguments:arguments error:error]) {
    return NO;
  }

  self.activeRemoteDownloadDirectory = directory;
  self.remoteRecording = YES;
  [self setRecordingVisualState:YES];
  [self setStatus:@"Recording on iPhone"];
  if (startCompletion) {
    startCompletion();
  }
  return YES;
}

- (NSString *)downloadedPathFromVideoSyncOutput:(NSString *)output {
  for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    if ([line hasPrefix:@"downloaded "]) {
      return [line substringFromIndex:@"downloaded ".length];
    }
  }
  return nil;
}

- (NSDictionary<NSString *, NSString *> *)recordingDescriptorFromVideoSyncOutput:(NSString *)output {
  for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    if ([line hasPrefix:@"recording\t"]) {
      return [self fieldsFromHelperLine:line];
    }
  }
  return nil;
}

- (void)handleVideoSyncProgressLine:(NSString *)line {
  if ([line hasPrefix:@"encode "]) {
    NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
    for (NSString *part in [line componentsSeparatedByString:@" "]) {
      NSRange equals = [part rangeOfString:@"="];
      if (equals.location == NSNotFound || equals.location == 0) {
        continue;
      }
      NSString *key = [part substringToIndex:equals.location];
      NSString *value = [part substringFromIndex:equals.location + 1];
      fields[key] = value;
    }
    NSString *percent = fields[@"percent"];
    if (percent.length > 0) {
      [self setStatus:[NSString stringWithFormat:@"Encoding iPhone look: %@%%", percent]];
    } else {
      [self setStatus:@"Encoding iPhone look"];
    }
    return;
  }
  if (![line hasPrefix:@"progress "]) {
    return;
  }
  NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
  for (NSString *part in [line componentsSeparatedByString:@" "]) {
    NSRange equals = [part rangeOfString:@"="];
    if (equals.location == NSNotFound || equals.location == 0) {
      continue;
    }
    NSString *key = [part substringToIndex:equals.location];
    NSString *value = [part substringFromIndex:equals.location + 1];
    fields[key] = value;
  }
  NSString *percent = fields[@"percent"];
  NSString *bytes = fields[@"bytes"];
  NSString *total = fields[@"total"];
  if (percent.length > 0) {
    [self setStatus:[NSString stringWithFormat:@"Downloading iPhone video: %@%%", percent]];
  } else if (bytes.length > 0 && total.length > 0) {
    [self setStatus:[NSString stringWithFormat:@"Downloading iPhone video: %@/%@ bytes", bytes, total]];
  }
}

- (void)finishIPhoneStopWithPath:(NSString *)path error:(NSError *)error {
  if (self.stopCompletion) {
    self.stopCompletion(path, error);
    self.stopCompletion = nil;
  }
}

- (void)downloadStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording {
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObjects:
    @"--http-port",
    [NSString stringWithUTF8String:g_iPhoneHttpPort.c_str()],
    @"--token",
    [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
    @"--recording-id",
    recording[@"id"] ?: @"",
    @"--filename",
    recording[@"filename"] ?: @"recording.mov",
    @"--byte-count",
    recording[@"byteCount"] ?: @"0",
    @"--download-path",
    recording[@"downloadPath"] ?: @"",
    @"--download-dir",
    self.activeRemoteDownloadDirectory ?: NSHomeDirectory(),
    @"--progress",
    nil];
  NSString *checksum = recording[@"checksum"];
  if (checksum.length > 0) {
    [arguments addObjectsFromArray:@[ @"--checksum", checksum ]];
  }
  [self setStatus:@"Downloading iPhone video"];
  [self runVideoSyncCommandAsync:@"download-recording" extraArguments:arguments outputHandler:^(NSString *line) {
    [self handleVideoSyncProgressLine:line];
  } completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone download failed"];
      [self finishIPhoneStopWithPath:nil error:error];
      return;
    }
    NSString *path = [self downloadedPathFromVideoSyncOutput:output ?: @""];
    NSError *missingPathError = nil;
    if (path.length == 0) {
      missingPathError = [NSError errorWithDomain:@"KlongVideoRecorder"
                                             code:23
                                         userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording downloaded, but video-sync-mac did not report a file path."}];
    }
    [self finishIPhoneStopWithPath:path error:missingPathError];
  }];
}

- (void)deleteStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording {
  NSString *recordingID = recording[@"id"];
  if (recordingID.length == 0) {
    NSError *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                         code:24
                                     userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording stopped, but video-sync-mac did not report a recording ID to delete."}];
    [self finishIPhoneStopWithPath:nil error:error];
    return;
  }
  [self setStatus:@"Deleting iPhone video"];
  NSArray<NSString *> *arguments = @[
    @"--token",
    [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
    @"--recording-id",
    recordingID
  ];
  [self runVideoSyncCommandAsync:@"delete-recording" extraArguments:arguments completion:^(NSString *output, NSError *error) {
    (void)output;
    if (error) {
      [self setStatus:@"iPhone delete failed"];
      [self finishIPhoneStopWithPath:nil error:error];
      return;
    }
    [self setStatus:@"iPhone video deleted"];
    [self finishIPhoneStopWithPath:nil error:nil];
  }];
}

- (void)promptForStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording {
  NSString *filename = recording[@"filename"] ?: @"the stopped iPhone video";
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Download iPhone video?";
  alert.informativeText = [NSString stringWithFormat:@"Download %@ into the REAPER project, or delete it from the iPhone without downloading?", filename];
  [alert addButtonWithTitle:@"Download"];
  [alert addButtonWithTitle:@"Delete from iPhone"];
  NSModalResponse response = [alert runModal];
  if (response == NSAlertFirstButtonReturn) {
    [self downloadStoppedIPhoneRecording:recording];
    return;
  }

  NSAlert *confirm = [[NSAlert alloc] init];
  confirm.alertStyle = NSAlertStyleWarning;
  confirm.messageText = @"Delete iPhone recording?";
  confirm.informativeText = [NSString stringWithFormat:@"This will permanently delete %@ from the iPhone without downloading it.", filename];
  [confirm addButtonWithTitle:@"Delete"];
  [confirm addButtonWithTitle:@"Cancel"];
  if ([confirm runModal] == NSAlertFirstButtonReturn) {
    [self deleteStoppedIPhoneRecording:recording];
  } else {
    [self downloadStoppedIPhoneRecording:recording];
  }
}

- (BOOL)startRecordingToPath:(const std::string &)path
             startCompletion:(void (^)(void))startCompletion
                        error:(NSError **)error {
  if (g_useIPhoneSource) {
    return [self startIPhoneRecordingWithSuggestedPath:path startCompletion:startCompletion error:error];
  }
  if (![self ensureSession:error]) {
    return NO;
  }
  if (!self.hasAudioInput) {
    if (error) {
      NSString *message = @"No microphone/camera audio input is available for the selected camera. Grant microphone permission to REAPER and make sure the camera microphone is available in macOS.";
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                   code:6
                               userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
  }
  if (self.movieOutput.isRecording) {
    if (error) {
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey: @"Video recording is already active."}];
    }
    return NO;
  }

  NSString *outputPath = [NSString stringWithUTF8String:path.c_str()];
  NSString *directory = [outputPath stringByDeletingLastPathComponent];
  NSError *directoryError = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:directory
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&directoryError]) {
    if (error) {
      *error = directoryError;
    }
    return NO;
  }

  if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath]) {
    [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
  }

  self.activeOutputPath = outputPath;
  self.startCompletion = startCompletion;
  [self showLivePreview];
  [self ensureDockView];
  if (self.floatingPreview) {
    [self showFloatingPreview];
  } else {
    [self showDockedPreview];
  }
  [self setStatus:@"Starting recording"];
  [self.movieOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputPath]
                                recordingDelegate:self];
  return YES;
}

- (void)stopRecordingWithCompletion:(void (^)(NSString *path, NSError *error))completion {
  if (g_useIPhoneSource) {
    self.stopCompletion = completion;
    if (!self.remoteRecording) {
      if (self.stopCompletion) {
        self.stopCompletion(nil, nil);
        self.stopCompletion = nil;
      }
      return;
    }
    [self setStatus:@"Stopping iPhone recording"];
    NSArray<NSString *> *arguments = @[
      @"--token",
      [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
      @"--progress"
    ];
    [self runVideoSyncCommandAsync:@"stop-only" extraArguments:arguments outputHandler:^(NSString *line) {
      [self handleVideoSyncProgressLine:line];
    } completion:^(NSString *output, NSError *error) {
      self.remoteRecording = NO;
      [self setRecordingVisualState:NO];
      if (error) {
        [self setStatus:@"iPhone stop failed"];
        [self finishIPhoneStopWithPath:nil error:error];
        return;
      }
      NSDictionary<NSString *, NSString *> *recording = [self recordingDescriptorFromVideoSyncOutput:output ?: @""];
      if (!recording) {
        NSError *descriptorError = [NSError errorWithDomain:@"KlongVideoRecorder"
                                                       code:25
                                                   userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording stopped, but video-sync-mac did not report recording details."}];
        [self finishIPhoneStopWithPath:nil error:descriptorError];
        return;
      }
      [self promptForStoppedIPhoneRecording:recording];
    }];
    return;
  }
  self.stopCompletion = completion;
  if (!self.movieOutput.isRecording) {
    if (self.stopCompletion) {
      self.stopCompletion(self.activeOutputPath, nil);
      self.stopCompletion = nil;
    }
    return;
  }
  [self setStatus:@"Finalizing"];
  [self.movieOutput stopRecording];
}

- (void)ensureCaptureAccessThenRun:(dispatch_block_t)block {
  AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status == AVAuthorizationStatusAuthorized) {
    [self ensureAudioAccessThenRun:block];
    return;
  }
  if (status == AVAuthorizationStatusNotDetermined) {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (granted) {
          [self ensureAudioAccessThenRun:block];
        } else {
          showError("Camera permission was denied. Enable camera access for REAPER in macOS System Settings.");
        }
      });
    }];
    return;
  }
  showError("Camera permission is not available. Enable camera access for REAPER in macOS System Settings.");
}

- (void)ensureAudioAccessThenRun:(dispatch_block_t)block {
  AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
  if (status == AVAuthorizationStatusAuthorized) {
    block();
    return;
  }
  if (status == AVAuthorizationStatusNotDetermined) {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!granted) {
          [self setStatus:@"Microphone denied; recording video only"];
        }
        block();
      });
    }];
    return;
  }

  [self setStatus:@"Microphone unavailable; recording video only"];
  block();
}

- (BOOL)format:(AVCaptureDeviceFormat *)format supportsFPS:(double)fps {
  for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
    if (range.minFrameRate <= fps && fps <= range.maxFrameRate) {
      return YES;
    }
  }
  return NO;
}

- (double)bestFPSForFormat:(AVCaptureDeviceFormat *)format preferredFPS:(double)preferredFPS {
  for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
    if (range.minFrameRate <= preferredFPS && preferredFPS <= range.maxFrameRate) {
      return preferredFPS;
    }
  }

  double bestFPS = 0.0;
  for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
    if (range.maxFrameRate > bestFPS) {
      bestFPS = range.maxFrameRate;
    }
  }
  return bestFPS;
}

- (AVCaptureDeviceFormat *)formatForDevice:(AVCaptureDevice *)device
                                     width:(int)width
                                    height:(int)height
                                       fps:(double)fps {
  AVCaptureDeviceFormat *bestFormat = nil;
  for (AVCaptureDeviceFormat *format in device.formats) {
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    if (dimensions.width == width && dimensions.height == height && [self format:format supportsFPS:fps]) {
      bestFormat = format;
      break;
    }
  }
  return bestFormat;
}

- (AVCaptureDeviceFormat *)highestAvailableFormatForDevice:(AVCaptureDevice *)device
                                              preferredFPS:(double)preferredFPS
                                                 targetFPS:(double *)targetFPS
                                              qualityLabel:(NSString **)qualityLabel {
  AVCaptureDeviceFormat *bestFormat = nil;
  int bestArea = 0;
  double bestFPS = 0.0;

  for (AVCaptureDeviceFormat *format in device.formats) {
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
    const int area = dimensions.width * dimensions.height;
    const double fps = [self bestFPSForFormat:format preferredFPS:preferredFPS];
    if (area > bestArea || (area == bestArea && fps > bestFPS)) {
      bestFormat = format;
      bestArea = area;
      bestFPS = fps;
    }
  }

  if (targetFPS) {
    *targetFPS = bestFPS > 0.0 ? bestFPS : 30.0;
  }
  if (qualityLabel && bestFormat) {
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription);
    *qualityLabel = [NSString stringWithFormat:@"Highest available %dx%d %.2f fps",
                                               dimensions.width,
                                               dimensions.height,
                                               bestFPS];
  }
  return bestFormat;
}

- (void)applyPreferredCaptureFormatForDevice:(AVCaptureDevice *)device {
  AVCaptureDeviceFormat *format = [self formatForDevice:device width:3840 height:2160 fps:30.0];
  double targetFPS = 30.0;
  NSString *qualityLabel = @"Requested 4K30";

  if (!format) {
    format = [self formatForDevice:device width:1920 height:1080 fps:30.0];
    qualityLabel = @"4K30 unavailable; using stable 1080p30";
  }
  if (!format) {
    targetFPS = 30.0;
    format = [self highestAvailableFormatForDevice:device
                                      preferredFPS:30.0
                                         targetFPS:&targetFPS
                                      qualityLabel:&qualityLabel];
    if (format) {
      qualityLabel = [@"4K30/1080p30 unavailable; using " stringByAppendingString:qualityLabel];
    }
  }
  if (!format) {
    self.captureQualityLabel = @"Using device default format";
    return;
  }

  NSError *lockError = nil;
  if (![device lockForConfiguration:&lockError]) {
    self.captureQualityLabel = [NSString stringWithFormat:@"Could not set 4K format: %@",
                                                          lockError.localizedDescription ?: @"lock failed"];
    return;
  }

  device.activeFormat = format;
  CMTime frameDuration = CMTimeMake(1000, static_cast<int32_t>(std::llround(targetFPS * 1000.0)));
  device.activeVideoMinFrameDuration = frameDuration;
  device.activeVideoMaxFrameDuration = frameDuration;
  [device unlockForConfiguration];

  self.captureQualityLabel = qualityLabel;
}

- (BOOL)ensureSession:(NSError **)error {
  AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status != AVAuthorizationStatusAuthorized) {
    if (error) {
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                   code:2
                               userInfo:@{NSLocalizedDescriptionKey: @"Camera permission is not granted. Open the preview once and allow camera access before recording."}];
    }
    return NO;
  }

  if (self.session) {
    return YES;
  }

  AVCaptureDevice *device = [self selectedVideoDevice];
  if (!device) {
    if (error) {
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                   code:3
                               userInfo:@{NSLocalizedDescriptionKey: @"No macOS camera device was found."}];
    }
    return NO;
  }

  NSError *inputError = nil;
  AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&inputError];
  if (!input) {
    if (error) {
      *error = inputError;
    }
    return NO;
  }

  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  session.sessionPreset = AVCaptureSessionPresetHigh;
  if (![session canAddInput:input]) {
    if (error) {
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                   code:4
                               userInfo:@{NSLocalizedDescriptionKey: @"The selected camera cannot be added to the capture session."}];
    }
    return NO;
  }
  [session addInput:input];
  [self applyPreferredCaptureFormatForDevice:device];

  self.hasAudioInput = NO;
  self.audioDeviceName = nil;
  AVCaptureDevice *audioDevice = [self audioDeviceForVideoDevice:device];
  AVCaptureDeviceInput *audioInput = nil;
  if (audioDevice) {
    NSError *audioInputError = nil;
    audioInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:&audioInputError];
    if (audioInput && [session canAddInput:audioInput]) {
      [session addInput:audioInput];
      self.audioDeviceName = audioDevice.localizedName ?: @"Camera audio";
    } else {
      [self setStatus:@"Camera audio unavailable; recording video only"];
    }
  } else {
    [self setStatus:@"No camera audio input found"];
  }

  AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
  if (![session canAddOutput:movieOutput]) {
    if (error) {
      *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                   code:5
                               userInfo:@{NSLocalizedDescriptionKey: @"The movie recorder cannot be added to the capture session."}];
    }
    return NO;
  }
  [session addOutput:movieOutput];
  if (audioInput) {
    AVCaptureConnection *audioConnection = [movieOutput connectionWithMediaType:AVMediaTypeAudio];
    self.hasAudioInput = audioConnection != nil;
    audioConnection.enabled = self.hasAudioInput;
    if (!self.hasAudioInput) {
      self.audioDeviceName = nil;
      [self setStatus:@"Movie recorder has no audio connection"];
    }
  }

  self.session = session;
  self.movieOutput = movieOutput;
  [session startRunning];
  [self applyPreferredCaptureFormatForDevice:device];
  [self updateCaptureFormatLabel];
  return YES;
}

- (NSArray<AVCaptureDevice *> *)availableAudioDevices {
  if (@available(macOS 14.0, *)) {
    AVCaptureDeviceDiscoverySession *session =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[ AVCaptureDeviceTypeMicrophone ]
                                                               mediaType:AVMediaTypeAudio
                                                                position:AVCaptureDevicePositionUnspecified];
    if (session.devices.count > 0) {
      return session.devices;
    }
  }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  NSArray<AVCaptureDevice *> *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
#pragma clang diagnostic pop
  AVCaptureDevice *fallback = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
  if (devices.count > 0) {
    return devices;
  }
  return fallback ? @[ fallback ] : @[];
}

- (NSString *)normalizedDeviceMatchName:(NSString *)name {
  NSMutableString *normalized = [[name ?: @"" lowercaseString] mutableCopy];
  NSArray<NSString *> *noiseWords = @[ @"camera", @"microphone", @"mic", @"continuity" ];
  for (NSString *word in noiseWords) {
    [normalized replaceOccurrencesOfString:word
                                withString:@""
                                   options:NSCaseInsensitiveSearch
                                     range:NSMakeRange(0, normalized.length)];
  }
  while ([normalized containsString:@"  "]) {
    [normalized replaceOccurrencesOfString:@"  "
                                withString:@" "
                                   options:0
                                     range:NSMakeRange(0, normalized.length)];
  }
  return [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (AVCaptureDevice *)audioDeviceForVideoDevice:(AVCaptureDevice *)videoDevice {
  NSArray<AVCaptureDevice *> *audioDevices = [self availableAudioDevices];
  if (audioDevices.count == 0) {
    return nil;
  }

  NSString *videoName = videoDevice.localizedName ?: @"";
  NSString *normalizedVideoName = [self normalizedDeviceMatchName:videoName];
  for (AVCaptureDevice *audioDevice in audioDevices) {
    NSString *audioName = audioDevice.localizedName ?: @"";
    NSString *normalizedAudioName = [self normalizedDeviceMatchName:audioName];
    if ([audioName isEqualToString:videoName] ||
        (videoName.length > 0 && [audioName localizedCaseInsensitiveContainsString:videoName]) ||
        (audioName.length > 0 && [videoName localizedCaseInsensitiveContainsString:audioName]) ||
        (normalizedVideoName.length > 0 && [normalizedAudioName isEqualToString:normalizedVideoName]) ||
        (normalizedVideoName.length > 0 && [normalizedAudioName localizedCaseInsensitiveContainsString:normalizedVideoName]) ||
        (normalizedAudioName.length > 0 && [normalizedVideoName localizedCaseInsensitiveContainsString:normalizedAudioName])) {
      return audioDevice;
    }
  }

  return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio] ?: audioDevices.firstObject;
}

- (NSArray<AVCaptureDevice *> *)availableVideoDevices {
  NSMutableArray<AVCaptureDeviceType> *deviceTypes = [NSMutableArray arrayWithObjects:
      AVCaptureDeviceTypeBuiltInWideAngleCamera,
      nil];
  if (@available(macOS 14.0, *)) {
    [deviceTypes addObject:AVCaptureDeviceTypeExternal];
    [deviceTypes addObject:AVCaptureDeviceTypeContinuityCamera];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [deviceTypes addObject:AVCaptureDeviceTypeExternalUnknown];
#pragma clang diagnostic pop
  }

  AVCaptureDeviceDiscoverySession *session =
      [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:deviceTypes
                                                             mediaType:AVMediaTypeVideo
                                                              position:AVCaptureDevicePositionUnspecified];
  NSArray<AVCaptureDevice *> *devices = session.devices;
  if (devices.count > 0) {
    return devices;
  }

  AVCaptureDevice *fallback = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  return fallback ? @[ fallback ] : @[];
}

- (AVCaptureDevice *)selectedVideoDevice {
  NSArray<AVCaptureDevice *> *devices = [self availableVideoDevices];
  NSString *selectedID = g_selectedDeviceUniqueID.empty() ? nil : [NSString stringWithUTF8String:g_selectedDeviceUniqueID.c_str()];
  if (selectedID.length > 0) {
    for (AVCaptureDevice *device in devices) {
      if ([device.uniqueID isEqualToString:selectedID]) {
        return device;
      }
    }
  }
  return devices.firstObject;
}

- (NSString *)fourCharacterCodeString:(FourCharCode)code {
  char chars[5] = {
      static_cast<char>((code >> 24) & 0xff),
      static_cast<char>((code >> 16) & 0xff),
      static_cast<char>((code >> 8) & 0xff),
      static_cast<char>(code & 0xff),
      '\0',
  };
  for (int i = 0; i < 4; ++i) {
    if (chars[i] < 32 || chars[i] > 126) {
      return [NSString stringWithFormat:@"0x%08x", code];
    }
  }
  return [NSString stringWithUTF8String:chars];
}

- (NSString *)captureFormatDescription {
  AVCaptureDevice *device = [self selectedVideoDevice];
  AVCaptureDeviceFormat *format = device.activeFormat;
  if (!device || !format) {
    return @"Format: unavailable";
  }

  CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
  double fps = 0.0;
  if (CMTIME_IS_NUMERIC(device.activeVideoMinFrameDuration) &&
      device.activeVideoMinFrameDuration.value != 0) {
    fps = static_cast<double>(device.activeVideoMinFrameDuration.timescale) /
          static_cast<double>(device.activeVideoMinFrameDuration.value);
  }
  if (fps <= 0.0 && format.videoSupportedFrameRateRanges.count > 0) {
    fps = format.videoSupportedFrameRateRanges.firstObject.maxFrameRate;
  }

  NSString *codec = nil;
  if (self.movieOutput) {
    AVCaptureConnection *videoConnection = [self.movieOutput connectionWithMediaType:AVMediaTypeVideo];
    if (videoConnection) {
      NSDictionary<NSString *, id> *settings = [self.movieOutput outputSettingsForConnection:videoConnection];
      id codecValue = settings[AVVideoCodecKey];
      if ([codecValue isKindOfClass:NSString.class]) {
        codec = codecValue;
      }
    }
  }
  if (codec.length == 0) {
    codec = [self fourCharacterCodeString:CMFormatDescriptionGetMediaSubType(format.formatDescription)];
  }

  NSString *fpsText = fps > 0.0 ? [NSString stringWithFormat:@"%.2f fps", fps] : @"fps unknown";
  NSString *quality = self.captureQualityLabel.length > 0 ? self.captureQualityLabel : @"Auto";
  return [NSString stringWithFormat:@"Format: %dx%d, %@, codec/source: %@ (%@)",
                                    dimensions.width,
                                    dimensions.height,
                                    fpsText,
                                    codec,
                                    quality];
}

- (void)updateCaptureFormatLabel {
  if (!self.formatLabel) {
    return;
  }
  if (g_useIPhoneSource) {
    self.formatLabel.stringValue = [NSString stringWithFormat:@"iPhone: %s %@ fps, %s, %s, %s lens, %sx, look %s + 640px preview",
                                                              g_iPhoneResolution.c_str(),
                                                              [NSString stringWithUTF8String:g_iPhoneFPS.c_str()],
                                                              g_iPhoneOrientation.c_str(),
                                                              g_iPhoneAspect.c_str(),
                                                              g_iPhoneLens.c_str(),
                                                              g_iPhoneZoom.c_str(),
                                                              g_iPhoneLook.c_str()];
    [self updateRecordingTextColor];
    return;
  }
  self.formatLabel.stringValue = [self captureFormatDescription];
  [self updateRecordingTextColor];
}

- (NSString *)formatDiagnosticTitleForFormat:(AVCaptureDeviceFormat *)format {
  CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
  NSString *codec = [self fourCharacterCodeString:CMFormatDescriptionGetMediaSubType(format.formatDescription)];
  double minFPS = 0.0;
  double maxFPS = 0.0;
  for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
    if (minFPS == 0.0 || range.minFrameRate < minFPS) {
      minFPS = range.minFrameRate;
    }
    if (range.maxFrameRate > maxFPS) {
      maxFPS = range.maxFrameRate;
    }
  }
  NSString *fpsText = minFPS > 0.0 && std::fabs(minFPS - maxFPS) > 0.01
                          ? [NSString stringWithFormat:@"%.2f-%.2f fps", minFPS, maxFPS]
                          : [NSString stringWithFormat:@"%.2f fps", maxFPS];
  return [NSString stringWithFormat:@"%dx%d, %@, %@", dimensions.width, dimensions.height, fpsText, codec];
}

- (void)refreshFormatDiagnosticMenu {
  if (!self.formatDiagnosticPopup) {
    return;
  }

  [self.formatDiagnosticPopup removeAllItems];
  if (g_useIPhoneSource) {
    [self.formatDiagnosticPopup addItemWithTitle:@"Preview: WebRTC first; /preview.bin fallback"];
    [self.formatDiagnosticPopup addItemWithTitle:[NSString stringWithFormat:@"Transport: %@",
                                                    self.webRTCPreviewActive ? @"WebRTC" :
                                                    (self.remotePreviewTask ? @"binary stream fallback" : @"not connected")]];
    [self.formatDiagnosticPopup addItemWithTitle:@"Recording: full-resolution iPhone .mov"];
    [self.formatDiagnosticPopup selectItemAtIndex:0];
    return;
  }
  AVCaptureDevice *device = [self selectedVideoDevice];
  if (!device) {
    [self.formatDiagnosticPopup addItemWithTitle:@"Formats: no camera selected"];
    return;
  }

  BOOL has4K30 = [self formatForDevice:device width:3840 height:2160 fps:30.0] != nil;
  BOOL has1080p30 = [self formatForDevice:device width:1920 height:1080 fps:30.0] != nil;
  BOOL has1080p60 = [self formatForDevice:device width:1920 height:1080 fps:60.0] != nil;
  [self.formatDiagnosticPopup addItemWithTitle:[NSString stringWithFormat:@"4K30: %@", has4K30 ? @"available" : @"unavailable"]];
  [self.formatDiagnosticPopup addItemWithTitle:[NSString stringWithFormat:@"1080p30: %@", has1080p30 ? @"available" : @"unavailable"]];
  [self.formatDiagnosticPopup addItemWithTitle:[NSString stringWithFormat:@"1080p60: %@", has1080p60 ? @"available" : @"unavailable"]];

  NSMutableSet<NSString *> *seen = [NSMutableSet set];
  NSMutableArray<NSString *> *formats = [NSMutableArray array];
  for (AVCaptureDeviceFormat *format in device.formats) {
    NSString *title = [self formatDiagnosticTitleForFormat:format];
    if (![seen containsObject:title]) {
      [seen addObject:title];
      [formats addObject:title];
    }
  }
  [formats sortUsingSelector:@selector(localizedStandardCompare:)];
  for (NSString *formatTitle in formats) {
    [self.formatDiagnosticPopup addItemWithTitle:[@"Format: " stringByAppendingString:formatTitle]];
  }
  if (self.formatDiagnosticPopup.numberOfItems > 0) {
    [self.formatDiagnosticPopup selectItemAtIndex:0];
  }
}

- (void)refreshDeviceMenu {
  if (!self.devicePopup) {
    return;
  }

  [self.devicePopup removeAllItems];
  NSArray<AVCaptureDevice *> *devices = [self availableVideoDevices];
  for (AVCaptureDevice *device in devices) {
    NSString *title = device.localizedName ?: @"Camera";
    [self.devicePopup addItemWithTitle:title];
    self.devicePopup.lastItem.representedObject = device.uniqueID;
  }

  NSString *selectedID = g_selectedDeviceUniqueID.empty() ? nil : [NSString stringWithUTF8String:g_selectedDeviceUniqueID.c_str()];
  if (selectedID.length > 0) {
    NSInteger index = [self.devicePopup indexOfItemWithRepresentedObject:selectedID];
    if (index >= 0) {
      [self.devicePopup selectItemAtIndex:index];
      [self refreshFormatDiagnosticMenu];
      return;
    }
  }
  if (self.devicePopup.numberOfItems > 0) {
    [self.devicePopup selectItemAtIndex:0];
    NSString *uniqueID = self.devicePopup.selectedItem.representedObject;
    if (uniqueID.length > 0 && g_selectedDeviceUniqueID.empty()) {
      g_selectedDeviceUniqueID = uniqueID.UTF8String;
    }
  }
  [self refreshFormatDiagnosticMenu];
}

- (void)refreshSourceMenu {
  if (!self.sourcePopup) {
    return;
  }
  [self.sourcePopup removeAllItems];
  [self.sourcePopup addItemWithTitle:@"Mac camera"];
  self.sourcePopup.lastItem.representedObject = @"mac";
  [self.sourcePopup addItemWithTitle:@"iPhone Video Sync"];
  self.sourcePopup.lastItem.representedObject = @"iphone";
  [self.sourcePopup selectItemWithTitle:g_useIPhoneSource ? @"iPhone Video Sync" : @"Mac camera"];
}

- (void)persistIPhoneSettings {
  NSTextField *hostField = self.iPhoneSetupWindow.visible && self.iPhoneSetupHostField ? self.iPhoneSetupHostField : self.iPhoneHostField;
  NSTextField *tokenField = self.iPhoneSetupWindow.visible && self.iPhoneSetupTokenField ? self.iPhoneSetupTokenField : self.iPhoneTokenField;
  if (hostField) {
    g_iPhoneHost = hostField.stringValue.UTF8String ?: "";
  }
  if (tokenField) {
    g_iPhoneToken = tokenField.stringValue.UTF8String ?: "";
  }
  self.iPhoneHostField.stringValue = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
  self.iPhoneTokenField.stringValue = [NSString stringWithUTF8String:g_iPhoneToken.c_str()];
  self.iPhoneSetupHostField.stringValue = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
  self.iPhoneSetupTokenField.stringValue = [NSString stringWithUTF8String:g_iPhoneToken.c_str()];
  if (self.iPhoneResolutionPopup.selectedItem.title.length > 0) {
    g_iPhoneResolution = self.iPhoneResolutionPopup.selectedItem.title.UTF8String ?: "4K";
  }
  if (self.iPhoneFPSPopup.selectedItem.title.length > 0) {
    g_iPhoneFPS = self.iPhoneFPSPopup.selectedItem.title.UTF8String ?: "30";
  }
  if (self.iPhoneOrientationPopup.selectedItem.representedObject) {
    NSString *orientation = self.iPhoneOrientationPopup.selectedItem.representedObject;
    g_iPhoneOrientation = orientation.UTF8String ?: "portrait";
  }
  if (self.iPhoneAspectPopup.selectedItem.title.length > 0) {
    g_iPhoneAspect = self.iPhoneAspectPopup.selectedItem.title.UTF8String ?: "9:16";
  }
  if (self.iPhoneLensPopup.selectedItem.representedObject) {
    NSString *lens = self.iPhoneLensPopup.selectedItem.representedObject;
    g_iPhoneLens = lens.UTF8String ?: "wide";
  }
  if (self.iPhoneZoomPopup.selectedItem.representedObject) {
    NSString *zoom = self.iPhoneZoomPopup.selectedItem.representedObject;
    g_iPhoneZoom = zoom.UTF8String ?: "1.0";
  }
  if (self.iPhoneLookPopup.selectedItem.representedObject) {
    NSString *look = self.iPhoneLookPopup.selectedItem.representedObject;
    g_iPhoneLook = look.UTF8String ?: "natural";
  }
  if (SetExtState) {
    SetExtState(kExtStateSection, kIPhoneHostKey, g_iPhoneHost.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneTokenKey, g_iPhoneToken.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneControlPortKey, g_iPhoneControlPort.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneHttpPortKey, g_iPhoneHttpPort.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneResolutionKey, g_iPhoneResolution.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneFPSKey, g_iPhoneFPS.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneOrientationKey, g_iPhoneOrientation.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneAspectKey, g_iPhoneAspect.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneLensKey, g_iPhoneLens.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneZoomKey, g_iPhoneZoom.c_str(), true);
    SetExtState(kExtStateSection, kIPhoneLookKey, g_iPhoneLook.c_str(), true);
  }
}

- (void)profileSelectionChanged:(id)sender {
  (void)sender;
  [self persistIPhoneSettings];
  [self updateCaptureFormatLabel];
  if (!g_useIPhoneSource || g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    return;
  }
  NSArray<NSString *> *arguments = @[
    @"--token",
    [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
    @"--resolution",
    [NSString stringWithUTF8String:g_iPhoneResolution.c_str()],
    @"--fps",
    [NSString stringWithUTF8String:g_iPhoneFPS.c_str()],
    @"--orientation",
    [NSString stringWithUTF8String:g_iPhoneOrientation.c_str()],
    @"--aspect",
    [NSString stringWithUTF8String:g_iPhoneAspect.c_str()],
    @"--lens",
    [NSString stringWithUTF8String:g_iPhoneLens.c_str()],
    @"--zoom",
    [NSString stringWithUTF8String:g_iPhoneZoom.c_str()],
    @"--look",
    [NSString stringWithUTF8String:g_iPhoneLook.c_str()]
  ];
  [self setStatus:@"Configuring iPhone profile"];
  [self runVideoSyncCommandAsync:@"configure" extraArguments:arguments completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone profile configure failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone profile configure failed.");
      return;
    }
    NSString *message = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self setStatus:message.length > 0 ? message : @"iPhone profile configured"];
    [self stopRemotePreview];
    [self startRemotePreview];
  }];
}

- (NSArray<NSString *> *)iPhoneConfigureArguments {
  return @[
    @"--token",
    [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
    @"--resolution",
    [NSString stringWithUTF8String:g_iPhoneResolution.c_str()],
    @"--fps",
    [NSString stringWithUTF8String:g_iPhoneFPS.c_str()],
    @"--orientation",
    [NSString stringWithUTF8String:g_iPhoneOrientation.c_str()],
    @"--aspect",
    [NSString stringWithUTF8String:g_iPhoneAspect.c_str()],
    @"--lens",
    [NSString stringWithUTF8String:g_iPhoneLens.c_str()],
    @"--zoom",
    [NSString stringWithUTF8String:g_iPhoneZoom.c_str()],
    @"--look",
    [NSString stringWithUTF8String:g_iPhoneLook.c_str()]
  ];
}

- (NSDictionary<NSString *, NSString *> *)fieldsFromHelperLine:(NSString *)line {
  NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
  for (NSString *part in [line componentsSeparatedByString:@"\t"]) {
    NSRange equals = [part rangeOfString:@"="];
    if (equals.location == NSNotFound || equals.location == 0) {
      continue;
    }
    NSString *key = [part substringToIndex:equals.location];
    NSString *value = [part substringFromIndex:equals.location + 1];
    fields[key] = value;
  }
  return fields;
}

- (BOOL)applyFirstDiscoveredIPhoneFromOutput:(NSString *)output {
  for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    if (![line hasPrefix:@"device\t"]) {
      continue;
    }
    NSDictionary<NSString *, NSString *> *fields = [self fieldsFromHelperLine:line];
    NSString *host = fields[@"host"];
    NSString *controlPort = fields[@"controlPort"];
    NSString *httpPort = fields[@"httpPort"];
    if (host.length == 0) {
      continue;
    }
    g_iPhoneHost = host.UTF8String;
    if (controlPort.length > 0) {
      g_iPhoneControlPort = controlPort.UTF8String;
    }
    if (httpPort.length > 0) {
      g_iPhoneHttpPort = httpPort.UTF8String;
    }
    self.iPhoneHostField.stringValue = host;
    self.iPhoneSetupHostField.stringValue = host;
    [self persistIPhoneSettings];
    [self setStatus:[NSString stringWithFormat:@"Found iPhone: %@", fields[@"name"] ?: host]];
    return YES;
  }
  return NO;
}

- (void)discoverIPhone:(id)sender {
  (void)sender;
  [self setStatus:@"Searching for iPhone Video Sync"];
  [self runVideoSyncCommandAsync:@"discover" extraArguments:@[ @"--timeout", @"3" ] completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone discovery failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone discovery failed.");
      return;
    }
    if (![self applyFirstDiscoveredIPhoneFromOutput:output ?: @""]) {
      if (g_iPhoneHost.empty()) {
        g_iPhoneHost = kDefaultIPhoneHost;
        self.iPhoneHostField.stringValue = [NSString stringWithUTF8String:kDefaultIPhoneHost];
        self.iPhoneSetupHostField.stringValue = [NSString stringWithUTF8String:kDefaultIPhoneHost];
        [self persistIPhoneSettings];
        [self setStatus:@"Bonjour not found; using known iPhone host"];
      } else {
        [self setStatus:@"Bonjour not found; using entered host"];
      }
    }
  }];
}

- (void)pairIPhone:(id)sender {
  (void)sender;
  [self persistIPhoneSettings];
  NSTextField *codeField = self.iPhoneSetupWindow.visible && self.iPhoneSetupPairingCodeField ? self.iPhoneSetupPairingCodeField : self.iPhonePairingCodeField;
  NSString *code = codeField.stringValue;
  if (g_iPhoneHost.empty() || code.length == 0) {
    [self setStatus:@"Enter iPhone host and pairing code"];
    return;
  }
  [self setStatus:@"Pairing with iPhone"];
  [self runVideoSyncCommandAsync:@"pair" extraArguments:@[ @"--code", code ] completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone pairing failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone pairing failed.");
      return;
    }
    NSString *prefix = @"paired token=";
    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
      if ([line hasPrefix:prefix]) {
        NSString *token = [line substringFromIndex:prefix.length];
        self.iPhoneTokenField.stringValue = token;
        self.iPhoneSetupTokenField.stringValue = token;
        g_iPhoneToken = token.UTF8String ?: "";
        [self persistIPhoneSettings];
        [self setStatus:@"iPhone paired"];
        return;
      }
    }
    [self setStatus:@"Pairing did not return a token"];
  }];
}

- (void)testIPhoneConnection:(id)sender {
  (void)sender;
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty()) {
    [self setStatus:@"Enter iPhone host first"];
    return;
  }
  NSMutableArray<NSString *> *arguments = [NSMutableArray array];
  if (!g_iPhoneToken.empty()) {
    [arguments addObjectsFromArray:@[ @"--token", [NSString stringWithUTF8String:g_iPhoneToken.c_str()] ]];
  }
  [self setStatus:@"Testing iPhone connection"];
  [self runVideoSyncCommandAsync:@"ping" extraArguments:arguments completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone connection failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone connection failed.");
      return;
    }
    NSString *message = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self setStatus:message.length > 0 ? [@"iPhone: " stringByAppendingString:message] : @"iPhone connection OK"];
    [self stopRemotePreview];
    self.webRTCPreviewFailed = NO;
    self.webRTCPreviewFallbackReason = nil;
    [self startRemotePreview];
  }];
}

- (void)updateSourceControls {
  self.devicePopup.enabled = !g_useIPhoneSource;
  self.devicePopup.hidden = g_useIPhoneSource;
  self.formatDiagnosticPopup.enabled = !g_useIPhoneSource;
  self.formatDiagnosticPopup.hidden = g_useIPhoneSource;
  self.iPhoneSetupButton.hidden = !g_useIPhoneSource;
  self.iPhoneHostField.hidden = YES;
  self.iPhoneTokenField.hidden = YES;
  self.iPhonePairingCodeField.hidden = YES;
  self.iPhoneDiscoverButton.hidden = YES;
  self.iPhonePairButton.hidden = YES;
  self.iPhoneTestButton.hidden = YES;
  self.iPhoneResolutionPopup.hidden = !g_useIPhoneSource;
  self.iPhoneFPSPopup.hidden = !g_useIPhoneSource;
  self.iPhoneOrientationPopup.hidden = !g_useIPhoneSource;
  self.iPhoneAspectPopup.hidden = !g_useIPhoneSource;
  self.iPhoneLensPopup.hidden = !g_useIPhoneSource;
  self.iPhoneZoomPopup.hidden = !g_useIPhoneSource;
  self.iPhoneLookPopup.hidden = !g_useIPhoneSource;
  [self refreshFormatDiagnosticMenu];
  [self updateCaptureFormatLabel];
}

- (void)sourceSelectionChanged:(id)sender {
  (void)sender;
  const BOOL nextUseIPhoneSource = [self.sourcePopup.selectedItem.representedObject isEqual:@"iphone"];
  if (nextUseIPhoneSource == g_useIPhoneSource) {
    return;
  }
  if (self.isRecording) {
    [self refreshSourceMenu];
    [self setStatus:@"Cannot switch source while recording"];
    return;
  }

  g_useIPhoneSource = nextUseIPhoneSource;
  if (SetExtState) {
    SetExtState(kExtStateSection, kSourceKindKey, g_useIPhoneSource ? "iphone" : "mac", true);
  }
  [self stopRemotePreview];
  if (g_useIPhoneSource) {
    [self.session stopRunning];
    self.session = nil;
    self.movieOutput = nil;
    [self.previewLayer removeFromSuperlayer];
    self.previewLayer = nil;
  } else {
    NSError *error = nil;
    if (![self ensureSession:&error]) {
      showError(error.localizedDescription.UTF8String ?: "Unable to initialize camera session.");
      [self refreshSourceMenu];
      return;
    }
    [self ensureDockView];
  }
  [self updateSourceControls];
  [self showLivePreview];
  [self setStatus:g_useIPhoneSource ? @"iPhone source selected" : @"Mac camera source selected"];
}

- (void)iPhoneSettingsChanged:(id)sender {
  (void)sender;
  [self persistIPhoneSettings];
  [self stopRemotePreview];
  if (g_useIPhoneSource) {
    [self startRemotePreview];
  }
}

- (void)showIPhoneSetup:(id)sender {
  (void)sender;
  if (!self.iPhoneSetupWindow) {
    NSRect frame = NSMakeRect(0, 0, 520, 150);
    self.iPhoneSetupWindow = [[NSWindow alloc] initWithContentRect:frame
                                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
    self.iPhoneSetupWindow.releasedWhenClosed = NO;
    self.iPhoneSetupWindow.title = @"iPhone Video Sync Setup";
    NSView *content = self.iPhoneSetupWindow.contentView;

    self.iPhoneSetupHostField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 112, 240, 22)];
    self.iPhoneSetupHostField.placeholderString = @"iPhone host, e.g. kevin-long-iphone.local";
    self.iPhoneSetupHostField.target = self;
    self.iPhoneSetupHostField.action = @selector(iPhoneSettingsChanged:);
    [content addSubview:self.iPhoneSetupHostField];

    self.iPhoneSetupTokenField = [[NSTextField alloc] initWithFrame:NSMakeRect(268, 112, 240, 22)];
    self.iPhoneSetupTokenField.placeholderString = @"Pairing token";
    self.iPhoneSetupTokenField.target = self;
    self.iPhoneSetupTokenField.action = @selector(iPhoneSettingsChanged:);
    [content addSubview:self.iPhoneSetupTokenField];

    self.iPhoneSetupPairingCodeField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 78, 220, 22)];
    self.iPhoneSetupPairingCodeField.placeholderString = @"Pairing code from iPhone";
    [content addSubview:self.iPhoneSetupPairingCodeField];

    self.iPhoneSetupDiscoverButton = [[NSButton alloc] initWithFrame:NSMakeRect(244, 77, 82, 24)];
    self.iPhoneSetupDiscoverButton.title = @"Discover";
    self.iPhoneSetupDiscoverButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneSetupDiscoverButton.target = self;
    self.iPhoneSetupDiscoverButton.action = @selector(discoverIPhone:);
    [content addSubview:self.iPhoneSetupDiscoverButton];

    self.iPhoneSetupPairButton = [[NSButton alloc] initWithFrame:NSMakeRect(338, 77, 76, 24)];
    self.iPhoneSetupPairButton.title = @"Pair";
    self.iPhoneSetupPairButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneSetupPairButton.target = self;
    self.iPhoneSetupPairButton.action = @selector(pairIPhone:);
    [content addSubview:self.iPhoneSetupPairButton];

    self.iPhoneSetupTestButton = [[NSButton alloc] initWithFrame:NSMakeRect(426, 77, 76, 24)];
    self.iPhoneSetupTestButton.title = @"Test";
    self.iPhoneSetupTestButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneSetupTestButton.target = self;
    self.iPhoneSetupTestButton.action = @selector(testIPhoneConnection:);
    [content addSubview:self.iPhoneSetupTestButton];

    NSTextField *hint = [NSTextField labelWithString:@"Launch the iPhone app, Discover, enter pairing code, Pair, then Test."];
    hint.frame = NSMakeRect(12, 24, 496, 36);
    hint.lineBreakMode = NSLineBreakByWordWrapping;
    [content addSubview:hint];
  }
  self.iPhoneSetupHostField.stringValue = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
  self.iPhoneSetupTokenField.stringValue = [NSString stringWithUTF8String:g_iPhoneToken.c_str()];
  [self.iPhoneSetupWindow makeKeyAndOrderFront:nil];
}

- (void)deviceSelectionChanged:(id)sender {
  (void)sender;
  if (self.movieOutput.isRecording) {
    [self refreshDeviceMenu];
    [self setStatus:@"Cannot switch camera while recording"];
    return;
  }

  NSString *uniqueID = self.devicePopup.selectedItem.representedObject;
  if (uniqueID.length == 0) {
    return;
  }

  g_selectedDeviceUniqueID = uniqueID.UTF8String;
  if (SetExtState) {
    SetExtState(kExtStateSection, kSelectedDeviceKey, g_selectedDeviceUniqueID.c_str(), true);
  }

  [self.session stopRunning];
  self.session = nil;
  self.movieOutput = nil;
  [self.previewLayer removeFromSuperlayer];
  self.previewLayer = nil;

  NSError *error = nil;
  if (![self ensureSession:&error]) {
    showError(error.localizedDescription.UTF8String ?: "Unable to switch camera.");
    return;
  }
  [self ensureDockView];
  [self showLivePreview];
  [self refreshFormatDiagnosticMenu];
  [self updateCaptureFormatLabel];
  [self setStatus:[NSString stringWithFormat:@"Camera: %@", self.devicePopup.selectedItem.title]];
}

- (void)ensureDockView {
  if (!self.dockView) {
    NSRect frame = NSMakeRect(0, 0, 640, 480);
    self.dockView = [[NSView alloc] initWithFrame:frame];
    self.dockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.dockView.wantsLayer = YES;

    self.previewView = [[NSView alloc] initWithFrame:NSMakeRect(0, 130, frame.size.width, frame.size.height - 130)];
    self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.previewView.wantsLayer = YES;
    [self.dockView addSubview:self.previewView];

    self.remotePreviewView = [[NSImageView alloc] initWithFrame:self.previewView.bounds];
    self.remotePreviewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.remotePreviewView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.remotePreviewView.hidden = YES;
    [self.previewView addSubview:self.remotePreviewView];

    self.webRTCPreviewView = [[LKRTCMTLVideoView alloc] initWithFrame:self.previewView.bounds];
    self.webRTCPreviewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.webRTCPreviewView.hidden = YES;
    [self.previewView addSubview:self.webRTCPreviewView positioned:NSWindowBelow relativeTo:self.remotePreviewView];

    self.sourcePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(12, 101, frame.size.width - 132, 24) pullsDown:NO];
    self.sourcePopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.sourcePopup.target = self;
    self.sourcePopup.action = @selector(sourceSelectionChanged:);
    [self.dockView addSubview:self.sourcePopup];

    self.iPhoneSetupButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 112, 101, 100, 24)];
    self.iPhoneSetupButton.title = @"iPhone Setup";
    self.iPhoneSetupButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneSetupButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.iPhoneSetupButton.target = self;
    self.iPhoneSetupButton.action = @selector(showIPhoneSetup:);
    [self.dockView addSubview:self.iPhoneSetupButton];

    self.devicePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(12, 75, frame.size.width - 24, 24) pullsDown:NO];
    self.devicePopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.devicePopup.target = self;
    self.devicePopup.action = @selector(deviceSelectionChanged:);
    [self.dockView addSubview:self.devicePopup];

    self.iPhoneHostField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 127, (frame.size.width - 36) / 2.0, 22)];
    self.iPhoneHostField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneHostField.placeholderString = @"iPhone host, e.g. kevin-long-iphone.local";
    self.iPhoneHostField.stringValue = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
    self.iPhoneHostField.target = self;
    self.iPhoneHostField.action = @selector(iPhoneSettingsChanged:);
    [self.dockView addSubview:self.iPhoneHostField];

    self.iPhoneTokenField = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneHostField.frame) + 12, 127, (frame.size.width - 36) / 2.0, 22)];
    self.iPhoneTokenField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneTokenField.placeholderString = @"Pairing token";
    self.iPhoneTokenField.stringValue = [NSString stringWithUTF8String:g_iPhoneToken.c_str()];
    self.iPhoneTokenField.target = self;
    self.iPhoneTokenField.action = @selector(iPhoneSettingsChanged:);
    [self.dockView addSubview:self.iPhoneTokenField];

    const CGFloat buttonWidth = 88.0;
    self.iPhonePairingCodeField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 101, frame.size.width - 24 - (buttonWidth * 3.0) - 18.0, 22)];
    self.iPhonePairingCodeField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhonePairingCodeField.placeholderString = @"Pairing code from iPhone";
    [self.dockView addSubview:self.iPhonePairingCodeField];

    CGFloat buttonX = NSMaxX(self.iPhonePairingCodeField.frame) + 6.0;
    self.iPhoneDiscoverButton = [[NSButton alloc] initWithFrame:NSMakeRect(buttonX, 101, buttonWidth, 22)];
    self.iPhoneDiscoverButton.title = @"Discover";
    self.iPhoneDiscoverButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneDiscoverButton.target = self;
    self.iPhoneDiscoverButton.action = @selector(discoverIPhone:);
    [self.dockView addSubview:self.iPhoneDiscoverButton];

    buttonX += buttonWidth + 6.0;
    self.iPhonePairButton = [[NSButton alloc] initWithFrame:NSMakeRect(buttonX, 101, buttonWidth, 22)];
    self.iPhonePairButton.title = @"Pair";
    self.iPhonePairButton.bezelStyle = NSBezelStyleRounded;
    self.iPhonePairButton.target = self;
    self.iPhonePairButton.action = @selector(pairIPhone:);
    [self.dockView addSubview:self.iPhonePairButton];

    buttonX += buttonWidth + 6.0;
    self.iPhoneTestButton = [[NSButton alloc] initWithFrame:NSMakeRect(buttonX, 101, buttonWidth, 22)];
    self.iPhoneTestButton.title = @"Test";
    self.iPhoneTestButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneTestButton.target = self;
    self.iPhoneTestButton.action = @selector(testIPhoneConnection:);
    [self.dockView addSubview:self.iPhoneTestButton];

    self.iPhoneDiscoverButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.iPhonePairButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.iPhoneTestButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;

    const CGFloat popupWidth = (frame.size.width - 64.0) / 6.0;
    self.iPhoneResolutionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(12, 75, popupWidth, 24) pullsDown:NO];
    [self.iPhoneResolutionPopup addItemsWithTitles:@[ @"4K", @"1080p", @"720p" ]];
    [self.iPhoneResolutionPopup selectItemWithTitle:[NSString stringWithUTF8String:g_iPhoneResolution.c_str()]];
    self.iPhoneResolutionPopup.target = self;
    self.iPhoneResolutionPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneResolutionPopup];

    self.iPhoneFPSPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneResolutionPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
    [self.iPhoneFPSPopup addItemsWithTitles:@[ @"24", @"30", @"60" ]];
    [self.iPhoneFPSPopup selectItemWithTitle:[NSString stringWithUTF8String:g_iPhoneFPS.c_str()]];
    self.iPhoneFPSPopup.target = self;
    self.iPhoneFPSPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneFPSPopup];

    self.iPhoneOrientationPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneFPSPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
    [self.iPhoneOrientationPopup addItemWithTitle:@"Portrait"];
    self.iPhoneOrientationPopup.lastItem.representedObject = @"portrait";
    [self.iPhoneOrientationPopup addItemWithTitle:@"Landscape R"];
    self.iPhoneOrientationPopup.lastItem.representedObject = @"landscapeRight";
    [self.iPhoneOrientationPopup addItemWithTitle:@"Landscape L"];
    self.iPhoneOrientationPopup.lastItem.representedObject = @"landscapeLeft";
    NSInteger orientationIndex = [self.iPhoneOrientationPopup indexOfItemWithRepresentedObject:[NSString stringWithUTF8String:g_iPhoneOrientation.c_str()]];
    if (orientationIndex >= 0) {
      [self.iPhoneOrientationPopup selectItemAtIndex:orientationIndex];
    }
    self.iPhoneOrientationPopup.target = self;
    self.iPhoneOrientationPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneOrientationPopup];

    self.iPhoneAspectPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneOrientationPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
    [self.iPhoneAspectPopup addItemsWithTitles:@[ @"9:16", @"16:9", @"1:1", @"4:5" ]];
    [self.iPhoneAspectPopup selectItemWithTitle:[NSString stringWithUTF8String:g_iPhoneAspect.c_str()]];
    self.iPhoneAspectPopup.target = self;
    self.iPhoneAspectPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneAspectPopup];

    self.iPhoneLensPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneAspectPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
    [self.iPhoneLensPopup addItemWithTitle:@"Wide"];
    self.iPhoneLensPopup.lastItem.representedObject = @"wide";
    [self.iPhoneLensPopup addItemWithTitle:@"Ultra Wide"];
    self.iPhoneLensPopup.lastItem.representedObject = @"ultrawide";
    [self.iPhoneLensPopup addItemWithTitle:@"Tele"];
    self.iPhoneLensPopup.lastItem.representedObject = @"telephoto";
    [self.iPhoneLensPopup addItemWithTitle:@"Auto"];
    self.iPhoneLensPopup.lastItem.representedObject = @"auto";
    NSInteger lensIndex = [self.iPhoneLensPopup indexOfItemWithRepresentedObject:[NSString stringWithUTF8String:g_iPhoneLens.c_str()]];
    if (lensIndex >= 0) {
      [self.iPhoneLensPopup selectItemAtIndex:lensIndex];
    }
    self.iPhoneLensPopup.target = self;
    self.iPhoneLensPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneLensPopup];

    self.iPhoneZoomPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneLensPopup.frame) + 8, 75, popupWidth, 24) pullsDown:NO];
    [self.iPhoneZoomPopup addItemWithTitle:@"0.5x"];
    self.iPhoneZoomPopup.lastItem.representedObject = @"0.5";
    [self.iPhoneZoomPopup addItemWithTitle:@"1x"];
    self.iPhoneZoomPopup.lastItem.representedObject = @"1.0";
    [self.iPhoneZoomPopup addItemWithTitle:@"2x"];
    self.iPhoneZoomPopup.lastItem.representedObject = @"2.0";
    [self.iPhoneZoomPopup addItemWithTitle:@"3x"];
    self.iPhoneZoomPopup.lastItem.representedObject = @"3.0";
    NSInteger zoomIndex = [self.iPhoneZoomPopup indexOfItemWithRepresentedObject:[NSString stringWithUTF8String:g_iPhoneZoom.c_str()]];
    if (zoomIndex >= 0) {
      [self.iPhoneZoomPopup selectItemAtIndex:zoomIndex];
    }
    self.iPhoneZoomPopup.target = self;
    self.iPhoneZoomPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneZoomPopup];

    self.iPhoneLookPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(12, 49, frame.size.width - 24, 24) pullsDown:NO];
    [self.iPhoneLookPopup addItemWithTitle:@"Natural"];
    self.iPhoneLookPopup.lastItem.representedObject = @"natural";
    [self.iPhoneLookPopup addItemWithTitle:@"Warm Vintage"];
    self.iPhoneLookPopup.lastItem.representedObject = @"warmVintage";
    [self.iPhoneLookPopup addItemWithTitle:@"Cool Blue"];
    self.iPhoneLookPopup.lastItem.representedObject = @"coolBlue";
    [self.iPhoneLookPopup addItemWithTitle:@"High Contrast B&W"];
    self.iPhoneLookPopup.lastItem.representedObject = @"highContrastBW";
    [self.iPhoneLookPopup addItemWithTitle:@"Faded Film"];
    self.iPhoneLookPopup.lastItem.representedObject = @"fadedFilm";
    [self.iPhoneLookPopup addItemWithTitle:@"Dream Glow"];
    self.iPhoneLookPopup.lastItem.representedObject = @"dreamGlow";
    [self.iPhoneLookPopup addItemWithTitle:@"Noir"];
    self.iPhoneLookPopup.lastItem.representedObject = @"noir";
    [self.iPhoneLookPopup addItemWithTitle:@"Saturated Pop"];
    self.iPhoneLookPopup.lastItem.representedObject = @"saturatedPop";
    [self.iPhoneLookPopup addItemWithTitle:@"Bleach Bypass"];
    self.iPhoneLookPopup.lastItem.representedObject = @"bleachBypass";
    [self.iPhoneLookPopup addItemWithTitle:@"Sepia"];
    self.iPhoneLookPopup.lastItem.representedObject = @"sepia";
    [self.iPhoneLookPopup addItemWithTitle:@"Instant Photo"];
    self.iPhoneLookPopup.lastItem.representedObject = @"instantPhoto";
    [self.iPhoneLookPopup addItemWithTitle:@"Chrome"];
    self.iPhoneLookPopup.lastItem.representedObject = @"chrome";
    [self.iPhoneLookPopup addItemWithTitle:@"Tonal"];
    self.iPhoneLookPopup.lastItem.representedObject = @"tonal";
    [self.iPhoneLookPopup addItemWithTitle:@"Silvertone"];
    self.iPhoneLookPopup.lastItem.representedObject = @"silvertone";
    [self.iPhoneLookPopup addItemWithTitle:@"Dramatic Warm"];
    self.iPhoneLookPopup.lastItem.representedObject = @"dramaticWarm";
    [self.iPhoneLookPopup addItemWithTitle:@"Dramatic Cool"];
    self.iPhoneLookPopup.lastItem.representedObject = @"dramaticCool";
    [self.iPhoneLookPopup addItemWithTitle:@"Soft Matte"];
    self.iPhoneLookPopup.lastItem.representedObject = @"softMatte";
    [self.iPhoneLookPopup addItemWithTitle:@"Comic Book"];
    self.iPhoneLookPopup.lastItem.representedObject = @"comicBook";
    [self.iPhoneLookPopup addItemWithTitle:@"VHS"];
    self.iPhoneLookPopup.lastItem.representedObject = @"vhs";
    [self.iPhoneLookPopup addItemWithTitle:@"Music Video Pop"];
    self.iPhoneLookPopup.lastItem.representedObject = @"musicVideoPop";
    NSInteger lookIndex = [self.iPhoneLookPopup indexOfItemWithRepresentedObject:[NSString stringWithUTF8String:g_iPhoneLook.c_str()]];
    if (lookIndex >= 0) {
      [self.iPhoneLookPopup selectItemAtIndex:lookIndex];
    }
    self.iPhoneLookPopup.target = self;
    self.iPhoneLookPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneLookPopup];

    self.iPhoneResolutionPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneFPSPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneOrientationPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneAspectPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneLensPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneZoomPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneLookPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;

    self.formatDiagnosticPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(12, 49, frame.size.width - 24, 24) pullsDown:NO];
    self.formatDiagnosticPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.dockView addSubview:self.formatDiagnosticPopup];

    self.formatLabel = [NSTextField labelWithString:@"Format: unavailable"];
    self.formatLabel.frame = NSMakeRect(12, 29, frame.size.width - 24, 18);
    self.formatLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.dockView addSubview:self.formatLabel];

    self.statusLabel = [NSTextField labelWithString:[NSString stringWithUTF8String:followStatusText().c_str()]];
    self.statusLabel.frame = NSMakeRect(12, 9, frame.size.width - 24, 18);
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.dockView addSubview:self.statusLabel];
    [self refreshSourceMenu];
    [self refreshDeviceMenu];
    [self refreshFormatDiagnosticMenu];
    [self updateCaptureFormatLabel];
    [self updateSourceControls];
  }

  if (!g_useIPhoneSource && !self.previewLayer && self.session) {
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.previewLayer.frame = self.previewView.bounds;
    self.previewLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [self.previewView.layer addSublayer:self.previewLayer];
  }
}

- (NSURL *)remotePreviewSnapshotURL {
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    return nil;
  }
  NSString *urlString = [NSString stringWithFormat:@"http://%s:%s/preview.jpg?token=%@",
                                                   g_iPhoneHost.c_str(),
                                                   g_iPhoneHttpPort.c_str(),
                                                   [NSString stringWithUTF8String:g_iPhoneToken.c_str()]];
  return [NSURL URLWithString:urlString];
}

- (NSString *)answerForWebRTCOffer:(NSString *)offer error:(NSError **)error {
  NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"iphone-preview-offer-%@.sdp", NSUUID.UUID.UUIDString]];
  if (![offer writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
    return nil;
  }
  @try {
    NSArray<NSString *> *arguments = @[
      @"--token",
      [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
      @"--offer-file",
      tempPath
    ];
    NSString *output = [self runVideoSyncCommand:@"webrtc-answer" extraArguments:arguments error:error];
    return [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  } @finally {
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:nil];
  }
}

- (void)startBinaryRemotePreviewFallback {
  if (!g_useIPhoneSource || self.showingPlayback || self.remotePreviewTask) {
    return;
  }
  self.remotePreviewView.hidden = NO;
  self.webRTCPreviewView.hidden = YES;
  [self startRemotePreviewStream];
}

- (void)sendWebRTCIceCandidateToIPhone:(LKRTCIceCandidate *)candidate {
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty() || candidate.sdp.length == 0) {
    return;
  }
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObjects:
    @"--token", [NSString stringWithUTF8String:g_iPhoneToken.c_str()],
    @"--candidate", candidate.sdp,
    @"--mline", [NSString stringWithFormat:@"%d", candidate.sdpMLineIndex],
    nil];
  if (candidate.sdpMid.length > 0) {
    [arguments addObjectsFromArray:@[ @"--mid", candidate.sdpMid ]];
  }
  [self runVideoSyncCommandAsync:@"webrtc-candidate" extraArguments:arguments completion:^(NSString *output, NSError *error) {
    (void)output;
    if (error && g_useIPhoneSource && !self.showingPlayback && !self.recordingVisualState) {
      [self setStatus:@"Preview: WebRTC ICE candidate failed"];
    }
  }];
}

- (NSString *)webRTCAnswerSDPByRemovingInlineCandidates:(NSString *)answerSDP
                                             candidates:(NSArray<LKRTCIceCandidate *> **)candidates {
  NSMutableArray<NSString *> *keptLines = [NSMutableArray array];
  NSMutableArray<LKRTCIceCandidate *> *parsedCandidates = [NSMutableArray array];
  NSString *currentMid = nil;
  int currentMLineIndex = -1;

  for (NSString *rawLine in [answerSDP componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r"]];
    if (line.length == 0) {
      continue;
    }
    if ([line hasPrefix:@"m="]) {
      currentMLineIndex += 1;
    }
    if ([line hasPrefix:@"a=mid:"]) {
      currentMid = [line substringFromIndex:@"a=mid:".length];
    }
    if ([line hasPrefix:@"a=candidate:"]) {
      NSString *candidateSDP = [line substringFromIndex:@"a=".length];
      LKRTCIceCandidate *candidate = [[LKRTCIceCandidate alloc] initWithSdp:candidateSDP
                                                               sdpMLineIndex:MAX(currentMLineIndex, 0)
                                                                      sdpMid:currentMid];
      [parsedCandidates addObject:candidate];
      continue;
    }
    if ([line hasPrefix:@"a=end-of-candidates"]) {
      continue;
    }
    [keptLines addObject:line];
  }

  if (candidates) {
    *candidates = parsedCandidates;
  }
  return [[keptLines componentsJoinedByString:@"\r\n"] stringByAppendingString:@"\r\n"];
}

- (void)addRemoteWebRTCIceCandidates:(NSArray<LKRTCIceCandidate *> *)candidates
                    toPeerConnection:(LKRTCPeerConnection *)peerConnection {
  for (LKRTCIceCandidate *candidate in candidates) {
    [peerConnection addIceCandidate:candidate completionHandler:^(NSError *error) {
      if (error && g_useIPhoneSource && !self.showingPlayback && !self.recordingVisualState) {
        [self setStatus:@"Preview: WebRTC remote ICE failed"];
      }
    }];
  }
}

- (void)startWebRTCPreviewIfNeeded {
  if (!g_useIPhoneSource || self.showingPlayback || self.webRTCPeerConnection || self.webRTCPreviewStarting || self.webRTCPreviewFailed) {
    return;
  }
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    [self startBinaryRemotePreviewFallback];
    return;
  }

  self.webRTCPreviewStarting = YES;
  self.webRTCPreviewActive = NO;
  self.webRTCPreviewFallbackReason = nil;
  self.webRTCLocalIceCandidates = [NSMutableArray array];
  self.webRTCIceGatheringSemaphore = dispatch_semaphore_create(0);
  self.webRTCPreviewView.hidden = NO;
  self.remotePreviewView.hidden = YES;
  [self setStatus:@"Preview: WebRTC connecting"];

  if (!self.webRTCPeerConnectionFactory) {
    self.webRTCPeerConnectionFactory = [[LKRTCPeerConnectionFactory alloc] init];
  }

  LKRTCConfiguration *configuration = [[LKRTCConfiguration alloc] init];
  configuration.sdpSemantics = LKRTCSdpSemanticsUnifiedPlan;
  configuration.iceServers = @[];
  LKRTCMediaConstraints *constraints = [[LKRTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil];
  LKRTCPeerConnection *peerConnection = [self.webRTCPeerConnectionFactory peerConnectionWithConfiguration:configuration
                                                                                              constraints:constraints
                                                                                                 delegate:self];
  if (!peerConnection) {
    self.webRTCPreviewStarting = NO;
    self.webRTCPreviewFailed = YES;
    self.webRTCPreviewFallbackReason = @"WebRTC unavailable";
    [self setStatus:@"Preview: WebRTC unavailable; using stream"];
    [self startBinaryRemotePreviewFallback];
    return;
  }
  self.webRTCPeerConnection = peerConnection;

  LKRTCRtpTransceiverInit *transceiverInit = [[LKRTCRtpTransceiverInit alloc] init];
  transceiverInit.direction = LKRTCRtpTransceiverDirectionRecvOnly;
  [peerConnection addTransceiverOfType:LKRTCRtpMediaTypeVideo init:transceiverInit];

  __weak KlongVideoRecorder *weakSelf = self;
  [peerConnection offerForConstraints:constraints completionHandler:^(LKRTCSessionDescription *offer, NSError *offerError) {
    KlongVideoRecorder *strongSelf = weakSelf;
    if (!strongSelf || !offer || offerError) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [strongSelf stopWebRTCPreview];
        strongSelf.webRTCPreviewFailed = YES;
        strongSelf.webRTCPreviewFallbackReason = @"WebRTC offer failed";
        [strongSelf setStatus:@"Preview: WebRTC offer failed; using stream"];
        [strongSelf startBinaryRemotePreviewFallback];
      });
      return;
    }
    __weak LKRTCPeerConnection *weakPeerConnection = peerConnection;
    [peerConnection setLocalDescription:offer completionHandler:^(NSError *localError) {
      LKRTCPeerConnection *strongPeerConnection = weakPeerConnection;
      if (!strongPeerConnection) {
        return;
      }
      if (localError) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [strongSelf stopWebRTCPreview];
          strongSelf.webRTCPreviewFailed = YES;
          strongSelf.webRTCPreviewFallbackReason = @"WebRTC local setup failed";
          [strongSelf setStatus:@"Preview: WebRTC local setup failed; using stream"];
          [strongSelf startBinaryRemotePreviewFallback];
        });
        return;
      }

      dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        dispatch_semaphore_wait(strongSelf.webRTCIceGatheringSemaphore, dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(3.0 * NSEC_PER_SEC)));
        NSString *localSDP = strongPeerConnection.localDescription.sdp ?: offer.sdp;
        const NSUInteger localCandidateCount = strongSelf.webRTCLocalIceCandidates.count;
        dispatch_async(dispatch_get_main_queue(), ^{
          if (g_useIPhoneSource && !strongSelf.showingPlayback && !strongSelf.recordingVisualState) {
            [strongSelf setStatus:[NSString stringWithFormat:@"Preview: WebRTC signaling (%lu local ICE)",
                                                             static_cast<unsigned long>(localCandidateCount)]];
          }
        });
        NSError *answerError = nil;
        NSString *answerSDP = [strongSelf answerForWebRTCOffer:localSDP error:&answerError];
        if (answerError || answerSDP.length == 0) {
          dispatch_async(dispatch_get_main_queue(), ^{
            [strongSelf stopWebRTCPreview];
            strongSelf.webRTCPreviewFailed = YES;
            strongSelf.webRTCPreviewFallbackReason = @"WebRTC signaling failed";
            [strongSelf setStatus:@"Preview: WebRTC signaling failed; using stream"];
            [strongSelf startBinaryRemotePreviewFallback];
          });
          return;
        }
        NSArray<LKRTCIceCandidate *> *remoteCandidates = @[];
        NSString *answerWithoutCandidates = [strongSelf webRTCAnswerSDPByRemovingInlineCandidates:answerSDP candidates:&remoteCandidates];
        LKRTCSessionDescription *answer = [[LKRTCSessionDescription alloc] initWithType:LKRTCSdpTypeAnswer sdp:answerWithoutCandidates];
        [strongPeerConnection setRemoteDescription:answer completionHandler:^(NSError *remoteError) {
          dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.webRTCPreviewStarting = NO;
            if (remoteError) {
              [strongSelf stopWebRTCPreview];
              strongSelf.webRTCPreviewFailed = YES;
              strongSelf.webRTCPreviewFallbackReason = @"WebRTC answer failed";
              [strongSelf setStatus:@"Preview: WebRTC answer failed; using stream"];
              [strongSelf startBinaryRemotePreviewFallback];
              return;
            }
            strongSelf.webRTCPreviewActive = YES;
            strongSelf.webRTCPreviewFailed = NO;
            strongSelf.webRTCPreviewFallbackReason = nil;
            strongSelf.webRTCPreviewView.hidden = NO;
            strongSelf.remotePreviewView.hidden = YES;
            [strongSelf stopRemotePreviewStreamOnly];
            [strongSelf setStatus:@"Preview: WebRTC"];
            [strongSelf addRemoteWebRTCIceCandidates:remoteCandidates toPeerConnection:strongPeerConnection];
            NSArray<LKRTCIceCandidate *> *candidates = [strongSelf.webRTCLocalIceCandidates copy];
            for (LKRTCIceCandidate *candidate in candidates) {
              [strongSelf sendWebRTCIceCandidateToIPhone:candidate];
            }
          });
        }];
      });
    }];
  }];
}

- (void)stopWebRTCPreview {
  self.webRTCPreviewStarting = NO;
  self.webRTCPreviewActive = NO;
  if (self.webRTCVideoTrack && self.webRTCPreviewView) {
    [self.webRTCVideoTrack removeRenderer:self.webRTCPreviewView];
  }
  self.webRTCVideoTrack = nil;
  self.webRTCLocalIceCandidates = nil;
  [self.webRTCPeerConnection close];
  self.webRTCPeerConnection = nil;
  self.webRTCIceGatheringSemaphore = nil;
  self.webRTCPreviewView.hidden = YES;
  if (!g_iPhoneHost.empty() && !g_iPhoneToken.empty()) {
    [self runVideoSyncCommandAsync:@"stop-webrtc"
                    extraArguments:@[ @"--token", [NSString stringWithUTF8String:g_iPhoneToken.c_str()] ]
                        completion:^(NSString *output, NSError *error) {
      (void)output;
      (void)error;
    }];
  }
}

- (NSURL *)remotePreviewStreamURL {
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    return nil;
  }
  NSString *urlString = [NSString stringWithFormat:@"http://%s:%s/preview.bin?token=%@",
                                                   g_iPhoneHost.c_str(),
                                                   g_iPhoneHttpPort.c_str(),
                                                   [NSString stringWithUTF8String:g_iPhoneToken.c_str()]];
  return [NSURL URLWithString:urlString];
}

- (void)stopRemotePreviewStreamOnly {
  self.remotePreviewStreaming = NO;
  [self.remotePreviewTask cancel];
  self.remotePreviewTask = nil;
  [self.remotePreviewSession invalidateAndCancel];
  self.remotePreviewSession = nil;
  self.remotePreviewBuffer = nil;
  self.remotePreviewDecoding = NO;
  self.remotePreviewUsingSnapshotFallback = NO;
  [self refreshFormatDiagnosticMenu];
}

- (void)startRemotePreviewStream {
  if (self.remotePreviewTask || !g_useIPhoneSource) {
    return;
  }
  NSURL *url = [self remotePreviewStreamURL];
  if (!url) {
    return;
  }
  if (!self.remotePreviewQueue) {
    self.remotePreviewQueue = [[NSOperationQueue alloc] init];
    self.remotePreviewQueue.maxConcurrentOperationCount = 1;
    self.remotePreviewQueue.name = @"KlongVideoRecorderRemotePreview";
  }
  self.remotePreviewBuffer = [NSMutableData data];
  self.remotePreviewFramesReceived = 0;
  self.remotePreviewFramesDisplayed = 0;
  self.remotePreviewFramesDropped = 0;
  self.remotePreviewFramesDisplayedAtLastUpdate = 0;
  self.remotePreviewLastDisplayTime = 0.0;
  self.remotePreviewLastStatusTime = CACurrentMediaTime();
  self.remotePreviewUsingSnapshotFallback = NO;
  self.remotePreviewStreaming = YES;
  NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
  configuration.timeoutIntervalForRequest = 10.0;
  configuration.timeoutIntervalForResource = 0.0;
  self.remotePreviewSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:self.remotePreviewQueue];
  self.remotePreviewTask = [self.remotePreviewSession dataTaskWithURL:url];
  [self.remotePreviewTask resume];
  [self setStatus:@"Preview: binary stream connecting"];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (self.remotePreviewStreaming && self.remotePreviewFramesDisplayed == 0 && g_useIPhoneSource && !self.showingPlayback) {
      self.remotePreviewUsingSnapshotFallback = YES;
      [self setStatus:@"Preview: snapshot fallback"];
      [self refreshRemotePreviewSnapshotFallback];
    }
  });
}

- (void)refreshRemotePreviewSnapshotFallback {
  if (!self.remotePreviewUsingSnapshotFallback || !g_useIPhoneSource || self.showingPlayback) {
    return;
  }
  NSURL *url = [self remotePreviewSnapshotURL];
  if (!url) {
    return;
  }
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    NSImage *image = nil;
    if (!error && data.length > 0) {
      image = [[NSImage alloc] initWithData:data];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (image && self.remotePreviewUsingSnapshotFallback && g_useIPhoneSource && !self.showingPlayback) {
        self.remotePreviewView.image = image;
      }
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self refreshRemotePreviewSnapshotFallback];
      });
    });
  }];
  [task resume];
}

- (void)startRemotePreview {
  if (!g_useIPhoneSource) {
    return;
  }
  [self persistIPhoneSettings];
  if (!self.remotePreviewTask && !self.webRTCPeerConnection && !self.webRTCPreviewStarting) {
    self.webRTCPreviewFailed = NO;
    self.webRTCPreviewFallbackReason = nil;
  }
  self.previewLayer.hidden = YES;
  if (self.iPhonePreviewProfileConfiguring) {
    return;
  }
  if (!g_iPhoneHost.empty() && !g_iPhoneToken.empty()) {
    self.iPhonePreviewProfileConfiguring = YES;
    [self setStatus:@"Configuring iPhone preview"];
    [self runVideoSyncCommandAsync:@"configure" extraArguments:[self iPhoneConfigureArguments] completion:^(NSString *output, NSError *error) {
      self.iPhonePreviewProfileConfiguring = NO;
      if (error) {
        [self setStatus:@"iPhone preview configure failed"];
        return;
      }
      NSString *message = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (message.length > 0 && !self.webRTCPeerConnection && !self.webRTCPreviewStarting) {
        [self setStatus:message];
      }
      [self startWebRTCPreviewIfNeeded];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (g_useIPhoneSource && !self.showingPlayback && self.webRTCPreviewFailed && !self.webRTCPeerConnection && !self.webRTCPreviewStarting && !self.remotePreviewTask) {
          [self startBinaryRemotePreviewFallback];
        }
      });
    }];
    return;
  }
  [self startWebRTCPreviewIfNeeded];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (g_useIPhoneSource && !self.showingPlayback && self.webRTCPreviewFailed && !self.webRTCPeerConnection && !self.webRTCPreviewStarting && !self.remotePreviewTask) {
      [self startBinaryRemotePreviewFallback];
    }
  });
}

- (void)stopRemotePreview {
  [self stopWebRTCPreview];
  [self stopRemotePreviewStreamOnly];
  self.webRTCPreviewFailed = NO;
  self.webRTCPreviewFallbackReason = nil;
  self.remotePreviewView.hidden = YES;
  [self refreshFormatDiagnosticMenu];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
  (void)session;
  (void)dataTask;
  if (!self.remotePreviewBuffer) {
    self.remotePreviewBuffer = [NSMutableData data];
  }
  [self.remotePreviewBuffer appendData:data];
  [self processRemotePreviewBuffer];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  (void)session;
  (void)task;
  dispatch_async(dispatch_get_main_queue(), ^{
    self.remotePreviewTask = nil;
    self.remotePreviewSession = nil;
    if (self.remotePreviewStreaming && g_useIPhoneSource && !self.showingPlayback) {
      [self setStatus:error ? @"Preview: reconnecting" : @"Preview: reconnecting"];
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.remotePreviewStreaming && !self.remotePreviewTask && g_useIPhoneSource && !self.showingPlayback) {
          [self startRemotePreviewStream];
        }
      });
    }
  });
}

- (void)processRemotePreviewBuffer {
  while (self.remotePreviewBuffer.length >= 4) {
    const uint8_t *bytes = static_cast<const uint8_t *>(self.remotePreviewBuffer.bytes);
    const uint32_t frameLength = (static_cast<uint32_t>(bytes[0]) << 24) |
                                 (static_cast<uint32_t>(bytes[1]) << 16) |
                                 (static_cast<uint32_t>(bytes[2]) << 8) |
                                 static_cast<uint32_t>(bytes[3]);
    if (frameLength == 0 || frameLength > 2 * 1024 * 1024) {
      [self.remotePreviewBuffer setLength:0];
      return;
    }
    if (self.remotePreviewBuffer.length < 4 + frameLength) {
      return;
    }
    NSData *frameData = [self.remotePreviewBuffer subdataWithRange:NSMakeRange(4, frameLength)];
    [self.remotePreviewBuffer replaceBytesInRange:NSMakeRange(0, 4 + frameLength) withBytes:nullptr length:0];
    [self handleRemotePreviewFrame:frameData];
  }
}

- (void)handleRemotePreviewFrame:(NSData *)frameData {
  self.remotePreviewFramesReceived += 1;
  const CFTimeInterval now = CACurrentMediaTime();
  const double minimumInterval = g_activeTransportRecording ? (1.0 / 6.0) : (1.0 / 12.0);
  if (now - self.remotePreviewLastDisplayTime < minimumInterval || self.remotePreviewDecoding) {
    self.remotePreviewFramesDropped += 1;
    return;
  }
  self.remotePreviewDecoding = YES;
  self.remotePreviewLastDisplayTime = now;
  NSData *dataCopy = [frameData copy];
  __weak KlongVideoRecorder *weakSelf = self;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    CGImageRef cgImage = nullptr;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)dataCopy, nullptr);
    if (source) {
      cgImage = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
      CFRelease(source);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      KlongVideoRecorder *strongSelf = weakSelf;
      if (!strongSelf) {
        if (cgImage) {
          CGImageRelease(cgImage);
        }
        return;
      }
      strongSelf.remotePreviewDecoding = NO;
      if (cgImage && g_useIPhoneSource && !strongSelf.showingPlayback) {
        NSImage *image = [[NSImage alloc] initWithCGImage:cgImage size:NSZeroSize];
        strongSelf.remotePreviewView.image = image;
        strongSelf.remotePreviewFramesDisplayed += 1;
        strongSelf.remotePreviewUsingSnapshotFallback = NO;
        [strongSelf updateRemotePreviewStatusIfNeeded];
      } else {
        strongSelf.remotePreviewFramesDropped += 1;
      }
      if (cgImage) {
        CGImageRelease(cgImage);
      }
    });
  });
}

- (void)updateRemotePreviewStatusIfNeeded {
  const CFTimeInterval now = CACurrentMediaTime();
  if (now - self.remotePreviewLastStatusTime < 1.0 || self.recordingVisualState) {
    return;
  }
  const NSUInteger displayedDelta = self.remotePreviewFramesDisplayed - self.remotePreviewFramesDisplayedAtLastUpdate;
  self.remotePreviewFramesDisplayedAtLastUpdate = self.remotePreviewFramesDisplayed;
  self.remotePreviewLastStatusTime = now;
  NSString *safe = g_activeTransportRecording ? @" safe" : @"";
  NSString *transport = self.webRTCPreviewFallbackReason.length > 0 ? [NSString stringWithFormat:@"stream fallback (%@)", self.webRTCPreviewFallbackReason] : @"stream";
  [self setStatus:[NSString stringWithFormat:@"Preview: %@%@, %lu fps, dropped %lu",
                                             transport,
                                             safe,
                                             static_cast<unsigned long>(displayedDelta),
                                             static_cast<unsigned long>(self.remotePreviewFramesDropped)]];
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didChangeSignalingState:(LKRTCSignalingState)stateChanged {
  (void)peerConnection;
  (void)stateChanged;
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didAddStream:(LKRTCMediaStream *)stream {
  (void)peerConnection;
  (void)stream;
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didRemoveStream:(LKRTCMediaStream *)stream {
  (void)peerConnection;
  (void)stream;
}

- (void)peerConnectionShouldNegotiate:(LKRTCPeerConnection *)peerConnection {
  (void)peerConnection;
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didChangeIceConnectionState:(LKRTCIceConnectionState)newState {
  (void)peerConnection;
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!g_useIPhoneSource || self.recordingVisualState) {
      return;
    }
    switch (newState) {
      case LKRTCIceConnectionStateConnected:
      case LKRTCIceConnectionStateCompleted:
        [self setStatus:@"Preview: WebRTC connected"];
        break;
      case LKRTCIceConnectionStateFailed:
      case LKRTCIceConnectionStateDisconnected:
        [self setStatus:@"Preview: WebRTC disconnected"];
        break;
      default:
        break;
    }
  });
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didChangeIceGatheringState:(LKRTCIceGatheringState)newState {
  (void)peerConnection;
  if (newState == LKRTCIceGatheringStateComplete && self.webRTCIceGatheringSemaphore) {
    dispatch_semaphore_signal(self.webRTCIceGatheringSemaphore);
  }
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didGenerateIceCandidate:(LKRTCIceCandidate *)candidate {
  (void)peerConnection;
  @synchronized(self) {
    if (!self.webRTCLocalIceCandidates) {
      self.webRTCLocalIceCandidates = [NSMutableArray array];
    }
    [self.webRTCLocalIceCandidates addObject:candidate];
  }
  if (self.webRTCPreviewActive) {
    [self sendWebRTCIceCandidateToIPhone:candidate];
  }
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<LKRTCIceCandidate *> *)candidates {
  (void)peerConnection;
  (void)candidates;
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didOpenDataChannel:(LKRTCDataChannel *)dataChannel {
  (void)peerConnection;
  (void)dataChannel;
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didAddReceiver:(LKRTCRtpReceiver *)rtpReceiver streams:(NSArray<LKRTCMediaStream *> *)mediaStreams {
  (void)peerConnection;
  (void)mediaStreams;
  LKRTCMediaStreamTrack *track = rtpReceiver.track;
  if (![track isKindOfClass:LKRTCVideoTrack.class]) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    if (self.webRTCVideoTrack && self.webRTCPreviewView) {
      [self.webRTCVideoTrack removeRenderer:self.webRTCPreviewView];
    }
    self.webRTCVideoTrack = (LKRTCVideoTrack *)track;
    [self.webRTCVideoTrack addRenderer:self.webRTCPreviewView];
    self.webRTCPreviewView.hidden = NO;
    self.remotePreviewView.hidden = YES;
    self.webRTCPreviewActive = YES;
    [self setStatus:@"Preview: WebRTC video"];
  });
}

- (void)peerConnection:(LKRTCPeerConnection *)peerConnection didRemoveReceiver:(LKRTCRtpReceiver *)rtpReceiver {
  (void)peerConnection;
  (void)rtpReceiver;
}

- (void)showLivePreview {
  self.showingPlayback = NO;
  [self.player pause];
  self.playerLayer.hidden = YES;
  if (g_useIPhoneSource) {
    self.previewLayer.hidden = YES;
    [self startRemotePreview];
  } else {
    [self stopRemotePreview];
    self.previewLayer.hidden = NO;
  }
}

- (void)updatePlaybackWithPath:(const std::string &)path
                     itemStart:(double)itemStart
                   sourceOffset:(double)sourceOffset
                projectPosition:(double)projectPosition {
  [self ensureDockView];
  NSString *playbackPath = [NSString stringWithUTF8String:path.c_str()];
  const BOOL switchedSource = !self.player || ![self.activePlaybackPath isEqualToString:playbackPath];
  const BOOL startingPlayback = !self.showingPlayback;
  if (switchedSource) {
    self.activePlaybackPath = playbackPath;
    self.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:playbackPath]];
    self.player.automaticallyWaitsToMinimizeStalling = NO;
    if (!self.playerLayer) {
      self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
      self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
      self.playerLayer.frame = self.previewView.bounds;
      self.playerLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
      [self.previewView.layer addSublayer:self.playerLayer];
    } else {
      self.playerLayer.player = self.player;
    }
    self.player.muted = YES;
    self.player.volume = 0.0f;
  }

  self.showingPlayback = YES;
  [self stopRemotePreview];
  self.previewLayer.hidden = YES;
  self.playerLayer.hidden = NO;

  const double sourceTime = projectPosition - itemStart + sourceOffset;
  CMTime targetTime = CMTimeMakeWithSeconds(sourceTime > 0.0 ? sourceTime : 0.0, 600);
  const double currentTime = CMTimeGetSeconds(self.player.currentTime);
  const CFTimeInterval now = CACurrentMediaTime();
  const bool forceSeek = switchedSource || startingPlayback || !std::isfinite(currentTime);
  const bool drifted = std::isfinite(currentTime) && std::fabs(currentTime - sourceTime) > 0.50;
  if (forceSeek || (drifted && now - self.lastPlaybackSeekHostTime > 1.0)) {
    const CMTime tolerance = forceSeek ? kCMTimeZero : CMTimeMakeWithSeconds(0.05, 600);
    [self.player seekToTime:targetTime toleranceBefore:tolerance toleranceAfter:tolerance];
    self.lastPlaybackSeekHostTime = now;
  }
  if (self.player.rate != 1.0f) {
    [self.player play];
  }
  [self setStatus:@"Playback"];
}

- (void)stopPlaybackAndShowLive {
  if (!self.showingPlayback) {
    return;
  }
  [self showLivePreview];
  [self setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
}

- (void)showDockedPreview {
  if (!DockWindowAddEx || !self.dockView) {
    return;
  }
  [self hideFloatingPreview];
  HWND hwnd = (__bridge HWND)self.dockView;
  if (!self.docked) {
    DockWindowAddEx(hwnd, "Video Recorder", kDockIdent, true);
    self.docked = YES;
  }
  if (DockWindowActivate) {
    DockWindowActivate(hwnd);
  }
  if (DockWindowRefreshForHWND) {
    DockWindowRefreshForHWND(hwnd);
  }
}

- (void)showFloatingPreview {
  if (!self.dockView) {
    return;
  }
  [self hideDockedPreview];
  if (!self.floatingPreviewWindow) {
    self.floatingPreviewWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(120, 120, 720, 540)
                                                             styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                               backing:NSBackingStoreBuffered
                                                                 defer:NO];
    self.floatingPreviewWindow.title = @"Video Recorder Preview";
    self.floatingPreviewWindow.releasedWhenClosed = NO;
  }
  self.dockView.frame = self.floatingPreviewWindow.contentView.bounds;
  self.dockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  self.floatingPreviewWindow.contentView = self.dockView;
  [self.floatingPreviewWindow makeKeyAndOrderFront:nil];
}

- (void)hideFloatingPreview {
  if (!self.floatingPreviewWindow) {
    return;
  }
  [self.floatingPreviewWindow orderOut:nil];
  if (self.floatingPreviewWindow.contentView == self.dockView) {
    self.floatingPreviewWindow.contentView = [[NSView alloc] initWithFrame:self.floatingPreviewWindow.contentView.bounds];
  }
}

- (void)hideDockedPreview {
  if (DockWindowRemove && self.docked && self.dockView) {
    DockWindowRemove((__bridge HWND)self.dockView);
  }
  self.docked = NO;
}

- (void)setStatus:(NSString *)status {
  self.statusLabel.stringValue = status ?: @"Idle";
  [self updateRecordingTextColor];
}

- (void)setRecordingVisualState:(BOOL)recording {
  _recordingVisualState = recording;
  [self updateRecordingTextColor];
}

- (void)updateRecordingTextColor {
  NSColor *color = _recordingVisualState ? NSColor.systemRedColor : NSColor.labelColor;
  self.statusLabel.textColor = color;
  self.formatLabel.textColor = color;
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
      fromConnections:(NSArray<AVCaptureConnection *> *)connections {
  (void)captureOutput;
  (void)fileURL;
  (void)connections;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self setRecordingVisualState:YES];
    [self updateCaptureFormatLabel];
    if (self.hasAudioInput) {
      NSString *audioName = self.audioDeviceName.length > 0 ? self.audioDeviceName : @"camera audio";
      [self setStatus:[NSString stringWithFormat:@"Recording video + %@", audioName]];
    } else {
      [self setStatus:@"Recording video only"];
    }
    if (self.startCompletion) {
      self.startCompletion();
      self.startCompletion = nil;
    }
  });
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray<AVCaptureConnection *> *)connections
                error:(NSError *)error {
  (void)captureOutput;
  (void)connections;
  dispatch_async(dispatch_get_main_queue(), ^{
    [self setRecordingVisualState:NO];
    [self updateCaptureFormatLabel];
    [self setStatus:error ? @"Error" : @"Finalizing"];
    NSString *path = outputFileURL.path ?: self.activeOutputPath;
    if (self.stopCompletion) {
      self.stopCompletion(path, error);
      self.stopCompletion = nil;
    }
  });
}

@end

namespace {

KlongVideoRecorder *recorder() {
  static KlongVideoRecorder *instance = nil;
  if (!instance) {
    instance = [[KlongVideoRecorder alloc] init];
  }
  return instance;
}

void updateFollowStatusText() {
  [recorder() setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
}

void refreshToolbarState() {
  if (!RefreshToolbar2) {
    return;
  }
  if (g_videoEnabledCommand != 0) {
    RefreshToolbar2(0, g_videoEnabledCommand);
  }
  if (g_toggleFollowCommand != 0) {
    RefreshToolbar2(0, g_toggleFollowCommand);
  }
}

void setVideoEnabled(bool enabled) {
  if (g_videoEnabled == enabled) {
    return;
  }

  g_videoEnabled = enabled;
  if (enabled) {
    g_followEnabled = true;
    ensureVideoTrackReady(currentProject(), false);
    [recorder() showPreview];
  } else {
    g_followEnabled = false;
    if (recorder().isRecording) {
      stopTransportRecording();
    }
    [recorder() stopPlaybackAndShowLive];
    [recorder() hideDockedPreview];
    [recorder() hideFloatingPreview];
  }

  updateFollowStatusText();
  refreshToolbarState();
}

bool isRecordingState(int playState) {
  return (playState & kRecordBit) != 0;
}

void startTransportRecording(ReaProject *project) {
  if (g_activeTransportRecording || recorder().isRecording) {
    return;
  }

  g_recordProject = project;
  ensureVideoTrackReady(project, false);
  g_recordStartPosition = GetCursorPositionEx ? GetCursorPositionEx(project) : 0.0;
  if (g_recordStartPosition < 0.0 && GetPlayPositionEx) {
    g_recordStartPosition = GetPlayPositionEx(project);
  }

  const std::string outputPath = captureOutputPath(project);
  NSError *error = nil;
  if (![recorder() startRecordingToPath:outputPath
                        startCompletion:^{
                          if (g_recordProject && GetPlayPositionEx) {
                            g_recordStartPosition = GetPlayPositionEx(g_recordProject);
                          }
                        }
                                   error:&error]) {
    showError(error.localizedDescription.UTF8String ?: "Unable to start video recording.");
    return;
  }
  g_activeTransportRecording = true;
}

void stopTransportRecording() {
  if (!g_activeTransportRecording && !recorder().isRecording) {
    return;
  }

  double insertPosition = g_recordStartPosition;
  if (insertPosition < 0.0) {
    insertPosition = 0.0;
  }
  [recorder() stopRecordingWithCompletion:^(NSString *path, NSError *error) {
    if (error) {
      showError(std::string("Video recording failed:\n") + (error.localizedDescription.UTF8String ?: "Unknown AVFoundation error."));
      g_activeTransportRecording = false;
      return;
    }
    g_pendingInsertPath = path.UTF8String ?: "";
    g_pendingInsertPosition = insertPosition;
    g_pendingInsert = !g_pendingInsertPath.empty();
    g_activeTransportRecording = false;
  }];
}

void processPendingInsert() {
  if (!g_pendingInsert) {
    return;
  }
  const std::string path = g_pendingInsertPath;
  const double position = g_pendingInsertPosition;
  const bool fromIPhone = g_useIPhoneSource;
  g_pendingInsert = false;
  g_pendingInsertPath.clear();

  std::string error;
  if (insertRecordedMedia(path, position, fromIPhone, error)) {
    const char *status = g_lastAlignmentStatus.empty() ? "Recorded to Video Recorder track" : g_lastAlignmentStatus.c_str();
    [recorder() setStatus:[NSString stringWithUTF8String:status]];
  } else {
    [recorder() setStatus:@"Import error"];
    showError(error);
  }
}

void processPendingAlignment() {
  if (!g_pendingAlignment) {
    return;
  }

  const std::time_t now = std::time(nullptr);
  if (now < g_nextAlignmentAttemptTime) {
    return;
  }

  if (ValidatePtr2 &&
      (!ValidatePtr2(g_pendingAlignmentProject, g_pendingAlignmentTrack, "MediaTrack*") ||
       !ValidatePtr2(g_pendingAlignmentProject, g_pendingAlignmentItem, "MediaItem*"))) {
    clearPendingAlignment();
    return;
  }

  ++g_pendingAlignmentAttempts;
  AlignmentResult alignment =
      alignVideoItemToReference(g_pendingAlignmentProject, g_pendingAlignmentTrack, g_pendingAlignmentItem);
  if (alignment.aligned) {
    clearPendingAlignment();
    g_lastAlignmentStatus = alignmentStatusText(alignment);
    [recorder() setStatus:[NSString stringWithUTF8String:g_lastAlignmentStatus.c_str()]];
    return;
  }

  if (g_pendingAlignmentAttempts >= kAlignmentRetryLimit) {
    clearPendingAlignment();
    g_lastAlignmentStatus = alignmentStatusText(alignment);
    [recorder() setStatus:[NSString stringWithUTF8String:g_lastAlignmentStatus.c_str()]];
    return;
  }

  g_nextAlignmentAttemptTime = now + 1;
  [recorder() setStatus:@"Recorded to Video Recorder track; aligning audio"];
}

MediaItem *selectedOrLatestVideoTrackItem(MediaTrack *track) {
  if (!track || !CountTrackMediaItems || !GetTrackMediaItem) {
    return nullptr;
  }

  MediaItem *latestItem = nullptr;
  double latestPosition = -std::numeric_limits<double>::infinity();
  const int itemCount = CountTrackMediaItems(track);
  for (int i = 0; i < itemCount; ++i) {
    MediaItem *item = GetTrackMediaItem(track, i);
    if (!item) {
      continue;
    }
    if (IsMediaItemSelected && IsMediaItemSelected(item)) {
      return item;
    }
    if (GetMediaItemInfo_Value) {
      const double position = GetMediaItemInfo_Value(item, "D_POSITION");
      if (position >= latestPosition) {
        latestPosition = position;
        latestItem = item;
      }
    } else if (!latestItem) {
      latestItem = item;
    }
  }
  return latestItem;
}

bool itemUsesMovieFile(MediaItem *item) {
  if (!item || !GetActiveTake || !GetMediaItemTake_Source || !GetMediaSourceFileName) {
    return false;
  }
  MediaItem_Take *take = GetActiveTake(item);
  PCM_source *source = take ? GetMediaItemTake_Source(take) : nullptr;
  if (!source) {
    return false;
  }
  char filePath[4096] = {};
  GetMediaSourceFileName(source, filePath, sizeof(filePath));
  return hasPathExtension(filePath, ".mov") || hasPathExtension(filePath, ".mp4") || hasPathExtension(filePath, ".m4v");
}

MediaItem *selectedMovieItem(ReaProject *project) {
  if (!project || !CountSelectedMediaItems || !GetSelectedMediaItem) {
    return nullptr;
  }
  const int selectedCount = CountSelectedMediaItems(project);
  for (int i = 0; i < selectedCount; ++i) {
    MediaItem *item = GetSelectedMediaItem(project, i);
    if (itemUsesMovieFile(item)) {
      return item;
    }
  }
  return nullptr;
}

AlignmentWindow currentTimeSelection(ReaProject *project) {
  AlignmentWindow window;
  if (!project || !GetSet_LoopTimeRange2) {
    return window;
  }
  double start = 0.0;
  double end = 0.0;
  GetSet_LoopTimeRange2(project, false, false, &start, &end, false);
  if (std::isfinite(start) && std::isfinite(end) && end > start) {
    window.active = true;
    window.start = start;
    window.end = end;
  }
  return window;
}

void alignSelectedVideoItem() {
  ReaProject *project = currentProject();
  MediaTrack *track = project ? findVideoTrack(project) : nullptr;
  MediaItem *item = selectedMovieItem(project);
  if (!item) {
    item = selectedOrLatestVideoTrackItem(track);
  }
  MediaTrack *itemTrack = item && GetMediaItemTrack ? GetMediaItemTrack(item) : track;
  if (!project || !item || !itemTrack) {
    const char *message = "Select a movie item, then run the align action again.";
    [recorder() setStatus:[NSString stringWithUTF8String:message]];
    showError(message);
    return;
  }

  clearPendingAlignment();
  [recorder() setStatus:@"Aligning selected video item"];
  AlignmentWindow timeSelection = currentTimeSelection(project);
  AlignmentResult alignment = alignVideoItemToReference(project, itemTrack ? itemTrack : track, item, nullptr, timeSelection);
  g_lastAlignmentStatus = alignmentStatusText(alignment);
  if (timeSelection.active) {
    g_lastAlignmentStatus += " using time selection";
  }
  [recorder() setStatus:[NSString stringWithUTF8String:g_lastAlignmentStatus.c_str()]];
  ShowMessageBox(g_lastAlignmentStatus.c_str(), "Video Recorder Alignment", 0);
}

void timerPoll() {
  @autoreleasepool {
    processPendingInsert();
    processPendingAlignment();

    if (!g_videoEnabled) {
      g_previousPlayState = 0;
      return;
    }

    ReaProject *project = currentProject();
    if (!project || !GetPlayStateEx) {
      return;
    }

    const int playState = GetPlayStateEx(project);
    const bool recording = isRecordingState(playState);
    const bool wasRecording = isRecordingState(g_previousPlayState);
    const bool playing = (playState & 1) != 0;

    if (g_followEnabled) {
      if (recording && !wasRecording) {
        startTransportRecording(project);
      } else if (!recording && wasRecording) {
        stopTransportRecording();
      }
    }

    if (!recording && playing && GetPlayPositionEx) {
      const double position = GetPlayPositionEx(project);
      PlaybackVideo video = findPlaybackVideoAtPosition(project, position);
      if (video.found) {
        [recorder() updatePlaybackWithPath:video.path
                                 itemStart:video.itemStart
                              sourceOffset:video.sourceOffset
                           projectPosition:position];
      } else {
        [recorder() stopPlaybackAndShowLive];
      }
    } else if (!recording) {
      [recorder() stopPlaybackAndShowLive];
    }

    g_previousPlayState = playState;
  }
}

bool hookCommand2(KbdSectionInfo *section, int command, int val, int val2, int relmode, HWND hwnd) {
  (void)section;
  (void)val;
  (void)val2;
  (void)relmode;
  (void)hwnd;

  if (command == g_videoEnabledCommand) {
    setVideoEnabled(!g_videoEnabled);
    return true;
  }

  if (command == g_showPreviewCommand) {
    [recorder() togglePreview];
    return true;
  }

  if (command == g_floatPreviewCommand) {
    [recorder() togglePreviewDockMode];
    return true;
  }

  if (command == g_alignSelectedCommand) {
    alignSelectedVideoItem();
    return true;
  }

  if (command == g_toggleFollowCommand) {
    setFollowEnabled(!g_followEnabled);
    if (!g_followEnabled && recorder().isRecording) {
      stopTransportRecording();
    }
    return true;
  }

  return false;
}

int toggleActionHook(int command) {
  if (command == g_videoEnabledCommand) {
    return g_videoEnabled ? 1 : 0;
  }
  if (command == g_toggleFollowCommand) {
    return g_followEnabled ? 1 : 0;
  }
  if (command == g_floatPreviewCommand) {
    return recorder().floatingPreview ? 1 : 0;
  }
  return -1;
}

void cleanup() {
  if (recorder().isRecording) {
    stopTransportRecording();
  }
}

bool registerActions(reaper_plugin_info_t *rec) {
  custom_action_register_t videoEnabledAction = {
      0,
      "KLONG_VIDEO_RECORDER_ENABLE",
      "Video Recorder: Enable/Disable video features",
      nullptr,
  };
  custom_action_register_t showPreviewAction = {
      0,
      "KLONG_VIDEO_RECORDER_SHOW_PREVIEW",
      "Video Recorder: Show/Hide Preview",
      nullptr,
  };
  custom_action_register_t floatPreviewAction = {
      0,
      "KLONG_VIDEO_RECORDER_FLOAT_PREVIEW",
      "Video Recorder: Float/Dock Preview",
      nullptr,
  };
  custom_action_register_t alignSelectedAction = {
      0,
      "KLONG_VIDEO_RECORDER_ALIGN_SELECTED",
      "Video Recorder: Align Selected Video Item",
      nullptr,
  };
  custom_action_register_t toggleFollowAction = {
      0,
      "KLONG_VIDEO_RECORDER_TOGGLE_FOLLOW",
      "Video Recorder: Enable/Disable Transport Follow",
      nullptr,
  };

  g_videoEnabledCommand = rec->Register("custom_action", &videoEnabledAction);
  g_showPreviewCommand = rec->Register("custom_action", &showPreviewAction);
  g_floatPreviewCommand = rec->Register("custom_action", &floatPreviewAction);
  g_alignSelectedCommand = rec->Register("custom_action", &alignSelectedAction);
  g_toggleFollowCommand = rec->Register("custom_action", &toggleFollowAction);

  return g_videoEnabledCommand != 0 && g_showPreviewCommand != 0 && g_floatPreviewCommand != 0 &&
         g_alignSelectedCommand != 0 && g_toggleFollowCommand != 0 &&
         rec->Register("hookcommand2", reinterpret_cast<void *>(hookCommand2)) &&
         rec->Register("toggleaction", reinterpret_cast<void *>(toggleActionHook)) &&
         rec->Register("timer", reinterpret_cast<void *>(timerPoll)) &&
         rec->Register("atexit", reinterpret_cast<void *>(cleanup));
}

void unregisterCallbacks(reaper_plugin_info_t *rec) {
  rec->Register("-timer", reinterpret_cast<void *>(timerPoll));
  rec->Register("-hookcommand2", reinterpret_cast<void *>(hookCommand2));
  rec->Register("-toggleaction", reinterpret_cast<void *>(toggleActionHook));
  rec->Register("-atexit", reinterpret_cast<void *>(cleanup));
}

void loadSettings() {
  if (!GetExtState) {
    return;
  }
  const char *follow = GetExtState(kExtStateSection, kFollowEnabledKey);
  if (follow && follow[0] != '\0') {
    g_followEnabled = std::string(follow) != "0";
  }
  const char *previewFloating = GetExtState(kExtStateSection, kPreviewFloatingKey);
  if (previewFloating && previewFloating[0] != '\0') {
    g_previewFloating = std::string(previewFloating) != "0";
  }
  const char *selectedDevice = GetExtState(kExtStateSection, kSelectedDeviceKey);
  if (selectedDevice && selectedDevice[0] != '\0') {
    g_selectedDeviceUniqueID = selectedDevice;
  }
  const char *sourceKind = GetExtState(kExtStateSection, kSourceKindKey);
  if (sourceKind && sourceKind[0] != '\0') {
    g_useIPhoneSource = std::string(sourceKind) == "iphone";
  }
  const char *iPhoneHost = GetExtState(kExtStateSection, kIPhoneHostKey);
  if (iPhoneHost && iPhoneHost[0] != '\0') {
    g_iPhoneHost = iPhoneHost;
  }
  const char *iPhoneControlPort = GetExtState(kExtStateSection, kIPhoneControlPortKey);
  if (iPhoneControlPort && iPhoneControlPort[0] != '\0') {
    g_iPhoneControlPort = iPhoneControlPort;
  }
  const char *iPhoneHttpPort = GetExtState(kExtStateSection, kIPhoneHttpPortKey);
  if (iPhoneHttpPort && iPhoneHttpPort[0] != '\0') {
    g_iPhoneHttpPort = iPhoneHttpPort;
  }
  const char *iPhoneToken = GetExtState(kExtStateSection, kIPhoneTokenKey);
  if (iPhoneToken && iPhoneToken[0] != '\0') {
    g_iPhoneToken = iPhoneToken;
  }
  const char *iPhoneResolution = GetExtState(kExtStateSection, kIPhoneResolutionKey);
  if (iPhoneResolution && iPhoneResolution[0] != '\0') {
    g_iPhoneResolution = iPhoneResolution;
  }
  const char *iPhoneFPS = GetExtState(kExtStateSection, kIPhoneFPSKey);
  if (iPhoneFPS && iPhoneFPS[0] != '\0') {
    g_iPhoneFPS = iPhoneFPS;
  }
  const char *iPhoneOrientation = GetExtState(kExtStateSection, kIPhoneOrientationKey);
  if (iPhoneOrientation && iPhoneOrientation[0] != '\0') {
    g_iPhoneOrientation = iPhoneOrientation;
  }
  const char *iPhoneAspect = GetExtState(kExtStateSection, kIPhoneAspectKey);
  if (iPhoneAspect && iPhoneAspect[0] != '\0') {
    g_iPhoneAspect = iPhoneAspect;
  }
  const char *iPhoneLens = GetExtState(kExtStateSection, kIPhoneLensKey);
  if (iPhoneLens && iPhoneLens[0] != '\0') {
    g_iPhoneLens = iPhoneLens;
  }
  const char *iPhoneZoom = GetExtState(kExtStateSection, kIPhoneZoomKey);
  if (iPhoneZoom && iPhoneZoom[0] != '\0') {
    g_iPhoneZoom = iPhoneZoom;
  }
  const char *iPhoneLook = GetExtState(kExtStateSection, kIPhoneLookKey);
  if (iPhoneLook && iPhoneLook[0] != '\0') {
    g_iPhoneLook = iPhoneLook;
  }
}

} // namespace

extern "C" {

REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE hInstance, reaper_plugin_info_t *rec) {
  (void)hInstance;
  @autoreleasepool {
    if (!rec) {
      if (g_reaper) {
        cleanup();
        unregisterCallbacks(g_reaper);
      }
      g_reaper = nullptr;
      return 0;
    }

    g_reaper = rec;
    const int loadError = REAPERAPI_LoadAPI(rec->GetFunc);
    if (loadError != 0) {
      return 0;
    }

    loadSettings();
    if (!registerActions(rec)) {
      showError("REAPER Video Recorder failed to register its actions.");
      return 0;
    }

    return 1;
  }
}

}
