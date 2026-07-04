#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "core/capture_profile.h"
#include "core/helper_output_parser.h"
#include "core/path_utils.h"
#include "core/remote_camera.h"
#include "core/reashoot_controller.h"
#include "core/reashoot_status.h"
#include "platform/swell/swell_panel_probe.h"
#include "platform/swell/swell_runtime.h"
#include "platform/win32/win32_h264_preview_renderer.h"
#include "platform/win32/win32_helper_process.h"
#include "platform/win32/win32_playback_preview_renderer.h"
#include "platform/win32/win32_preview_stream_client.h"
#include "reaper/reaper_host.h"

#define REAPERAPI_IMPLEMENT
#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_AddMediaItemToTrack
#define REAPERAPI_WANT_AddTakeToMediaItem
#define REAPERAPI_WANT_CountTrackMediaItems
#define REAPERAPI_WANT_CountTracks
#define REAPERAPI_WANT_DockWindowActivate
#define REAPERAPI_WANT_DockWindowAddEx
#define REAPERAPI_WANT_DockWindowRefreshForHWND
#define REAPERAPI_WANT_DockWindowRemove
#define REAPERAPI_WANT_EnumProjects
#define REAPERAPI_WANT_GetActiveTake
#define REAPERAPI_WANT_GetCursorPositionEx
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_get_ini_file
#define REAPERAPI_WANT_GetMediaItemInfo_Value
#define REAPERAPI_WANT_GetMediaItemTake_Source
#define REAPERAPI_WANT_GetMediaItemTakeInfo_Value
#define REAPERAPI_WANT_GetMediaSourceFileName
#define REAPERAPI_WANT_GetMediaSourceLength
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

constexpr const char *kExtStateSection = "klong_reashoot";
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
constexpr const char *kVideoTrackName = "ReaShoot";
constexpr int kRecordBit = 4;
constexpr const char *kDockIdent = "reashoot_preview";
constexpr auto kPlaybackMissGrace = std::chrono::milliseconds(500);

HINSTANCE g_instance = nullptr;
reaper_plugin_info_t *g_reaper = nullptr;
int g_videoEnabledCommand = 0;
int g_floatPreviewCommand = 0;
int g_alignSelectedCommand = 0;
int g_restoreIPhoneCommand = 0;
int g_deleteAllIPhoneCommand = 0;
int g_toggleFollowCommand = 0;
int g_previousPlayState = 0;
HWND g_panel = nullptr;
bool g_panelVisible = false;
bool g_previewFloating = true;
bool g_panelDocked = false;
bool g_activeTransportRecording = false;
bool g_pendingInsert = false;
std::string g_pendingInsertPath;
double g_pendingInsertPosition = 0.0;
ReaProject *g_recordProject = nullptr;
double g_recordStartPosition = 0.0;
reashoot::core::ReaShootController g_extensionController;
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
std::mutex g_mainQueueMutex;
std::queue<std::function<void()>> g_mainQueue;
std::shared_ptr<reashoot::core::AsyncCommandHandle> g_stopHandle;
std::shared_ptr<reashoot::core::AsyncCommandHandle> g_downloadHandle;
std::shared_ptr<reashoot::core::AsyncCommandHandle> g_listHandle;
std::shared_ptr<reashoot::core::AsyncCommandHandle> g_deleteHandle;
ReaProject *g_pendingInsertProject = nullptr;
std::unique_ptr<reashoot::core::PreviewStreamClient> g_previewStreamClient;
std::unique_ptr<reashoot::core::PreviewRenderer> g_previewRenderer;
std::unique_ptr<reashoot::core::PlaybackPreview> g_playbackPreviewRenderer;
std::shared_ptr<reashoot::core::AsyncCommandHandle> g_previewCommandHandle;
bool g_previewStreamStarting = false;
bool g_previewStreamActive = false;
bool g_previewCommandInFlight = false;
bool g_previewReceivedAccessUnit = false;
bool g_previewReceivedFrame = false;
// Single authoritative owner of the preview panel. Every path that paints the
// panel (live H.264 frames, playback frames, status/placeholder text) must
// respect this so live preview can never repaint over active playback and
// cause the panel to blink. See stopPlaybackAndShowLive/updatePlaybackWithVideo.
enum class PreviewMode { Idle, Live, Playback };
PreviewMode g_previewMode = PreviewMode::Idle;
inline bool showingPlayback() { return g_previewMode == PreviewMode::Playback; }
bool g_transportPlaybackActive = false;
bool g_stoppingRemotePreview = false;
bool g_restartPreviewAfterStop = false;
std::chrono::steady_clock::time_point g_lastPlaybackVideoHit;
std::string g_playbackDecoderStatus;

struct PlaybackVideo {
  bool found = false;
  std::string path;
  double itemStart = 0.0;
  double itemEnd = 0.0;
  double sourceOffset = 0.0;
  double playRate = 1.0;
};

struct WindowPlacement {
  int x = 120;
  int y = 120;
  int width = 960;
  int height = 690;
};

WindowPlacement defaultPreviewWindowPlacement() {
  RECT workArea = {};
  if (!SystemParametersInfoA(SPI_GETWORKAREA, 0, &workArea, 0)) {
    workArea = {0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)};
  }
  const int workWidth = (std::max)(640, static_cast<int>(workArea.right - workArea.left));
  const int workHeight = (std::max)(480, static_cast<int>(workArea.bottom - workArea.top));
  WindowPlacement placement;
  placement.width = (std::min)(1120, (std::max)(860, (workWidth * 3) / 5));
  placement.height = (std::min)(820, (std::max)(620, (workHeight * 3) / 5));
  placement.width = (std::min)(placement.width, workWidth - 80);
  placement.height = (std::min)(placement.height, workHeight - 80);
  placement.x = static_cast<int>(workArea.left) + (std::max)(40, (workWidth - placement.width) / 2);
  placement.y = static_cast<int>(workArea.top) + (std::max)(40, (workHeight - placement.height) / 2);
  return placement;
}

std::string withoutAsciiWhitespace(std::string value) {
  value.erase(std::remove_if(value.begin(), value.end(), [](unsigned char ch) {
                return std::isspace(ch) != 0;
              }),
              value.end());
  return value;
}

void debugLog(const std::string &message) {
  const std::string line = "ReaShoot: " + message + "\n";
  OutputDebugStringA(line.c_str());
  char appData[MAX_PATH] = {};
  if (GetEnvironmentVariableA("APPDATA", appData, sizeof(appData)) > 0) {
    std::filesystem::path logPath = std::filesystem::path(appData) / "REAPER" / "reashoot-win.log";
    std::ofstream log(logPath, std::ios::app);
    if (log) {
      log << line;
    }
  }
}

void postToMain(std::function<void()> callback) {
  std::lock_guard<std::mutex> lock(g_mainQueueMutex);
  g_mainQueue.push(std::move(callback));
}

const char *previewModeName(PreviewMode mode) {
  switch (mode) {
    case PreviewMode::Idle: return "idle";
    case PreviewMode::Live: return "live";
    case PreviewMode::Playback: return "playback";
  }
  return "idle";
}

void setPreviewMode(PreviewMode mode) {
  if (g_previewMode == mode) {
    return;
  }
  debugLog(std::string("preview mode ") + previewModeName(g_previewMode) + " -> " + previewModeName(mode));
  g_previewMode = mode;
}

void drainMainQueue() {
  std::queue<std::function<void()>> pending;
  {
    std::lock_guard<std::mutex> lock(g_mainQueueMutex);
    std::swap(pending, g_mainQueue);
  }
  while (!pending.empty()) {
    pending.front()();
    pending.pop();
  }
}

std::string moduleDirectory() {
  char path[MAX_PATH] = {};
  GetModuleFileNameA(g_instance, path, sizeof(path));
  std::filesystem::path modulePath(path);
  return modulePath.parent_path().string();
}

std::string helperPath() {
  return (std::filesystem::path(moduleDirectory()) / "reashoot-win.exe").string();
}

reashoot::core::HelperProcess &helperProcess() {
  static std::unique_ptr<reashoot::core::HelperProcess> helper =
      reashoot::platform::win32::createHelperProcess(helperPath(), debugLog);
  return *helper;
}

reashoot::core::RemoteCameraController &remoteCameraController() {
  static reashoot::core::RemoteCameraController controller(helperProcess());
  return controller;
}

void showError(const std::string &message) {
  if (ShowMessageBox) {
    ShowMessageBox(message.c_str(), "ReaShoot", 0);
  } else {
    MessageBoxA(nullptr, message.c_str(), "ReaShoot", MB_OK | MB_ICONERROR);
  }
}

reashoot::core::RemoteCameraSettings cameraSettings() {
  reashoot::core::RemoteCameraSettings settings;
  settings.host = g_iPhoneHost;
  settings.controlPort = g_iPhoneControlPort;
  settings.httpPort = g_iPhoneHttpPort;
  settings.token = withoutAsciiWhitespace(g_iPhoneToken);
  settings.resolution = g_iPhoneResolution;
  settings.fps = g_iPhoneFPS;
  settings.orientation = g_iPhoneOrientation;
  settings.aspect = g_iPhoneAspect;
  settings.lens = g_iPhoneLens;
  settings.zoom = g_iPhoneZoom;
  settings.look = g_iPhoneLook;
  return settings;
}

void updatePanel() {
  if (!g_panel) {
    return;
  }
  std::string status;
  if (!g_extensionController.videoEnabled()) {
    status = g_iPhoneToken.empty() ? "Video disabled" : "ReaShoot disabled; enable ReaShoot to start preview";
  } else if (g_activeTransportRecording) {
    status = "Recording iPhone video";
  } else if (g_iPhoneToken.empty()) {
    status = "Discover the iPhone, enter the pairing code, then Pair";
  } else {
    status = "Ready";
  }
  const std::string format = "Wi-Fi " + g_iPhoneResolution + " " + g_iPhoneFPS + "fps " +
                             g_iPhoneOrientation + " " + g_iPhoneAspect + " " + g_iPhoneLens +
                             " zoom " + g_iPhoneZoom + " look " + g_iPhoneLook;
  reashoot::platform::swell::updateSwellPanelProbe(g_panel, status.c_str(), format.c_str(), g_iPhoneHost.c_str(), g_iPhoneToken.c_str());
  reashoot::platform::swell::updateSwellPanelProfile(g_panel,
                                                     g_iPhoneResolution.c_str(),
                                                     g_iPhoneFPS.c_str(),
                                                     g_iPhoneOrientation.c_str(),
                                                     g_iPhoneLens.c_str());
  reashoot::platform::swell::setSwellPanelLook(g_panel, g_iPhoneLook.c_str());
  if (DockWindowRefreshForHWND) {
    DockWindowRefreshForHWND(g_panel);
  }
}

void setPanelStatus(const std::string &status) {
  if (!g_panel) {
    return;
  }
  const std::string friendlyStatus = reashoot::core::friendlyStatusText(status);
  // Skip redundant updates. updateSwellPanelProbe re-sets label text, syncs the
  // setup fields, and invalidates the whole panel; calling it every timer tick
  // (e.g. setPanelStatus("Playback") during playback) caused the docked panel to
  // flicker because the REAPER docker repaints on each invalidate. Only push
  // when the visible status actually changes.
  static std::string lastStatus;
  static std::string lastHost;
  static std::string lastToken;
  if (friendlyStatus == lastStatus && g_iPhoneHost == lastHost && g_iPhoneToken == lastToken) {
    return;
  }
  lastStatus = friendlyStatus;
  lastHost = g_iPhoneHost;
  lastToken = g_iPhoneToken;
  reashoot::platform::swell::updateSwellPanelProbe(g_panel, friendlyStatus.c_str(), nullptr, g_iPhoneHost.c_str(), g_iPhoneToken.c_str());
}

std::string captureOutputDirectory(ReaProject *project);
void startRemotePreview();
void stopPlaybackAndShowLive();
void togglePreviewDockMode();

void persistSettings() {
  if (g_panel) {
    reashoot::platform::swell::SwellPanelSettings panelSettings = reashoot::platform::swell::swellPanelSettings(g_panel);
    if (panelSettings.host[0]) {
      g_iPhoneHost = panelSettings.host;
    }
    if (panelSettings.resolution[0]) {
      g_iPhoneResolution = panelSettings.resolution;
    }
    if (panelSettings.fps[0]) {
      g_iPhoneFPS = panelSettings.fps;
    }
    if (panelSettings.orientation[0]) {
      g_iPhoneOrientation = panelSettings.orientation;
    }
    if (panelSettings.lens[0]) {
      g_iPhoneLens = panelSettings.lens;
    }
  }
  g_iPhoneToken = withoutAsciiWhitespace(g_iPhoneToken);
  reashoot::reaper::setExtState(kExtStateSection, kFollowEnabledKey, g_extensionController.followEnabled() ? "1" : "0", true);
  reashoot::reaper::setExtState(kExtStateSection, kPreviewFloatingKey, g_previewFloating ? "1" : "0", true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneHostKey, g_iPhoneHost.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneControlPortKey, g_iPhoneControlPort.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneHttpPortKey, g_iPhoneHttpPort.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneTokenKey, g_iPhoneToken.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneResolutionKey, g_iPhoneResolution.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneFPSKey, g_iPhoneFPS.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneOrientationKey, g_iPhoneOrientation.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneAspectKey, g_iPhoneAspect.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneLensKey, g_iPhoneLens.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneZoomKey, g_iPhoneZoom.c_str(), true);
  reashoot::reaper::setExtState(kExtStateSection, kIPhoneLookKey, g_iPhoneLook.c_str(), true);
}

void readPanelSettings() {
  if (!g_panel) {
    return;
  }
  reashoot::platform::swell::SwellPanelSettings panelSettings = reashoot::platform::swell::swellPanelSettings(g_panel);
  if (panelSettings.host[0]) {
    g_iPhoneHost = panelSettings.host;
  }
  if (panelSettings.resolution[0]) {
    g_iPhoneResolution = panelSettings.resolution;
  }
  if (panelSettings.fps[0]) {
    g_iPhoneFPS = panelSettings.fps;
  }
  if (panelSettings.orientation[0]) {
    g_iPhoneOrientation = panelSettings.orientation;
  }
  if (panelSettings.lens[0]) {
    g_iPhoneLens = panelSettings.lens;
  }
}

void runHelperOnWorker(std::string command,
                       std::vector<std::string> arguments,
                       std::function<void(reashoot::core::CommandResult)> completion) {
  std::thread([command = std::move(command), arguments = std::move(arguments), completion = std::move(completion)]() mutable {
    reashoot::core::CommandResult result = helperProcess().run(command, arguments);
    postToMain([result = std::move(result), completion = std::move(completion)]() mutable {
      if (completion) {
        completion(std::move(result));
      }
    });
  }).detach();
}

std::string resultError(const reashoot::core::CommandResult &result, const std::string &fallback) {
  if (!result.errorMessage.empty()) {
    return reashoot::core::friendlyStatusText(result.errorMessage);
  }
  if (!result.output.empty()) {
    std::istringstream stream(result.output);
    std::ostringstream filtered;
    std::string line;
    while (std::getline(stream, line)) {
      if (!line.empty() && line.back() == '\r') {
        line.pop_back();
      }
      if (line.rfind("progress ", 0) == 0 || line.rfind("encode ", 0) == 0) {
        continue;
      }
      if (!line.empty()) {
        filtered << line << '\n';
      }
    }
    const std::string text = filtered.str();
    return text.empty() ? fallback : reashoot::core::friendlyStatusText(text);
  }
  return fallback;
}

bool isUnauthorizedResult(const reashoot::core::CommandResult &result) {
  std::string text = result.errorMessage + "\n" + result.output;
  std::transform(text.begin(), text.end(), text.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return text.find("unauthorized") != std::string::npos;
}

bool transportPlaying() {
  return GetPlayStateEx && ((GetPlayStateEx(reashoot::reaper::currentProject()) & 1) != 0);
}

bool recentlySawPlaybackVideo() {
  return g_lastPlaybackVideoHit.time_since_epoch().count() != 0 &&
         std::chrono::steady_clock::now() - g_lastPlaybackVideoHit <= std::chrono::seconds(2);
}

bool playbackOwnsPreview() {
  return showingPlayback() || g_transportPlaybackActive || transportPlaying() || recentlySawPlaybackVideo();
}

bool ensureCameraConfiguredForAction(const char *action) {
  readPanelSettings();
  persistSettings();
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    setPanelStatus(std::string("Set iPhone host and token before ") + action);
    return false;
  }
  return true;
}

void configureOnWorker(bool reportErrors = false) {
  readPanelSettings();
  persistSettings();
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    setPanelStatus("Pair the iPhone before changing the capture profile");
    return;
  }
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  runHelperOnWorker("configure", reashoot::core::commandArguments(settings, "configure", reashoot::core::configureArguments(settings)),
                    [reportErrors](reashoot::core::CommandResult result) {
                      if (result.exitCode != 0) {
                        if (isUnauthorizedResult(result)) {
                          g_iPhoneToken.clear();
                          persistSettings();
                          updatePanel();
                          setPanelStatus("Pair the iPhone before changing the capture profile");
                          if (reportErrors) {
                            showError("The iPhone rejected the saved pairing token. Pair again from ReaShoot Setup.");
                          }
                          return;
                        }
                        setPanelStatus("iPhone configure failed");
                        if (reportErrors) {
                          showError(resultError(result, "iPhone configure failed."));
                        }
                        return;
                      }
                      updatePanel();
                      if (g_extensionController.videoEnabled() && !playbackOwnsPreview()) {
                        startRemotePreview();
                      }
                    });
}

void discoverPhone() {
  runHelperOnWorker("discover", {"--timeout", "3"}, [](reashoot::core::CommandResult result) {
    if (result.exitCode != 0) {
      showError(resultError(result, "iPhone discovery failed."));
      return;
    }
    reashoot::core::FieldMap device = reashoot::core::parseFirstDevice(result.output);
    if (device.empty()) {
      showError("No ReaShoot iPhone was discovered on the local network.");
      return;
    }
    g_iPhoneHost = device["host"];
    if (!device["controlPort"].empty()) {
      g_iPhoneControlPort = device["controlPort"];
    }
    if (!device["httpPort"].empty()) {
      g_iPhoneHttpPort = device["httpPort"];
    }
    persistSettings();
    updatePanel();
  });
}

void pairPhone() {
  readPanelSettings();
  reashoot::platform::swell::SwellPanelSettings panelSettings = reashoot::platform::swell::swellPanelSettings(g_panel);
  if (g_iPhoneHost.empty() || panelSettings.pairingCode[0] == '\0') {
    showError("Enter the iPhone host and pairing code first.");
    return;
  }
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  runHelperOnWorker("pair",
                    reashoot::core::commandArguments(settings, "pair", {"--code", panelSettings.pairingCode}),
                    [](reashoot::core::CommandResult result) {
                      if (result.exitCode != 0) {
                        showError(resultError(result, "iPhone pairing failed."));
                        return;
                      }
                      std::istringstream stream(result.output);
                      std::string line;
                      while (std::getline(stream, line)) {
                        reashoot::core::FieldMap fields = reashoot::core::parseFields(line, ' ');
                        if (!fields["token"].empty()) {
                          g_iPhoneToken = withoutAsciiWhitespace(fields["token"]);
                          break;
                        }
                      }
                      if (g_iPhoneToken.empty()) {
                        showError("The iPhone paired, but no token was returned.");
                        return;
                      }
                      updatePanel();
                      setPanelStatus("iPhone paired. Click Reconnect to start preview.");
                      persistSettings();
                    });
}

std::vector<std::string> lookIDs() {
  return {"natural",       "warmVintage", "coolBlue",       "highContrastBW", "fadedFilm",
          "dreamGlow",     "noir",        "saturatedPop",   "bleachBypass",   "sepia",
          "instantPhoto",  "chrome",      "tonal",          "silvertone",     "dramaticWarm",
          "dramaticCool",  "softMatte",   "comicBook",      "vhs",            "musicVideoPop"};
}

void selectRelativeLook(int delta) {
  std::vector<std::string> looks = lookIDs();
  auto found = std::find(looks.begin(), looks.end(), g_iPhoneLook);
  int index = found == looks.end() ? 0 : static_cast<int>(found - looks.begin());
  index = (index + delta + static_cast<int>(looks.size())) % static_cast<int>(looks.size());
  g_iPhoneLook = looks[static_cast<size_t>(index)];
  updatePanel();
  persistSettings();
  if (!g_iPhoneToken.empty()) {
    configureOnWorker(false);
  }
}

void chooseLook(const char *lookID) {
  g_iPhoneLook = lookID && lookID[0] ? lookID : "natural";
  updatePanel();
  persistSettings();
  if (!g_iPhoneToken.empty()) {
    configureOnWorker(false);
  }
}

void stopPreviewStream() {
  g_previewStreamStarting = false;
  g_previewStreamActive = false;
  g_previewReceivedAccessUnit = false;
  g_previewReceivedFrame = false;
  if (g_previewStreamClient) {
    g_previewStreamClient->stop();
  }
  if (g_previewRenderer) {
    g_previewRenderer->reset();
    g_previewRenderer.reset();
  }
  if (!showingPlayback()) {
    setPreviewMode(PreviewMode::Idle);
    reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview stopped");
  }
}

void stopRemotePreview() {
  stopPreviewStream();
  if (!g_iPhoneHost.empty() && !g_iPhoneToken.empty()) {
    if (g_stoppingRemotePreview) {
      return;
    }
    g_stoppingRemotePreview = true;
    reashoot::core::RemoteCameraSettings settings = cameraSettings();
    runHelperOnWorker("stop-preview",
                      reashoot::core::commandArguments(settings, "stop-preview", reashoot::core::tokenArguments(settings)),
                      [](reashoot::core::CommandResult) {
                        g_stoppingRemotePreview = false;
                        const bool shouldRestart = g_restartPreviewAfterStop &&
                                                   !playbackOwnsPreview() &&
                                                   g_extensionController.videoEnabled();
                        g_restartPreviewAfterStop = false;
                        if (shouldRestart) {
                          startRemotePreview();
                        }
                      });
  }
}

void startPreviewStreamWithFields(const reashoot::core::FieldMap &fields) {
  if (playbackOwnsPreview() || g_previewStreamStarting || g_previewStreamActive || g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    return;
  }
  if (!g_previewStreamClient) {
    g_previewStreamClient = reashoot::platform::win32::createPreviewStreamClient();
  }
  const reashoot::core::PreviewStreamDescriptor descriptor =
      reashoot::core::previewStreamDescriptorFromFields(fields);
  if (!g_previewRenderer) {
    g_previewRenderer = reashoot::platform::win32::createH264PreviewRenderer([](const reashoot::core::VideoFrame &frame) {
      const auto queuedAt = std::chrono::steady_clock::now();
      postToMain([frame, queuedAt]() {
        if (frame.pixels.empty() || g_previewMode != PreviewMode::Live) {
          return;
        }
        (void)queuedAt;
        reashoot::platform::swell::setSwellPanelPreviewFrame(g_panel,
                                                             frame.pixels.data(),
                                                             frame.width,
                                                             frame.height,
                                                             frame.strideBytes);
        if (!g_previewReceivedFrame) {
          g_previewReceivedFrame = true;
          setPanelStatus("ReaShoot live video");
        }
      });
    });
  }
  reashoot::core::PreviewStreamRequest request;
  request.host = g_iPhoneHost;
  request.port = descriptor.port;
  request.path = descriptor.streamPath;
  request.token = g_iPhoneToken;
  g_previewStreamStarting = true;
  g_previewStreamActive = false;
  g_previewReceivedAccessUnit = false;
  g_previewReceivedFrame = false;
  reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview: connecting H.264 stream");
  setPanelStatus("Preview: connecting H.264 stream");
  const bool started = g_previewStreamClient->start(
      request,
      [](std::vector<uint8_t> accessUnit) {
        if (accessUnit.empty()) {
          return;
        }
        if (g_previewRenderer) {
          g_previewRenderer->renderAnnexBAccessUnit(accessUnit.data(), accessUnit.size());
        }
        postToMain([]() {
          if (!g_previewReceivedAccessUnit && g_previewMode == PreviewMode::Live) {
            g_previewReceivedAccessUnit = true;
            reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview: H.264 received; decoding");
            setPanelStatus("Preview: H.264 received; decoding");
          }
        });
      },
      []() {
        postToMain([]() {
          g_previewStreamStarting = false;
          g_previewStreamActive = true;
          if (g_previewMode == PreviewMode::Live) {
            setPanelStatus("Preview: H.264 stream");
          }
        });
      },
      [](const std::string &error) {
        postToMain([error]() {
          // Keep stream state accurate even during playback so live preview is
          // restarted when playback ends; just don't repaint over playback.
          g_previewStreamStarting = false;
          g_previewStreamActive = false;
          if (playbackOwnsPreview()) {
            return;
          }
          reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview: stream disconnected");
          setPanelStatus(error.empty() ? "Preview: stream disconnected" : error);
        });
      });
  if (!started) {
    g_previewStreamStarting = false;
    reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview: invalid stream URL");
    setPanelStatus("Preview: invalid stream URL");
  }
}

void startRemotePreview() {
  readPanelSettings();
  persistSettings();
  if (playbackOwnsPreview()) {
    return;
  }
  setPreviewMode(PreviewMode::Live);
  if (g_stoppingRemotePreview) {
    g_restartPreviewAfterStop = true;
    return;
  }
  if (g_iPhoneHost.empty() || g_iPhoneToken.empty()) {
    reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview unavailable: discover the iPhone, enter its pairing code, then Pair.");
    return;
  }
  if (g_previewStreamStarting || g_previewStreamActive) {
    return;
  }
  if (g_previewCommandInFlight) {
    return;
  }
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  g_previewCommandInFlight = true;
  setPanelStatus("Configuring iPhone preview");
  g_previewCommandHandle = remoteCameraController().runAsync(
      settings,
      "configure",
      reashoot::core::configureArguments(settings),
      {},
      [settings](reashoot::core::CommandResult configureResult) {
        postToMain([settings, configureResult = std::move(configureResult)]() mutable {
          if (configureResult.exitCode != 0) {
            g_previewCommandInFlight = false;
            if (showingPlayback()) {
              return;
            }
            if (isUnauthorizedResult(configureResult)) {
              g_iPhoneToken.clear();
              persistSettings();
              updatePanel();
              reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview unavailable: pair the iPhone again.");
              setPanelStatus("Pair the iPhone before starting preview");
              return;
            }
            reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview configure failed");
            setPanelStatus("Preview configure failed");
            showError(resultError(configureResult, "Preview configure failed."));
            return;
          }
          if (playbackOwnsPreview() || !g_extensionController.videoEnabled()) {
            g_previewCommandInFlight = false;
            return;
          }
          setPanelStatus("Preview: starting iPhone stream");
          g_previewCommandHandle = remoteCameraController().runAsync(
              settings,
              "start-preview",
              reashoot::core::tokenArguments(settings),
              {},
              [](reashoot::core::CommandResult result) {
                postToMain([result = std::move(result)]() mutable {
                  g_previewCommandInFlight = false;
                  if (playbackOwnsPreview()) {
                    return;
                  }
                  if (result.exitCode != 0) {
                    if (isUnauthorizedResult(result)) {
                      g_iPhoneToken.clear();
                      persistSettings();
                      updatePanel();
                      reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview unavailable: pair the iPhone again.");
                      setPanelStatus("Pair the iPhone before starting preview");
                      return;
                    }
                    reashoot::platform::swell::setSwellPanelPreviewPending(g_panel, "Preview start failed");
                    setPanelStatus("Preview start failed");
                    showError(resultError(result, "Preview start failed."));
                    return;
                  }
                  startPreviewStreamWithFields(reashoot::core::parseFields(result.output, '\t'));
                });
              });
        });
      });
}

void deleteRecordingByID(const std::string &recordingID,
                         const std::string &statusText,
                         std::function<void(bool)> completion = {}) {
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  setPanelStatus(statusText);
  g_deleteHandle = remoteCameraController().deleteRecording(settings, recordingID, [completion = std::move(completion)](reashoot::core::CommandResult result) mutable {
    postToMain([result = std::move(result), completion = std::move(completion)]() mutable {
      if (result.exitCode != 0) {
        setPanelStatus("iPhone delete failed");
        showError(resultError(result, "iPhone delete failed."));
        if (completion) {
          completion(false);
        }
        return;
      }
      setPanelStatus("Deleted pending iPhone recording");
      if (completion) {
        completion(true);
      }
    });
  });
}

void downloadRecordingAt(const reashoot::core::RemoteRecordingDescriptor &recording,
                         ReaProject *project,
                         double insertPosition) {
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  const std::string directory = captureOutputDirectory(project);
  const std::string expectedPath =
      (std::filesystem::path(directory) / (recording.filename.empty() ? "recording.mov" : recording.filename)).string();
  g_downloadHandle = remoteCameraController().downloadRecording(
      settings,
      recording,
      directory,
      [](const std::string &line) {
        const std::string status = reashoot::core::progressStatusText(line);
        if (!status.empty()) {
          postToMain([status]() { setPanelStatus(status); });
        }
      },
      [recording, expectedPath, project, insertPosition](reashoot::core::CommandResult result) {
        postToMain([recording, expectedPath, result = std::move(result), project, insertPosition]() mutable {
          bool recoveredCompletedDownload = false;
          if (result.exitCode != 0) {
            const int64_t expectedBytes = recording.byteCount.empty() ? 0 : std::strtoll(recording.byteCount.c_str(), nullptr, 10);
            std::error_code ec;
            const bool fileLooksComplete = std::filesystem::exists(expectedPath, ec) &&
                                           (expectedBytes <= 0 || static_cast<int64_t>(std::filesystem::file_size(expectedPath, ec)) == expectedBytes);
            if (!fileLooksComplete) {
              setPanelStatus("iPhone download failed");
              showError(resultError(result, "iPhone download failed."));
              return;
            }
            recoveredCompletedDownload = true;
            setPanelStatus("Downloaded iPhone video; transfer acknowledgement failed");
          }
          std::string path = reashoot::core::parseDownloadedPath(result.output);
          if (path.empty()) {
            if (!recoveredCompletedDownload) {
              setPanelStatus("iPhone download failed");
              showError("The iPhone video downloaded, but the helper did not report the downloaded path.");
              return;
            }
            path = expectedPath;
          }
          g_pendingInsertPath = path;
          g_pendingInsertPosition = insertPosition;
          g_pendingInsertProject = project;
          g_pendingInsert = true;
          updatePanel();
        });
      });
}

std::vector<reashoot::core::RemoteRecordingDescriptor> recordingsFromOutput(const std::string &output) {
  std::vector<reashoot::core::RemoteRecordingDescriptor> recordings;
  for (const reashoot::core::FieldMap &fields : reashoot::core::parseRecordings(output)) {
    recordings.push_back(reashoot::core::recordingDescriptorFromFields(fields));
  }
  return recordings;
}

void restorePendingRecording() {
  if (!ensureCameraConfiguredForAction("restore")) {
    return;
  }
  setPanelStatus("Checking iPhone recordings");
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  g_listHandle = remoteCameraController().listRecordings(settings, [](reashoot::core::CommandResult result) {
    postToMain([result = std::move(result)]() mutable {
      if (result.exitCode != 0) {
        setPanelStatus("iPhone recording list failed");
        showError(resultError(result, "iPhone recording list failed."));
        return;
      }
      std::vector<reashoot::core::RemoteRecordingDescriptor> recordings = recordingsFromOutput(result.output);
      if (recordings.empty()) {
        setPanelStatus("No pending iPhone recordings");
        showError("No pending iPhone recordings were found on the phone.");
        return;
      }

      for (const reashoot::core::RemoteRecordingDescriptor &recording : recordings) {
        const std::string filename = recording.filename.empty() ? recording.id : recording.filename;
        const std::string prompt = "Pending iPhone recording:\n\n" + filename +
                                   "\n\nYes = download and insert at the edit cursor\nNo = delete from iPhone\nCancel = skip";
        const int choice = MessageBoxA(g_panel, prompt.c_str(), "ReaShoot", MB_YESNOCANCEL | MB_ICONQUESTION);
        if (choice == IDYES) {
          ReaProject *project = reashoot::reaper::currentProject();
          downloadRecordingAt(recording, project, reashoot::reaper::cursorPosition(project));
          return;
        }
        if (choice == IDNO) {
          const std::string confirm = "Delete " + filename + " from the iPhone without downloading it?";
          if (MessageBoxA(g_panel, confirm.c_str(), "ReaShoot", MB_YESNO | MB_ICONWARNING) == IDYES) {
            deleteRecordingByID(recording.id, "Deleting iPhone video");
            return;
          }
        }
      }
      setPanelStatus("Restore canceled");
    });
  });
}

void deletePendingRecordingsSequentially(std::vector<reashoot::core::RemoteRecordingDescriptor> recordings, size_t index, size_t deleted) {
  if (index >= recordings.size()) {
    setPanelStatus("Deleted " + std::to_string(deleted) + " pending iPhone recording(s)");
    return;
  }
  deleteRecordingByID(recordings[index].id,
                      "Deleting iPhone video " + std::to_string(index + 1) + "/" + std::to_string(recordings.size()),
                      [recordings = std::move(recordings), index, deleted](bool success) mutable {
                        if (success) {
                          deletePendingRecordingsSequentially(std::move(recordings), index + 1, deleted + 1);
                        }
                      });
}

void deleteAllPendingRecordings() {
  if (!ensureCameraConfiguredForAction("delete")) {
    return;
  }
  setPanelStatus("Checking iPhone recordings");
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  g_listHandle = remoteCameraController().listRecordings(settings, [](reashoot::core::CommandResult result) {
    postToMain([result = std::move(result)]() mutable {
      if (result.exitCode != 0) {
        setPanelStatus("iPhone recording list failed");
        showError(resultError(result, "iPhone recording list failed."));
        return;
      }
      std::vector<reashoot::core::RemoteRecordingDescriptor> recordings = recordingsFromOutput(result.output);
      if (recordings.empty()) {
        setPanelStatus("No pending iPhone recordings");
        showError("No pending iPhone recordings were found on the phone.");
        return;
      }
      const std::string prompt = "Delete " + std::to_string(recordings.size()) +
                                 " pending iPhone recording(s) without downloading them?";
      if (MessageBoxA(g_panel, prompt.c_str(), "ReaShoot", MB_YESNO | MB_ICONWARNING) != IDYES) {
        setPanelStatus("Delete all canceled");
        return;
      }
      deletePendingRecordingsSequentially(std::move(recordings), 0, 0);
    });
  });
}

void ensurePanel() {
  if (g_panel) {
    return;
  }
  reashoot::platform::swell::SwellPanelCallbacks callbacks;
  callbacks.discover = [](void *) { discoverPhone(); };
  callbacks.pair = [](void *) { pairPhone(); };
  callbacks.testConnection = [](void *) { configureOnWorker(true); };
  callbacks.profileChanged = [](void *) {
    readPanelSettings();
    persistSettings();
    if (!g_iPhoneToken.empty()) {
      configureOnWorker(false);
    }
  };
  callbacks.previousLook = [](void *) { selectRelativeLook(-1); };
  callbacks.nextLook = [](void *) { selectRelativeLook(1); };
  callbacks.selectLook = [](void *, const char *lookID) { chooseLook(lookID); };
  callbacks.toggleDock = [](void *) { togglePreviewDockMode(); };
  callbacks.restorePending = [](void *) { restorePendingRecording(); };
  callbacks.deleteAllPending = [](void *) { deleteAllPendingRecordings(); };
  callbacks.closed = [](void *) {
    g_panelVisible = false;
  };
  g_panel = reashoot::platform::swell::createSwellPanelProbe(nullptr, callbacks);
  if (g_panel) {
    SetWindowTextA(g_panel, "ReaShoot Preview");
    WindowPlacement placement = defaultPreviewWindowPlacement();
    SetWindowPos(g_panel, nullptr, placement.x, placement.y, placement.width, placement.height, SWP_NOZORDER);
    updatePanel();
  }
}

void removePanelFromDock() {
  if (g_panel && g_panelDocked && DockWindowRemove) {
    DockWindowRemove(g_panel);
  }
  g_panelDocked = false;
}

void destroyPanel() {
  if (!g_panel) {
    return;
  }
  removePanelFromDock();
  DestroyWindow(g_panel);
  g_panel = nullptr;
}

void applyPanelDockMode() {
  if (!g_panel) {
    return;
  }
  if (!g_previewFloating) {
    if (DockWindowAddEx && !g_panelDocked) {
      DockWindowAddEx(g_panel, "ReaShoot", kDockIdent, true);
      g_panelDocked = true;
    }
    if (DockWindowActivate) {
      DockWindowActivate(g_panel);
    }
    if (DockWindowRefreshForHWND) {
      DockWindowRefreshForHWND(g_panel);
    }
    return;
  }
  removePanelFromDock();
  SetWindowLongPtr(g_panel, GWL_STYLE, WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
  SetWindowLongPtr(g_panel, GWL_EXSTYLE, GetWindowLongPtr(g_panel, GWL_EXSTYLE) | WS_EX_TOPMOST);
  SetParent(g_panel, nullptr);
  WindowPlacement placement = defaultPreviewWindowPlacement();
  SetWindowPos(g_panel, HWND_TOPMOST, placement.x, placement.y, placement.width, placement.height, SWP_FRAMECHANGED);
}

void showPanel(bool visible) {
  ensurePanel();
  if (!g_panel) {
    showError("ReaShoot could not create the Windows preview panel.");
    return;
  }
  g_panelVisible = visible;
  if (visible) {
    applyPanelDockMode();
  }
  reashoot::platform::swell::showWindow(g_panel, visible ? SW_SHOW : SW_HIDE);
  if (visible && g_extensionController.videoEnabled()) {
    startRemotePreview();
  }
}

void togglePreviewDockMode() {
  g_previewFloating = !g_previewFloating;
  persistSettings();
  if (g_panel) {
    stopPreviewStream();
    destroyPanel();
  }
  showPanel(true);
}

MediaTrack *findVideoTrack(ReaProject *project) {
  if (!CountTracks || !GetTrack || !GetTrackName) {
    return nullptr;
  }
  const int trackCount = CountTracks(project);
  for (int i = 0; i < trackCount; ++i) {
    MediaTrack *track = GetTrack(project, i);
    char name[256] = {};
    if (track && GetTrackName(track, name, sizeof(name)) && std::string(name) == kVideoTrackName) {
      return track;
    }
  }
  return nullptr;
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
    if (filePath[0] == '\0' || !reashoot::core::isVideoPath(filePath)) {
      continue;
    }
    result.found = true;
    result.path = filePath;
    result.itemStart = itemStart;
    result.itemEnd = itemEnd;
    result.sourceOffset = GetMediaItemTakeInfo_Value ? GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") : 0.0;
    result.playRate = GetMediaItemTakeInfo_Value ? GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") : 1.0;
    if (result.playRate <= 0.0) {
      result.playRate = 1.0;
    }
    return result;
  }
  return result;
}

MediaTrack *ensureVideoTrackReady(ReaProject *project) {
  if (!InsertTrackAtIndex || !GetSetMediaTrackInfo_String || !CountTracks || !GetTrack || !SetMediaTrackInfo_Value) {
    return nullptr;
  }
  MediaTrack *track = findVideoTrack(project);
  if (!track) {
    const int trackCount = CountTracks(project);
    InsertTrackAtIndex(trackCount, true);
    track = GetTrack(project, trackCount);
    if (track) {
      char name[] = "ReaShoot";
      GetSetMediaTrackInfo_String(track, "P_NAME", name, true);
    }
  }
  if (track) {
    SetMediaTrackInfo_Value(track, "I_RECARM", 0.0);
    SetMediaTrackInfo_Value(track, "I_RECINPUT", -1.0);
    SetMediaTrackInfo_Value(track, "I_RECMODE", 2.0);
    SetMediaTrackInfo_Value(track, "I_RECMON", 0.0);
    SetMediaTrackInfo_Value(track, "I_RECMONITEMS", 0.0);
    SetMediaTrackInfo_Value(track, "B_AUTO_RECARM", 0.0);
  }
  reashoot::reaper::refreshArrangeTimeline();
  return track;
}

std::string captureOutputDirectory(ReaProject *project) {
  std::string outputRoot = reashoot::reaper::defaultRecordingPath();
  std::string projectName = "unsaved_project";
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
  std::filesystem::path directory = std::filesystem::path(outputRoot) / "ReaShoot Recordings";
  std::filesystem::create_directories(directory);
  return directory.string();
}

MediaItem *insertMediaItem(MediaTrack *track, const std::string &path, double position, std::string &error) {
  PCM_source *source = PCM_Source_CreateFromFile ? PCM_Source_CreateFromFile(path.c_str()) : nullptr;
  if (!source) {
    error = "Recording finished, but REAPER could not open the video file:\n" + path;
    return nullptr;
  }
  MediaItem *item = AddMediaItemToTrack ? AddMediaItemToTrack(track) : nullptr;
  MediaItem_Take *take = item && AddTakeToMediaItem ? AddTakeToMediaItem(item) : nullptr;
  if (!item || !take || !SetMediaItemTake_Source || !SetMediaItemTake_Source(take, source)) {
    error = "Recording finished, but REAPER could not create a video media item.";
    return nullptr;
  }
  bool lengthIsQN = false;
  const double length = GetMediaSourceLength ? GetMediaSourceLength(source, &lengthIsQN) : 0.0;
  reashoot::reaper::moveMediaItem(item, position);
  if (!lengthIsQN && length > 0.0 && SetMediaItemInfo_Value) {
    SetMediaItemInfo_Value(item, "D_LENGTH", length);
    SetMediaItemInfo_Value(item, "B_LOOPSRC", 0.0);
  }
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

void processPendingInsert() {
  if (!g_pendingInsert) {
    return;
  }
  g_pendingInsert = false;
  ReaProject *project = g_pendingInsertProject ? g_pendingInsertProject : reashoot::reaper::currentProject();
  MediaTrack *track = ensureVideoTrackReady(project);
  if (!track) {
    showError("Recording downloaded, but ReaShoot could not create the ReaShoot track.");
    return;
  }
  std::string error;
  if (!insertMediaItem(track, g_pendingInsertPath, g_pendingInsertPosition, error)) {
    showError(error);
    return;
  }
  reashoot::reaper::refreshArrangeTimeline();
  setPanelStatus("Inserted iPhone recording on ReaShoot track");
  g_pendingInsertProject = nullptr;
}

void ensurePlaybackPreviewRenderer() {
  if (g_playbackPreviewRenderer) {
    return;
  }
  g_playbackPreviewRenderer = reashoot::platform::win32::createPlaybackPreview(
      [](const reashoot::core::VideoFrame &frame) {
        postToMain([frame]() {
          if (frame.pixels.empty() || g_previewMode != PreviewMode::Playback) {
            return;
          }
          reashoot::platform::swell::setSwellPanelPreviewFrame(g_panel,
                                                               frame.pixels.data(),
                                                               frame.width,
                                                               frame.height,
                                                               frame.strideBytes);
        });
      },
      [](const reashoot::core::PlaybackDecoderStatus &status) {
        const std::string system = status.system.empty() ? (status.hardwareAccelerated ? "hardware" : "FFmpeg software") : status.system;
        const std::string statusText = std::string(status.hardwareAccelerated ? "HW decode: " : "Software decode: ") + system;
        postToMain([statusText]() {
          g_playbackDecoderStatus = statusText;
          if (showingPlayback()) {
            setPanelStatus("Playback: " + g_playbackDecoderStatus);
          }
        });
      });
}

void updatePlaybackWithVideo(const PlaybackVideo &video, double projectPosition) {
  ensurePanel();
  ensurePlaybackPreviewRenderer();
  const bool enteringPlayback = !showingPlayback();
  if (enteringPlayback) {
    // Take ownership of the panel for playback. We intentionally do NOT tear
    // down the live H.264 stream here: leaving it running (its frames are now
    // gated out by PreviewMode) avoids the configure/start-preview churn that
    // previously fired on every play/stop and made the panel blink. Any
    // in-flight preview command will simply no-op on completion because
    // playbackOwnsPreview() is now true.
    g_previewCommandInFlight = false;
    g_restartPreviewAfterStop = false;
    setPreviewMode(PreviewMode::Playback);
  }
  if (g_playbackPreviewRenderer) {
    const double sourceOffset = video.sourceOffset + ((projectPosition - video.itemStart) * (video.playRate - 1.0));
    g_playbackPreviewRenderer->showMedia(video.path, video.itemStart, sourceOffset, projectPosition);
    setPanelStatus(g_playbackDecoderStatus.empty() ? "Playback: decoder starting" : "Playback: " + g_playbackDecoderStatus);
  }
}

void stopPlaybackAndShowLive() {
  if (!showingPlayback()) {
    return;
  }
  g_transportPlaybackActive = false;
  g_lastPlaybackVideoHit = {};
  g_playbackDecoderStatus.clear();
  if (g_playbackPreviewRenderer) {
    g_playbackPreviewRenderer->hide();
  }
  if (g_extensionController.videoEnabled()) {
    // Hand the panel back to live preview. If the live stream is still
    // connected (we never stopped it), just resume painting its frames; only
    // (re)issue configure/start-preview when the stream is actually gone.
    setPreviewMode(PreviewMode::Live);
    if (g_previewStreamActive || g_previewStreamStarting) {
      setPanelStatus(g_previewReceivedFrame ? "ReaShoot live video" : "Preview: H.264 stream");
    } else {
      startRemotePreview();
    }
  } else {
    setPreviewMode(PreviewMode::Idle);
    updatePanel();
  }
}

void beginRecording() {
  if (g_activeTransportRecording || g_iPhoneToken.empty() || g_iPhoneHost.empty()) {
    return;
  }
  g_activeTransportRecording = true;
  g_recordProject = reashoot::reaper::currentProject();
  g_recordStartPosition = GetCursorPositionEx ? GetCursorPositionEx(g_recordProject) : 0.0;
  ensureVideoTrackReady(g_recordProject);
  updatePanel();
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  const std::string sessionID = "reaper-" + reashoot::core::timestampString();
  runHelperOnWorker("start",
                    reashoot::core::commandArguments(settings, "start", reashoot::core::startArguments(settings, sessionID)),
                    [](reashoot::core::CommandResult result) {
                      if (result.exitCode != 0) {
                        showError(resultError(result, "iPhone start failed."));
                      }
                    });
}

void finishRecording() {
  if (!g_activeTransportRecording) {
    return;
  }
  g_activeTransportRecording = false;
  updatePanel();
  reashoot::core::RemoteCameraSettings settings = cameraSettings();
  g_stopHandle = remoteCameraController().stop(settings, [](reashoot::core::CommandResult result) {
    postToMain([result = std::move(result)]() mutable {
      if (result.exitCode != 0) {
        showError(result.errorMessage.empty() ? result.output : result.errorMessage);
        return;
      }
      std::vector<reashoot::core::FieldMap> recordings = reashoot::core::parseRecordings(result.output);
      if (recordings.empty()) {
        showError("The iPhone stopped recording, but no recording metadata was returned.");
        return;
      }
      reashoot::core::RemoteRecordingDescriptor recording =
          reashoot::core::recordingDescriptorFromFields(recordings.front());
      const int choice = MessageBoxA(g_panel,
                                     ("Download " + recording.filename + " into the REAPER project?").c_str(),
                                     "ReaShoot",
                                     MB_YESNO | MB_ICONQUESTION);
      if (choice == IDYES) {
        downloadRecordingAt(recording, g_recordProject, g_recordStartPosition);
      }
    });
  });
}

void pollTransport() {
  if (!g_extensionController.videoEnabled() || !g_extensionController.followEnabled() || !GetPlayStateEx) {
    return;
  }
  ReaProject *project = reashoot::reaper::currentProject();
  const int playState = GetPlayStateEx(project);
  const bool wasRecording = (g_previousPlayState & kRecordBit) != 0;
  const bool isRecording = (playState & kRecordBit) != 0;
  const bool isPlaying = (playState & 1) != 0;
  if (!wasRecording && isRecording) {
    beginRecording();
  } else if (wasRecording && !isRecording) {
    finishRecording();
  }
  if (!isRecording && isPlaying && GetPlayPositionEx) {
    const double position = GetPlayPositionEx(project);
    PlaybackVideo video = findPlaybackVideoAtPosition(project, position);
    if (video.found) {
      const auto now = std::chrono::steady_clock::now();
      g_transportPlaybackActive = true;
      g_lastPlaybackVideoHit = now;
      updatePlaybackWithVideo(video, position);
    } else if (!showingPlayback()) {
      return;
    }
  } else if (!isRecording &&
             (!showingPlayback() ||
              g_lastPlaybackVideoHit.time_since_epoch().count() == 0 ||
              std::chrono::steady_clock::now() - g_lastPlaybackVideoHit > kPlaybackMissGrace)) {
    g_transportPlaybackActive = false;
    stopPlaybackAndShowLive();
  }
  g_previousPlayState = playState;
}

void setVideoEnabled(bool enabled) {
  g_extensionController.setVideoEnabled(enabled);
  if (enabled) {
    ensureVideoTrackReady(reashoot::reaper::currentProject());
    showPanel(true);
    startRemotePreview();
  } else {
    finishRecording();
    stopPlaybackAndShowLive();
    stopRemotePreview();
  }
  updatePanel();
  persistSettings();
  reashoot::reaper::refreshToolbar(g_videoEnabledCommand);
}

bool hookCommand2(KbdSectionInfo *, int command, int, int, int, HWND) {
  if (command == g_videoEnabledCommand) {
    setVideoEnabled(!g_extensionController.videoEnabled());
    return true;
  }
  if (command == g_floatPreviewCommand) {
    togglePreviewDockMode();
    return true;
  }
  if (command == g_alignSelectedCommand) {
    showError("Manual video alignment is not implemented in the Windows preview build yet.");
    return true;
  }
  if (command == g_restoreIPhoneCommand) {
    restorePendingRecording();
    return true;
  }
  if (command == g_deleteAllIPhoneCommand) {
    deleteAllPendingRecordings();
    return true;
  }
  if (command == g_toggleFollowCommand) {
    g_extensionController.setFollowEnabled(!g_extensionController.followEnabled());
    persistSettings();
    reashoot::reaper::refreshToolbar(g_toggleFollowCommand);
    updatePanel();
    return true;
  }
  return false;
}

int toggleActionHook(int command) {
  if (command == g_videoEnabledCommand) {
    return g_extensionController.videoEnabled() ? 1 : 0;
  }
  if (command == g_toggleFollowCommand) {
    return g_extensionController.followEnabled() ? 1 : 0;
  }
  return -1;
}

void timerPoll() {
  drainMainQueue();
  processPendingInsert();
  pollTransport();
}

void cleanup() {
  persistSettings();
  if (g_stopHandle && g_stopHandle->isRunning()) {
    g_stopHandle->terminate();
  }
  if (g_downloadHandle && g_downloadHandle->isRunning()) {
    g_downloadHandle->terminate();
  }
  if (g_listHandle && g_listHandle->isRunning()) {
    g_listHandle->terminate();
  }
  if (g_deleteHandle && g_deleteHandle->isRunning()) {
    g_deleteHandle->terminate();
  }
  if (g_previewCommandHandle && g_previewCommandHandle->isRunning()) {
    g_previewCommandHandle->terminate();
  }
  stopPreviewStream();
  g_previewRenderer.reset();
  destroyPanel();
  g_playbackPreviewRenderer.reset();
}

custom_action_register_t action(const char *id, const char *name) {
  custom_action_register_t action = {};
  action.idStr = id;
  action.name = name;
  return action;
}

bool registerActions(reaper_plugin_info_t *rec) {
  custom_action_register_t videoEnabledAction = action("KLONG_REASHOOT_ENABLE", "ReaShoot: Enable ReaShoot");
  custom_action_register_t floatPreviewAction = action("KLONG_REASHOOT_FLOAT_PREVIEW", "ReaShoot: Float/Dock Preview");
  custom_action_register_t alignSelectedAction = action("KLONG_REASHOOT_ALIGN_SELECTED", "ReaShoot: Align Selected Video Item");
  custom_action_register_t restoreIPhoneAction = action("KLONG_REASHOOT_RESTORE_IPHONE", "ReaShoot: Restore Pending iPhone Recording");
  custom_action_register_t deleteAllIPhoneAction = action("KLONG_REASHOOT_DELETE_ALL_IPHONE", "ReaShoot: Delete All Pending iPhone Recordings");
  custom_action_register_t toggleFollowAction = action("KLONG_REASHOOT_TOGGLE_FOLLOW", "ReaShoot: Enable/Disable Transport Follow");
  g_videoEnabledCommand = rec->Register("custom_action", &videoEnabledAction);
  g_floatPreviewCommand = rec->Register("custom_action", &floatPreviewAction);
  g_alignSelectedCommand = rec->Register("custom_action", &alignSelectedAction);
  g_restoreIPhoneCommand = rec->Register("custom_action", &restoreIPhoneAction);
  g_deleteAllIPhoneCommand = rec->Register("custom_action", &deleteAllIPhoneAction);
  g_toggleFollowCommand = rec->Register("custom_action", &toggleFollowAction);
  return g_videoEnabledCommand != 0 && g_floatPreviewCommand != 0 &&
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
  std::string follow = reashoot::reaper::extState(kExtStateSection, kFollowEnabledKey);
  if (!follow.empty()) {
    g_extensionController.setFollowEnabled(follow != "0");
  }
  std::string previewFloating = reashoot::reaper::extState(kExtStateSection, kPreviewFloatingKey);
  if (!previewFloating.empty()) {
    g_previewFloating = previewFloating != "0";
  }
  auto load = [](const char *key, std::string &value) {
    std::string loaded = reashoot::reaper::extState(kExtStateSection, key);
    if (!loaded.empty()) {
      value = loaded;
    }
  };
  load(kIPhoneHostKey, g_iPhoneHost);
  load(kIPhoneControlPortKey, g_iPhoneControlPort);
  load(kIPhoneHttpPortKey, g_iPhoneHttpPort);
  load(kIPhoneTokenKey, g_iPhoneToken);
  g_iPhoneToken = withoutAsciiWhitespace(g_iPhoneToken);
  load(kIPhoneResolutionKey, g_iPhoneResolution);
  load(kIPhoneFPSKey, g_iPhoneFPS);
  load(kIPhoneOrientationKey, g_iPhoneOrientation);
  load(kIPhoneAspectKey, g_iPhoneAspect);
  load(kIPhoneLensKey, g_iPhoneLens);
  load(kIPhoneZoomKey, g_iPhoneZoom);
  load(kIPhoneLookKey, g_iPhoneLook);
}

} // namespace

extern "C" {

REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE hInstance, reaper_plugin_info_t *rec) {
  if (!rec) {
    if (g_reaper) {
      cleanup();
      unregisterCallbacks(g_reaper);
    }
    g_reaper = nullptr;
    return 0;
  }

  g_instance = reinterpret_cast<HINSTANCE>(hInstance);
  g_reaper = rec;
  if (REAPERAPI_LoadAPI(rec->GetFunc) != 0) {
    return 0;
  }
  loadSettings();
  if (!registerActions(rec)) {
    showError("ReaShoot failed to register its Windows actions.");
    return 0;
  }
  return 1;
}

}
