#pragma once

#include "reaper_plugin.h"

namespace reashoot::platform::swell {

HWND createSwellPanelProbe(HWND parent);
void updateSwellPanelProbe(HWND panel, const char *status, const char *host, const char *token);

} // namespace reashoot::platform::swell
