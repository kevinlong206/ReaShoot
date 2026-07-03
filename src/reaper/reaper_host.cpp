#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_GetResourcePath
#define REAPERAPI_WANT_RefreshToolbar2
#define REAPERAPI_WANT_SetExtState
#include "reaper_plugin_functions.h"

#include "reaper_host.h"

namespace reashoot::reaper {

std::string resourcePath() {
  if (!GetResourcePath) {
    return {};
  }
  const char *path = GetResourcePath();
  return path ? path : "";
}

std::string extState(const char *section, const char *key) {
  if (!GetExtState) {
    return {};
  }
  const char *value = GetExtState(section, key);
  return value ? value : "";
}

bool setExtState(const char *section, const char *key, const char *value, bool persist) {
  if (!SetExtState) {
    return false;
  }
  SetExtState(section, key, value ? value : "", persist);
  return true;
}

void refreshToolbar(int commandId) {
  if (RefreshToolbar2 && commandId != 0) {
    RefreshToolbar2(0, commandId);
  }
}

} // namespace reashoot::reaper
