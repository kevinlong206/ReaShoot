#define REAPERAPI_MINIMAL
#define REAPERAPI_WANT_AddMediaItemToTrack
#define REAPERAPI_WANT_AddTakeToMediaItem
#define REAPERAPI_WANT_CountTracks
#define REAPERAPI_WANT_EnumProjects
#define REAPERAPI_WANT_GetExtState
#define REAPERAPI_WANT_GetCursorPositionEx
#define REAPERAPI_WANT_GetMediaSourceLength
#define REAPERAPI_WANT_GetProjectPathEx
#define REAPERAPI_WANT_GetResourcePath
#define REAPERAPI_WANT_GetSetMediaTrackInfo_String
#define REAPERAPI_WANT_GetTrack
#define REAPERAPI_WANT_get_ini_file
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

int messageBox(const std::string &text, const std::string &title, int flags) {
  return ShowMessageBox ? ShowMessageBox(text.c_str(), title.c_str(), flags) : 0;
}

namespace {

constexpr const char *kReaShootTrackName = "ReaShoot";

MediaTrack *findReaShootTrack(ReaProject *project) {
  if (!CountTracks || !GetTrack || !GetSetMediaTrackInfo_String) {
    return nullptr;
  }
  const int count = CountTracks(project);
  for (int i = 0; i < count; ++i) {
    MediaTrack *track = GetTrack(project, i);
    if (!track) {
      continue;
    }
    char name[512] = {};
    if (GetSetMediaTrackInfo_String(track, "P_NAME", name, false) && std::string(name) == kReaShootTrackName) {
      return track;
    }
  }
  return nullptr;
}

} // namespace

MediaTrack *ensureReaShootTrack(ReaProject *project) {
  if (!CountTracks || !GetTrack || !InsertTrackAtIndex || !GetSetMediaTrackInfo_String || !SetMediaTrackInfo_Value) {
    return nullptr;
  }
  MediaTrack *track = findReaShootTrack(project);
  if (!track) {
    const int count = CountTracks(project);
    InsertTrackAtIndex(count, true);
    track = GetTrack(project, count);
    if (track) {
      char name[] = "ReaShoot";
      GetSetMediaTrackInfo_String(track, "P_NAME", name, true);
      SetMediaTrackInfo_Value(track, "D_VOL", 0.0);
    }
  }
  if (track) {
    SetMediaTrackInfo_Value(track, "I_FREEMODE", 0.0);
    SetMediaTrackInfo_Value(track, "I_RECARM", 0.0);
    SetMediaTrackInfo_Value(track, "I_RECINPUT", -1.0);
    SetMediaTrackInfo_Value(track, "I_RECMODE", 2.0);
    SetMediaTrackInfo_Value(track, "I_RECMON", 0.0);
    SetMediaTrackInfo_Value(track, "I_RECMONITEMS", 0.0);
    SetMediaTrackInfo_Value(track, "B_AUTO_RECARM", 0.0);
  }
  refreshArrangeTimeline();
  return track;
}

MediaItem *insertVideoItem(MediaTrack *track, const std::string &path, double position, std::string &error) {
  if (!PCM_Source_CreateFromFile || !AddMediaItemToTrack || !AddTakeToMediaItem || !SetMediaItemTake_Source ||
      !SetMediaItemInfo_Value || !GetMediaSourceLength) {
    error = "Recording finished, but required REAPER media insertion APIs are unavailable.";
    return nullptr;
  }
  PCM_source *source = PCM_Source_CreateFromFile(path.c_str());
  if (!source) {
    error = "Recording finished, but REAPER could not open the video file:\n" + path;
    return nullptr;
  }
  MediaItem *item = AddMediaItemToTrack(track);
  MediaItem_Take *take = item ? AddTakeToMediaItem(item) : nullptr;
  if (!item || !take || !SetMediaItemTake_Source(take, source)) {
    error = "Recording finished, but REAPER could not create a video media item.";
    return nullptr;
  }
  bool lengthIsQN = false;
  const double length = GetMediaSourceLength(source, &lengthIsQN);
  moveMediaItem(item, position);
  if (!lengthIsQN && length > 0.0) {
    SetMediaItemInfo_Value(item, "D_LENGTH", length);
  }
  SetMediaItemInfo_Value(item, "B_LOOPSRC", 0.0);
  SetMediaItemInfo_Value(item, "F_FREEMODE_Y", 0.0);
  SetMediaItemInfo_Value(item, "F_FREEMODE_H", 1.0);
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

} // namespace reashoot::reaper
