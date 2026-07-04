#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_EnumProjects
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_GetCursorPositionEx
#define REAPERAPI_WANT_GetProjectPathEx
#define REAPERAPI_WANT_GetResourcePath
#define REAPERAPI_WANT_get_ini_file
#define REAPERAPI_WANT_RefreshToolbar2
#define REAPERAPI_WANT_SetExtState
#define REAPERAPI_WANT_SetMediaItemInfo_Value
#define REAPERAPI_WANT_UpdateArrange
#define REAPERAPI_WANT_UpdateTimeline
#include "reaper_plugin_functions.h"

#include "reaper_host.h"

#include <fstream>
#include <string>

namespace reashoot::reaper {
namespace {

std::string trim(std::string value) {
  while (!value.empty() && (value.back() == '\r' || value.back() == '\n' || value.back() == ' ' || value.back() == '\t')) {
    value.pop_back();
  }
  size_t start = 0;
  while (start < value.size() && (value[start] == ' ' || value[start] == '\t')) {
    ++start;
  }
  return start == 0 ? value : value.substr(start);
}

} // namespace

ReaProject *currentProject(std::string *projectFileOut) {
  char projectFile[4096] = {};
  if (!EnumProjects) {
    return nullptr;
  }
  ReaProject *project = EnumProjects(-1, projectFile, sizeof(projectFile));
  if (projectFileOut) {
    *projectFileOut = projectFile;
  }
  return project;
}

std::string projectPath(ReaProject *project) {
  char path[4096] = {};
  if (GetProjectPathEx && project) {
    GetProjectPathEx(project, path, sizeof(path));
  }
  return path;
}

std::string defaultRecordingPath() {
  if (!get_ini_file) {
    return {};
  }
  const char *iniPath = get_ini_file();
  if (!iniPath || !iniPath[0]) {
    return {};
  }
  std::ifstream ini(iniPath);
  std::string line;
  while (std::getline(ini, line)) {
    line = trim(line);
    constexpr const char *prefix = "defrecpath=";
    if (line.rfind(prefix, 0) == 0) {
      std::string value = trim(line.substr(std::char_traits<char>::length(prefix)));
      if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
        value = value.substr(1, value.size() - 2);
      }
      return value;
    }
  }
  return {};
}

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

double cursorPosition(ReaProject *project) {
  return GetCursorPositionEx ? GetCursorPositionEx(project) : 0.0;
}

void moveMediaItem(MediaItem *item, double position) {
  if (SetMediaItemInfo_Value && item) {
    SetMediaItemInfo_Value(item, "D_POSITION", position);
  }
}

void refreshArrangeTimeline() {
  if (UpdateArrange) {
    UpdateArrange();
  }
  if (UpdateTimeline) {
    UpdateTimeline();
  }
}

void refreshToolbar(int commandId) {
  if (RefreshToolbar2 && commandId != 0) {
    RefreshToolbar2(0, commandId);
  }
}

} // namespace reashoot::reaper
