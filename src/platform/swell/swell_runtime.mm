#include "swell_runtime.h"

#ifndef _WIN32
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#endif

namespace reashoot::platform::swell {
namespace {

using SwellGetFunc = void *(*)(const char *);
using MakeSetCurParmsFn = void (*)(float, float, float, float, HWND, bool, bool);
using CreateDialogFn = HWND (*)(void *, const char *, HWND, DLGPROC, LPARAM);
using MakeButtonFn = HWND (*)(int, const char *, int, int, int, int, int, int);
using MakeEditFieldFn = HWND (*)(int, int, int, int, int, int);
using MakeLabelFn = HWND (*)(int, const char *, int, int, int, int, int, int);
using SetDlgItemTextFn = BOOL (*)(HWND, int, const char *);

SwellGetFunc g_getFunc = nullptr;
MakeSetCurParmsFn g_makeSetCurParms = nullptr;
CreateDialogFn g_createDialog = nullptr;
MakeButtonFn g_makeButton = nullptr;
MakeEditFieldFn g_makeEditField = nullptr;
MakeLabelFn g_makeLabel = nullptr;
SetDlgItemTextFn g_setDlgItemText = nullptr;

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
  return hasSwellRuntime();
#endif
}

bool hasSwellRuntime() {
  return g_makeSetCurParms && g_createDialog && g_makeButton && g_makeEditField && g_makeLabel && g_setDlgItemText;
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

} // namespace reashoot::platform::swell
