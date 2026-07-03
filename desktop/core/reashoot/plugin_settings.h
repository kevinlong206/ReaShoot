#pragma once

#include <string>

namespace reashoot {

// Host-neutral persisted settings for the ReaShoot plugin. Field names and
// the backing store keys mirror the macOS plugin's REAPER ExtState 1:1 so that
// settings are interchangeable across platforms.
struct PluginSettings {
  std::string host;
  std::string controlPort;
  std::string httpPort;
  std::string token;
  std::string resolution;
  std::string fps;
  std::string orientation;
  std::string aspect;
  std::string lens;
  std::string zoom;
  std::string look;
  bool followEnabled = false;
  bool previewFloating = false;
};

// Abstract key/value store so the plugin can back this with REAPER ExtState while
// tests use an in-memory implementation. Values are UTF-8 strings.
class ISettingsStore {
public:
  virtual ~ISettingsStore() = default;

  // Returns the stored value for the key, or an empty string if unset.
  virtual std::string getString(const std::string &section, const std::string &key) const = 0;

  // Persists the value for the key.
  virtual void setString(const std::string &section, const std::string &key, const std::string &value) = 0;
};

// ExtState section and key identifiers, matching the macOS plugin.
namespace settings_keys {

inline constexpr const char *kSection = "klong_reashoot";
inline constexpr const char *kFollowEnabled = "follow_enabled";
inline constexpr const char *kPreviewFloating = "preview_floating";
inline constexpr const char *kHost = "iphone_host";
inline constexpr const char *kControlPort = "iphone_control_port";
inline constexpr const char *kHttpPort = "iphone_http_port";
inline constexpr const char *kToken = "iphone_token";
inline constexpr const char *kResolution = "iphone_resolution";
inline constexpr const char *kFps = "iphone_fps";
inline constexpr const char *kOrientation = "iphone_orientation";
inline constexpr const char *kAspect = "iphone_aspect";
inline constexpr const char *kLens = "iphone_lens";
inline constexpr const char *kZoom = "iphone_zoom";
inline constexpr const char *kLook = "iphone_look";

} // namespace settings_keys

// Reads all known settings from the store into a PluginSettings.
PluginSettings loadSettings(const ISettingsStore &store);

// Writes all settings from the struct back into the store.
void saveSettings(ISettingsStore &store, const PluginSettings &settings);

} // namespace reashoot
