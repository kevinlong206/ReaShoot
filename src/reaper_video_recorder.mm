#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <ctime>
#include <limits>
#include <string>
#include <vector>

#define REAPERAPI_IMPLEMENT
#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_AddMediaItemToTrack
#define REAPERAPI_WANT_AddTakeToMediaItem
#define REAPERAPI_WANT_CountMediaItems
#define REAPERAPI_WANT_CountTracks
#define REAPERAPI_WANT_CountTrackMediaItems
#define REAPERAPI_WANT_DockWindowActivate
#define REAPERAPI_WANT_DockWindowAddEx
#define REAPERAPI_WANT_DockWindowRefreshForHWND
#define REAPERAPI_WANT_DockWindowRemove
#define REAPERAPI_WANT_EnumProjects
#define REAPERAPI_WANT_GetActiveTake
#define REAPERAPI_WANT_GetCursorPositionEx
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_GetMediaItemInfo_Value
#define REAPERAPI_WANT_GetMediaItem
#define REAPERAPI_WANT_GetMediaItemTake_Source
#define REAPERAPI_WANT_GetMediaItemTake_Peaks
#define REAPERAPI_WANT_GetMediaItemTakeInfo_Value
#define REAPERAPI_WANT_GetMediaItemTrack
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
#define REAPERAPI_WANT_PCM_Source_BuildPeaks
#define REAPERAPI_WANT_PCM_Source_CreateFromFile
#define REAPERAPI_WANT_RefreshToolbar2
#define REAPERAPI_WANT_SetExtState
#define REAPERAPI_WANT_SetMediaItemInfo_Value
#define REAPERAPI_WANT_SetMediaItemSelected
#define REAPERAPI_WANT_SetMediaItemTake_Source
#define REAPERAPI_WANT_SetMediaTrackInfo_Value
#define REAPERAPI_WANT_ShowMessageBox
#define REAPERAPI_WANT_UpdateArrange
#define REAPERAPI_WANT_UpdateTimeline
#include "reaper_plugin_functions.h"

namespace {

constexpr const char *kExtStateSection = "klong_reaper_video_recorder";
constexpr const char *kFollowEnabledKey = "follow_enabled";
constexpr const char *kSelectedDeviceKey = "selected_device_unique_id";
constexpr const char *kDockIdent = "klong_reaper_video_recorder_preview";
constexpr const char *kVideoTrackName = "Video Recorder";
constexpr int kRecordBit = 4;
constexpr double kAlignmentPeakRate = 100.0;
constexpr double kAlignmentMaxDuration = 120.0;
constexpr double kAlignmentSearchSeconds = 5.0;
constexpr double kAlignmentMinimumScore = 0.15;

reaper_plugin_info_t *g_reaper = nullptr;
int g_videoEnabledCommand = 0;
int g_showPreviewCommand = 0;
int g_toggleFollowCommand = 0;
int g_previousPlayState = 0;
bool g_videoEnabled = false;
bool g_followEnabled = true;
bool g_activeTransportRecording = false;
bool g_pendingInsert = false;
std::string g_selectedDeviceUniqueID;
std::string g_pendingInsertPath;
double g_pendingInsertPosition = 0.0;
ReaProject *g_recordProject = nullptr;
double g_recordStartPosition = 0.0;

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

std::vector<double> takeEnvelope(MediaItem_Take *take, double itemPosition, double duration, int &sampleCountOut) {
  sampleCountOut = 0;
  if (!take || !GetMediaItemTake_Peaks || duration <= 0.0) {
    return {};
  }

  const int sampleCount = (std::max)(1, static_cast<int>(std::floor(duration * kAlignmentPeakRate)));
  std::vector<double> peaks(static_cast<size_t>(sampleCount) * 2);
  const int result = GetMediaItemTake_Peaks(take,
                                            kAlignmentPeakRate,
                                            itemPosition,
                                            1,
                                            sampleCount,
                                            0,
                                            peaks.data());
  const int returnedSamples = result & 0xfffff;
  if (returnedSamples <= 0) {
    return {};
  }

  std::vector<double> envelope(static_cast<size_t>(returnedSamples));
  double mean = 0.0;
  for (int i = 0; i < returnedSamples; ++i) {
    const double value = (std::max)(std::fabs(peaks[static_cast<size_t>(i)]),
                                    std::fabs(peaks[static_cast<size_t>(returnedSamples + i)]));
    envelope[static_cast<size_t>(i)] = value;
    mean += value;
  }
  mean /= returnedSamples;

  double energy = 0.0;
  for (double &value : envelope) {
    value -= mean;
    energy += value * value;
  }
  if (energy <= 1e-9) {
    return {};
  }

  sampleCountOut = returnedSamples;
  return envelope;
}

double normalizedCorrelationAtLag(const std::vector<double> &video,
                                  const std::vector<double> &reference,
                                  int lagSamples) {
  int videoStart = 0;
  int referenceStart = lagSamples;
  int count = static_cast<int>(video.size());
  if (referenceStart < 0) {
    videoStart = -referenceStart;
    referenceStart = 0;
    count -= videoStart;
  }
  count = (std::min)(count, static_cast<int>(reference.size()) - referenceStart);
  if (count < static_cast<int>(kAlignmentPeakRate)) {
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

AlignmentResult alignVideoItemToReference(ReaProject *project, MediaTrack *videoTrack, MediaItem *videoItem) {
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

  int videoSampleCount = 0;
  std::vector<double> videoEnvelope =
      takeEnvelope(videoTake, videoPosition, (std::min)(videoLength, kAlignmentMaxDuration), videoSampleCount);
  if (videoEnvelope.empty()) {
    return result;
  }

  const int itemCount = CountMediaItems(project);
  double bestScore = -std::numeric_limits<double>::infinity();
  double bestPosition = videoPosition;

  for (int i = 0; i < itemCount; ++i) {
    MediaItem *referenceItem = GetMediaItem(project, i);
    if (!referenceItem || referenceItem == videoItem || GetMediaItemTrack(referenceItem) == videoTrack) {
      continue;
    }

    MediaItem_Take *referenceTake = GetActiveTake(referenceItem);
    if (!referenceTake) {
      continue;
    }

    const double referencePosition = GetMediaItemInfo_Value(referenceItem, "D_POSITION");
    const double referenceLength = GetMediaItemInfo_Value(referenceItem, "D_LENGTH");
    const double expectedLag = videoPosition - referencePosition;
    if (referenceLength <= 0.0 ||
        expectedLag < -kAlignmentSearchSeconds ||
        expectedLag > referenceLength + kAlignmentSearchSeconds) {
      continue;
    }

    int referenceSampleCount = 0;
    std::vector<double> referenceEnvelope =
        takeEnvelope(referenceTake,
                     referencePosition,
                     (std::min)(referenceLength, kAlignmentMaxDuration),
                     referenceSampleCount);
    if (referenceEnvelope.empty()) {
      continue;
    }

    const int expectedLagSamples = static_cast<int>(std::llround(expectedLag * kAlignmentPeakRate));
    const int searchSamples = static_cast<int>(std::llround(kAlignmentSearchSeconds * kAlignmentPeakRate));
    const int minLag = (std::max)(-videoSampleCount + 1, expectedLagSamples - searchSamples);
    const int maxLag = (std::min)(referenceSampleCount - 1, expectedLagSamples + searchSamples);

    for (int lag = minLag; lag <= maxLag; ++lag) {
      const double score = normalizedCorrelationAtLag(videoEnvelope, referenceEnvelope, lag);
      if (score > bestScore) {
        bestScore = score;
        bestPosition = referencePosition + (static_cast<double>(lag) / kAlignmentPeakRate);
      }
    }
  }

  if (std::isfinite(bestScore) && bestScore >= kAlignmentMinimumScore) {
    result.aligned = true;
    result.correction = bestPosition - videoPosition;
    result.score = bestScore;
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

  alignVideoItemToReference(project, track, videoItem);

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

@interface KlongVideoRecorder : NSObject <AVCaptureFileOutputRecordingDelegate>
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, copy) NSString *activePlaybackPath;
@property(nonatomic, strong) NSView *dockView;
@property(nonatomic, strong) NSView *previewView;
@property(nonatomic, strong) NSPopUpButton *devicePopup;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, copy) void (^startCompletion)(void);
@property(nonatomic, copy) void (^stopCompletion)(NSString *path, NSError *error);
@property(nonatomic, copy) NSString *activeOutputPath;
@property(nonatomic, copy) NSString *audioDeviceName;
@property(nonatomic, assign) BOOL docked;
@property(nonatomic, assign) BOOL hasAudioInput;
@property(nonatomic, assign) BOOL showingPlayback;
@end

@implementation KlongVideoRecorder

- (void)showPreview {
  dispatch_async(dispatch_get_main_queue(), ^{
    [self ensureCaptureAccessThenRun:^{
      NSError *error = nil;
      if (![self ensureSession:&error]) {
        showError(error.localizedDescription.UTF8String ?: "Unable to initialize camera session.");
        return;
      }
      [self ensureDockView];
      [self showDockedPreview];
      [self setStatus:[NSString stringWithUTF8String:followStatusText().c_str()]];
    }];
  });
}

- (void)togglePreview {
  if (self.docked) {
    [self hideDockedPreview];
  } else {
    [self showPreview];
  }
}

- (BOOL)isRecording {
  return self.movieOutput.isRecording;
}

- (BOOL)startRecordingToPath:(const std::string &)path
             startCompletion:(void (^)(void))startCompletion
                        error:(NSError **)error {
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
  [self showDockedPreview];
  [self setStatus:@"Starting recording"];
  [self.movieOutput startRecordingToOutputFileURL:[NSURL fileURLWithPath:outputPath]
                                recordingDelegate:self];
  return YES;
}

- (void)stopRecordingWithCompletion:(void (^)(NSString *path, NSError *error))completion {
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
  [self setStatus:[NSString stringWithFormat:@"Camera: %@", self.devicePopup.selectedItem.title]];
}

- (void)ensureDockView {
  if (!self.dockView) {
    NSRect frame = NSMakeRect(0, 0, 640, 420);
    self.dockView = [[NSView alloc] initWithFrame:frame];
    self.dockView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.dockView.wantsLayer = YES;

    self.previewView = [[NSView alloc] initWithFrame:NSMakeRect(0, 60, frame.size.width, frame.size.height - 60)];
    self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.previewView.wantsLayer = YES;
    [self.dockView addSubview:self.previewView];

    self.devicePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(12, 31, frame.size.width - 24, 24) pullsDown:NO];
    self.devicePopup.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    self.devicePopup.target = self;
    self.devicePopup.action = @selector(deviceSelectionChanged:);
    [self.dockView addSubview:self.devicePopup];

    self.statusLabel = [NSTextField labelWithString:[NSString stringWithUTF8String:followStatusText().c_str()]];
    self.statusLabel.frame = NSMakeRect(12, 7, frame.size.width - 24, 18);
    self.statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [self.dockView addSubview:self.statusLabel];
    [self refreshDeviceMenu];
  }

  if (!self.previewLayer && self.session) {
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.previewLayer.frame = self.previewView.bounds;
    self.previewLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    [self.previewView.layer addSublayer:self.previewLayer];
  }
}

- (void)showLivePreview {
  self.showingPlayback = NO;
  [self.player pause];
  self.playerLayer.hidden = YES;
  self.previewLayer.hidden = NO;
}

- (void)updatePlaybackWithPath:(const std::string &)path
                     itemStart:(double)itemStart
                   sourceOffset:(double)sourceOffset
                projectPosition:(double)projectPosition {
  [self ensureDockView];
  NSString *playbackPath = [NSString stringWithUTF8String:path.c_str()];
  if (!self.player || ![self.activePlaybackPath isEqualToString:playbackPath]) {
    self.activePlaybackPath = playbackPath;
    self.player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:playbackPath]];
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
  self.previewLayer.hidden = YES;
  self.playerLayer.hidden = NO;

  const double sourceTime = projectPosition - itemStart + sourceOffset;
  CMTime targetTime = CMTimeMakeWithSeconds(sourceTime > 0.0 ? sourceTime : 0.0, 600);
  const double currentTime = CMTimeGetSeconds(self.player.currentTime);
  if (!std::isfinite(currentTime) || std::fabs(currentTime - sourceTime) > 0.08) {
    [self.player seekToTime:targetTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
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

- (void)hideDockedPreview {
  if (DockWindowRemove && self.docked && self.dockView) {
    DockWindowRemove((__bridge HWND)self.dockView);
  }
  self.docked = NO;
}

- (void)setStatus:(NSString *)status {
  self.statusLabel.stringValue = status ?: @"Idle";
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
      fromConnections:(NSArray<AVCaptureConnection *> *)connections {
  (void)captureOutput;
  (void)fileURL;
  (void)connections;
  dispatch_async(dispatch_get_main_queue(), ^{
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
  if (insertRecordedMedia(path, position, error)) {
    [recorder() setStatus:@"Recorded to Video Recorder track"];
  } else {
    [recorder() setStatus:@"Import error"];
    showError(error);
  }
}

void timerPoll() {
  @autoreleasepool {
    processPendingInsert();

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
  custom_action_register_t toggleFollowAction = {
      0,
      "KLONG_VIDEO_RECORDER_TOGGLE_FOLLOW",
      "Video Recorder: Enable/Disable Transport Follow",
      nullptr,
  };

  g_videoEnabledCommand = rec->Register("custom_action", &videoEnabledAction);
  g_showPreviewCommand = rec->Register("custom_action", &showPreviewAction);
  g_toggleFollowCommand = rec->Register("custom_action", &toggleFollowAction);

  return g_videoEnabledCommand != 0 && g_showPreviewCommand != 0 && g_toggleFollowCommand != 0 &&
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
  const char *selectedDevice = GetExtState(kExtStateSection, kSelectedDeviceKey);
  if (selectedDevice && selectedDevice[0] != '\0') {
    g_selectedDeviceUniqueID = selectedDevice;
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
