#pragma once

#include "reaper_plugin.h"

namespace reashoot::platform::swell {

struct SwellPanelCallbacks {
  void *context = nullptr;
  void (*setup)(void *context) = nullptr;
  void (*discover)(void *context) = nullptr;
  void (*pair)(void *context) = nullptr;
  void (*testConnection)(void *context) = nullptr;
  void (*restorePending)(void *context) = nullptr;
  void (*deleteAllPending)(void *context) = nullptr;
  void (*previousLook)(void *context) = nullptr;
  void (*nextLook)(void *context) = nullptr;
  void (*selectLook)(void *context, const char *lookID) = nullptr;
};

struct SwellPanelSettings {
  char host[256] = {};
  char token[256] = {};
  char pairingCode[64] = {};
};

HWND createSwellPanelProbe(HWND parent, const SwellPanelCallbacks &callbacks = {});
void updateSwellPanelProbe(HWND panel, const char *status, const char *format, const char *host, const char *token);
void setSwellPanelLook(HWND panel, const char *lookID);
SwellPanelSettings swellPanelSettings(HWND panel);
void setSwellPanelPreviewFrame(HWND panel, const void *pixels, int width, int height, int strideBytes);
void setSwellPanelPreviewPending(HWND panel, const char *reason = nullptr);

} // namespace reashoot::platform::swell
