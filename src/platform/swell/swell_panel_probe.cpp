#include "swell_panel_probe.h"

#include "swell_runtime.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <vector>

namespace reashoot::platform::swell {

enum ControlID {
  kSetupButton = 1001,
  kPendingButton = 1002,
  kDeleteAllButton = 1003,
  kHostField = 1004,
  kTokenField = 1005,
  kStatusLabel = 1006,
  kAnimationTimer = 2001,
};

std::vector<uint32_t> g_previewFrame;
int g_previewWidth = 320;
int g_previewHeight = 180;
int g_frameCounter = 0;
bool g_usingLivePreview = false;
bool g_previewPending = false;
SwellPanelCallbacks g_callbacks;

void updateSyntheticPreviewFrame() {
  g_previewFrame.resize(static_cast<size_t>(g_previewWidth * g_previewHeight));
  ++g_frameCounter;
  for (int y = 0; y < g_previewHeight; ++y) {
    for (int x = 0; x < g_previewWidth; ++x) {
      const uint8_t red = static_cast<uint8_t>((x + g_frameCounter * 3) & 0xff);
      const uint8_t green = static_cast<uint8_t>((y * 2 + g_frameCounter * 5) & 0xff);
      const uint8_t blue = static_cast<uint8_t>(((x + y) / 2 + g_frameCounter * 7) & 0xff);
      g_previewFrame[static_cast<size_t>(y * g_previewWidth + x)] =
          0xff000000u | (static_cast<uint32_t>(red) << 16) | (static_cast<uint32_t>(green) << 8) | blue;
    }
  }
}

void paintSyntheticPreview(HWND hwnd) {
  PAINTSTRUCT paint = {};
  HDC hdc = beginPaint(hwnd, &paint);
  if (!hdc) {
    return;
  }

  RECT client = {};
  if (getClientRect(hwnd, &client)) {
    const int margin = 12;
    const int controlsHeight = 150;
    const int width = max(1, client.right - client.left - margin * 2);
    const int height = max(1, client.bottom - client.top - controlsHeight - margin);
    if (!g_previewFrame.empty()) {
      drawFrame(hdc, margin, controlsHeight, width, height, g_previewFrame.data(), g_previewWidth, g_previewHeight);
    }
  }
  endPaint(hwnd, &paint);
}

static LRESULT swellProbeWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  (void)lParam;
  if (msg == WM_PAINT) {
    paintSyntheticPreview(hwnd);
    return 0;
  }
  if (msg == WM_TIMER && wParam == kAnimationTimer) {
    if (!g_usingLivePreview && !g_previewPending) {
      updateSyntheticPreviewFrame();
      invalidateRect(hwnd, nullptr, false);
    }
    return 0;
  }
  if (msg == WM_DESTROY) {
    killTimer(hwnd, kAnimationTimer);
    return 0;
  }
  if (msg == WM_COMMAND) {
    const int controlID = LOWORD(wParam);
    if (controlID == kSetupButton) {
      if (g_callbacks.setup) {
        g_callbacks.setup(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kPendingButton) {
      if (g_callbacks.restorePending) {
        g_callbacks.restorePending(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kDeleteAllButton) {
      if (g_callbacks.deleteAllPending) {
        g_callbacks.deleteAllPending(g_callbacks.context);
      }
      return 0;
    }
  }
  return 0;
}

HWND createSwellPanelProbe(HWND parent, const SwellPanelCallbacks &callbacks) {
  if (!initializeSwellRuntime()) {
    return nullptr;
  }
  HWND panel = createDialog(nullptr, nullptr, parent, reinterpret_cast<DLGPROC>(swellProbeWindowProc), 0);
  if (!panel) {
    return nullptr;
  }
  g_callbacks = callbacks;
  updateSyntheticPreviewFrame();
  makeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, panel, false, false);
  makeButton(0, "Setup", kSetupButton, 528, 101, 100, 24, 0);
  makeButton(0, "Pending...", kPendingButton, 312, 101, 104, 24, 0);
  makeButton(0, "Delete All", kDeleteAllButton, 424, 101, 96, 24, 0);
  makeEditField(kHostField, 12, 127, 296, 22, 0);
  makeEditField(kTokenField, 320, 127, 296, 22, 0);
  makeLabel(0,
            hasSwellDrawingRuntime() ? "Format: SWELL prototype with frame drawing" : "Format: SWELL prototype; frame drawing unavailable",
            -1,
            12,
            29,
            600,
            18,
            0);
  makeLabel(0, "Video disabled", kStatusLabel, 12, 9, 600, 18, 0);
  if (hasSwellDrawingRuntime()) {
    setTimer(panel, kAnimationTimer, 33);
  }
  invalidateRect(panel, nullptr, false);
  return panel;
}

void updateSwellPanelProbe(HWND panel, const char *status, const char *host, const char *token) {
  if (!panel) {
    return;
  }
  setDlgItemText(panel, kStatusLabel, status ? status : "Video disabled");
  setDlgItemText(panel, kHostField, host ? host : "");
  setDlgItemText(panel, kTokenField, token ? token : "");
  if (!g_usingLivePreview && !g_previewPending) {
    updateSyntheticPreviewFrame();
  }
  invalidateRect(panel, nullptr, false);
}

void setSwellPanelPreviewFrame(HWND panel, const void *pixels, int width, int height, int strideBytes) {
  if (!panel || !pixels || width <= 0 || height <= 0 || strideBytes < width * 4) {
    return;
  }
  g_previewWidth = width;
  g_previewHeight = height;
  g_previewFrame.resize(static_cast<size_t>(width) * static_cast<size_t>(height));
  const auto *sourceRows = static_cast<const uint8_t *>(pixels);
  for (int y = 0; y < height; ++y) {
    memcpy(g_previewFrame.data() + static_cast<size_t>(y) * static_cast<size_t>(width),
           sourceRows + static_cast<size_t>(y) * static_cast<size_t>(strideBytes),
           static_cast<size_t>(width) * sizeof(uint32_t));
  }
  g_usingLivePreview = true;
  g_previewPending = false;
  invalidateRect(panel, nullptr, false);
}

void setSwellPanelPreviewPending(HWND panel) {
  if (!panel) {
    return;
  }
  g_usingLivePreview = false;
  g_previewPending = true;
  invalidateRect(panel, nullptr, false);
}

} // namespace reashoot::platform::swell
