#pragma once

#include "reaper_plugin.h"

namespace reashoot::platform::swell {

struct SwellPanelCallbacks {
  void *context = nullptr;
  void (*setup)(void *context) = nullptr;
  void (*restorePending)(void *context) = nullptr;
  void (*deleteAllPending)(void *context) = nullptr;
};

HWND createSwellPanelProbe(HWND parent, const SwellPanelCallbacks &callbacks = {});
void updateSwellPanelProbe(HWND panel, const char *status, const char *host, const char *token);
void setSwellPanelPreviewFrame(HWND panel, const void *pixels, int width, int height, int strideBytes);
void setSwellPanelPreviewPending(HWND panel);

} // namespace reashoot::platform::swell
