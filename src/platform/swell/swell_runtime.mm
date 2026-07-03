#include "swell_runtime.h"

#ifndef _WIN32
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#endif

#include <cstdint>
#include <cstring>

namespace reashoot::platform::swell {
namespace {

using SwellGetFunc = void *(*)(const char *);
using MakeSetCurParmsFn = void (*)(float, float, float, float, HWND, bool, bool);
using CreateDialogFn = HWND (*)(void *, const char *, HWND, DLGPROC, LPARAM);
using GetDlgItemFn = HWND (*)(HWND, int);
using ShowWindowFn = void (*)(HWND, int);
using SetWindowPosFn = void (*)(HWND, HWND, int, int, int, int, int);
using GetWindowRectFn = bool (*)(HWND, RECT *);
using GetWindowLongFn = LONG_PTR (*)(HWND, int);
using SetWindowLongFn = LONG_PTR (*)(HWND, int, LONG_PTR);
using SetCaptureFn = HWND (*)(HWND);
using ReleaseCaptureFn = void (*)();
using GetCursorPosFn = void (*)(POINT *);
using MakeButtonFn = HWND (*)(int, const char *, int, int, int, int, int, int);
using MakeEditFieldFn = HWND (*)(int, int, int, int, int, int);
using MakeLabelFn = HWND (*)(int, const char *, int, int, int, int, int, int);
using MakeComboFn = HWND (*)(int, int, int, int, int, int);
using SetDlgItemTextFn = BOOL (*)(HWND, int, const char *);
using GetDlgItemTextFn = BOOL (*)(HWND, int, char *, int);
using ComboAddStringFn = int (*)(HWND, int, const char *);
using ComboSetCurSelFn = void (*)(HWND, int, int);
using ComboGetCurSelFn = int (*)(HWND, int);
using GetClientRectFn = void (*)(HWND, RECT *);
using InvalidateRectFn = BOOL (*)(HWND, const RECT *, int);
using SetTimerFn = UINT_PTR (*)(HWND, UINT_PTR, UINT, TIMERPROC);
using KillTimerFn = BOOL (*)(HWND, UINT_PTR);
using BeginPaintFn = HDC (*)(HWND, PAINTSTRUCT *);
using EndPaintFn = BOOL (*)(HWND, PAINTSTRUCT *);
using CreateMemContextFn = HDC (*)(HDC, int, int);
using DeleteGfxContextFn = void (*)(HDC);
using GetCtxFrameBufferFn = void *(*)(HDC);
using StretchBltFn = void (*)(HDC, int, int, int, int, HDC, int, int, int, int, int);
using DrawTextFn = int (*)(HDC, const char *, int, RECT *, int);
using FillDialogBackgroundFn = void (*)(HDC, const RECT *, int);
using CreateFontFn = HFONT (*)(int, int, int, int, int, char, char, char, char, char, char, char, char, const char *);
using SendMessageFn = LRESULT (*)(HWND, UINT, WPARAM, LPARAM);
using DeleteObjectFn = void (*)(HGDIOBJ);

SwellGetFunc g_getFunc = nullptr;
MakeSetCurParmsFn g_makeSetCurParms = nullptr;
CreateDialogFn g_createDialog = nullptr;
GetDlgItemFn g_getDlgItem = nullptr;
ShowWindowFn g_showWindow = nullptr;
SetWindowPosFn g_setWindowPos = nullptr;
GetWindowRectFn g_getWindowRect = nullptr;
GetWindowLongFn g_getWindowLong = nullptr;
SetWindowLongFn g_setWindowLong = nullptr;
SetCaptureFn g_setCapture = nullptr;
ReleaseCaptureFn g_releaseCapture = nullptr;
GetCursorPosFn g_getCursorPos = nullptr;
MakeButtonFn g_makeButton = nullptr;
MakeEditFieldFn g_makeEditField = nullptr;
MakeLabelFn g_makeLabel = nullptr;
MakeComboFn g_makeCombo = nullptr;
SetDlgItemTextFn g_setDlgItemText = nullptr;
GetDlgItemTextFn g_getDlgItemText = nullptr;
ComboAddStringFn g_comboAddString = nullptr;
ComboSetCurSelFn g_comboSetCurSel = nullptr;
ComboGetCurSelFn g_comboGetCurSel = nullptr;
GetClientRectFn g_getClientRect = nullptr;
InvalidateRectFn g_invalidateRect = nullptr;
SetTimerFn g_setTimer = nullptr;
KillTimerFn g_killTimer = nullptr;
BeginPaintFn g_beginPaint = nullptr;
EndPaintFn g_endPaint = nullptr;
CreateMemContextFn g_createMemContext = nullptr;
DeleteGfxContextFn g_deleteGfxContext = nullptr;
GetCtxFrameBufferFn g_getCtxFrameBuffer = nullptr;
StretchBltFn g_stretchBlt = nullptr;
DrawTextFn g_drawText = nullptr;
FillDialogBackgroundFn g_fillDialogBackground = nullptr;
CreateFontFn g_createFont = nullptr;
SendMessageFn g_sendMessage = nullptr;
DeleteObjectFn g_deleteObject = nullptr;

template <typename T>
T loadFunction(const char *name) {
  return g_getFunc ? reinterpret_cast<T>(g_getFunc(name)) : nullptr;
}

#ifndef _WIN32
SwellGetFunc findSwellGetFunc() {
  if (auto getFunc = reinterpret_cast<SwellGetFunc>(dlsym(RTLD_DEFAULT, "SWELLAPI_GetFunc"))) {
    return getFunc;
  }

  @autoreleasepool {
    id delegate = [NSApp delegate];
    SEL selector = @selector(swellGetAPPAPIFunc);
    if (delegate && [delegate respondsToSelector:selector]) {
      using ObjCGetter = void *(*)(id, SEL);
      ObjCGetter getter = reinterpret_cast<ObjCGetter>([delegate methodForSelector:selector]);
      return reinterpret_cast<SwellGetFunc>(getter(delegate, selector));
    }
  }
  return nullptr;
}
#endif

} // namespace

bool initializeSwellRuntime() {
  if (hasSwellRuntime()) {
    return true;
  }

#ifdef _WIN32
  return false;
#else
  g_getFunc = findSwellGetFunc();
  if (!g_getFunc) {
    return false;
  }

  g_makeSetCurParms = loadFunction<MakeSetCurParmsFn>("SWELL_MakeSetCurParms");
  g_createDialog = loadFunction<CreateDialogFn>("SWELL_CreateDialog");
  g_getDlgItem = loadFunction<GetDlgItemFn>("GetDlgItem");
  g_showWindow = loadFunction<ShowWindowFn>("ShowWindow");
  g_setWindowPos = loadFunction<SetWindowPosFn>("SetWindowPos");
  g_getWindowRect = loadFunction<GetWindowRectFn>("GetWindowRect");
  g_getWindowLong = loadFunction<GetWindowLongFn>("GetWindowLong");
  g_setWindowLong = loadFunction<SetWindowLongFn>("SetWindowLong");
  g_setCapture = loadFunction<SetCaptureFn>("SetCapture");
  g_releaseCapture = loadFunction<ReleaseCaptureFn>("ReleaseCapture");
  g_getCursorPos = loadFunction<GetCursorPosFn>("GetCursorPos");
  g_makeButton = loadFunction<MakeButtonFn>("SWELL_MakeButton");
  g_makeEditField = loadFunction<MakeEditFieldFn>("SWELL_MakeEditField");
  g_makeLabel = loadFunction<MakeLabelFn>("SWELL_MakeLabel");
  g_makeCombo = loadFunction<MakeComboFn>("SWELL_MakeCombo");
  g_setDlgItemText = loadFunction<SetDlgItemTextFn>("SetDlgItemText");
  g_getDlgItemText = loadFunction<GetDlgItemTextFn>("GetDlgItemText");
  g_comboAddString = loadFunction<ComboAddStringFn>("SWELL_CB_AddString");
  g_comboSetCurSel = loadFunction<ComboSetCurSelFn>("SWELL_CB_SetCurSel");
  g_comboGetCurSel = loadFunction<ComboGetCurSelFn>("SWELL_CB_GetCurSel");
  g_getClientRect = loadFunction<GetClientRectFn>("GetClientRect");
  g_invalidateRect = loadFunction<InvalidateRectFn>("InvalidateRect");
  g_setTimer = loadFunction<SetTimerFn>("SetTimer");
  g_killTimer = loadFunction<KillTimerFn>("KillTimer");
  g_beginPaint = loadFunction<BeginPaintFn>("BeginPaint");
  g_endPaint = loadFunction<EndPaintFn>("EndPaint");
  g_createMemContext = loadFunction<CreateMemContextFn>("SWELL_CreateMemContext");
  g_deleteGfxContext = loadFunction<DeleteGfxContextFn>("SWELL_DeleteGfxContext");
  g_getCtxFrameBuffer = loadFunction<GetCtxFrameBufferFn>("SWELL_GetCtxFrameBuffer");
  g_stretchBlt = loadFunction<StretchBltFn>("StretchBlt");
  g_drawText = loadFunction<DrawTextFn>("SWELL_DrawText");
  g_fillDialogBackground = loadFunction<FillDialogBackgroundFn>("SWELL_FillDialogBackground");
  g_createFont = loadFunction<CreateFontFn>("CreateFont");
  g_sendMessage = loadFunction<SendMessageFn>("SendMessage");
  g_deleteObject = loadFunction<DeleteObjectFn>("DeleteObject");
  return hasSwellRuntime();
#endif
}

bool hasSwellRuntime() {
  return g_makeSetCurParms && g_createDialog && g_makeButton && g_makeEditField && g_makeLabel && g_setDlgItemText;
}

bool hasSwellDrawingRuntime() {
  return g_getClientRect && g_invalidateRect && g_beginPaint && g_endPaint && g_createMemContext && g_deleteGfxContext &&
         g_getCtxFrameBuffer && g_stretchBlt;
}

void makeSetCurParms(float xscale, float yscale, float xtrans, float ytrans, HWND parent, bool autoScale, bool sizeToFit) {
  if (g_makeSetCurParms) {
    g_makeSetCurParms(xscale, yscale, xtrans, ytrans, parent, autoScale, sizeToFit);
  }
}

HWND createDialog(void *resourceHead, const char *resourceID, HWND parent, DLGPROC proc, LPARAM param) {
  return g_createDialog ? g_createDialog(resourceHead, resourceID, parent, proc, param) : nullptr;
}

HWND getDlgItem(HWND parent, int controlID) {
  return g_getDlgItem && parent ? g_getDlgItem(parent, controlID) : nullptr;
}

void showWindow(HWND hwnd, int command) {
  if (g_showWindow && hwnd) {
    g_showWindow(hwnd, command);
  }
}

void setWindowPos(HWND hwnd, HWND insertAfter, int x, int y, int width, int height, int flags) {
  if (g_setWindowPos && hwnd) {
    g_setWindowPos(hwnd, insertAfter, x, y, width, height, flags);
  }
}

bool getWindowRect(HWND hwnd, RECT *rect) {
  return g_getWindowRect && hwnd && rect && g_getWindowRect(hwnd, rect);
}

LONG_PTR getWindowLong(HWND hwnd, int index) {
  return g_getWindowLong && hwnd ? g_getWindowLong(hwnd, index) : 0;
}

LONG_PTR setWindowLong(HWND hwnd, int index, LONG_PTR value) {
  return g_setWindowLong && hwnd ? g_setWindowLong(hwnd, index, value) : 0;
}

HWND setCapture(HWND hwnd) {
  return g_setCapture ? g_setCapture(hwnd) : nullptr;
}

void releaseCapture() {
  if (g_releaseCapture) {
    g_releaseCapture();
  }
}

void getCursorPos(POINT *point) {
  if (g_getCursorPos && point) {
    g_getCursorPos(point);
  }
}

HWND makeButton(int isDefault, const char *label, int controlID, int x, int y, int width, int height, int flags) {
  return g_makeButton ? g_makeButton(isDefault, label, controlID, x, y, width, height, flags) : nullptr;
}

HWND makeEditField(int controlID, int x, int y, int width, int height, int flags) {
  return g_makeEditField ? g_makeEditField(controlID, x, y, width, height, flags) : nullptr;
}

HWND makeLabel(int align, const char *label, int controlID, int x, int y, int width, int height, int flags) {
  return g_makeLabel ? g_makeLabel(align, label, controlID, x, y, width, height, flags) : nullptr;
}

HWND makeCombo(int controlID, int x, int y, int width, int height, int flags) {
  return g_makeCombo ? g_makeCombo(controlID, x, y, width, height, flags) : nullptr;
}

bool setDlgItemText(HWND parent, int controlID, const char *text) {
  return g_setDlgItemText && g_setDlgItemText(parent, controlID, text ? text : "");
}

bool getDlgItemText(HWND parent, int controlID, char *text, int textLength) {
  if (!g_getDlgItemText || !text || textLength <= 0) {
    return false;
  }
  text[0] = '\0';
  return g_getDlgItemText(parent, controlID, text, textLength);
}

int comboAddString(HWND parent, int controlID, const char *text) {
  return g_comboAddString ? g_comboAddString(parent, controlID, text ? text : "") : -1;
}

void comboSetCurSel(HWND parent, int controlID, int selection) {
  if (g_comboSetCurSel) {
    g_comboSetCurSel(parent, controlID, selection);
  }
}

int comboGetCurSel(HWND parent, int controlID) {
  return g_comboGetCurSel ? g_comboGetCurSel(parent, controlID) : -1;
}

bool getClientRect(HWND hwnd, RECT *rect) {
  if (!g_getClientRect || !rect) {
    return false;
  }
  g_getClientRect(hwnd, rect);
  return true;
}

bool invalidateRect(HWND hwnd, const RECT *rect, bool eraseBackground) {
  return g_invalidateRect && g_invalidateRect(hwnd, rect, eraseBackground ? 1 : 0);
}

bool setTimer(HWND hwnd, UINT_PTR timerID, UINT rateMs) {
  return g_setTimer && g_setTimer(hwnd, timerID, rateMs, nullptr) != 0;
}

bool killTimer(HWND hwnd, UINT_PTR timerID) {
  return g_killTimer && g_killTimer(hwnd, timerID);
}

HDC beginPaint(HWND hwnd, PAINTSTRUCT *paint) {
  return g_beginPaint ? g_beginPaint(hwnd, paint) : nullptr;
}

bool endPaint(HWND hwnd, PAINTSTRUCT *paint) {
  return g_endPaint && g_endPaint(hwnd, paint);
}

void fillDialogBackground(HDC hdc, const RECT *rect, int level) {
  if (g_fillDialogBackground && hdc && rect) {
    g_fillDialogBackground(hdc, rect, level);
  }
}

bool drawFrame(HDC output, int x, int y, int width, int height, const void *bits, int sourceWidth, int sourceHeight) {
  if (!hasSwellDrawingRuntime() || !output || !bits || sourceWidth <= 0 || sourceHeight <= 0 || width <= 0 || height <= 0) {
    return false;
  }

  HDC source = g_createMemContext(output, sourceWidth, sourceHeight);
  if (!source) {
    return false;
  }

  void *frameBuffer = g_getCtxFrameBuffer(source);
  if (!frameBuffer) {
    g_deleteGfxContext(source);
    return false;
  }

  const size_t byteCount = static_cast<size_t>(sourceWidth) * static_cast<size_t>(sourceHeight) * sizeof(uint32_t);
  memcpy(frameBuffer, bits, byteCount);
  g_stretchBlt(output, x, y, width, height, source, 0, 0, sourceWidth, sourceHeight, 0);
  g_deleteGfxContext(source);
  return true;
}

bool drawText(HDC output, const char *text, RECT *rect, int align) {
  if (!g_drawText || !output || !text || !rect) {
    return false;
  }
  return g_drawText(output, text, -1, rect, align) != 0;
}

HFONT createFont(int height, int weight, const char *faceName) {
  return g_createFont ? g_createFont(height, 0, 0, 0, weight, 0, 0, 0, 0, 0, 0, 0, 0, faceName ? faceName : "") : nullptr;
}

LRESULT sendMessage(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
  return g_sendMessage && hwnd ? g_sendMessage(hwnd, message, wParam, lParam) : 0;
}

void deleteObject(HGDIOBJ object) {
  if (g_deleteObject && object) {
    g_deleteObject(object);
  }
}

} // namespace reashoot::platform::swell
