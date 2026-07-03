#pragma once

#include "reaper_plugin.h"

namespace reashoot::platform::swell {

bool initializeSwellRuntime();
bool hasSwellRuntime();
bool hasSwellDrawingRuntime();
void makeSetCurParms(float xscale, float yscale, float xtrans, float ytrans, HWND parent, bool autoScale, bool sizeToFit);
HWND createDialog(void *resourceHead, const char *resourceID, HWND parent, DLGPROC proc, LPARAM param);
HWND getDlgItem(HWND parent, int controlID);
void showWindow(HWND hwnd, int command);
void setWindowPos(HWND hwnd, HWND insertAfter, int x, int y, int width, int height, int flags);
bool getWindowRect(HWND hwnd, RECT *rect);
LONG_PTR getWindowLong(HWND hwnd, int index);
LONG_PTR setWindowLong(HWND hwnd, int index, LONG_PTR value);
HWND setCapture(HWND hwnd);
void releaseCapture();
void getCursorPos(POINT *point);
HWND makeButton(int isDefault, const char *label, int controlID, int x, int y, int width, int height, int flags);
HWND makeEditField(int controlID, int x, int y, int width, int height, int flags);
HWND makeLabel(int align, const char *label, int controlID, int x, int y, int width, int height, int flags);
HWND makeCombo(int controlID, int x, int y, int width, int height, int flags);
bool setDlgItemText(HWND parent, int controlID, const char *text);
bool getDlgItemText(HWND parent, int controlID, char *text, int textLength);
int comboAddString(HWND parent, int controlID, const char *text);
void comboSetCurSel(HWND parent, int controlID, int selection);
int comboGetCurSel(HWND parent, int controlID);
bool getClientRect(HWND hwnd, RECT *rect);
bool invalidateRect(HWND hwnd, const RECT *rect, bool eraseBackground);
bool setTimer(HWND hwnd, UINT_PTR timerID, UINT rateMs);
bool killTimer(HWND hwnd, UINT_PTR timerID);
HDC beginPaint(HWND hwnd, PAINTSTRUCT *paint);
bool endPaint(HWND hwnd, PAINTSTRUCT *paint);
void fillDialogBackground(HDC hdc, const RECT *rect, int level);
bool drawFrame(HDC output, int x, int y, int width, int height, const void *bits, int sourceWidth, int sourceHeight);
bool drawText(HDC output, const char *text, RECT *rect, int align);
HFONT createFont(int height, int weight, const char *faceName);
LRESULT sendMessage(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam);
void deleteObject(HGDIOBJ object);

} // namespace reashoot::platform::swell
