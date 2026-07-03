#include "reashoot/plugin_settings.h"

#include <cassert>
#include <iostream>
#include <map>
#include <string>

namespace {

class InMemoryStore : public reashoot::ISettingsStore {
public:
  std::string getString(const std::string &section, const std::string &key) const override {
    const auto it = values_.find(section + "|" + key);
    return it == values_.end() ? std::string() : it->second;
  }

  void setString(const std::string &section, const std::string &key, const std::string &value) override {
    values_[section + "|" + key] = value;
  }

  std::map<std::string, std::string> values_;
};

void testDefaultsAreEmpty() {
  InMemoryStore store;
  const reashoot::PluginSettings settings = reashoot::loadSettings(store);

  assert(settings.host.empty());
  assert(settings.token.empty());
  assert(settings.controlPort.empty());
  assert(settings.httpPort.empty());
  assert(settings.followEnabled == false);
  assert(settings.previewFloating == false);
}

void testRoundTrip() {
  InMemoryStore store;

  reashoot::PluginSettings settings;
  settings.host = "kevin-long-iphone.local";
  settings.controlPort = "8787";
  settings.httpPort = "8788";
  settings.token = "abc123";
  settings.resolution = "1920x1080";
  settings.fps = "30";
  settings.orientation = "landscape";
  settings.aspect = "16:9";
  settings.lens = "wide";
  settings.zoom = "1.0";
  settings.look = "natural";
  settings.followEnabled = true;
  settings.previewFloating = true;

  reashoot::saveSettings(store, settings);
  const reashoot::PluginSettings loaded = reashoot::loadSettings(store);

  assert(loaded.host == settings.host);
  assert(loaded.controlPort == settings.controlPort);
  assert(loaded.httpPort == settings.httpPort);
  assert(loaded.token == settings.token);
  assert(loaded.resolution == settings.resolution);
  assert(loaded.fps == settings.fps);
  assert(loaded.orientation == settings.orientation);
  assert(loaded.aspect == settings.aspect);
  assert(loaded.lens == settings.lens);
  assert(loaded.zoom == settings.zoom);
  assert(loaded.look == settings.look);
  assert(loaded.followEnabled == true);
  assert(loaded.previewFloating == true);
}

void testBooleanEncoding() {
  InMemoryStore store;

  reashoot::PluginSettings settings;
  settings.followEnabled = false;
  settings.previewFloating = true;
  reashoot::saveSettings(store, settings);

  assert(store.getString(reashoot::settings_keys::kSection, reashoot::settings_keys::kFollowEnabled) == "0");
  assert(store.getString(reashoot::settings_keys::kSection, reashoot::settings_keys::kPreviewFloating) == "1");
}

void testUsesMacOsCompatibleKeys() {
  InMemoryStore store;

  reashoot::PluginSettings settings;
  settings.host = "host.local";
  settings.token = "tok";
  reashoot::saveSettings(store, settings);

  // These exact section/key strings must match the macOS plugin's ExtState.
  assert(store.getString("klong_reashoot", "iphone_host") == "host.local");
  assert(store.getString("klong_reashoot", "iphone_token") == "tok");
}

} // namespace

int main() {
  testDefaultsAreEmpty();
  testRoundTrip();
  testBooleanEncoding();
  testUsesMacOsCompatibleKeys();
  std::cout << "plugin_settings_tests passed\n";
  return 0;
}
