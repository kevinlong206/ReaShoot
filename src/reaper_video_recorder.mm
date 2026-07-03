#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cstdarg>
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
NSString *kDebugLogPath = @"/tmp/reaper_video_recorder_debug.log";

void debugLog(NSString *format, ...) {
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
  NSString *line = [NSString stringWithFormat:@"%@ REAPER %@\n", [formatter stringFromDate:[NSDate date]], message ?: @""];
  @synchronized (kDebugLogPath) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:kDebugLogPath]) {
      [[NSData data] writeToFile:kDebugLogPath atomically:YES];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:kDebugLogPath];
    [handle seekToEndOfFile];
    [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
  }
}

NSString *redactedArguments(NSArray<NSString *> *arguments) {
  NSMutableArray<NSString *> *redacted = [NSMutableArray arrayWithCapacity:arguments.count];
  BOOL redactNext = NO;
  for (NSString *argument in arguments) {
    if (redactNext) {
      [redacted addObject:@"REDACTED"];
      redactNext = NO;
    } else {
      [redacted addObject:argument ?: @""];
      if ([argument isEqualToString:@"--token"]) {
        redactNext = YES;
      }
    }
  }
  return [redacted componentsJoinedByString:@" "];
}

reaper_plugin_info_t *g_reaper = nullptr;
int g_videoEnabledCommand = 0;
int g_showPreviewCommand = 0;
int g_floatPreviewCommand = 0;
int g_alignSelectedCommand = 0;
int g_restoreIPhoneCommand = 0;
int g_deleteAllIPhoneCommand = 0;
int g_toggleFollowCommand = 0;
int g_previousPlayState = 0;
bool g_videoEnabled = false;
bool g_followEnabled = true;
bool g_previewFloating = true;
bool g_activeTransportRecording = false;
bool g_pendingInsert = false;
bool g_pendingAlignment = false;
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
  queuePendingAlignment(project, track, videoItem);
  g_lastAlignmentStatus = "Recorded to Video Recorder track; aligning audio";

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

@interface KlongVideoRecorder : NSObject
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, copy) NSString *activePlaybackPath;
@property(nonatomic, assign) CFTimeInterval lastPlaybackSeekHostTime;
@property(nonatomic, strong) NSView *dockView;
@property(nonatomic, strong) NSView *previewView;
@property(nonatomic, strong) NSWindow *floatingPreviewWindow;
@property(nonatomic, strong) NSButton *iPhoneSetupButton;
@property(nonatomic, strong) NSButton *iPhonePendingButton;
@property(nonatomic, strong) NSButton *iPhoneDeleteAllButton;
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
@property(nonatomic, strong) NSButton *iPhonePreviousLookButton;
@property(nonatomic, strong) NSButton *iPhoneNextLookButton;
@property(nonatomic, strong) NSTextField *formatLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) AVSampleBufferDisplayLayer *streamPreviewLayer;
@property(nonatomic, strong) NSURLSession *previewStreamSession;
@property(nonatomic, strong) NSURLSessionWebSocketTask *previewStreamTask;
@property(nonatomic, assign) CMVideoFormatDescriptionRef h264FormatDescription;
@property(nonatomic, assign) BOOL iPhonePreviewProfileConfiguring;
@property(nonatomic, assign) BOOL previewStreamStarting;
@property(nonatomic, assign) BOOL previewStreamActive;
@property(nonatomic, assign) BOOL previewStreamFailed;
@property(nonatomic, copy) NSString *previewStreamFailureReason;
@property(nonatomic, copy) void (^stopCompletion)(NSString *path, NSError *error);
@property(nonatomic, copy) NSString *activeRemoteDownloadDirectory;
@property(nonatomic, assign) BOOL docked;
@property(nonatomic, assign) BOOL floatingPreview;
@property(nonatomic, assign) BOOL recordingVisualState;
@property(nonatomic, assign) BOOL showingPlayback;
@property(nonatomic, assign) BOOL remoteRecording;
- (void)ensureDockView;
- (void)showLivePreview;
- (void)showFloatingPreview;
- (void)showDockedPreview;
- (void)hideFloatingPreview;
- (void)hideDockedPreview;
- (void)setStatus:(NSString *)status;
- (void)setRecordingVisualState:(BOOL)recording;
- (void)updateCaptureFormatLabel;
- (void)persistIPhoneSettings;
- (void)selectRelativeIPhoneLook:(NSInteger)offset;
- (NSDictionary<NSString *, NSString *> *)fieldsFromHelperLine:(NSString *)line;
- (NSArray<NSString *> *)iPhoneConfigureArguments;
- (void)startRemotePreview;
- (void)stopRemotePreview;
- (void)startPreviewStreamWithFields:(NSDictionary<NSString *, NSString *> *)fields;
- (void)stopPreviewStream;
- (void)receivePreviewStreamMessage;
- (void)handlePreviewAccessUnit:(NSData *)accessUnit;
- (NSString *)runVideoSyncCommand:(NSString *)command
                   extraArguments:(NSArray<NSString *> *)extraArguments
                            error:(NSError **)error;
- (NSTask *)runVideoSyncCommandAsync:(NSString *)command
                      extraArguments:(NSArray<NSString *> *)extraArguments
                          completion:(void (^)(NSString *output, NSError *error))completion;
- (NSTask *)runVideoSyncCommandAsync:(NSString *)command
                      extraArguments:(NSArray<NSString *> *)extraArguments
                       outputHandler:(void (^)(NSString *line))outputHandler
                          completion:(void (^)(NSString *output, NSError *error))completion;
- (void)handleVideoSyncProgressLine:(NSString *)line;
- (NSDictionary<NSString *, NSString *> *)recordingDescriptorFromVideoSyncOutput:(NSString *)output;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)recordingDescriptorsFromVideoSyncOutput:(NSString *)output;
- (void)promptForStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording;
- (void)deleteIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording
                   completion:(void (^)(NSError *error))completion;
- (void)deleteAllPendingIPhoneRecordings;
- (void)finishIPhoneStopWithPath:(NSString *)path error:(NSError *)error;
@end

@implementation KlongVideoRecorder

- (instancetype)init {
  self = [super init];
  if (self) {
    _floatingPreview = g_previewFloating;
  }
  return self;
}

- (void)dealloc {
  [self stopPreviewStream];
}

- (void)showPreview {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self ensureDockView];
    [self showLivePreview];
    if (self.floatingPreview) {
      [self showFloatingPreview];
    } else {
      [self showDockedPreview];
    }
    [self setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
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
  return self.remoteRecording;
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
  NSFileHandle *readHandle = pipe.fileHandleForReading;
  NSMutableData *outputData = [NSMutableData data];
  readHandle.readabilityHandler = ^(NSFileHandle *handle) {
    NSData *chunk = handle.availableData;
    if (chunk.length == 0) {
      return;
    }
    @synchronized (outputData) {
      [outputData appendData:chunk];
    }
  };

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    readHandle.readabilityHandler = nil;
    if (error) {
      *error = launchError;
    }
    return nil;
  }
  [task waitUntilExit];
  readHandle.readabilityHandler = nil;
  NSData *remainingData = [readHandle readDataToEndOfFile];
  @synchronized (outputData) {
    if (remainingData.length > 0) {
      [outputData appendData:remainingData];
    }
  }
  NSData *data = nil;
  @synchronized (outputData) {
    data = [outputData copy];
  }
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

- (NSTask *)runVideoSyncCommandAsync:(NSString *)command
                      extraArguments:(NSArray<NSString *> *)extraArguments
                          completion:(void (^)(NSString *output, NSError *error))completion {
  return [self runVideoSyncCommandAsync:command extraArguments:extraArguments outputHandler:nil completion:completion];
}

- (NSTask *)runVideoSyncCommandAsync:(NSString *)command
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
    return nil;
  }

  NSTask *task = [[NSTask alloc] init];
  task.executableURL = [NSURL fileURLWithPath:helperPath];
  task.arguments = [self videoSyncArgumentsForCommand:command extraArguments:extraArguments];
  debugLog(@"helper async start command=%@ args=%@", command ?: @"", redactedArguments(task.arguments));
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
    debugLog(@"helper async finish command=%@ status=%d output=%@", command ?: @"", finishedTask.terminationStatus, output ?: @"");
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(output, commandError);
    });
  };

  NSError *launchError = nil;
  if (![task launchAndReturnError:&launchError]) {
    debugLog(@"helper async launch failed command=%@ error=%@", command ?: @"", launchError.localizedDescription ?: @"");
    dispatch_async(dispatch_get_main_queue(), ^{
      completion(nil, launchError);
    });
    return nil;
  }
  return task;
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

- (NSArray<NSDictionary<NSString *, NSString *> *> *)recordingDescriptorsFromVideoSyncOutput:(NSString *)output {
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *recordings = [NSMutableArray array];
  for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
    if ([line hasPrefix:@"recording\t"]) {
      [recordings addObject:[self fieldsFromHelperLine:line]];
    }
  }
  return recordings;
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

- (void)downloadIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording
                      directory:(NSString *)directory
                     completion:(void (^)(NSString *path, NSError *error))completion {
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
    directory ?: NSHomeDirectory(),
    @"--progress",
    nil];
  NSString *checksum = recording[@"checksum"];
  if (checksum.length > 0) {
    [arguments addObjectsFromArray:@[ @"--checksum", checksum ]];
  }
  [self setStatus:@"Downloading iPhone video"];
  __block NSDate *lastProgressDate = [NSDate date];
  __block NSTask *downloadTask = nil;
  __block dispatch_source_t watchdogTimer = nil;
  __block BOOL watchdogCanceled = NO;
  void (^cancelWatchdog)(void) = ^{
    if (!watchdogTimer || watchdogCanceled) {
      return;
    }
    watchdogCanceled = YES;
    dispatch_source_cancel(watchdogTimer);
    watchdogTimer = nil;
  };
  debugLog(@"download start id=%@ filename=%@ bytes=%@ dir=%@", recording[@"id"] ?: @"", recording[@"filename"] ?: @"", recording[@"byteCount"] ?: @"", directory ?: @"");
  downloadTask = [self runVideoSyncCommandAsync:@"download-recording" extraArguments:arguments outputHandler:^(NSString *line) {
    lastProgressDate = [NSDate date];
    debugLog(@"download progress line=%@", line ?: @"");
    [self handleVideoSyncProgressLine:line];
  } completion:^(NSString *output, NSError *error) {
    cancelWatchdog();
    if (error) {
      debugLog(@"download failed error=%@ output=%@", error.localizedDescription ?: @"", output ?: @"");
      [self setStatus:@"iPhone download failed"];
      completion(nil, error);
      return;
    }
    NSString *path = [self downloadedPathFromVideoSyncOutput:output ?: @""];
    NSError *missingPathError = nil;
    if (path.length == 0) {
      missingPathError = [NSError errorWithDomain:@"KlongVideoRecorder"
                                             code:23
                                         userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording downloaded, but video-sync-mac did not report a file path."}];
      debugLog(@"download missing path output=%@", output ?: @"");
    } else {
      debugLog(@"download complete path=%@", path ?: @"");
    }
    completion(path, missingPathError);
  }];
  if (downloadTask) {
    watchdogTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(watchdogTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), (uint64_t)(30.0 * NSEC_PER_SEC), (uint64_t)(1.0 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(watchdogTimer, ^{
      if (!downloadTask || !downloadTask.running) {
        debugLog(@"download watchdog stopping; task finished or missing");
        cancelWatchdog();
        return;
      }
      if ([[NSDate date] timeIntervalSinceDate:lastProgressDate] > 180.0) {
        [self setStatus:@"iPhone download stalled; retry from Pending"];
        debugLog(@"download watchdog terminating stalled helper pid=%d", downloadTask.processIdentifier);
        [downloadTask terminate];
        cancelWatchdog();
      }
    });
    dispatch_resume(watchdogTimer);
  } else {
    debugLog(@"download helper failed to launch");
  }
}

- (void)downloadStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording {
  [self downloadIPhoneRecording:recording
                      directory:self.activeRemoteDownloadDirectory ?: NSHomeDirectory()
                     completion:^(NSString *path, NSError *error) {
    [self finishIPhoneStopWithPath:path error:error];
  }];
}

- (void)deleteStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording {
  [self deleteIPhoneRecording:recording completion:^(NSError *error) {
    if (error) {
      [self finishIPhoneStopWithPath:nil error:error];
      return;
    }
    [self finishIPhoneStopWithPath:nil error:nil];
  }];
}

- (void)deleteIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording
                   completion:(void (^)(NSError *error))completion {
  NSString *recordingID = recording[@"id"];
  if (recordingID.length == 0) {
    NSError *error = [NSError errorWithDomain:@"KlongVideoRecorder"
                                         code:24
                                     userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording stopped, but video-sync-mac did not report a recording ID to delete."}];
    if (completion) {
      completion(error);
    }
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
      if (completion) {
        completion(error);
      }
      return;
    }
    [self setStatus:@"iPhone video deleted"];
    if (completion) {
      completion(nil);
    }
  }];
}

- (NSDictionary<NSString *, id> *)choosePendingIPhoneRecordingAction:(NSArray<NSDictionary<NSString *, NSString *> *> *)recordings {
  if (recordings.count == 0) {
    return nil;
  }

  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"Pending iPhone Recordings";
  alert.informativeText = @"Choose a pending iPhone recording to download and insert at the current edit cursor, or delete it from the phone.";
  [alert addButtonWithTitle:@"Download"];
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];

  NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 420, 26) pullsDown:NO];
  for (NSDictionary<NSString *, NSString *> *recording in recordings) {
    NSString *filename = recording[@"filename"] ?: recording[@"id"] ?: @"recording.mov";
    NSString *byteCount = recording[@"byteCount"] ?: @"0";
    [popup addItemWithTitle:[NSString stringWithFormat:@"%@ (%@ bytes)", filename, byteCount]];
    popup.lastItem.representedObject = recording;
  }
  alert.accessoryView = popup;
  NSModalResponse response = [alert runModal];
  if (response == NSAlertThirdButtonReturn) {
    return nil;
  }
  NSDictionary<NSString *, NSString *> *recording = popup.selectedItem.representedObject;
  if (!recording) {
    return nil;
  }
  NSString *action = response == NSAlertSecondButtonReturn ? @"delete" : @"download";
  return @{@"action": action, @"recording": recording};
}

- (void)restoreIPhoneRecording {
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    [self setStatus:@"Set iPhone host and token before restore"];
    return;
  }

  [self setStatus:@"Checking iPhone recordings"];
  [self runVideoSyncCommandAsync:@"list-recordings"
                  extraArguments:@[ @"--token", [NSString stringWithUTF8String:g_iPhoneToken.c_str()] ]
                      completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone recording list failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone recording list failed.");
      return;
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *recordings = [self recordingDescriptorsFromVideoSyncOutput:output ?: @""];
    if (recordings.count == 0) {
      [self setStatus:@"No pending iPhone recordings"];
      showError("No pending iPhone recordings were found on the phone.");
      return;
    }

    NSDictionary<NSString *, id> *choice = [self choosePendingIPhoneRecordingAction:recordings];
    if (!choice) {
      [self setStatus:@"Restore canceled"];
      return;
    }
    NSDictionary<NSString *, NSString *> *recording = choice[@"recording"];
    NSString *action = choice[@"action"];
    if ([action isEqualToString:@"delete"]) {
      NSString *filename = recording[@"filename"] ?: recording[@"id"] ?: @"the selected iPhone video";
      NSAlert *confirm = [[NSAlert alloc] init];
      confirm.messageText = @"Delete pending iPhone recording?";
      confirm.informativeText = [NSString stringWithFormat:@"Delete %@ from the iPhone without downloading it?", filename];
      [confirm addButtonWithTitle:@"Delete"];
      [confirm addButtonWithTitle:@"Cancel"];
      if ([confirm runModal] != NSAlertFirstButtonReturn) {
        [self setStatus:@"Delete canceled"];
        return;
      }
      [self deleteIPhoneRecording:recording completion:^(NSError *deleteError) {
        if (deleteError) {
          showError(deleteError.localizedDescription.UTF8String ?: "iPhone delete failed.");
          return;
        }
        [self setStatus:@"Deleted pending iPhone recording"];
      }];
      return;
    }

    std::string outputPath = captureOutputPath(currentProject());
    NSString *directory = [[NSString stringWithUTF8String:outputPath.c_str()] stringByDeletingLastPathComponent];
    [self downloadIPhoneRecording:recording directory:directory completion:^(NSString *path, NSError *downloadError) {
      if (downloadError) {
        [self setStatus:@"iPhone restore download failed"];
        showError(downloadError.localizedDescription.UTF8String ?: "iPhone restore download failed.");
        return;
      }
      if (path.length == 0) {
        [self setStatus:@"iPhone restore failed"];
        showError("The iPhone recording downloaded, but no file path was reported.");
        return;
      }

      ReaProject *project = currentProject();
      double position = GetCursorPositionEx ? GetCursorPositionEx(project) : 0.0;
      std::string insertError;
      if (insertRecordedMedia(path.UTF8String ?: "", position, true, insertError)) {
        const char *status = g_lastAlignmentStatus.empty() ? "Restored iPhone recording to Video Recorder track" : g_lastAlignmentStatus.c_str();
        [self setStatus:[NSString stringWithUTF8String:status]];
      } else {
        [self setStatus:@"iPhone restore import failed"];
        showError(insertError);
      }
    }];
  }];
}

- (void)deletePendingIPhoneRecordings:(NSArray<NSDictionary<NSString *, NSString *> *> *)recordings
                                index:(NSUInteger)index
                              deleted:(NSUInteger)deleted {
  if (index >= recordings.count) {
    [self setStatus:[NSString stringWithFormat:@"Deleted %lu pending iPhone recording(s)", (unsigned long)deleted]];
    return;
  }

  NSDictionary<NSString *, NSString *> *recording = recordings[index];
  [self deleteIPhoneRecording:recording completion:^(NSError *deleteError) {
    if (deleteError) {
      [self setStatus:@"iPhone delete all failed"];
      showError(deleteError.localizedDescription.UTF8String ?: "iPhone delete failed.");
      return;
    }
    [self deletePendingIPhoneRecordings:recordings index:index + 1 deleted:deleted + 1];
  }];
}

- (void)deleteAllPendingIPhoneRecordings {
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    [self setStatus:@"Set iPhone host and token before delete"];
    return;
  }

  [self setStatus:@"Checking iPhone recordings"];
  [self runVideoSyncCommandAsync:@"list-recordings"
                  extraArguments:@[ @"--token", [NSString stringWithUTF8String:g_iPhoneToken.c_str()] ]
                      completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone recording list failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone recording list failed.");
      return;
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *recordings = [self recordingDescriptorsFromVideoSyncOutput:output ?: @""];
    if (recordings.count == 0) {
      [self setStatus:@"No pending iPhone recordings"];
      showError("No pending iPhone recordings were found on the phone.");
      return;
    }

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Delete all pending iPhone recordings?";
    confirm.informativeText = [NSString stringWithFormat:@"Delete %lu pending video(s) from the iPhone without downloading them?", (unsigned long)recordings.count];
    [confirm addButtonWithTitle:@"Delete All"];
    [confirm addButtonWithTitle:@"Cancel"];
    if ([confirm runModal] != NSAlertFirstButtonReturn) {
      [self setStatus:@"Delete all canceled"];
      return;
    }

    [self deletePendingIPhoneRecordings:recordings index:0 deleted:0];
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
  return [self startIPhoneRecordingWithSuggestedPath:path startCompletion:startCompletion error:error];
}

- (void)stopRecordingWithCompletion:(void (^)(NSString *path, NSError *error))completion {
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
    [NSString stringWithUTF8String:g_iPhoneToken.c_str()]
  ];
  [self runVideoSyncCommandAsync:@"stop-only" extraArguments:arguments completion:^(NSString *output, NSError *error) {
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
}

- (void)updateCaptureFormatLabel {
  if (!self.formatLabel) {
    return;
  }
  NSString *previewState = self.previewStreamActive ? @"H.264 preview" : (self.previewStreamStarting ? @"preview connecting" : @"preview idle");
  self.formatLabel.stringValue = [NSString stringWithFormat:@"iPhone %@: %s %@ fps, %s, %s, %s lens, %sx, look %s, %@",
                                                            @"Wi-Fi",
                                                            g_iPhoneResolution.c_str(),
                                                            [NSString stringWithUTF8String:g_iPhoneFPS.c_str()],
                                                            g_iPhoneOrientation.c_str(),
                                                            g_iPhoneAspect.c_str(),
                                                            g_iPhoneLens.c_str(),
                                                            g_iPhoneZoom.c_str(),
                                                            g_iPhoneLook.c_str(),
                                                            previewState];
  [self updateRecordingTextColor];
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
  if (self.iPhonePreviewProfileConfiguring) {
    [self setStatus:@"iPhone profile configure already running"];
    return;
  }
  [self persistIPhoneSettings];
  [self updateCaptureFormatLabel];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
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
  self.iPhonePreviewProfileConfiguring = YES;
  [self runVideoSyncCommandAsync:@"configure" extraArguments:arguments completion:^(NSString *output, NSError *error) {
    self.iPhonePreviewProfileConfiguring = NO;
    if (error) {
      [self setStatus:@"iPhone profile configure failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone profile configure failed.");
      return;
    }
    NSString *message = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self setStatus:message.length > 0 ? message : @"iPhone profile configured"];
    if (self.previewStreamActive || self.previewStreamStarting) {
      [self stopRemotePreview];
      [self startRemotePreview];
    }
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
  [self setStatus:@"Searching for ReaShoot"];
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
    self.previewStreamFailed = NO;
    self.previewStreamFailureReason = nil;
    [self startRemotePreview];
  }];
}

- (void)iPhoneSettingsChanged:(id)sender {
  (void)sender;
  [self persistIPhoneSettings];
  [self stopRemotePreview];
  [self startRemotePreview];
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
    self.iPhoneSetupWindow.title = @"ReaShoot Setup";
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

- (NSString *)displayTitleForRawFilterID:(NSString *)filterID {
  NSString *name = [filterID hasPrefix:@"CI"] ? [filterID substringFromIndex:2] : filterID;
  NSMutableString *title = [NSMutableString stringWithString:@"CI: "];
  for (NSUInteger index = 0; index < name.length; ++index) {
    unichar character = [name characterAtIndex:index];
    if (index > 0) {
      unichar previous = [name characterAtIndex:index - 1];
      const BOOL previousIsLower = previous >= 'a' && previous <= 'z';
      const BOOL previousIsDigit = previous >= '0' && previous <= '9';
      const BOOL currentIsUpper = character >= 'A' && character <= 'Z';
      const BOOL currentIsDigit = character >= '0' && character <= '9';
      const BOOL currentIsLetter = (character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z');
      if ((previousIsLower && currentIsUpper) ||
          (!previousIsDigit && currentIsDigit) ||
          (previousIsDigit && currentIsLetter)) {
        [title appendString:@" "];
      }
    }
    [title appendFormat:@"%C", character];
  }
  return title;
}

- (void)addRawCoreImageLookItems {
  NSArray<NSString *> *rawFilterIDs = @[
    @"CIThermal", @"CIXRay", @"CIFalseColor", @"CIColorInvert", @"CIColorPosterize",
    @"CIColorThreshold", @"CIColorThresholdOtsu", @"CIVibrance", @"CIHueAdjust", @"CITemperatureAndTint",
    @"CIGloom", @"CISobelGradients", @"CIGaborGradients", @"CIMorphologyGradient", @"CIEdges",
    @"CIEdgeWork", @"CILineOverlay", @"CICannyEdgeDetector", @"CICrystallize", @"CIHexagonalPixellate",
    @"CIPixellate", @"CIPointillize", @"CIDotScreen", @"CICircularScreen", @"CILineScreen",
    @"CIHatchedScreen", @"CICMYKHalftone", @"CIKaleidoscope", @"CITriangleKaleidoscope", @"CITwirlDistortion",
    @"CIVortexDistortion", @"CILightTunnel", @"CIGlassDistortion", @"CIDisplacementDistortion"
  ];
  for (NSString *filterID in rawFilterIDs) {
    [self.iPhoneLookPopup addItemWithTitle:[self displayTitleForRawFilterID:filterID]];
    self.iPhoneLookPopup.lastItem.representedObject = [@"ci:" stringByAppendingString:filterID];
  }
}

- (void)selectRelativeIPhoneLook:(NSInteger)offset {
  const NSInteger itemCount = self.iPhoneLookPopup.numberOfItems;
  if (itemCount <= 0) {
    return;
  }
  NSInteger selectedIndex = self.iPhoneLookPopup.indexOfSelectedItem;
  if (selectedIndex < 0) {
    selectedIndex = 0;
  }
  NSInteger nextIndex = (selectedIndex + offset) % itemCount;
  if (nextIndex < 0) {
    nextIndex += itemCount;
  }
  [self.iPhoneLookPopup selectItemAtIndex:nextIndex];
  [self profileSelectionChanged:self.iPhoneLookPopup];
}

- (void)previousIPhoneLook:(id)sender {
  (void)sender;
  [self selectRelativeIPhoneLook:-1];
}

- (void)nextIPhoneLook:(id)sender {
  (void)sender;
  [self selectRelativeIPhoneLook:1];
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

    self.streamPreviewLayer = [AVSampleBufferDisplayLayer layer];
    self.streamPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.streamPreviewLayer.frame = self.previewView.bounds;
    self.streamPreviewLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    self.streamPreviewLayer.hidden = YES;
    [self.previewView.layer addSublayer:self.streamPreviewLayer];

    self.iPhoneSetupButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 112, 101, 100, 24)];
    self.iPhoneSetupButton.title = @"iPhone Setup";
    self.iPhoneSetupButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneSetupButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.iPhoneSetupButton.target = self;
    self.iPhoneSetupButton.action = @selector(showIPhoneSetup:);
    [self.dockView addSubview:self.iPhoneSetupButton];

    self.iPhoneDeleteAllButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 216, 101, 96, 24)];
    self.iPhoneDeleteAllButton.title = @"Delete All";
    self.iPhoneDeleteAllButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneDeleteAllButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.iPhoneDeleteAllButton.target = self;
    self.iPhoneDeleteAllButton.action = @selector(deleteAllPendingIPhoneRecordings);
    [self.dockView addSubview:self.iPhoneDeleteAllButton];

    self.iPhonePendingButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 328, 101, 104, 24)];
    self.iPhonePendingButton.title = @"Pending...";
    self.iPhonePendingButton.bezelStyle = NSBezelStyleRounded;
    self.iPhonePendingButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    self.iPhonePendingButton.target = self;
    self.iPhonePendingButton.action = @selector(restoreIPhoneRecording);
    [self.dockView addSubview:self.iPhonePendingButton];

    self.iPhoneHostField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 127, (frame.size.width - 36) / 2.0, 22)];
    self.iPhoneHostField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneHostField.placeholderString = @"iPhone host, e.g. kevin-long-iphone.local";
    self.iPhoneHostField.stringValue = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
    self.iPhoneHostField.target = self;
    self.iPhoneHostField.action = @selector(iPhoneSettingsChanged:);
    self.iPhoneHostField.hidden = YES;
    [self.dockView addSubview:self.iPhoneHostField];

    self.iPhoneTokenField = [[NSTextField alloc] initWithFrame:NSMakeRect(NSMaxX(self.iPhoneHostField.frame) + 12, 127, (frame.size.width - 36) / 2.0, 22)];
    self.iPhoneTokenField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneTokenField.placeholderString = @"Pairing token";
    self.iPhoneTokenField.stringValue = [NSString stringWithUTF8String:g_iPhoneToken.c_str()];
    self.iPhoneTokenField.target = self;
    self.iPhoneTokenField.action = @selector(iPhoneSettingsChanged:);
    self.iPhoneTokenField.hidden = YES;
    [self.dockView addSubview:self.iPhoneTokenField];

    const CGFloat buttonWidth = 88.0;
    self.iPhonePairingCodeField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, 101, frame.size.width - 24 - (buttonWidth * 3.0) - 18.0, 22)];
    self.iPhonePairingCodeField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhonePairingCodeField.placeholderString = @"Pairing code from iPhone";
    self.iPhonePairingCodeField.hidden = YES;
    [self.dockView addSubview:self.iPhonePairingCodeField];

    CGFloat buttonX = NSMaxX(self.iPhonePairingCodeField.frame) + 6.0;
    self.iPhoneDiscoverButton = [[NSButton alloc] initWithFrame:NSMakeRect(buttonX, 101, buttonWidth, 22)];
    self.iPhoneDiscoverButton.title = @"Discover";
    self.iPhoneDiscoverButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneDiscoverButton.target = self;
    self.iPhoneDiscoverButton.action = @selector(discoverIPhone:);
    self.iPhoneDiscoverButton.hidden = YES;
    [self.dockView addSubview:self.iPhoneDiscoverButton];

    buttonX += buttonWidth + 6.0;
    self.iPhonePairButton = [[NSButton alloc] initWithFrame:NSMakeRect(buttonX, 101, buttonWidth, 22)];
    self.iPhonePairButton.title = @"Pair";
    self.iPhonePairButton.bezelStyle = NSBezelStyleRounded;
    self.iPhonePairButton.target = self;
    self.iPhonePairButton.action = @selector(pairIPhone:);
    self.iPhonePairButton.hidden = YES;
    [self.dockView addSubview:self.iPhonePairButton];

    buttonX += buttonWidth + 6.0;
    self.iPhoneTestButton = [[NSButton alloc] initWithFrame:NSMakeRect(buttonX, 101, buttonWidth, 22)];
    self.iPhoneTestButton.title = @"Test";
    self.iPhoneTestButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneTestButton.target = self;
    self.iPhoneTestButton.action = @selector(testIPhoneConnection:);
    self.iPhoneTestButton.hidden = YES;
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

    self.iPhonePreviousLookButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 49, 52, 24)];
    self.iPhonePreviousLookButton.title = @"Prev";
    self.iPhonePreviousLookButton.bezelStyle = NSBezelStyleRounded;
    self.iPhonePreviousLookButton.target = self;
    self.iPhonePreviousLookButton.action = @selector(previousIPhoneLook:);
    [self.dockView addSubview:self.iPhonePreviousLookButton];

    self.iPhoneLookPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(70, 49, frame.size.width - 140, 24) pullsDown:NO];
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
    [self addRawCoreImageLookItems];
    NSInteger lookIndex = [self.iPhoneLookPopup indexOfItemWithRepresentedObject:[NSString stringWithUTF8String:g_iPhoneLook.c_str()]];
    if (lookIndex >= 0) {
      [self.iPhoneLookPopup selectItemAtIndex:lookIndex];
    } else {
      [self.iPhoneLookPopup selectItemAtIndex:0];
      g_iPhoneLook = "natural";
    }
    self.iPhoneLookPopup.target = self;
    self.iPhoneLookPopup.action = @selector(profileSelectionChanged:);
    [self.dockView addSubview:self.iPhoneLookPopup];

    self.iPhoneNextLookButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - 64, 49, 52, 24)];
    self.iPhoneNextLookButton.title = @"Next";
    self.iPhoneNextLookButton.bezelStyle = NSBezelStyleRounded;
    self.iPhoneNextLookButton.target = self;
    self.iPhoneNextLookButton.action = @selector(nextIPhoneLook:);
    [self.dockView addSubview:self.iPhoneNextLookButton];

    self.iPhoneResolutionPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneFPSPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneOrientationPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneAspectPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneLensPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneZoomPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhoneLookPopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.iPhonePreviousLookButton.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    self.iPhoneNextLookButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;

    self.formatLabel = [NSTextField labelWithString:@"Format: unavailable"];
    self.formatLabel.frame = NSMakeRect(12, 29, frame.size.width - 24, 18);
    self.formatLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.dockView addSubview:self.formatLabel];

    self.statusLabel = [NSTextField labelWithString:[NSString stringWithUTF8String:followStatusText().c_str()]];
    self.statusLabel.frame = NSMakeRect(12, 9, frame.size.width - 24, 18);
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.dockView addSubview:self.statusLabel];
    [self updateCaptureFormatLabel];
  }
}

- (void)startRemotePreview {
  [self persistIPhoneSettings];
  if (!self.previewStreamTask && !self.previewStreamStarting) {
    self.previewStreamFailed = NO;
    self.previewStreamFailureReason = nil;
  }
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
      if (message.length > 0 && !self.previewStreamTask && !self.previewStreamStarting) {
        [self setStatus:message];
      }
      [self runVideoSyncCommandAsync:@"start-preview"
                       extraArguments:@[ @"--token", [NSString stringWithUTF8String:g_iPhoneToken.c_str()] ]
                           completion:^(NSString *previewOutput, NSError *previewError) {
        if (previewError) {
          self.previewStreamFailed = YES;
          self.previewStreamFailureReason = previewError.localizedDescription ?: @"Preview start failed";
          [self setStatus:@"Preview: start failed"];
          return;
        }
        [self startPreviewStreamWithFields:[self fieldsFromHelperLine:previewOutput]];
      }];
    }];
    return;
  }
  self.previewStreamFailed = YES;
  self.previewStreamFailureReason = @"iPhone host/token missing";
  [self setStatus:@"Preview: set iPhone host and token"];
}

- (void)stopRemotePreview {
  [self stopPreviewStream];
  self.previewStreamFailed = NO;
  self.previewStreamFailureReason = nil;
  if (!g_iPhoneHost.empty() && !g_iPhoneToken.empty()) {
    [self runVideoSyncCommandAsync:@"stop-preview"
                    extraArguments:@[ @"--token", [NSString stringWithUTF8String:g_iPhoneToken.c_str()] ]
                        completion:^(NSString *output, NSError *error) {
      (void)output;
      (void)error;
    }];
  }
}

- (void)startPreviewStreamWithFields:(NSDictionary<NSString *, NSString *> *)fields {
  if (self.showingPlayback || self.previewStreamTask || self.previewStreamStarting || self.previewStreamFailed) {
    return;
  }
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    self.previewStreamFailed = YES;
    self.previewStreamFailureReason = @"iPhone host/token missing";
    [self setStatus:@"Preview: set iPhone host and token"];
    return;
  }

  NSString *streamPath = fields[@"streamPath"];
  if (streamPath.length == 0) {
    streamPath = @"/preview";
  }
  NSString *portText = fields[@"port"];
  NSInteger port = portText.length > 0 ? portText.integerValue : 8789;
  if (port <= 0) {
    port = 8789;
  }

  NSURLComponents *components = [[NSURLComponents alloc] init];
  components.scheme = @"ws";
  components.host = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
  components.port = @(port);
  components.path = streamPath;
  components.queryItems = @[ [NSURLQueryItem queryItemWithName:@"token" value:[NSString stringWithUTF8String:g_iPhoneToken.c_str()]] ];
  NSURL *url = components.URL;
  if (!url) {
    self.previewStreamFailed = YES;
    self.previewStreamFailureReason = @"Invalid preview URL";
    [self setStatus:@"Preview: invalid stream URL"];
    return;
  }

  self.previewStreamStarting = YES;
  self.previewStreamActive = NO;
  self.previewStreamFailureReason = nil;
  self.streamPreviewLayer.hidden = NO;
  [self.streamPreviewLayer flushAndRemoveImage];
  self.previewStreamSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration];
  self.previewStreamTask = [self.previewStreamSession webSocketTaskWithURL:url];
  [self.previewStreamTask resume];
  [self setStatus:@"Preview: connecting H.264 stream"];
  [self receivePreviewStreamMessage];
}

- (void)stopPreviewStream {
  self.previewStreamStarting = NO;
  self.previewStreamActive = NO;
  [self.previewStreamTask cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
  self.previewStreamTask = nil;
  [self.previewStreamSession invalidateAndCancel];
  self.previewStreamSession = nil;
  self.streamPreviewLayer.hidden = YES;
  [self.streamPreviewLayer flushAndRemoveImage];
  if (self.h264FormatDescription) {
    CFRelease(self.h264FormatDescription);
    self.h264FormatDescription = nil;
  }
}

- (void)receivePreviewStreamMessage {
  NSURLSessionWebSocketTask *task = self.previewStreamTask;
  if (!task) {
    return;
  }
  __weak KlongVideoRecorder *weakSelf = self;
  [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      KlongVideoRecorder *strongSelf = weakSelf;
      if (!strongSelf || task != strongSelf.previewStreamTask) {
        return;
      }
      if (error) {
        [strongSelf stopPreviewStream];
        strongSelf.previewStreamFailed = YES;
        strongSelf.previewStreamFailureReason = error.localizedDescription ?: @"Preview stream failed";
        if (!strongSelf.showingPlayback && !strongSelf.recordingVisualState) {
          [strongSelf setStatus:@"Preview: stream disconnected"];
        }
        return;
      }
      if (message.type == NSURLSessionWebSocketMessageTypeData) {
        if (!strongSelf.previewStreamActive) {
          strongSelf.previewStreamStarting = NO;
          strongSelf.previewStreamActive = YES;
          [strongSelf setStatus:@"Preview: H.264 stream"];
          [strongSelf updateCaptureFormatLabel];
        }
        [strongSelf handlePreviewAccessUnit:message.data];
      } else if (message.type == NSURLSessionWebSocketMessageTypeString && !strongSelf.previewStreamActive) {
        strongSelf.previewStreamStarting = NO;
        strongSelf.previewStreamActive = YES;
        [strongSelf setStatus:@"Preview: H.264 stream"];
        [strongSelf updateCaptureFormatLabel];
      }
      [strongSelf receivePreviewStreamMessage];
    });
  }];
}

- (void)handlePreviewAccessUnit:(NSData *)accessUnit {
  if (accessUnit.length < 5) {
    return;
  }
  const uint8_t *bytes = static_cast<const uint8_t *>(accessUnit.bytes);
  const NSUInteger length = accessUnit.length;
  auto startCodeLengthAt = ^NSUInteger(NSUInteger offset) {
    if (offset + 3 <= length && bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 1) {
      return static_cast<NSUInteger>(3);
    }
    if (offset + 4 <= length && bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 0 && bytes[offset + 3] == 1) {
      return static_cast<NSUInteger>(4);
    }
    return static_cast<NSUInteger>(0);
  };

  std::vector<std::pair<NSUInteger, NSUInteger>> ranges;
  NSUInteger offset = 0;
  while (offset < length) {
    NSUInteger codeLength = 0;
    while (offset < length && (codeLength = startCodeLengthAt(offset)) == 0) {
      ++offset;
    }
    if (offset >= length) {
      break;
    }
    const NSUInteger naluStart = offset + codeLength;
    offset = naluStart;
    while (offset < length && startCodeLengthAt(offset) == 0) {
      ++offset;
    }
    if (offset > naluStart) {
      ranges.push_back({naluStart, offset - naluStart});
    }
  }

  NSData *sps = nil;
  NSData *pps = nil;
  NSMutableData *sampleData = [NSMutableData data];
  for (const auto &range : ranges) {
    const NSUInteger naluStart = range.first;
    const NSUInteger naluLength = range.second;
    if (naluLength == 0) {
      continue;
    }
    const uint8_t naluType = bytes[naluStart] & 0x1f;
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
      if (self.h264FormatDescription) {
        CFRelease(self.h264FormatDescription);
      }
      self.h264FormatDescription = formatDescription;
    }
  }

  if (!self.h264FormatDescription || sampleData.length == 0) {
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
                                                    self.h264FormatDescription,
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
  if (self.streamPreviewLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
    [self.streamPreviewLayer flush];
  }
  [self.streamPreviewLayer enqueueSampleBuffer:sampleBuffer];
  CFRelease(sampleBuffer);
}

- (void)showLivePreview {
  self.showingPlayback = NO;
  [self.player pause];
  self.playerLayer.hidden = YES;
  [self startRemotePreview];
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
  g_pendingInsert = false;
  g_pendingInsertPath.clear();

  std::string error;
  if (insertRecordedMedia(path, position, true, error)) {
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

  if (GetPlayStateEx) {
    const int playState = GetPlayStateEx(g_pendingAlignmentProject);
    if ((playState & 5) != 0) {
      g_nextAlignmentAttemptTime = now + 1;
      return;
    }
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

  if (command == g_restoreIPhoneCommand) {
    [recorder() restoreIPhoneRecording];
    return true;
  }

  if (command == g_deleteAllIPhoneCommand) {
    [recorder() deleteAllPendingIPhoneRecordings];
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
  custom_action_register_t restoreIPhoneAction = {
      0,
      "KLONG_VIDEO_RECORDER_RESTORE_IPHONE",
      "Video Recorder: Restore Pending iPhone Recording",
      nullptr,
  };
  custom_action_register_t deleteAllIPhoneAction = {
      0,
      "KLONG_VIDEO_RECORDER_DELETE_ALL_IPHONE",
      "Video Recorder: Delete All Pending iPhone Recordings",
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
  g_restoreIPhoneCommand = rec->Register("custom_action", &restoreIPhoneAction);
  g_deleteAllIPhoneCommand = rec->Register("custom_action", &deleteAllIPhoneAction);
  g_toggleFollowCommand = rec->Register("custom_action", &toggleFollowAction);

  return g_videoEnabledCommand != 0 && g_showPreviewCommand != 0 && g_floatPreviewCommand != 0 &&
         g_alignSelectedCommand != 0 && g_restoreIPhoneCommand != 0 && g_deleteAllIPhoneCommand != 0 &&
         g_toggleFollowCommand != 0 &&
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
