#import <Cocoa/Cocoa.h>

#include <algorithm>
#include <cstdarg>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <ctime>
#include <exception>
#include <limits>
#include <memory>
#include <string>
#include <thread>
#include <vector>

#include "core/alignment_math.h"
#include "core/capture_profile.h"
#include "desktop/desktop_api_client.h"
#include "core/json_value.h"
#include "core/path_utils.h"
#include "core/reashoot_controller.h"
#include "core/reashoot_status.h"
#include "platform/mac/mac_media_audio_reader.h"
#include "reaper/reaper_host.h"

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
#define REAPERAPI_WANT_get_ini_file
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

constexpr const char *kExtStateSection = "klong_reashoot";
constexpr const char *kLegacyExtStateSection = "klong_reaper_video_recorder";
constexpr const char *kFollowEnabledKey = "follow_enabled";
constexpr const char *kDesktopApiEnabledKey = "desktop_api_enabled";
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
constexpr const char *kVideoTrackName = "ReaShoot";
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
NSString *kDebugLogPath = @"/tmp/reashoot_debug.log";

constexpr const char *kExtStateKeys[] = {
    kFollowEnabledKey,
    kDesktopApiEnabledKey,
    kPreviewFloatingKey,
    kIPhoneHostKey,
    kIPhoneControlPortKey,
    kIPhoneHttpPortKey,
    kIPhoneTokenKey,
    kIPhoneResolutionKey,
    kIPhoneFPSKey,
    kIPhoneOrientationKey,
    kIPhoneAspectKey,
    kIPhoneLensKey,
    kIPhoneZoomKey,
    kIPhoneLookKey,
};

struct ActionRename {
  const char *legacy;
  const char *current;
};

constexpr ActionRename kActionRenames[] = {
    {"KLONG_VIDEO_RECORDER_ENABLE", "KLONG_REASHOOT_ENABLE"},
    {"KLONG_VIDEO_RECORDER_ALIGN_SELECTED", "KLONG_REASHOOT_ALIGN_SELECTED"},
    {"KLONG_VIDEO_RECORDER_TOGGLE_FOLLOW", "KLONG_REASHOOT_TOGGLE_FOLLOW"},
};

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

NSString *stringFromStd(const std::string &value) {
  return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string stdStringFromNSString(NSString *value) {
  return value.UTF8String ? value.UTF8String : "";
}

reashoot::core::MediaAudioReader &mediaAudioReader() {
  static std::unique_ptr<reashoot::core::MediaAudioReader> reader = reashoot::platform::mac::createMediaAudioReader();
  return *reader;
}

reaper_plugin_info_t *g_reaper = nullptr;
int g_videoEnabledCommand = 0;
int g_alignSelectedCommand = 0;
int g_toggleFollowCommand = 0;
int g_previousPlayState = 0;
HWND g_swellPanelPrototype = nullptr;
bool g_swellPanelPrototypeDocked = false;
bool g_videoEnabled = false;
bool g_followEnabled = true;
bool g_desktopApiEnabled = false;
reashoot::core::ReaShootController g_extensionController;
bool g_previewFloating = true;
bool g_activeTransportRecording = false;
bool g_transportStartInFlight = false;
bool g_transportStopRequested = false;
bool g_pendingInsert = false;
bool g_pendingAlignment = false;
std::string g_iPhoneHost;
std::string g_iPhoneControlPort = "8787";
std::string g_iPhoneHttpPort = "8788";
std::string g_iPhoneToken;
std::string g_iPhoneResolution = "4K";
std::string g_iPhoneFPS = "30";
std::string g_iPhoneOrientation = "auto";
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

struct AlignmentWindow {
  bool active = false;
  double start = 0.0;
  double end = 0.0;
};

void showError(const std::string &message) {
  if (ShowMessageBox) {
    ShowMessageBox(message.c_str(), "ReaShoot", 0);
  }
}

ReaProject *currentProject() {
  return reashoot::reaper::currentProject();
}

std::string captureOutputPath(ReaProject *project) {
  std::string outputRoot;
  std::string projectName = "unsaved_project";

  outputRoot = reashoot::reaper::defaultRecordingPath();

  std::string projectFile;
  reashoot::reaper::currentProject(&projectFile);
  if (!projectFile.empty()) {
    projectName = reashoot::core::baseNameWithoutExtension(projectFile);
    if (outputRoot.empty()) {
      outputRoot = reashoot::reaper::projectPath(project);
      if (outputRoot.empty()) {
        outputRoot = reashoot::core::directoryName(projectFile);
      }
    }
  }

  if (outputRoot.empty()) {
    outputRoot = reashoot::reaper::resourcePath();
  }
  if (outputRoot.empty()) {
    outputRoot = NSHomeDirectory().UTF8String;
  }

  return outputRoot + "/ReaShoot Recordings/" + projectName + "_" + reashoot::core::timestampString() + ".mov";
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
    char name[] = "ReaShoot";
    GetSetMediaTrackInfo_String(track, "P_NAME", name, true);
    if (SetMediaTrackInfo_Value) {
      SetMediaTrackInfo_Value(track, "D_VOL", 0.0);
    }
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
  reashoot::reaper::refreshArrangeTimeline();
  return track;
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
  reashoot::reaper::moveMediaItem(item, position);
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
  return reashoot::core::isVideoPath(path);
}

std::vector<double> envelopeFromPeakBuffer(const std::vector<double> &peaks, int returnedSamples, double peakRate) {
  std::vector<double> envelope(static_cast<size_t>(returnedSamples));
  for (int i = 0; i < returnedSamples; ++i) {
    const double value = (std::max)(std::fabs(peaks[static_cast<size_t>(i)]),
                                    std::fabs(peaks[static_cast<size_t>(returnedSamples + i)]));
    envelope[static_cast<size_t>(i)] = value;
  }

  return reashoot::core::shapeEnvelope(std::move(envelope), peakRate, kAlignmentFinePeakRate);
}

std::vector<double> movieAudioEnvelope(const std::string &path, double sourceStart, double duration, double peakRate, int &sampleCountOut, std::string *debug) {
  sampleCountOut = 0;
  if (path.empty() || duration <= 0.0) {
    if (debug) {
      *debug = "movie fallback skipped: empty path or duration";
    }
    return {};
  }

  std::vector<double> samples = mediaAudioReader().readMonoSamples(path, sourceStart, duration, kAlignmentSampleRate);
  if (samples.empty()) {
    if (debug) {
      *debug = "movie fallback failed: no decoded audio samples in " + path;
    }
    return {};
  }

  const int bucketCount = (std::max)(1, static_cast<int>(std::floor(duration * peakRate)));
  std::vector<double> envelope(static_cast<size_t>(bucketCount), 0.0);
  int observedBuckets = 0;
  for (size_t index = 0; index < samples.size(); ++index) {
    const int bucket = static_cast<int>(std::floor((static_cast<double>(index) / kAlignmentSampleRate) * peakRate));
    if (bucket < 0 || bucket >= bucketCount) {
      continue;
    }
    envelope[static_cast<size_t>(bucket)] =
        (std::max)(envelope[static_cast<size_t>(bucket)], std::fabs(samples[index]));
    observedBuckets = (std::max)(observedBuckets, bucket + 1);
  }

  if (observedBuckets <= 0) {
    if (debug && debug->empty()) {
      *debug = "movie fallback failed: decoded samples produced no audio buckets";
    }
    return {};
  }
  if (observedBuckets < static_cast<int>(envelope.size())) {
    envelope.resize(static_cast<size_t>(observedBuckets));
  }

  envelope = reashoot::core::shapeEnvelope(std::move(envelope), peakRate, kAlignmentFinePeakRate);
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

  std::vector<double> videoSamples =
      reashoot::core::normalizedSampleShape(mediaAudioReader().readMonoSamples(videoPath, videoSourceStart, duration, kAlignmentSampleRate),
                                            kAlignmentSampleRate);
  std::vector<double> referenceSamples = reashoot::core::normalizedSampleShape(
      takeAudioAccessorSamples(referenceTake, referenceWindowProjectPosition, referenceDuration), kAlignmentSampleRate);
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
    const double score = reashoot::core::normalizedCorrelationAtLag(videoSamples, referenceSamples, lag, minimumOverlapSamples);
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
    const double score = reashoot::core::normalizedCorrelationAtLag(videoEnvelope, referenceEnvelope, lag, minimumOverlapSamples);
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
  result.videoPeaks =
      static_cast<int>(reashoot::core::strongestTransientPeaks(reashoot::core::transientEnvelope(videoEnvelope), kAlignmentPeakRate).size());

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
      const double score =
          reashoot::core::normalizedCorrelationAtLag(videoEnvelope, referenceEnvelope, lag, static_cast<int>(kAlignmentPeakRate));
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
    reashoot::reaper::moveMediaItem(videoItem, bestPosition);
    reashoot::reaper::refreshArrangeTimeline();
  }

  return result;
}

std::string alignmentStatusText(const AlignmentResult &alignment) {
  if (alignment.aligned) {
    const double correctionMs = alignment.correction * 1000.0;
    char message[160] = {};
    std::snprintf(message,
                  sizeof(message),
                  "Recorded to ReaShoot track; aligned %.0f ms (score %.2f)",
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

bool insertRecordedMedia(const std::string &path, double position, std::string &error) {
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
    error = "Recording finished, but REAPER could not create or find the ReaShoot track.";
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

  queuePendingAlignment(project, track, videoItem);
  g_lastAlignmentStatus = "Recorded to ReaShoot track; aligning audio";

  reashoot::reaper::refreshArrangeTimeline();

  return true;
}

void updateFollowStatusText();
void refreshToolbarState();
void stopTransportRecording();

std::string followStatusText() {
  return g_extensionController.followStatusText();
}

void syncExtensionStateGlobals() {
  g_videoEnabled = g_extensionController.videoEnabled();
  g_followEnabled = g_extensionController.followEnabled();
}

void setFollowEnabled(bool enabled) {
  g_extensionController.setFollowEnabled(enabled);
  syncExtensionStateGlobals();
  reashoot::reaper::setExtState(kExtStateSection, kFollowEnabledKey, enabled ? "1" : "0", true);
  updateFollowStatusText();
  refreshToolbarState();
}

void setVideoEnabled(bool enabled);

} // namespace


@interface ReaShootRecorder : NSObject
- (void)setStatus:(NSString *)status;
- (void)setRecordingVisualState:(BOOL)recording;
@end

@implementation ReaShootRecorder

- (void)setStatus:(NSString *)status {
  std::string friendlyStatus = reashoot::core::friendlyStatusText(status ? status.UTF8String : "Idle");
  debugLog(@"status: %s", friendlyStatus.c_str());
}

- (void)setRecordingVisualState:(BOOL)recording {
  (void)recording;
}

@end

namespace {

ReaShootRecorder *recorder() {
  static ReaShootRecorder *instance = nil;
  if (!instance) {
    instance = [[ReaShootRecorder alloc] init];
  }
  return instance;
}

void updateFollowStatusText() {
  [recorder() setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
}

void refreshToolbarState() {
  reashoot::reaper::refreshToolbar(g_videoEnabledCommand);
  reashoot::reaper::refreshToolbar(g_toggleFollowCommand);
}

void setVideoEnabled(bool enabled) {
  if (g_videoEnabled == enabled) {
    return;
  }

  g_extensionController.setVideoEnabled(enabled);
  syncExtensionStateGlobals();
  if (enabled) {
    ensureVideoTrackReady(currentProject(), false);
    [recorder() setStatus:@"ReaShoot enabled. Use ReaShoot.app for setup and preview."];
  } else {
    if (g_activeTransportRecording) {
      stopTransportRecording();
    }
    [recorder() setStatus:@"ReaShoot disabled."];
  }

  updateFollowStatusText();
  refreshToolbarState();
}

bool isRecordingState(int playState) {
  return (playState & kRecordBit) != 0;
}

NSError *desktopApiNSError(const std::string &message, NSInteger code) {
  NSString *text = stringFromStd(reashoot::core::friendlyStatusText(message));
  if (text.length == 0) {
    text = @"Unknown desktop API error.";
  }
  return [NSError errorWithDomain:@"com.klong.reashoot.desktop-api"
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: text}];
}

void runDesktopStartRecordingAsync(void (^completion)(NSError *error)) {
  void (^completionCopy)(NSError *) = [completion copy];
  std::thread([completionCopy] {
    std::string errorMessage;
    @autoreleasepool {
      try {
        reashoot::desktop::DesktopApiClient().startRecording();
      } catch (const std::exception &error) {
        errorMessage = error.what();
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      NSError *error = errorMessage.empty() ? nil : desktopApiNSError(errorMessage, 30);
      completionCopy(error);
    });
  }).detach();
}

void runDesktopStopDownloadAsync(const std::string &downloadDirectory,
                                 void (^progress)(NSString *message),
                                 void (^completion)(NSString *path, NSError *error)) {
  void (^progressCopy)(NSString *) = [progress copy];
  void (^completionCopy)(NSString *, NSError *) = [completion copy];
  std::thread([downloadDirectory, progressCopy, completionCopy] {
    std::string downloadedPath;
    std::string errorMessage;
    @autoreleasepool {
      try {
        downloadedPath = reashoot::desktop::DesktopApiClient().stopRecordingAndDownload(downloadDirectory, [progressCopy](const std::string &message) {
          if (!progressCopy) {
            return;
          }
          NSString *status = stringFromStd(message);
          dispatch_async(dispatch_get_main_queue(), ^{
            progressCopy(status);
          });
        });
      } catch (const std::exception &error) {
        errorMessage = error.what();
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      NSError *error = errorMessage.empty() ? nil : desktopApiNSError(errorMessage, 31);
      completionCopy(stringFromStd(downloadedPath), error);
    });
  }).detach();
}

void startTransportRecording(ReaProject *project) {
  if (g_activeTransportRecording) {
    return;
  }

  g_recordProject = project;
  g_transportStartInFlight = true;
  g_transportStopRequested = false;
  ensureVideoTrackReady(project, false);
  g_recordStartPosition = reashoot::reaper::cursorPosition(project);
  if (g_recordStartPosition < 0.0 && GetPlayPositionEx) {
    g_recordStartPosition = GetPlayPositionEx(project);
  }

  g_activeTransportRecording = true;
  [recorder() setRecordingVisualState:YES];
  [recorder() setStatus:@"Starting recording through ReaShoot.app"];
  runDesktopStartRecordingAsync(^(NSError *error) {
    if (error) {
      g_activeTransportRecording = false;
      g_transportStartInFlight = false;
      g_transportStopRequested = false;
      [recorder() setRecordingVisualState:NO];
      showError(std::string("ReaShoot.app recording start failed:\n") + (error.localizedDescription.UTF8String ?: "Unknown desktop API error."));
      return;
    }
    g_transportStartInFlight = false;
    if (g_recordProject && GetPlayPositionEx) {
      g_recordStartPosition = GetPlayPositionEx(g_recordProject);
    }
    [recorder() setStatus:@"Recording through ReaShoot.app"];
    if (g_transportStopRequested) {
      g_transportStopRequested = false;
      stopTransportRecording();
    }
  });
}

void stopTransportRecording() {
  if (!g_activeTransportRecording) {
    return;
  }
  if (g_transportStartInFlight) {
    g_transportStopRequested = true;
    [recorder() setStatus:@"Waiting for ReaShoot.app recording to start"];
    return;
  }

  double insertPosition = g_recordStartPosition;
  if (insertPosition < 0.0) {
    insertPosition = 0.0;
  }
  std::string outputPath = captureOutputPath(g_recordProject ? g_recordProject : currentProject());
  std::string directory = reashoot::core::directoryName(outputPath);
  if (directory.empty()) {
    directory = NSHomeDirectory().UTF8String ?: "";
  }
  [recorder() setStatus:@"Stopping recording through ReaShoot.app"];
  runDesktopStopDownloadAsync(directory, ^(NSString *message) {
    [recorder() setStatus:message.length ? message : @"Downloading recording through ReaShoot.app"];
  }, ^(NSString *pathText, NSError *error) {
    [recorder() setRecordingVisualState:NO];
    if (error) {
      showError(std::string("ReaShoot.app recording stop/download failed:\n") + (error.localizedDescription.UTF8String ?: "Unknown desktop API error."));
      g_activeTransportRecording = false;
      return;
    }
    std::string path = stdStringFromNSString(pathText ?: @"");
    g_pendingInsertPath = path;
    g_pendingInsertPosition = insertPosition;
    g_pendingInsert = !g_pendingInsertPath.empty();
    g_activeTransportRecording = false;
    if (!g_pendingInsert) {
      showError("ReaShoot.app downloaded the recording, but did not report a local file path.");
    }
  });
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
  if (insertRecordedMedia(path, position, error)) {
    const char *status = g_lastAlignmentStatus.empty() ? "Recorded to ReaShoot track" : g_lastAlignmentStatus.c_str();
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
  [recorder() setStatus:@"Recorded to ReaShoot track; aligning audio"];
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
  return reashoot::core::isVideoPath(filePath);
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
  ShowMessageBox(g_lastAlignmentStatus.c_str(), "ReaShoot Alignment", 0);
}

void timerPoll() {
  if (!g_videoEnabled && !g_pendingInsert && !g_pendingAlignment) {
    g_previousPlayState = 0;
    return;
  }

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

    (void)playing;

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

  if (command == g_alignSelectedCommand) {
    alignSelectedVideoItem();
    return true;
  }

  if (command == g_toggleFollowCommand) {
    setFollowEnabled(!g_followEnabled);
    if (!g_followEnabled && g_activeTransportRecording) {
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
  return -1;
}

void cleanup() {
  if (g_activeTransportRecording) {
    stopTransportRecording();
  }
  if (DockWindowRemove && g_swellPanelPrototypeDocked && g_swellPanelPrototype) {
    DockWindowRemove(g_swellPanelPrototype);
    g_swellPanelPrototypeDocked = false;
  }
}

bool registerActions(reaper_plugin_info_t *rec) {
  custom_action_register_t videoEnabledAction = {
      0,
      "KLONG_REASHOOT_ENABLE",
      "ReaShoot: Enable ReaShoot",
      nullptr,
  };
  custom_action_register_t alignSelectedAction = {
      0,
      "KLONG_REASHOOT_ALIGN_SELECTED",
      "ReaShoot: Align Selected Video Item",
      nullptr,
  };
  custom_action_register_t toggleFollowAction = {
      0,
      "KLONG_REASHOOT_TOGGLE_FOLLOW",
      "ReaShoot: Enable/Disable Transport Follow",
      nullptr,
  };

  g_videoEnabledCommand = rec->Register("custom_action", &videoEnabledAction);
  g_alignSelectedCommand = rec->Register("custom_action", &alignSelectedAction);
  g_toggleFollowCommand = rec->Register("custom_action", &toggleFollowAction);

  return g_videoEnabledCommand != 0 && g_alignSelectedCommand != 0 && g_toggleFollowCommand != 0 &&
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

void migrateLegacyExtState() {
  for (const char *key : kExtStateKeys) {
    if (!reashoot::reaper::extState(kExtStateSection, key).empty()) {
      continue;
    }
    std::string legacy = reashoot::reaper::extState(kLegacyExtStateSection, key);
    if (!legacy.empty()) {
      reashoot::reaper::setExtState(kExtStateSection, key, legacy.c_str(), true);
    }
  }
}

void migrateLegacyToolbarActions() {
  std::string resourcePath = reashoot::reaper::resourcePath();
  if (resourcePath.empty()) {
    return;
  }

  NSString *menuPath = [stringFromStd(resourcePath) stringByAppendingPathComponent:@"reaper-menu.ini"];
  NSError *readError = nil;
  NSMutableString *contents =
      [NSMutableString stringWithContentsOfFile:menuPath encoding:NSUTF8StringEncoding error:&readError];
  if (!contents || readError) {
    return;
  }

  NSString *original = [contents copy];
  for (const ActionRename &rename : kActionRenames) {
    NSString *legacy = [NSString stringWithFormat:@"_%s", rename.legacy];
    NSString *current = [NSString stringWithFormat:@"_%s", rename.current];
    [contents replaceOccurrencesOfString:legacy
                              withString:current
                                 options:0
                                   range:NSMakeRange(0, contents.length)];
  }

  if (![contents isEqualToString:original]) {
    NSError *writeError = nil;
    if (![contents writeToFile:menuPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
      debugLog(@"Failed to migrate ReaShoot toolbar actions: %@", writeError.localizedDescription);
    }
  }
}

void loadSettings() {
  std::string follow = reashoot::reaper::extState(kExtStateSection, kFollowEnabledKey);
  if (!follow.empty()) {
    g_extensionController.setFollowEnabled(follow != "0");
    syncExtensionStateGlobals();
  }
  std::string desktopApi = reashoot::reaper::extState(kExtStateSection, kDesktopApiEnabledKey);
  if (!desktopApi.empty()) {
    g_desktopApiEnabled = desktopApi != "0";
  }
  std::string previewFloating = reashoot::reaper::extState(kExtStateSection, kPreviewFloatingKey);
  if (!previewFloating.empty()) {
    g_previewFloating = previewFloating != "0";
  }
  std::string iPhoneHost = reashoot::reaper::extState(kExtStateSection, kIPhoneHostKey);
  if (!iPhoneHost.empty()) {
    g_iPhoneHost = iPhoneHost;
  }
  std::string iPhoneControlPort = reashoot::reaper::extState(kExtStateSection, kIPhoneControlPortKey);
  if (!iPhoneControlPort.empty()) {
    g_iPhoneControlPort = iPhoneControlPort;
  }
  std::string iPhoneHttpPort = reashoot::reaper::extState(kExtStateSection, kIPhoneHttpPortKey);
  if (!iPhoneHttpPort.empty()) {
    g_iPhoneHttpPort = iPhoneHttpPort;
  }
  std::string iPhoneToken = reashoot::reaper::extState(kExtStateSection, kIPhoneTokenKey);
  if (!iPhoneToken.empty()) {
    g_iPhoneToken = iPhoneToken;
  }
  std::string iPhoneResolution = reashoot::reaper::extState(kExtStateSection, kIPhoneResolutionKey);
  if (!iPhoneResolution.empty()) {
    g_iPhoneResolution = iPhoneResolution;
  }
  std::string iPhoneFPS = reashoot::reaper::extState(kExtStateSection, kIPhoneFPSKey);
  if (!iPhoneFPS.empty()) {
    g_iPhoneFPS = iPhoneFPS;
  }
  std::string iPhoneOrientation = reashoot::reaper::extState(kExtStateSection, kIPhoneOrientationKey);
  if (!iPhoneOrientation.empty()) {
    g_iPhoneOrientation = iPhoneOrientation;
  }
  std::string iPhoneAspect = reashoot::reaper::extState(kExtStateSection, kIPhoneAspectKey);
  if (!iPhoneAspect.empty()) {
    g_iPhoneAspect = iPhoneAspect;
  }
  std::string iPhoneLens = reashoot::reaper::extState(kExtStateSection, kIPhoneLensKey);
  if (!iPhoneLens.empty()) {
    g_iPhoneLens = iPhoneLens;
  }
  std::string iPhoneZoom = reashoot::reaper::extState(kExtStateSection, kIPhoneZoomKey);
  if (!iPhoneZoom.empty()) {
    g_iPhoneZoom = iPhoneZoom;
  }
  std::string iPhoneLook = reashoot::reaper::extState(kExtStateSection, kIPhoneLookKey);
  if (!iPhoneLook.empty()) {
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

    migrateLegacyExtState();
    migrateLegacyToolbarActions();
    loadSettings();
    if (!registerActions(rec)) {
      showError("ReaShoot failed to register its actions.");
      return 0;
    }

    return 1;
  }
}

}
