#ifndef _WIN32
#error "reaphonevideo_win_skeleton.cpp is only intended for Windows builds."
#endif

#include "reaper_plugin.h"

#define REAPERAPI_IMPLEMENT
#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_ShowConsoleMsg
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_SetExtState
#include "reaper_plugin_functions.h"

#include "reaphone_action_ids.h"

#include "reaphone/debug_logger.h"
#include "reaphone/plugin_settings.h"
#include "reaphone/windows/helper_launcher.h"

#include "preview_panel_win32.h"

#include <windows.h>

#include <filesystem>
#include <memory>
#include <string>
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

std::unique_ptr<reaphone::Win32PreviewPanel> g_previewPanel;

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
  runCommand("stop", settings, {L"--token", widen(settings.token)});
}

void handleShowPreview() {
  reaphone::Win32PreviewPanel &panel = previewPanel();
  if (panel.isVisible()) {
    panel.hide();
    report("ReaPhoneVideo: preview hidden.");
  } else {
    panel.show();
    report("ReaPhoneVideo: preview shown (WebRTC rendering not yet wired).");
  }
}

void handleFloatPreview() {
  reaphone::Win32PreviewPanel &panel = previewPanel();
  panel.setFloating(!panel.isFloating());
  report(panel.isFloating() ? "ReaPhoneVideo: preview set to floating."
                            : "ReaPhoneVideo: preview set to docked.");
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
  return false;
}

int registerAction(reaper_plugin_info_t *rec, const char *id, const char *name) {
  custom_action_register_t action = {0, id, name, nullptr};
  return rec->Register("custom_action", &action);
}

bool registerActions(reaper_plugin_info_t *rec) {
  using namespace reaphone::actions;

  g_diagnosticCommand = registerAction(rec, kWindowsDiagnosticId, kWindowsDiagnosticName);
  g_pairCommand = registerAction(rec, kPairId, kPairName);
  g_testConnectionCommand = registerAction(rec, kTestConnectionId, kTestConnectionName);
  g_startCommand = registerAction(rec, kStartRecordingId, kStartRecordingName);
  g_stopCommand = registerAction(rec, kStopRecordingId, kStopRecordingName);
  g_showPreviewCommand = registerAction(rec, kShowPreviewId, kShowPreviewName);
  g_floatPreviewCommand = registerAction(rec, kFloatPreviewId, kFloatPreviewName);

  const bool allRegistered = g_diagnosticCommand != 0 && g_pairCommand != 0 &&
                             g_testConnectionCommand != 0 && g_startCommand != 0 &&
                             g_stopCommand != 0 && g_showPreviewCommand != 0 &&
                             g_floatPreviewCommand != 0;

  return allRegistered && rec->Register("hookcommand2", reinterpret_cast<void *>(hookCommand2));
}

void unregisterActions(reaper_plugin_info_t *rec) {
  rec->Register("-hookcommand2", reinterpret_cast<void *>(hookCommand2));
}

} // namespace

extern "C" {

REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(REAPER_PLUGIN_HINSTANCE hInstance, reaper_plugin_info_t *rec) {
  g_instance = static_cast<HINSTANCE>(hInstance);

  if (!rec) {
    if (g_reaper) {
      unregisterActions(g_reaper);
    }
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
