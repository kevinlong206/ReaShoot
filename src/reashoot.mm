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

#include "core/alignment_math.h"
#include "core/capture_profile.h"
#include "core/helper_output_parser.h"
#include "core/path_utils.h"
#include "core/remote_camera.h"
#import "platform/mac/mac_h264_preview_renderer.h"
#include "platform/mac/mac_helper_process.h"
#include "platform/mac/mac_media_audio_reader.h"
#import "platform/mac/mac_modal_prompts.h"
#import "platform/mac/mac_playback_preview_renderer.h"
#import "platform/mac/mac_preview_stream_client.h"
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

#include "platform/swell/swell_panel_probe.h"

namespace {

constexpr const char *kExtStateSection = "klong_reashoot";
constexpr const char *kLegacyExtStateSection = "klong_reaper_video_recorder";
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
constexpr const char *kDockIdent = "klong_reashoot_preview";
constexpr const char *kVideoTrackName = "ReaShoot";
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
NSString *kDebugLogPath = @"/tmp/reashoot_debug.log";

constexpr const char *kExtStateKeys[] = {
    kFollowEnabledKey,
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
    {"KLONG_VIDEO_RECORDER_SHOW_PREVIEW", "KLONG_REASHOOT_SHOW_PREVIEW"},
    {"KLONG_VIDEO_RECORDER_FLOAT_PREVIEW", "KLONG_REASHOOT_FLOAT_PREVIEW"},
    {"KLONG_VIDEO_RECORDER_ALIGN_SELECTED", "KLONG_REASHOOT_ALIGN_SELECTED"},
    {"KLONG_VIDEO_RECORDER_RESTORE_IPHONE", "KLONG_REASHOOT_RESTORE_IPHONE"},
    {"KLONG_VIDEO_RECORDER_DELETE_ALL_IPHONE", "KLONG_REASHOOT_DELETE_ALL_IPHONE"},
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

NSArray<NSString *> *stringArrayFromStdVector(const std::vector<std::string> &values) {
  NSMutableArray<NSString *> *array = [NSMutableArray arrayWithCapacity:values.size()];
  for (const std::string &value : values) {
    [array addObject:stringFromStd(value)];
  }
  return array;
}

std::vector<std::string> stdVectorFromStringArray(NSArray<NSString *> *values) {
  std::vector<std::string> vector;
  vector.reserve(values.count);
  for (NSString *value in values) {
    vector.push_back(stdStringFromNSString(value ?: @""));
  }
  return vector;
}

NSDictionary<NSString *, NSString *> *dictionaryFromFields(const reashoot::core::FieldMap &fields) {
  NSMutableDictionary<NSString *, NSString *> *dictionary = [NSMutableDictionary dictionaryWithCapacity:fields.size()];
  for (const auto &entry : fields) {
    dictionary[stringFromStd(entry.first)] = stringFromStd(entry.second);
  }
  return dictionary;
}

std::string reashootHelperPath() {
  return stdStringFromNSString([NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/REAPER/UserPlugins/reashoot-mac"]);
}

reashoot::core::HelperProcess &helperProcess() {
  static std::unique_ptr<reashoot::core::HelperProcess> helper =
      reashoot::platform::mac::createHelperProcess(reashootHelperPath(), [](const std::string &message) {
        debugLog(@"%s", message.c_str());
      });
  return *helper;
}

reashoot::core::RemoteCameraController &remoteCameraController() {
  static reashoot::core::RemoteCameraController controller(helperProcess());
  return controller;
}

reashoot::core::MediaAudioReader &mediaAudioReader() {
  static std::unique_ptr<reashoot::core::MediaAudioReader> reader = reashoot::platform::mac::createMediaAudioReader();
  return *reader;
}

reaper_plugin_info_t *g_reaper = nullptr;
int g_videoEnabledCommand = 0;
int g_showPreviewCommand = 0;
int g_floatPreviewCommand = 0;
int g_alignSelectedCommand = 0;
int g_restoreIPhoneCommand = 0;
int g_deleteAllIPhoneCommand = 0;
int g_toggleFollowCommand = 0;
int g_swellPanelPrototypeCommand = 0;
int g_previousPlayState = 0;
HWND g_swellPanelPrototype = nullptr;
bool g_swellPanelPrototypeDocked = false;
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

  outputRoot = reashoot::reaper::projectPath(project);

  std::string projectFile;
  reashoot::reaper::currentProject(&projectFile);
  if (!projectFile.empty()) {
    projectName = reashoot::core::baseNameWithoutExtension(projectFile);
    if (outputRoot.empty()) {
      outputRoot = reashoot::core::directoryName(projectFile);
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
    if (!reashoot::core::isVideoPath(filePath)) {
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
bool toggleSwellPanelPrototype();

std::string followStatusText() {
  if (!g_videoEnabled) {
    return "Video disabled";
  }
  return std::string("Video enabled; transport follow ") + (g_followEnabled ? "on" : "off");
}

void setFollowEnabled(bool enabled) {
  g_followEnabled = enabled;
  reashoot::reaper::setExtState(kExtStateSection, kFollowEnabledKey, enabled ? "1" : "0", true);
  updateFollowStatusText();
  refreshToolbarState();
}

void setVideoEnabled(bool enabled);

} // namespace

@interface ReaShootRecorder : NSObject
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
@property(nonatomic, strong) ReaShootMacH264FrameDecoder *swellPreviewDecoder;
@property(nonatomic, strong) ReaShootMacPlaybackPreviewRenderer *playbackPreviewRenderer;
@property(nonatomic, strong) ReaShootMacPreviewStreamClient *previewStreamClient;
@property(nonatomic, assign) BOOL iPhonePreviewProfileConfiguring;
@property(nonatomic, assign) BOOL previewStreamStarting;
@property(nonatomic, assign) BOOL previewStreamActive;
@property(nonatomic, assign) BOOL previewStreamFailed;
@property(nonatomic, assign) BOOL swellPreviewReceivedAccessUnit;
@property(nonatomic, assign) BOOL swellPreviewReceivedFrame;
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
- (void)showIPhoneSetup:(id)sender;
- (void)restoreIPhoneRecording;
- (reashoot::core::RemoteCameraSettings)remoteCameraSettings;
- (NSDictionary<NSString *, NSString *> *)fieldsFromHelperLine:(NSString *)line;
- (NSArray<NSString *> *)iPhoneConfigureArguments;
- (void)startRemotePreview;
- (void)startSwellPreviewPrototype;
- (void)stopRemotePreview;
- (void)startPreviewStreamWithFields:(NSDictionary<NSString *, NSString *> *)fields;
- (void)stopPreviewStream;
- (void)handlePreviewAccessUnit:(NSData *)accessUnit;
- (NSString *)runReaShootCommand:(NSString *)command
                   extraArguments:(NSArray<NSString *> *)extraArguments
                            error:(NSError **)error;
- (std::shared_ptr<reashoot::core::AsyncCommandHandle>)runReaShootCommandAsync:(NSString *)command
                                                               extraArguments:(NSArray<NSString *> *)extraArguments
                                                                   completion:(void (^)(NSString *output, NSError *error))completion;
- (std::shared_ptr<reashoot::core::AsyncCommandHandle>)runReaShootCommandAsync:(NSString *)command
                                                               extraArguments:(NSArray<NSString *> *)extraArguments
                                                                outputHandler:(void (^)(NSString *line))outputHandler
                                                                   completion:(void (^)(NSString *output, NSError *error))completion;
- (void)handleReaShootProgressLine:(NSString *)line;
- (NSDictionary<NSString *, NSString *> *)recordingDescriptorFromReaShootOutput:(NSString *)output;
- (NSArray<NSDictionary<NSString *, NSString *> *> *)recordingDescriptorsFromReaShootOutput:(NSString *)output;
- (void)promptForStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording;
- (void)deleteIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording
                   completion:(void (^)(NSError *error))completion;
- (void)deleteAllPendingIPhoneRecordings;
- (void)finishIPhoneStopWithPath:(NSString *)path error:(NSError *)error;
@end

@implementation ReaShootRecorder

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
  });
}

- (void)startSwellPreviewPrototype {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self ensureDockView];
    self.showingPlayback = NO;
    [self.playbackPreviewRenderer hide];
    if (g_swellPanelPrototype) {
      reashoot::platform::swell::setSwellPanelPreviewPending(g_swellPanelPrototype);
    }
    [self startRemotePreview];
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
  reashoot::reaper::setExtState(kExtStateSection, kPreviewFloatingKey, g_previewFloating ? "1" : "0", true);
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

- (NSError *)errorFromHelperResult:(const reashoot::core::CommandResult &)result code:(NSInteger)code {
  if (result.exitCode == 0) {
    return nil;
  }
  NSString *message = result.errorMessage.empty() ? stringFromStd(result.output) : stringFromStd(result.errorMessage);
  if (message.length == 0) {
    message = @"reashoot-mac failed.";
  }
  return [NSError errorWithDomain:@"com.klong.reashoot"
                            code:code
                         userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (NSString *)runReaShootCommand:(NSString *)command
                   extraArguments:(NSArray<NSString *> *)extraArguments
                           error:(NSError **)error {
  reashoot::core::CommandResult result = remoteCameraController().run([self remoteCameraSettings],
                                                                      stdStringFromNSString(command ?: @""),
                                                                      stdVectorFromStringArray(extraArguments ?: @[]));
  NSError *commandError = [self errorFromHelperResult:result code:20];
  if (commandError) {
    if (error) {
      *error = commandError;
    }
    return nil;
  }
  return stringFromStd(result.output);
}

- (std::shared_ptr<reashoot::core::AsyncCommandHandle>)runReaShootCommandAsync:(NSString *)command
                                                               extraArguments:(NSArray<NSString *> *)extraArguments
                                                                   completion:(void (^)(NSString *output, NSError *error))completion {
  return [self runReaShootCommandAsync:command extraArguments:extraArguments outputHandler:nil completion:completion];
}

- (std::shared_ptr<reashoot::core::AsyncCommandHandle>)runReaShootCommandAsync:(NSString *)command
                                                               extraArguments:(NSArray<NSString *> *)extraArguments
                                                                outputHandler:(void (^)(NSString *line))outputHandler
                                                                   completion:(void (^)(NSString *output, NSError *error))completion {
  std::string commandText = stdStringFromNSString(command ?: @"");
  ReaShootRecorder *recorder = self;
  return remoteCameraController().runAsync([self remoteCameraSettings],
                                          commandText,
                                          stdVectorFromStringArray(extraArguments ?: @[]),
                                          outputHandler ? [outputHandler](const std::string &line) {
                                            outputHandler(stringFromStd(line));
                                          }
                                                        : reashoot::core::ProgressCallback(),
                                          [recorder, completion](reashoot::core::CommandResult result) {
                                            NSError *commandError = [recorder errorFromHelperResult:result code:21];
                                            completion(stringFromStd(result.output), commandError);
                                          });
}

- (BOOL)startIPhoneRecordingWithSuggestedPath:(const std::string &)path
                             startCompletion:(void (^)(void))startCompletion
                                        error:(NSError **)error {
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    if (error) {
      *error = [NSError errorWithDomain:@"com.klong.reashoot"
                                  code:22
                              userInfo:@{NSLocalizedDescriptionKey: @"Set the iPhone host and pairing token before recording."}];
    }
    return NO;
  }

  if (![self runReaShootCommand:@"configure" extraArguments:[self iPhoneConfigureArguments] error:error]) {
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

  NSString *sessionID = [NSString stringWithFormat:@"reaper-%s", reashoot::core::timestampString().c_str()];
  NSArray<NSString *> *arguments =
      stringArrayFromStdVector(reashoot::core::startArguments([self remoteCameraSettings], stdStringFromNSString(sessionID)));
  if (![self runReaShootCommand:@"start" extraArguments:arguments error:error]) {
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

- (NSString *)downloadedPathFromReaShootOutput:(NSString *)output {
  std::string path = reashoot::core::parseDownloadedPath(output.UTF8String ?: "");
  return path.empty() ? nil : stringFromStd(path);
}

- (NSDictionary<NSString *, NSString *> *)recordingDescriptorFromReaShootOutput:(NSString *)output {
  std::vector<reashoot::core::FieldMap> recordings = reashoot::core::parseRecordings(output.UTF8String ?: "");
  if (recordings.empty()) {
    return nil;
  }
  return dictionaryFromFields(recordings.front());
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)recordingDescriptorsFromReaShootOutput:(NSString *)output {
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *recordings = [NSMutableArray array];
  for (const reashoot::core::FieldMap &fields : reashoot::core::parseRecordings(output.UTF8String ?: "")) {
    [recordings addObject:dictionaryFromFields(fields)];
  }
  return recordings;
}

- (void)handleReaShootProgressLine:(NSString *)line {
  if ([line hasPrefix:@"encode "]) {
    NSDictionary<NSString *, NSString *> *fields =
        dictionaryFromFields(reashoot::core::parseFields(line.UTF8String ?: "", ' '));
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
  NSDictionary<NSString *, NSString *> *fields =
      dictionaryFromFields(reashoot::core::parseFields(line.UTF8String ?: "", ' '));
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
  reashoot::core::RemoteRecordingDescriptor descriptor;
  descriptor.id = stdStringFromNSString(recording[@"id"] ?: @"");
  descriptor.filename = stdStringFromNSString(recording[@"filename"] ?: @"recording.mov");
  descriptor.byteCount = stdStringFromNSString(recording[@"byteCount"] ?: @"0");
  descriptor.downloadPath = stdStringFromNSString(recording[@"downloadPath"] ?: @"");
  descriptor.checksum = stdStringFromNSString(recording[@"checksum"] ?: @"");
  NSArray<NSString *> *arguments = stringArrayFromStdVector(
      reashoot::core::downloadArguments([self remoteCameraSettings], descriptor, stdStringFromNSString(directory ?: NSHomeDirectory())));
  [self setStatus:@"Downloading iPhone video"];
  __block NSDate *lastProgressDate = [NSDate date];
  __block std::shared_ptr<reashoot::core::AsyncCommandHandle> downloadTask;
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
  downloadTask = [self runReaShootCommandAsync:@"download-recording" extraArguments:arguments outputHandler:^(NSString *line) {
    lastProgressDate = [NSDate date];
    debugLog(@"download progress line=%@", line ?: @"");
    [self handleReaShootProgressLine:line];
  } completion:^(NSString *output, NSError *error) {
    cancelWatchdog();
    if (error) {
      debugLog(@"download failed error=%@ output=%@", error.localizedDescription ?: @"", output ?: @"");
      [self setStatus:@"iPhone download failed"];
      completion(nil, error);
      return;
    }
    NSString *path = [self downloadedPathFromReaShootOutput:output ?: @""];
    NSError *missingPathError = nil;
    if (path.length == 0) {
      missingPathError = [NSError errorWithDomain:@"com.klong.reashoot"
                                             code:23
                                         userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording downloaded, but reashoot-mac did not report a file path."}];
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
      if (!downloadTask || !downloadTask->isRunning()) {
        debugLog(@"download watchdog stopping; task finished or missing");
        cancelWatchdog();
        return;
      }
      if ([[NSDate date] timeIntervalSinceDate:lastProgressDate] > 180.0) {
        [self setStatus:@"iPhone download stalled; retry from Pending"];
        debugLog(@"download watchdog terminating stalled helper pid=%d", downloadTask->processIdentifier());
        downloadTask->terminate();
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
    NSError *error = [NSError errorWithDomain:@"com.klong.reashoot"
                                         code:24
                                     userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording stopped, but reashoot-mac did not report a recording ID to delete."}];
    if (completion) {
      completion(error);
    }
    return;
  }
  [self setStatus:@"Deleting iPhone video"];
  NSArray<NSString *> *arguments =
      stringArrayFromStdVector(reashoot::core::recordingIDArguments([self remoteCameraSettings], stdStringFromNSString(recordingID)));
  [self runReaShootCommandAsync:@"delete-recording" extraArguments:arguments completion:^(NSString *output, NSError *error) {
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

- (void)restoreIPhoneRecording {
  [self persistIPhoneSettings];
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    [self setStatus:@"Set iPhone host and token before restore"];
    return;
  }

  [self setStatus:@"Checking iPhone recordings"];
  [self runReaShootCommandAsync:@"list-recordings"
                  extraArguments:stringArrayFromStdVector(reashoot::core::tokenArguments([self remoteCameraSettings]))
                      completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone recording list failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone recording list failed.");
      return;
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *recordings = [self recordingDescriptorsFromReaShootOutput:output ?: @""];
    if (recordings.count == 0) {
      [self setStatus:@"No pending iPhone recordings"];
      showError("No pending iPhone recordings were found on the phone.");
      return;
    }

    NSDictionary<NSString *, id> *choice = [ReaShootMacModalPrompts choosePendingRecordingAction:recordings];
    if (!choice) {
      [self setStatus:@"Restore canceled"];
      return;
    }
    NSDictionary<NSString *, NSString *> *recording = choice[@"recording"];
    NSString *action = choice[@"action"];
    if ([action isEqualToString:@"delete"]) {
      NSString *filename = recording[@"filename"] ?: recording[@"id"] ?: @"the selected iPhone video";
      if (![ReaShootMacModalPrompts confirmDeleteRecordingNamed:filename]) {
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
      double position = reashoot::reaper::cursorPosition(project);
      std::string insertError;
      if (insertRecordedMedia(path.UTF8String ?: "", position, insertError)) {
        const char *status = g_lastAlignmentStatus.empty() ? "Restored iPhone recording to ReaShoot track" : g_lastAlignmentStatus.c_str();
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
  [self runReaShootCommandAsync:@"list-recordings"
                  extraArguments:stringArrayFromStdVector(reashoot::core::tokenArguments([self remoteCameraSettings]))
                      completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone recording list failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone recording list failed.");
      return;
    }

    NSArray<NSDictionary<NSString *, NSString *> *> *recordings = [self recordingDescriptorsFromReaShootOutput:output ?: @""];
    if (recordings.count == 0) {
      [self setStatus:@"No pending iPhone recordings"];
      showError("No pending iPhone recordings were found on the phone.");
      return;
    }

    if (![ReaShootMacModalPrompts confirmDeleteAllRecordingsCount:recordings.count]) {
      [self setStatus:@"Delete all canceled"];
      return;
    }

    [self deletePendingIPhoneRecordings:recordings index:0 deleted:0];
  }];
}

- (void)promptForStoppedIPhoneRecording:(NSDictionary<NSString *, NSString *> *)recording {
  NSString *filename = recording[@"filename"] ?: @"the stopped iPhone video";
  ReaShootStoppedRecordingChoice choice = [ReaShootMacModalPrompts chooseStoppedRecordingActionForFilename:filename];
  if (choice == ReaShootStoppedRecordingChoiceDownload) {
    [self downloadStoppedIPhoneRecording:recording];
    return;
  }
  [self deleteStoppedIPhoneRecording:recording];
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
  NSArray<NSString *> *arguments = stringArrayFromStdVector(reashoot::core::stopArguments([self remoteCameraSettings]));
  [self runReaShootCommandAsync:@"stop-only" extraArguments:arguments completion:^(NSString *output, NSError *error) {
    self.remoteRecording = NO;
    [self setRecordingVisualState:NO];
    if (error) {
      [self setStatus:@"iPhone stop failed"];
      [self finishIPhoneStopWithPath:nil error:error];
      return;
    }
    NSDictionary<NSString *, NSString *> *recording = [self recordingDescriptorFromReaShootOutput:output ?: @""];
    if (!recording) {
      NSError *descriptorError = [NSError errorWithDomain:@"com.klong.reashoot"
                                                     code:25
                                                 userInfo:@{NSLocalizedDescriptionKey: @"The iPhone recording stopped, but reashoot-mac did not report recording details."}];
      [self finishIPhoneStopWithPath:nil error:descriptorError];
      return;
    }
    [self promptForStoppedIPhoneRecording:recording];
  }];
}

- (void)updateCaptureFormatLabel {
  NSString *previewState = self.previewStreamActive ? @"H.264 preview" : (self.previewStreamStarting ? @"preview connecting" : @"preview idle");
  NSString *format = [NSString stringWithFormat:@"iPhone %@: %s %@ fps, %s, %s, %s lens, %sx, look %s, %@",
                                                @"Wi-Fi",
                                                g_iPhoneResolution.c_str(),
                                                [NSString stringWithUTF8String:g_iPhoneFPS.c_str()],
                                                g_iPhoneOrientation.c_str(),
                                                g_iPhoneAspect.c_str(),
                                                g_iPhoneLens.c_str(),
                                                g_iPhoneZoom.c_str(),
                                                g_iPhoneLook.c_str(),
                                                previewState];
  if (self.formatLabel) {
    self.formatLabel.stringValue = format;
  }
  if (g_swellPanelPrototype) {
    reashoot::platform::swell::updateSwellPanelProbe(g_swellPanelPrototype,
                                                     self.statusLabel ? self.statusLabel.stringValue.UTF8String : followStatusText().c_str(),
                                                     format.UTF8String,
                                                     g_iPhoneHost.c_str(),
                                                     g_iPhoneToken.c_str());
  }
  [self updateRecordingTextColor];
}

- (void)persistIPhoneSettings {
  reashoot::platform::swell::SwellPanelSettings swellSettings = reashoot::platform::swell::swellPanelSettings(g_swellPanelPrototype);
  if (swellSettings.host[0] != '\0') {
    g_iPhoneHost = swellSettings.host;
  }
  if (swellSettings.token[0] != '\0') {
    g_iPhoneToken = swellSettings.token;
  }
  NSTextField *hostField = self.iPhoneSetupWindow.visible && self.iPhoneSetupHostField ? self.iPhoneSetupHostField : self.iPhoneHostField;
  NSTextField *tokenField = self.iPhoneSetupWindow.visible && self.iPhoneSetupTokenField ? self.iPhoneSetupTokenField : self.iPhoneTokenField;
  if (hostField) {
    g_iPhoneHost = hostField.stringValue.UTF8String ?: "";
  }
  if (tokenField) {
    g_iPhoneToken = tokenField.stringValue.UTF8String ?: "";
  }
  if (self.iPhoneHostField) self.iPhoneHostField.stringValue = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
  if (self.iPhoneTokenField) self.iPhoneTokenField.stringValue = [NSString stringWithUTF8String:g_iPhoneToken.c_str()];
  if (self.iPhoneSetupHostField) self.iPhoneSetupHostField.stringValue = [NSString stringWithUTF8String:g_iPhoneHost.c_str()];
  if (self.iPhoneSetupTokenField) self.iPhoneSetupTokenField.stringValue = [NSString stringWithUTF8String:g_iPhoneToken.c_str()];
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
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneHostKey, g_iPhoneHost.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneTokenKey, g_iPhoneToken.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneControlPortKey, g_iPhoneControlPort.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneHttpPortKey, g_iPhoneHttpPort.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneResolutionKey, g_iPhoneResolution.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneFPSKey, g_iPhoneFPS.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneOrientationKey, g_iPhoneOrientation.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneAspectKey, g_iPhoneAspect.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneLensKey, g_iPhoneLens.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneZoomKey, g_iPhoneZoom.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneLookKey, g_iPhoneLook.c_str(), true);
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
  [self setStatus:@"Configuring iPhone profile"];
  self.iPhonePreviewProfileConfiguring = YES;
  [self runReaShootCommandAsync:@"configure" extraArguments:[self iPhoneConfigureArguments] completion:^(NSString *output, NSError *error) {
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

- (reashoot::core::RemoteCameraSettings)remoteCameraSettings {
  reashoot::core::RemoteCameraSettings settings;
  settings.host = g_iPhoneHost;
  settings.controlPort = g_iPhoneControlPort;
  settings.httpPort = g_iPhoneHttpPort;
  settings.token = g_iPhoneToken;
  settings.resolution = g_iPhoneResolution;
  settings.fps = g_iPhoneFPS;
  settings.orientation = g_iPhoneOrientation;
  settings.aspect = g_iPhoneAspect;
  settings.lens = g_iPhoneLens;
  settings.zoom = g_iPhoneZoom;
  settings.look = g_iPhoneLook;
  return settings;
}

- (NSArray<NSString *> *)iPhoneConfigureArguments {
  return stringArrayFromStdVector(reashoot::core::configureArguments([self remoteCameraSettings]));
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
  NSDictionary<NSString *, NSString *> *fields =
      dictionaryFromFields(reashoot::core::parseFirstDevice(output.UTF8String ?: ""));
  NSString *host = fields[@"host"];
  NSString *controlPort = fields[@"controlPort"];
  NSString *httpPort = fields[@"httpPort"];
  if (host.length == 0) {
    return NO;
  }
  g_iPhoneHost = host.UTF8String;
  if (controlPort.length > 0) {
    g_iPhoneControlPort = controlPort.UTF8String;
  }
  if (httpPort.length > 0) {
    g_iPhoneHttpPort = httpPort.UTF8String;
  }
  if (self.iPhoneHostField) self.iPhoneHostField.stringValue = host;
  if (self.iPhoneSetupHostField) self.iPhoneSetupHostField.stringValue = host;
  [self persistIPhoneSettings];
  [self setStatus:[NSString stringWithFormat:@"Found iPhone: %@", fields[@"name"] ?: host]];
  return YES;
}

- (void)discoverIPhone:(id)sender {
  (void)sender;
  [self setStatus:@"Searching for ReaShoot"];
  [self runReaShootCommandAsync:@"discover" extraArguments:@[ @"--timeout", @"3" ] completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone discovery failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone discovery failed.");
      return;
    }
    if (![self applyFirstDiscoveredIPhoneFromOutput:output ?: @""]) {
      if (g_iPhoneHost.empty()) {
        g_iPhoneHost = kDefaultIPhoneHost;
        if (self.iPhoneHostField) self.iPhoneHostField.stringValue = [NSString stringWithUTF8String:kDefaultIPhoneHost];
        if (self.iPhoneSetupHostField) self.iPhoneSetupHostField.stringValue = [NSString stringWithUTF8String:kDefaultIPhoneHost];
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
  NSString *code = codeField ? codeField.stringValue : [NSString stringWithUTF8String:reashoot::platform::swell::swellPanelSettings(g_swellPanelPrototype).pairingCode];
  if (g_iPhoneHost.empty() || code.length == 0) {
    [self setStatus:@"Enter iPhone host and pairing code"];
    return;
  }
  [self setStatus:@"Pairing with iPhone"];
  [self runReaShootCommandAsync:@"pair" extraArguments:@[ @"--code", code ] completion:^(NSString *output, NSError *error) {
    if (error) {
      [self setStatus:@"iPhone pairing failed"];
      showError(error.localizedDescription.UTF8String ?: "iPhone pairing failed.");
      return;
    }
    NSString *prefix = @"paired token=";
    for (NSString *line in [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
      if ([line hasPrefix:prefix]) {
        NSString *token = [line substringFromIndex:prefix.length];
        if (self.iPhoneTokenField) self.iPhoneTokenField.stringValue = token;
        if (self.iPhoneSetupTokenField) self.iPhoneSetupTokenField.stringValue = token;
        g_iPhoneToken = token.UTF8String ?: "";
        [self persistIPhoneSettings];
        reashoot::platform::swell::updateSwellPanelProbe(g_swellPanelPrototype, "iPhone paired", nullptr, g_iPhoneHost.c_str(), g_iPhoneToken.c_str());
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
  NSArray<NSString *> *arguments = @[];
  if (!g_iPhoneToken.empty()) {
    arguments = stringArrayFromStdVector(reashoot::core::tokenArguments([self remoteCameraSettings]));
  }
  [self setStatus:@"Testing iPhone connection"];
  [self runReaShootCommandAsync:@"ping" extraArguments:arguments completion:^(NSString *output, NSError *error) {
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
  [self ensureDockView];
  [self setStatus:@"Use SWELL host/token/code fields, then Discover, Pair, or Test"];
}

- (void)selectRelativeIPhoneLook:(NSInteger)offset {
  if (!self.iPhoneLookPopup) {
    static const char *looks[] = {"natural", "warmVintage", "coolBlue", "highContrastBW", "fadedFilm", "dreamGlow", "noir",
                                  "saturatedPop", "bleachBypass", "sepia", "instantPhoto", "chrome", "tonal", "silvertone",
                                  "dramaticWarm", "dramaticCool", "softMatte", "comicBook", "vhs", "musicVideoPop"};
    int selectedIndex = 0;
    const int count = static_cast<int>(sizeof(looks) / sizeof(looks[0]));
    for (int i = 0; i < count; ++i) {
      if (g_iPhoneLook == looks[i]) {
        selectedIndex = i;
        break;
      }
    }
    int nextIndex = (selectedIndex + static_cast<int>(offset)) % count;
    if (nextIndex < 0) nextIndex += count;
    g_iPhoneLook = looks[nextIndex];
    [self profileSelectionChanged:nil];
    return;
  }
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
  if (!g_swellPanelPrototype) {
    reashoot::platform::swell::SwellPanelCallbacks callbacks;
    callbacks.context = (__bridge void *)self;
    callbacks.setup = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target showIPhoneSetup:nil]; });
    };
    callbacks.discover = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target discoverIPhone:nil]; });
    };
    callbacks.pair = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target pairIPhone:nil]; });
    };
    callbacks.testConnection = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target testIPhoneConnection:nil]; });
    };
    callbacks.restorePending = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target restoreIPhoneRecording]; });
    };
    callbacks.deleteAllPending = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target deleteAllPendingIPhoneRecordings]; });
    };
    callbacks.previousLook = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target previousIPhoneLook:nil]; });
    };
    callbacks.nextLook = [](void *context) {
      ReaShootRecorder *target = (__bridge ReaShootRecorder *)context;
      dispatch_async(dispatch_get_main_queue(), ^{ [target nextIPhoneLook:nil]; });
    };
    g_swellPanelPrototype = reashoot::platform::swell::createSwellPanelProbe(nullptr, callbacks);
    reashoot::platform::swell::updateSwellPanelProbe(g_swellPanelPrototype, followStatusText().c_str(), nullptr, g_iPhoneHost.c_str(), g_iPhoneToken.c_str());
    __weak ReaShootRecorder *weakSelf = self;
    self.swellPreviewDecoder = [[ReaShootMacH264FrameDecoder alloc] initWithFrameHandler:^(const void *pixels, int width, int height, int strideBytes) {
      ReaShootRecorder *strongSelf = weakSelf;
      if (strongSelf && !strongSelf.swellPreviewReceivedFrame) {
        strongSelf.swellPreviewReceivedFrame = YES;
        [strongSelf setStatus:@"Preview: SWELL live video"];
      }
      if (g_swellPanelPrototypeDocked && g_swellPanelPrototype) {
        reashoot::platform::swell::setSwellPanelPreviewFrame(g_swellPanelPrototype, pixels, width, height, strideBytes);
      }
    }];
    self.playbackPreviewRenderer = [[ReaShootMacPlaybackPreviewRenderer alloc] initWithFrameHandler:^(const void *pixels, int width, int height, int strideBytes) {
      if (g_swellPanelPrototype) {
        reashoot::platform::swell::setSwellPanelPreviewFrame(g_swellPanelPrototype, pixels, width, height, strideBytes);
      }
    }];
    self.previewStreamClient = [[ReaShootMacPreviewStreamClient alloc] init];
    [self updateCaptureFormatLabel];
  }
}

- (void)startRemotePreview {
  [self persistIPhoneSettings];
  if (!self.previewStreamClient) {
    self.previewStreamClient = [[ReaShootMacPreviewStreamClient alloc] init];
  }
  if (!self.swellPreviewDecoder) {
    __weak ReaShootRecorder *weakSelf = self;
    self.swellPreviewDecoder = [[ReaShootMacH264FrameDecoder alloc] initWithFrameHandler:^(const void *pixels, int width, int height, int strideBytes) {
      ReaShootRecorder *strongSelf = weakSelf;
      if (strongSelf && !strongSelf.swellPreviewReceivedFrame) {
        strongSelf.swellPreviewReceivedFrame = YES;
        [strongSelf setStatus:@"Preview: SWELL live video"];
      }
      if (g_swellPanelPrototypeDocked && g_swellPanelPrototype) {
        reashoot::platform::swell::setSwellPanelPreviewFrame(g_swellPanelPrototype, pixels, width, height, strideBytes);
      }
    }];
  }
  if (!self.previewStreamClient.isRunning && !self.previewStreamStarting) {
    self.previewStreamFailed = NO;
    self.previewStreamFailureReason = nil;
  }
  if (self.iPhonePreviewProfileConfiguring) {
    return;
  }
  if (!g_iPhoneHost.empty() && !g_iPhoneToken.empty()) {
    self.iPhonePreviewProfileConfiguring = YES;
    [self setStatus:@"Configuring iPhone preview"];
    [self runReaShootCommandAsync:@"configure" extraArguments:[self iPhoneConfigureArguments] completion:^(NSString *output, NSError *error) {
      self.iPhonePreviewProfileConfiguring = NO;
      if (error) {
        [self setStatus:@"iPhone preview configure failed"];
        return;
      }
      NSString *message = [output stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (message.length > 0 && !self.previewStreamClient.isRunning && !self.previewStreamStarting) {
        [self setStatus:message];
      }
      [self runReaShootCommandAsync:@"start-preview"
                       extraArguments:stringArrayFromStdVector(reashoot::core::tokenArguments([self remoteCameraSettings]))
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
    [self runReaShootCommandAsync:@"stop-preview"
                    extraArguments:stringArrayFromStdVector(reashoot::core::tokenArguments([self remoteCameraSettings]))
                        completion:^(NSString *output, NSError *error) {
      (void)output;
      (void)error;
    }];
  }
}

- (void)startPreviewStreamWithFields:(NSDictionary<NSString *, NSString *> *)fields {
  if (self.showingPlayback || self.previewStreamClient.isRunning || self.previewStreamStarting || self.previewStreamFailed) {
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

  __weak ReaShootRecorder *weakSelf = self;
  BOOL started = [self.previewStreamClient startWithHost:[NSString stringWithUTF8String:g_iPhoneHost.c_str()]
                                                    port:port
                                                    path:streamPath
                                                   token:[NSString stringWithUTF8String:g_iPhoneToken.c_str()]
                                                  onData:^(NSData *accessUnit) {
    [weakSelf handlePreviewAccessUnit:accessUnit];
  }
                                                onActive:^{
    ReaShootRecorder *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf.previewStreamStarting = NO;
    strongSelf.previewStreamActive = YES;
    [strongSelf setStatus:@"Preview: H.264 stream"];
    [strongSelf updateCaptureFormatLabel];
  }
                                                 onError:^(NSError *error) {
    ReaShootRecorder *strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf.previewStreamStarting = NO;
    strongSelf.previewStreamActive = NO;
    strongSelf.previewStreamFailed = YES;
    strongSelf.previewStreamFailureReason = error.localizedDescription ?: @"Preview stream failed";
    if (!strongSelf.showingPlayback && !strongSelf.recordingVisualState) {
      [strongSelf setStatus:@"Preview: stream disconnected"];
    }
  }];
  if (!started) {
    self.previewStreamFailed = YES;
    self.previewStreamFailureReason = @"Invalid preview URL";
    [self setStatus:@"Preview: invalid stream URL"];
    return;
  }

  self.previewStreamStarting = YES;
  self.previewStreamActive = NO;
  self.previewStreamFailureReason = nil;
  self.swellPreviewReceivedAccessUnit = NO;
  self.swellPreviewReceivedFrame = NO;
  [self.swellPreviewDecoder reset];
  [self setStatus:@"Preview: connecting H.264 stream"];
}

- (void)stopPreviewStream {
  self.previewStreamStarting = NO;
  self.previewStreamActive = NO;
  self.swellPreviewReceivedAccessUnit = NO;
  self.swellPreviewReceivedFrame = NO;
  [self.previewStreamClient stop];
  [self.swellPreviewDecoder reset];
}

- (void)handlePreviewAccessUnit:(NSData *)accessUnit {
  if (!self.swellPreviewReceivedAccessUnit) {
    self.swellPreviewReceivedAccessUnit = YES;
    [self setStatus:@"Preview: H.264 received; decoding for SWELL"];
  }
  [self.swellPreviewDecoder decodeAccessUnit:accessUnit];
}

- (void)showLivePreview {
  self.showingPlayback = NO;
  [self.playbackPreviewRenderer hide];
  [self startRemotePreview];
}

- (void)updatePlaybackWithPath:(const std::string &)path
                     itemStart:(double)itemStart
                   sourceOffset:(double)sourceOffset
                projectPosition:(double)projectPosition {
  [self ensureDockView];
  const BOOL enteringPlayback = !self.showingPlayback;
  self.showingPlayback = YES;
  if (self.playbackPreviewRenderer) {
    if (enteringPlayback) {
      [self stopRemotePreview];
    }
    [self.playbackPreviewRenderer showPath:[NSString stringWithUTF8String:path.c_str()]
                                itemStart:itemStart
                             sourceOffset:sourceOffset
                           projectPosition:projectPosition];
    [self setStatus:@"Playback"];
  } else {
    (void)path;
    (void)itemStart;
    (void)sourceOffset;
    (void)projectPosition;
    [self setStatus:@"Playback preview pending SWELL implementation"];
  }
}

- (void)stopPlaybackAndShowLive {
  if (!self.showingPlayback) {
    return;
  }
  [self showLivePreview];
  [self setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
}

- (void)showDockedPreview {
  [self ensureDockView];
  if (!DockWindowAddEx || !g_swellPanelPrototype) {
    return;
  }
  if (!self.docked) {
    DockWindowAddEx(g_swellPanelPrototype, "ReaShoot", kDockIdent, true);
    self.docked = YES;
    g_swellPanelPrototypeDocked = true;
  }
  if (DockWindowActivate) {
    DockWindowActivate(g_swellPanelPrototype);
  }
  if (DockWindowRefreshForHWND) {
    DockWindowRefreshForHWND(g_swellPanelPrototype);
  }
}

- (void)showFloatingPreview {
  [self showDockedPreview];
  [self setStatus:@"SWELL preview uses REAPER dock"];
}

- (void)hideFloatingPreview {
  self.floatingPreviewWindow = nil;
}

- (void)hideDockedPreview {
  if (DockWindowRemove && self.docked && g_swellPanelPrototype) {
    DockWindowRemove(g_swellPanelPrototype);
  }
  self.docked = NO;
  g_swellPanelPrototypeDocked = false;
}

- (void)setStatus:(NSString *)status {
  NSString *statusText = status ?: @"Idle";
  if (self.statusLabel) {
    self.statusLabel.stringValue = statusText;
  }
  if (g_swellPanelPrototype) {
    if ([statusText hasPrefix:@"Preview:"] && ![statusText isEqualToString:@"Preview: SWELL live video"]) {
      reashoot::platform::swell::setSwellPanelPreviewPending(g_swellPanelPrototype, statusText.UTF8String);
    }
    reashoot::platform::swell::updateSwellPanelProbe(g_swellPanelPrototype,
                                                     statusText.UTF8String,
                                                     nullptr,
                                                     g_iPhoneHost.c_str(),
                                                     g_iPhoneToken.c_str());
  }
  [self updateRecordingTextColor];
}

- (void)setRecordingVisualState:(BOOL)recording {
  _recordingVisualState = recording;
  [self updateRecordingTextColor];
}

- (void)updateRecordingTextColor {
  if (!self.statusLabel || !self.formatLabel) {
    return;
  }
  NSColor *color = _recordingVisualState ? NSColor.systemRedColor : NSColor.labelColor;
  self.statusLabel.textColor = color;
  self.formatLabel.textColor = color;
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
  g_recordStartPosition = reashoot::reaper::cursorPosition(project);
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

bool toggleSwellPanelPrototype() {
  [recorder() togglePreview];
  return true;
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

  if (command == g_swellPanelPrototypeCommand) {
    return toggleSwellPanelPrototype();
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
  if (command == g_swellPanelPrototypeCommand) {
    return g_swellPanelPrototypeDocked ? 1 : 0;
  }
  return -1;
}

void cleanup() {
  if (recorder().isRecording) {
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
      "ReaShoot: Enable/Disable ReaShoot",
      nullptr,
  };
  custom_action_register_t showPreviewAction = {
      0,
      "KLONG_REASHOOT_SHOW_PREVIEW",
      "ReaShoot: Show/Hide Preview",
      nullptr,
  };
  custom_action_register_t floatPreviewAction = {
      0,
      "KLONG_REASHOOT_FLOAT_PREVIEW",
      "ReaShoot: Float/Dock Preview",
      nullptr,
  };
  custom_action_register_t alignSelectedAction = {
      0,
      "KLONG_REASHOOT_ALIGN_SELECTED",
      "ReaShoot: Align Selected Video Item",
      nullptr,
  };
  custom_action_register_t restoreIPhoneAction = {
      0,
      "KLONG_REASHOOT_RESTORE_IPHONE",
      "ReaShoot: Restore Pending iPhone Recording",
      nullptr,
  };
  custom_action_register_t deleteAllIPhoneAction = {
      0,
      "KLONG_REASHOOT_DELETE_ALL_IPHONE",
      "ReaShoot: Delete All Pending iPhone Recordings",
      nullptr,
  };
  custom_action_register_t toggleFollowAction = {
      0,
      "KLONG_REASHOOT_TOGGLE_FOLLOW",
      "ReaShoot: Enable/Disable Transport Follow",
      nullptr,
  };
  custom_action_register_t swellPanelPrototypeAction = {
      0,
      "KLONG_REASHOOT_SWELL",
        "ReaShoot: Show/Hide SWELL Panel",
      nullptr,
  };

  g_videoEnabledCommand = rec->Register("custom_action", &videoEnabledAction);
  g_showPreviewCommand = rec->Register("custom_action", &showPreviewAction);
  g_floatPreviewCommand = rec->Register("custom_action", &floatPreviewAction);
  g_alignSelectedCommand = rec->Register("custom_action", &alignSelectedAction);
  g_restoreIPhoneCommand = rec->Register("custom_action", &restoreIPhoneAction);
  g_deleteAllIPhoneCommand = rec->Register("custom_action", &deleteAllIPhoneAction);
  g_toggleFollowCommand = rec->Register("custom_action", &toggleFollowAction);
  g_swellPanelPrototypeCommand = rec->Register("custom_action", &swellPanelPrototypeAction);
  if (g_swellPanelPrototypeCommand == 0) {
    debugLog(@"Failed to register SWELL panel prototype action");
  }

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
    g_followEnabled = follow != "0";
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
