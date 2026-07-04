#pragma once

#include "reaper_plugin.h"

#include <string>

namespace reashoot::reaper {

ReaProject *currentProject(std::string *projectFile = nullptr);
std::string projectPath(ReaProject *project);
std::string defaultRecordingPath();
std::string resourcePath();
std::string extState(const char *section, const char *key);
bool setExtState(const char *section, const char *key, const char *value, bool persist);
double cursorPosition(ReaProject *project);
void moveMediaItem(MediaItem *item, double position);
void refreshArrangeTimeline();
void refreshToolbar(int commandId);

} // namespace reashoot::reaper
