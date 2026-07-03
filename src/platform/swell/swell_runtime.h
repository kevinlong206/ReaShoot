#pragma once

#include "reaper_plugin.h"

namespace reashoot::platform::swell {

bool initializeSwellRuntime();
bool hasSwellRuntime();
bool hasSwellDrawingRuntime();
void makeSetCurParms(float xscale, float yscale, float xtrans, float ytrans, HWND parent, bool autoScale, bool sizeToFit);
HWND createDialog(void *resourceHead, const char *resourceID, HWND parent, DLGPROC proc, LPARAM param);
HWND makeButton(int isDefault, const char *label, int controlID, int x, int y, int width, int height, int flags);
HWND makeEditField(int controlID, int x, int y, int width, int height, int flags);
HWND makeLabel(int align, const char *label, int controlID, int x, int y, int width, int height, int flags);
bool setDlgItemText(HWND parent, int controlID, const char *text);
bool getClientRect(HWND hwnd, RECT *rect);
bool invalidateRect(HWND hwnd, const RECT *rect, bool eraseBackground);
bool setTimer(HWND hwnd, UINT_PTR timerID, UINT rateMs);
bool killTimer(HWND hwnd, UINT_PTR timerID);
HDC beginPaint(HWND hwnd, PAINTSTRUCT *paint);
bool endPaint(HWND hwnd, PAINTSTRUCT *paint);
bool drawFrame(HDC output, int x, int y, int width, int height, const void *bits, int sourceWidth, int sourceHeight);

} // namespace reashoot::platform::swell
