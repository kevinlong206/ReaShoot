#include "reashoot/plugin_settings.h"

namespace reashoot {

namespace {

bool parseBool(const std::string &value) { return value == "1"; }

} // namespace

PluginSettings loadSettings(const ISettingsStore &store) {
  using namespace settings_keys;

  PluginSettings settings;
  settings.host = store.getString(kSection, kHost);
  settings.controlPort = store.getString(kSection, kControlPort);
  settings.httpPort = store.getString(kSection, kHttpPort);
  settings.token = store.getString(kSection, kToken);
  settings.resolution = store.getString(kSection, kResolution);
  settings.fps = store.getString(kSection, kFps);
  settings.orientation = store.getString(kSection, kOrientation);
  settings.aspect = store.getString(kSection, kAspect);
  settings.lens = store.getString(kSection, kLens);
  settings.zoom = store.getString(kSection, kZoom);
  settings.look = store.getString(kSection, kLook);
  settings.followEnabled = parseBool(store.getString(kSection, kFollowEnabled));
  settings.previewFloating = parseBool(store.getString(kSection, kPreviewFloating));
  settings.previewAlwaysOnTop = parseBool(store.getString(kSection, kPreviewAlwaysOnTop));
  return settings;
}

void saveSettings(ISettingsStore &store, const PluginSettings &settings) {
  using namespace settings_keys;

  store.setString(kSection, kHost, settings.host);
  store.setString(kSection, kControlPort, settings.controlPort);
  store.setString(kSection, kHttpPort, settings.httpPort);
  store.setString(kSection, kToken, settings.token);
  store.setString(kSection, kResolution, settings.resolution);
  store.setString(kSection, kFps, settings.fps);
  store.setString(kSection, kOrientation, settings.orientation);
  store.setString(kSection, kAspect, settings.aspect);
  store.setString(kSection, kLens, settings.lens);
  store.setString(kSection, kZoom, settings.zoom);
  store.setString(kSection, kLook, settings.look);
  store.setString(kSection, kFollowEnabled, settings.followEnabled ? "1" : "0");
  store.setString(kSection, kPreviewFloating, settings.previewFloating ? "1" : "0");
  store.setString(kSection, kPreviewAlwaysOnTop, settings.previewAlwaysOnTop ? "1" : "0");
}

} // namespace reashoot
