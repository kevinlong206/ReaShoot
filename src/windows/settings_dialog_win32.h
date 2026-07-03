#pragma once

#ifndef _WIN32
#error "settings_dialog_win32.h is only intended for Windows builds."
#endif

#include "reashoot/plugin_settings.h"

#include <windows.h>

namespace reashoot {

// Shows a modal settings dialog pre-filled from settings. On OK, writes the
// edited values back into settings and returns true; on Cancel/close returns
// false and leaves settings unchanged. Built programmatically (no .rc resource).
bool showSettingsDialog(HWND parent, HINSTANCE instance, PluginSettings &settings);

} // namespace reashoot
