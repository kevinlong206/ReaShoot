#pragma once

#include "reaper_plugin.h"

namespace reashoot::platform::swell {

bool initializeSwellRuntime();
bool hasSwellRuntime();
void makeSetCurParms(float xscale, float yscale, float xtrans, float ytrans, HWND parent, bool autoScale, bool sizeToFit);
HWND createDialog(void *resourceHead, const char *resourceID, HWND parent, DLGPROC proc, LPARAM param);
HWND makeButton(int isDefault, const char *label, int controlID, int x, int y, int width, int height, int flags);
HWND makeEditField(int controlID, int x, int y, int width, int height, int flags);
HWND makeLabel(int align, const char *label, int controlID, int x, int y, int width, int height, int flags);
bool setDlgItemText(HWND parent, int controlID, const char *text);

} // namespace reashoot::platform::swell
