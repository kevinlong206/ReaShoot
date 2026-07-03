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
using MakeButtonFn = HWND (*)(int, const char *, int, int, int, int, int, int);
using MakeEditFieldFn = HWND (*)(int, int, int, int, int, int);
using MakeLabelFn = HWND (*)(int, const char *, int, int, int, int, int, int);
using SetDlgItemTextFn = BOOL (*)(HWND, int, const char *);
using GetDlgItemTextFn = BOOL (*)(HWND, int, char *, int);
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

SwellGetFunc g_getFunc = nullptr;
MakeSetCurParmsFn g_makeSetCurParms = nullptr;
CreateDialogFn g_createDialog = nullptr;
MakeButtonFn g_makeButton = nullptr;
MakeEditFieldFn g_makeEditField = nullptr;
MakeLabelFn g_makeLabel = nullptr;
SetDlgItemTextFn g_setDlgItemText = nullptr;
GetDlgItemTextFn g_getDlgItemText = nullptr;
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
  g_makeButton = loadFunction<MakeButtonFn>("SWELL_MakeButton");
  g_makeEditField = loadFunction<MakeEditFieldFn>("SWELL_MakeEditField");
  g_makeLabel = loadFunction<MakeLabelFn>("SWELL_MakeLabel");
  g_setDlgItemText = loadFunction<SetDlgItemTextFn>("SetDlgItemText");
  g_getDlgItemText = loadFunction<GetDlgItemTextFn>("GetDlgItemText");
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

HWND makeButton(int isDefault, const char *label, int controlID, int x, int y, int width, int height, int flags) {
  return g_makeButton ? g_makeButton(isDefault, label, controlID, x, y, width, height, flags) : nullptr;
}

HWND makeEditField(int controlID, int x, int y, int width, int height, int flags) {
  return g_makeEditField ? g_makeEditField(controlID, x, y, width, height, flags) : nullptr;
}

HWND makeLabel(int align, const char *label, int controlID, int x, int y, int width, int height, int flags) {
  return g_makeLabel ? g_makeLabel(align, label, controlID, x, y, width, height, flags) : nullptr;
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

} // namespace reashoot::platform::swell
