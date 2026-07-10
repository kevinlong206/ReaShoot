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

// Shows a modal REAPER message box (ShowMessageBox); flags/return use the
// Win32 MB_* / ID* conventions (e.g. flags 3 = Yes/No/Cancel).
int messageBox(const std::string &text, const std::string &title, int flags);
// Finds or creates the dedicated "ReaShoot" track, muted and with REAPER audio
// recording disabled, ready to receive inserted iPhone video items.
MediaTrack *ensureReaShootTrack(ReaProject *project);
// Inserts a video file as a new selected media item at the given timeline
// position on the track. Returns the item, or nullptr with error set.
MediaItem *insertVideoItem(MediaTrack *track, const std::string &path, double position, std::string &error);

} // namespace reashoot::reaper
