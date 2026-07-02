#ifndef _WIN32
#error "reaphonevideo_win_skeleton.cpp is only intended for Windows builds."
#endif

#include "reaper_plugin.h"

#define REAPERAPI_IMPLEMENT
#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_ShowConsoleMsg
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_SetExtState
#define REAPERAPI_WANT_EnumProjects
#define REAPERAPI_WANT_CountTracks
#define REAPERAPI_WANT_GetTrack
#define REAPERAPI_WANT_GetTrackName
#define REAPERAPI_WANT_InsertTrackAtIndex
#define REAPERAPI_WANT_GetSetMediaTrackInfo_String
#define REAPERAPI_WANT_SetMediaTrackInfo_Value
#define REAPERAPI_WANT_CountTrackMediaItems
#define REAPERAPI_WANT_GetTrackMediaItem
#define REAPERAPI_WANT_AddMediaItemToTrack
#define REAPERAPI_WANT_AddTakeToMediaItem
#define REAPERAPI_WANT_GetActiveTake
#define REAPERAPI_WANT_GetMediaItemTake_Source
#define REAPERAPI_WANT_SetMediaItemTake_Source
#define REAPERAPI_WANT_GetMediaItemInfo_Value
#define REAPERAPI_WANT_SetMediaItemInfo_Value
#define REAPERAPI_WANT_GetMediaItemTakeInfo_Value
#define REAPERAPI_WANT_SetMediaItemSelected
#define REAPERAPI_WANT_PCM_Source_CreateFromFile
#define REAPERAPI_WANT_GetMediaSourceLength
#define REAPERAPI_WANT_PCM_Source_BuildPeaks
#define REAPERAPI_WANT_CreateTakeAudioAccessor
#define REAPERAPI_WANT_DestroyAudioAccessor
#define REAPERAPI_WANT_GetAudioAccessorSamples
#define REAPERAPI_WANT_GetCursorPosition
#define REAPERAPI_WANT_GetProjectPath
#define REAPERAPI_WANT_UpdateArrange
#define REAPERAPI_WANT_UpdateTimeline
#define REAPERAPI_WANT_Undo_BeginBlock
#define REAPERAPI_WANT_Undo_EndBlock
#define REAPERAPI_WANT_GetMainHwnd
#define REAPERAPI_WANT_GetPlayState
#include "reaper_plugin_functions.h"

#include "reaphone_action_ids.h"

#include "reaphone/audio_align.h"
#include "reaphone/debug_logger.h"
#include "reaphone/plugin_settings.h"
#include "reaphone/windows/helper_launcher.h"

#include "preview_panel_win32.h"
#include "settings_dialog_win32.h"

#include <windows.h>

#include <cmath>
#include <filesystem>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

reaper_plugin_info_t *g_reaper = nullptr;
HINSTANCE g_instance = nullptr;

int g_diagnosticCommand = 0;
int g_pairCommand = 0;
int g_testConnectionCommand = 0;
int g_startCommand = 0;
int g_stopCommand = 0;
int g_showPreviewCommand = 0;
int g_floatPreviewCommand = 0;
int g_configureCommand = 0;
int g_toggleFollowCommand = 0;

std::unique_ptr<reaphone::Win32PreviewPanel> g_previewPanel;

// Optional sink so report() mirrors status messages into the preview panel's
// status line. Set when the panel is configured; only touched on the UI thread.
std::function<void(const std::string &)> g_statusSink;

reaphone::Win32PreviewPanel &previewPanel() {
  if (!g_previewPanel) {
    g_previewPanel = std::make_unique<reaphone::Win32PreviewPanel>(g_instance);
  }
  return *g_previewPanel;
}

// Transient pairing code, read from ExtState so it can be set from a future UI
// or ReaScript without persisting alongside the durable settings.
constexpr const char *kPairCodeKey = "iphone_pair_code";

reaphone::DebugLogger &logger() {
  static reaphone::DebugLogger instance(reaphone::DebugLogger::defaultPath());
  return instance;
}

// REAPER ExtState-backed settings store, so the portable settings layer never
// depends on the REAPER SDK directly.
class ReaperExtStateStore : public reaphone::ISettingsStore {
public:
  std::string getString(const std::string &section, const std::string &key) const override {
    if (!GetExtState) {
      return {};
    }
    const char *value = GetExtState(section.c_str(), key.c_str());
    return value ? std::string(value) : std::string();
  }

  void setString(const std::string &section, const std::string &key, const std::string &value) override {
    if (SetExtState) {
      SetExtState(section.c_str(), key.c_str(), value.c_str(), true);
    }
  }
};

std::wstring widen(const std::string &value) {
  if (value.empty()) {
    return {};
  }
  const int needed = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(static_cast<std::size_t>(needed), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(), needed);
  return result;
}

// Resolves video-sync-win.exe relative to the loaded plugin DLL.
std::wstring helperExecutablePath() {
  wchar_t buffer[MAX_PATH] = {0};
  const DWORD length = GetModuleFileNameW(g_instance, buffer, MAX_PATH);
  if (length == 0 || length == MAX_PATH) {
    return L"video-sync-win.exe";
  }
  std::filesystem::path modulePath(std::wstring(buffer, length));
  return (modulePath.parent_path() / L"video-sync-win.exe").wstring();
}

void report(const std::string &message) {
  logger().log(message);
  if (ShowConsoleMsg) {
    ShowConsoleMsg((message + "\n").c_str());
  }
  if (g_statusSink) {
    g_statusSink(message);
  }
}

// Runs a helper command with the persisted connection and reports its output.
// Returns the ProcessResult so callers can post-process stdout (e.g. pairing).
reaphone::ProcessResult runCommand(const std::string &command,
                                   const reaphone::PluginSettings &settings,
                                   const std::vector<std::wstring> &extraArguments) {
  const reaphone::HelperConnection connection =
      reaphone::makeConnection(settings.host, settings.controlPort, settings.httpPort);
  const std::wstring helper = helperExecutablePath();

  logger().log("running helper command: " + command);
  reaphone::ProcessResult result = reaphone::runVideoSyncCommand(helper, command, connection, extraArguments);

  if (!result.standardOutput.empty()) {
    report(result.standardOutput);
  }
  if (!result.standardError.empty()) {
    report(std::string("helper stderr: ") + result.standardError);
  }
  logger().log("helper command " + command + " exited " + std::to_string(result.exitCode));
  return result;
}

// ---- REAPER media insertion + audio alignment -----------------------------

constexpr const char *kVideoTrackName = "Video Recorder";

ReaProject *activeProject() { return EnumProjects ? EnumProjects(-1, nullptr, 0) : nullptr; }

std::wstring widenPath(const std::string &value) { return widen(value); }

// Finds the "Video Recorder" track, or creates it at the end of the project.
MediaTrack *findOrCreateVideoTrack(ReaProject *project) {
  if (!CountTracks || !GetTrack || !GetTrackName || !InsertTrackAtIndex || !GetSetMediaTrackInfo_String) {
    return nullptr;
  }
  const int trackCount = CountTracks(project);
  for (int i = 0; i < trackCount; ++i) {
    MediaTrack *track = GetTrack(project, i);
    char name[256] = {0};
    if (track && GetTrackName(track, name, sizeof(name)) && std::string(name) == kVideoTrackName) {
      return track;
    }
  }

  InsertTrackAtIndex(trackCount, true);
  MediaTrack *track = GetTrack(project, trackCount);
  if (track) {
    char name[] = "Video Recorder";
    GetSetMediaTrackInfo_String(track, "P_NAME", name, true);
    if (SetMediaTrackInfo_Value) {
      SetMediaTrackInfo_Value(track, "I_RECARM", 0.0);
    }
  }
  return track;
}

// Inserts the media file as a new item+take on the track at project position.
// Returns the created item (nullptr on failure, with error populated).
MediaItem *insertVideoItem(MediaTrack *track, const std::string &path, double position, std::string &error) {
  if (!PCM_Source_CreateFromFile || !AddMediaItemToTrack || !AddTakeToMediaItem || !SetMediaItemTake_Source ||
      !SetMediaItemInfo_Value || !GetMediaSourceLength) {
    error = "required REAPER media insertion APIs are unavailable";
    return nullptr;
  }

  PCM_source *source = PCM_Source_CreateFromFile(path.c_str());
  if (!source) {
    error = "REAPER could not open the recording: " + path;
    return nullptr;
  }

  MediaItem *item = AddMediaItemToTrack(track);
  MediaItem_Take *take = item ? AddTakeToMediaItem(item) : nullptr;
  if (!item || !take || !SetMediaItemTake_Source(take, source)) {
    error = "REAPER could not create a media item for the recording";
    return nullptr;
  }

  bool lengthIsQN = false;
  const double length = GetMediaSourceLength(source, &lengthIsQN);
  SetMediaItemInfo_Value(item, "D_POSITION", position);
  if (!lengthIsQN && length > 0.0) {
    SetMediaItemInfo_Value(item, "D_LENGTH", length);
  }
  SetMediaItemInfo_Value(item, "B_LOOPSRC", 0.0);
  if (SetMediaItemSelected) {
    SetMediaItemSelected(item, true);
  }
  if (PCM_Source_BuildPeaks) {
    int remaining = PCM_Source_BuildPeaks(source, 0);
    int guard = 0;
    while (remaining > 0 && guard++ < 100000) {
      remaining = PCM_Source_BuildPeaks(source, 1);
    }
    PCM_Source_BuildPeaks(source, 2);
  }
  return item;
}

// Reads mono audio samples for a take over [projectStart, projectStart+duration]
// at the alignment sample rate, via a temporary audio accessor.
std::vector<double> takeSamples(MediaItem_Take *take, double projectStart, double duration) {
  if (!take || !CreateTakeAudioAccessor || !GetAudioAccessorSamples || !DestroyAudioAccessor || duration <= 0.0) {
    return {};
  }
  const int sampleCount = static_cast<int>(std::ceil(duration * reaphone::align_constants::kSampleRate));
  if (sampleCount <= 0) {
    return {};
  }
  std::vector<double> samples(static_cast<std::size_t>(sampleCount), 0.0);
  AudioAccessor *accessor = CreateTakeAudioAccessor(take);
  if (!accessor) {
    return {};
  }
  const int result = GetAudioAccessorSamples(accessor, reaphone::align_constants::kSampleRate, 1, projectStart,
                                             sampleCount, samples.data());
  DestroyAudioAccessor(accessor);
  if (result <= 0) {
    return {};
  }
  return samples;
}

// Finds the first non-video track item overlapping [position, position+length]
// and returns its active take (the alignment reference), plus the item position.
MediaItem_Take *findReferenceTake(ReaProject *project, MediaItem *videoItem, double position, double length,
                                  double &referencePosition, double &referenceLength) {
  if (!CountTracks || !GetTrack || !GetTrackName || !CountTrackMediaItems || !GetTrackMediaItem ||
      !GetMediaItemInfo_Value || !GetActiveTake) {
    return nullptr;
  }
  const double windowEnd = position + length;
  const int trackCount = CountTracks(project);
  for (int t = 0; t < trackCount; ++t) {
    MediaTrack *track = GetTrack(project, t);
    char name[256] = {0};
    if (!track || (GetTrackName(track, name, sizeof(name)) && std::string(name) == kVideoTrackName)) {
      continue;
    }
    const int itemCount = CountTrackMediaItems(track);
    for (int i = 0; i < itemCount; ++i) {
      MediaItem *item = GetTrackMediaItem(track, i);
      if (!item || item == videoItem) {
        continue;
      }
      const double itemStart = GetMediaItemInfo_Value(item, "D_POSITION");
      const double itemLength = GetMediaItemInfo_Value(item, "D_LENGTH");
      const double itemEnd = itemStart + itemLength;
      if (itemEnd <= position || itemStart >= windowEnd) {
        continue;
      }
      MediaItem_Take *take = GetActiveTake(item);
      if (take) {
        referencePosition = itemStart;
        referenceLength = itemLength;
        return take;
      }
    }
  }
  return nullptr;
}

// Best-effort audio alignment: correlates the inserted video's audio against a
// reference audio item and shifts the video item to the matched position.
// Returns true if the item was moved. Never fatal.
bool alignVideoItem(ReaProject *project, MediaItem *videoItem, MediaItem_Take *videoTake, double insertPosition) {
  using namespace reaphone::align_constants;
  if (!videoItem || !videoTake || !GetMediaItemInfo_Value || !SetMediaItemInfo_Value) {
    return false;
  }

  const double videoLength = GetMediaItemInfo_Value(videoItem, "D_LENGTH");
  const double duration = (std::min)(videoLength, kSampleRefineDuration);
  if (duration <= 0.0) {
    return false;
  }

  double referencePosition = 0.0;
  double referenceLength = 0.0;
  MediaItem_Take *referenceTake =
      findReferenceTake(project, videoItem, insertPosition, videoLength, referencePosition, referenceLength);
  if (!referenceTake) {
    report("ReaPhoneVideo: inserted recording; no overlapping audio to align against.");
    return false;
  }

  const double search = kSampleRefineSearchSeconds + kSearchSeconds;
  const double referenceWindowStart = (std::max)(referencePosition, insertPosition - search);
  const double referenceDuration =
      (std::min)(referenceLength - (referenceWindowStart - referencePosition), duration + (2.0 * search));
  if (referenceDuration <= duration * 0.5) {
    return false;
  }

  const std::vector<double> videoSamples =
      reaphone::normalizedSampleShape(takeSamples(videoTake, insertPosition, duration));
  const std::vector<double> referenceSamples =
      reaphone::normalizedSampleShape(takeSamples(referenceTake, referenceWindowStart, referenceDuration));
  if (videoSamples.empty() || referenceSamples.empty()) {
    return false;
  }

  const int expectedLag = static_cast<int>(std::llround((insertPosition - referenceWindowStart) * kSampleRate));
  const int searchSamples = static_cast<int>(std::llround(search * kSampleRate));
  const int minLag = (std::max)(0, expectedLag - searchSamples);
  const int maxLag = (std::min)(static_cast<int>(referenceSamples.size()) - static_cast<int>(videoSamples.size()),
                                expectedLag + searchSamples);
  const int minimumOverlapSamples = static_cast<int>(std::llround(0.25 * kSampleRate));

  const reaphone::LagMatch match =
      reaphone::findBestLag(videoSamples, referenceSamples, minLag, maxLag, minimumOverlapSamples);
  if (!match.valid || match.score < kMinimumScore) {
    char msg[128] = {0};
    std::snprintf(msg, sizeof(msg), "ReaPhoneVideo: inserted recording; alignment score %.2f below %.2f.",
                  match.valid ? match.score : 0.0, kMinimumScore);
    report(msg);
    return false;
  }

  const double refinedPosition = referenceWindowStart + (static_cast<double>(match.lag) / kSampleRate);
  SetMediaItemInfo_Value(videoItem, "D_POSITION", refinedPosition);

  char msg[160] = {0};
  std::snprintf(msg, sizeof(msg), "ReaPhoneVideo: aligned recording %.0f ms (score %.2f).",
                (refinedPosition - insertPosition) * 1000.0, match.score);
  report(msg);
  return true;
}

// Inserts a downloaded recording into the project and aligns it. Non-fatal.
void insertAndAlign(const std::string &path) {
  if (path.empty()) {
    return;
  }
  ReaProject *project = activeProject();
  if (!project) {
    report("ReaPhoneVideo: no active project to insert the recording into.");
    return;
  }
  MediaTrack *track = findOrCreateVideoTrack(project);
  if (!track) {
    report("ReaPhoneVideo: could not find or create the Video Recorder track.");
    return;
  }

  const double position = GetCursorPosition ? GetCursorPosition() : 0.0;
  if (Undo_BeginBlock) {
    Undo_BeginBlock();
  }

  std::string error;
  MediaItem *item = insertVideoItem(track, path, position, error);
  if (!item) {
    report("ReaPhoneVideo: " + error);
    if (Undo_EndBlock) {
      Undo_EndBlock("ReaPhoneVideo insert recording", -1);
    }
    return;
  }

  MediaItem_Take *take = GetActiveTake ? GetActiveTake(item) : nullptr;
  alignVideoItem(project, item, take, position);

  if (UpdateTimeline) {
    UpdateTimeline();
  }
  if (UpdateArrange) {
    UpdateArrange();
  }
  if (Undo_EndBlock) {
    Undo_EndBlock("ReaPhoneVideo insert recording", -1);
  }
}

// Chooses a download directory: the project directory if known, else %TEMP%.
std::wstring downloadDirectory() {
  if (GetProjectPath) {
    char buffer[4096] = {0};
    GetProjectPath(buffer, sizeof(buffer));
    if (buffer[0] != '\0') {
      return widenPath(buffer);
    }
  }
  std::error_code ec;
  std::filesystem::path temp = std::filesystem::temp_directory_path(ec);
  return ec ? std::wstring(L".") : temp.wstring();
}

// ---- Transport follow ------------------------------------------------------
// When enabled, hitting record in REAPER auto-starts the iPhone recording, and
// stopping auto-stops + downloads it. Helper calls run on worker threads so the
// REAPER UI thread (timer) never blocks on network I/O; completed downloads are
// handed back to the timer, which performs insert/align on the main thread
// (REAPER APIs are not thread-safe).

constexpr int kRecordBit = 4;

struct FollowState {
  std::mutex mutex;
  std::vector<std::string> completedPaths; // guarded by mutex
  std::vector<std::thread> workers;        // guarded by mutex
  bool recording = false;                  // main thread only
  bool enabled = false;                    // main thread only
};

FollowState g_follow;

// Worker-thread-safe helper runner: logs to file only, never touches REAPER APIs.
reaphone::ProcessResult runCommandSilent(const std::string &command, const reaphone::PluginSettings &settings,
                                         const std::vector<std::wstring> &extraArguments) {
  const reaphone::HelperConnection connection =
      reaphone::makeConnection(settings.host, settings.controlPort, settings.httpPort);
  logger().log("follow: running helper " + command);
  reaphone::ProcessResult result =
      reaphone::runVideoSyncCommand(helperExecutablePath(), command, connection, extraArguments);
  logger().log("follow: helper " + command + " exited " + std::to_string(result.exitCode));
  return result;
}

void launchStartWorker(const reaphone::PluginSettings &settings) {
  std::lock_guard<std::mutex> lock(g_follow.mutex);
  g_follow.workers.emplace_back(
      [settings]() { runCommandSilent("start", settings, {L"--token", widen(settings.token)}); });
}

void launchStopWorker(const reaphone::PluginSettings &settings, const std::wstring &downloadDir) {
  std::lock_guard<std::mutex> lock(g_follow.mutex);
  g_follow.workers.emplace_back([settings, downloadDir]() {
    const reaphone::ProcessResult result =
        runCommandSilent("stop", settings, {L"--token", widen(settings.token), L"--download-dir", downloadDir});
    if (result.exitCode != 0) {
      return;
    }
    if (const auto path = reaphone::parseDownloadedPath(result.standardOutput)) {
      std::lock_guard<std::mutex> lock(g_follow.mutex);
      g_follow.completedPaths.push_back(*path);
    }
  });
}

void onTimer() {
  // Insert any downloads finished by worker threads (main thread => REAPER-safe).
  std::vector<std::string> ready;
  {
    std::lock_guard<std::mutex> lock(g_follow.mutex);
    ready.swap(g_follow.completedPaths);
  }
  for (const std::string &path : ready) {
    insertAndAlign(path);
  }

  if (!GetPlayState) {
    return;
  }
  const bool recording = (GetPlayState() & kRecordBit) != 0;
  if (recording == g_follow.recording) {
    return;
  }
  g_follow.recording = recording;

  if (!g_follow.enabled) {
    return;
  }

  ReaperExtStateStore store;
  const reaphone::PluginSettings settings = reaphone::loadSettings(store);
  if (settings.host.empty() || settings.token.empty()) {
    logger().log("follow: skipped auto start/stop; host or token not set");
    return;
  }

  if (recording) {
    launchStartWorker(settings);
  } else {
    launchStopWorker(settings, downloadDirectory());
  }
}

void joinFollowWorkers() {
  std::vector<std::thread> workers;
  {
    std::lock_guard<std::mutex> lock(g_follow.mutex);
    workers.swap(g_follow.workers);
  }
  for (std::thread &worker : workers) {
    if (worker.joinable()) {
      worker.join();
    }
  }
}

void handleToggleFollow(ReaperExtStateStore &store) {
  g_follow.enabled = !g_follow.enabled;
  reaphone::PluginSettings settings = reaphone::loadSettings(store);
  settings.followEnabled = g_follow.enabled;
  reaphone::saveSettings(store, settings);
  report(g_follow.enabled ? "ReaPhoneVideo: transport follow ON (record in REAPER drives the iPhone)."
                          : "ReaPhoneVideo: transport follow OFF.");
}

void handlePair(ReaperExtStateStore &store) {
  const reaphone::PluginSettings settings = reaphone::loadSettings(store);
  if (settings.host.empty()) {
    report("ReaPhoneVideo: set the iPhone host before pairing.");
    return;
  }
  const std::string code = store.getString(reaphone::settings_keys::kSection, kPairCodeKey);
  if (code.empty()) {
    report("ReaPhoneVideo: set the pairing code (ExtState iphone_pair_code) before pairing.");
    return;
  }

  const reaphone::ProcessResult result = runCommand("pair", settings, {L"--code", widen(code)});
  if (result.exitCode != 0) {
    return;
  }

  if (const auto token = reaphone::parsePairedToken(result.standardOutput)) {
    reaphone::PluginSettings updated = settings;
    updated.token = *token;
    reaphone::saveSettings(store, updated);
    report("ReaPhoneVideo: paired and saved token.");
  } else {
    report("ReaPhoneVideo: pairing succeeded but no token was returned.");
  }
}

void handleTestConnection(ReaperExtStateStore &store) {
  const reaphone::PluginSettings settings = reaphone::loadSettings(store);
  if (settings.host.empty()) {
    report("ReaPhoneVideo: set the iPhone host before testing the connection.");
    return;
  }
  std::vector<std::wstring> extra;
  if (!settings.token.empty()) {
    extra = {L"--token", widen(settings.token)};
  }
  runCommand("ping", settings, extra);
}

bool requireHostAndToken(const reaphone::PluginSettings &settings, const char *verb) {
  if (settings.host.empty() || settings.token.empty()) {
    report(std::string("ReaPhoneVideo: set the iPhone host and token before ") + verb + ".");
    return false;
  }
  return true;
}

void handleStart(ReaperExtStateStore &store) {
  const reaphone::PluginSettings settings = reaphone::loadSettings(store);
  if (!requireHostAndToken(settings, "starting a recording")) {
    return;
  }
  runCommand("start", settings, {L"--token", widen(settings.token)});
}

void handleStop(ReaperExtStateStore &store) {
  const reaphone::PluginSettings settings = reaphone::loadSettings(store);
  if (!requireHostAndToken(settings, "stopping a recording")) {
    return;
  }
  const std::wstring dir = downloadDirectory();
  const reaphone::ProcessResult result =
      runCommand("stop", settings, {L"--token", widen(settings.token), L"--download-dir", dir});
  if (result.exitCode != 0) {
    return;
  }
  if (const auto path = reaphone::parseDownloadedPath(result.standardOutput)) {
    insertAndAlign(*path);
  } else {
    report("ReaPhoneVideo: stop completed but no downloaded file was reported.");
  }
}

// Persists the panel's editable fields into the durable settings before an
// action runs, so the helper sees the values shown in the window.
void applyPanelFields(ReaperExtStateStore &store, const reaphone::PanelControls &pc) {
  reaphone::PluginSettings settings = reaphone::loadSettings(store);
  if (!pc.host.empty()) {
    settings.host = pc.host;
  }
  if (!pc.resolution.empty()) {
    settings.resolution = pc.resolution;
  }
  if (!pc.fps.empty()) {
    settings.fps = pc.fps;
  }
  reaphone::saveSettings(store, settings);
}

// Wires the preview panel's control strip to the existing action handlers, and
// routes report() status text into the panel's status line. Runs once.
void ensurePanelConfigured() {
  static bool configured = false;
  reaphone::Win32PreviewPanel &panel = previewPanel();
  if (configured) {
    return;
  }
  configured = true;

  g_statusSink = [](const std::string &message) {
    if (g_previewPanel) {
      g_previewPanel->setStatus(message);
    }
  };

  reaphone::PanelCallbacks callbacks;
  callbacks.onPair = [](const reaphone::PanelControls &pc) {
    ReaperExtStateStore store;
    applyPanelFields(store, pc);
    store.setString(reaphone::settings_keys::kSection, kPairCodeKey, pc.pairingCode);
    handlePair(store);
  };
  callbacks.onTest = [](const reaphone::PanelControls &pc) {
    ReaperExtStateStore store;
    applyPanelFields(store, pc);
    handleTestConnection(store);
  };
  callbacks.onStart = [](const reaphone::PanelControls &pc) {
    ReaperExtStateStore store;
    applyPanelFields(store, pc);
    handleStart(store);
  };
  callbacks.onStop = [](const reaphone::PanelControls &pc) {
    ReaperExtStateStore store;
    applyPanelFields(store, pc);
    handleStop(store);
  };
  callbacks.onDiscover = [](const reaphone::PanelControls &) {
    report("ReaPhoneVideo: Discover needs mDNS and isn't available on Windows yet; enter the host "
           "manually.");
  };
  panel.setCallbacks(std::move(callbacks));
}

// Refreshes the panel's fields from the persisted settings (e.g. after the
// Configure dialog or a pairing round-trip updated them).
void primePanelValues() {
  ReaperExtStateStore store;
  const reaphone::PluginSettings settings = reaphone::loadSettings(store);
  reaphone::PanelControls pc;
  pc.host = settings.host;
  pc.pairingCode = store.getString(reaphone::settings_keys::kSection, kPairCodeKey);
  pc.resolution = settings.resolution;
  pc.fps = settings.fps;
  previewPanel().setInitialValues(pc);
}

void handleShowPreview() {
  ensurePanelConfigured();
  reaphone::Win32PreviewPanel &panel = previewPanel();
  if (panel.isVisible()) {
    panel.hide();
    report("ReaPhoneVideo: preview hidden.");
  } else {
    primePanelValues();
    panel.show();
    report("ReaPhoneVideo: preview panel shown. Pair and record from here (video preview pending "
           "WebRTC).");
  }
}

void handleFloatPreview() {
  reaphone::Win32PreviewPanel &panel = previewPanel();
  panel.setFloating(!panel.isFloating());
  report(panel.isFloating() ? "ReaPhoneVideo: preview set to floating."
                            : "ReaPhoneVideo: preview set to docked.");
}

void handleConfigure(ReaperExtStateStore &store) {
  reaphone::PluginSettings settings = reaphone::loadSettings(store);
  HWND parent = GetMainHwnd ? GetMainHwnd() : nullptr;
  if (reaphone::showSettingsDialog(parent, g_instance, settings)) {
    reaphone::saveSettings(store, settings);
    report("ReaPhoneVideo: settings saved.");
  }
}

bool hookCommand2(KbdSectionInfo *section, int command, int value, int valuehw, int relmode, HWND hwnd) {
  (void)section;
  (void)value;
  (void)valuehw;
  (void)relmode;
  (void)hwnd;

  ReaperExtStateStore store;

  if (command == g_diagnosticCommand) {
    report("ReaPhoneVideo Windows plugin loaded and handling actions.");
    return true;
  }
  if (command == g_pairCommand) {
    handlePair(store);
    return true;
  }
  if (command == g_testConnectionCommand) {
    handleTestConnection(store);
    return true;
  }
  if (command == g_startCommand) {
    handleStart(store);
    return true;
  }
  if (command == g_stopCommand) {
    handleStop(store);
    return true;
  }
  if (command == g_showPreviewCommand) {
    handleShowPreview();
    return true;
  }
  if (command == g_floatPreviewCommand) {
    handleFloatPreview();
    return true;
  }
  if (command == g_configureCommand) {
    handleConfigure(store);
    return true;
  }
  if (command == g_toggleFollowCommand) {
    handleToggleFollow(store);
    return true;
  }
  return false;
}

int registerAction(reaper_plugin_info_t *rec, const char *id, const char *name) {
  custom_action_register_t action = {0, id, name, nullptr};
  return rec->Register("custom_action", &action);
}

// Routes keystrokes to the preview panel's edit fields when it (or one of its
// children) has focus, so REAPER's global shortcuts don't swallow typing.
int translatePanelAccel(MSG *msg, accelerator_register_t *) {
  if (msg == nullptr || !g_previewPanel) {
    return 0;
  }
  const HWND panel = g_previewPanel->nativeHandle();
  if (panel != nullptr && (msg->hwnd == panel || IsChild(panel, msg->hwnd))) {
    return -1; // pass the key on to our window/controls
  }
  return 0;
}

accelerator_register_t g_panelAccel = {translatePanelAccel, true, nullptr};

bool registerActions(reaper_plugin_info_t *rec) {
  using namespace reaphone::actions;

  g_diagnosticCommand = registerAction(rec, kWindowsDiagnosticId, kWindowsDiagnosticName);
  g_pairCommand = registerAction(rec, kPairId, kPairName);
  g_testConnectionCommand = registerAction(rec, kTestConnectionId, kTestConnectionName);
  g_startCommand = registerAction(rec, kStartRecordingId, kStartRecordingName);
  g_stopCommand = registerAction(rec, kStopRecordingId, kStopRecordingName);
  g_showPreviewCommand = registerAction(rec, kShowPreviewId, kShowPreviewName);
  g_floatPreviewCommand = registerAction(rec, kFloatPreviewId, kFloatPreviewName);
  g_configureCommand = registerAction(rec, kConfigureId, kConfigureName);
  g_toggleFollowCommand = registerAction(rec, kToggleFollowId, kToggleFollowName);

  const bool allRegistered = g_diagnosticCommand != 0 && g_pairCommand != 0 &&
                             g_testConnectionCommand != 0 && g_startCommand != 0 &&
                             g_stopCommand != 0 && g_showPreviewCommand != 0 &&
                             g_floatPreviewCommand != 0 && g_configureCommand != 0 &&
                             g_toggleFollowCommand != 0;

  if (!allRegistered || !rec->Register("hookcommand2", reinterpret_cast<void *>(hookCommand2))) {
    return false;
  }

  // Seed the follow toggle from persisted settings and start the transport poll.
  ReaperExtStateStore store;
  g_follow.enabled = reaphone::loadSettings(store).followEnabled;
  rec->Register("accelerator", &g_panelAccel);
  return rec->Register("timer", reinterpret_cast<void *>(onTimer)) != 0;
}

void unregisterActions(reaper_plugin_info_t *rec) {
  rec->Register("-timer", reinterpret_cast<void *>(onTimer));
  rec->Register("-accelerator", &g_panelAccel);
  rec->Register("-hookcommand2", reinterpret_cast<void *>(hookCommand2));
  joinFollowWorkers();
}

} // namespace

extern "C" {

REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE hInstance, reaper_plugin_info_t *rec) {
  g_instance = static_cast<HINSTANCE>(hInstance);

  if (!rec) {
    if (g_reaper) {
      unregisterActions(g_reaper);
    }
    g_statusSink = nullptr;
    g_previewPanel.reset();
    g_reaper = nullptr;
    return 0;
  }

  g_reaper = rec;
  if (REAPERAPI_LoadAPI(rec->GetFunc) != 0) {
    return 0;
  }

  return registerActions(rec) ? 1 : 0;
}

}
