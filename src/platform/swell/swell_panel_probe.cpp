#include "swell_panel_probe.h"

#include "swell_runtime.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace reashoot::platform::swell {

enum ControlID {
  kSetupButton = 1001,
  kManageButton = 1002,
  kStatusLabel = 1006,
  kFormatLabel = 1011,
  kPreviousLookButton = 1012,
  kNextLookButton = 1013,
  kLookCombo = 1014,
  kSetupHostField = 1101,
  kSetupTokenField = 1102,
  kSetupPairingCodeField = 1103,
  kSetupDiscoverButton = 1104,
  kSetupPairButton = 1105,
  kSetupTestButton = 1106,
  kSetupCloseButton = 1107,
  kManagePendingButton = 1201,
  kManageDeleteAllButton = 1202,
  kManageCloseButton = 1203,
};

struct LookOption {
  const char *title;
  const char *id;
};

const LookOption kLookOptions[] = {
    {"Natural", "natural"},
    {"Warm Vintage", "warmVintage"},
    {"Cool Blue", "coolBlue"},
    {"High Contrast B&W", "highContrastBW"},
    {"Faded Film", "fadedFilm"},
    {"Dream Glow", "dreamGlow"},
    {"Noir", "noir"},
    {"Saturated Pop", "saturatedPop"},
    {"Bleach Bypass", "bleachBypass"},
    {"Sepia", "sepia"},
    {"Instant Photo", "instantPhoto"},
    {"Chrome", "chrome"},
    {"Tonal", "tonal"},
    {"Silvertone", "silvertone"},
    {"Dramatic Warm", "dramaticWarm"},
    {"Dramatic Cool", "dramaticCool"},
    {"Soft Matte", "softMatte"},
    {"Comic Book", "comicBook"},
    {"VHS", "vhs"},
    {"Music Video Pop", "musicVideoPop"},
};

std::vector<uint32_t> g_previewFrame;
int g_previewWidth = 320;
int g_previewHeight = 180;
bool g_usingLivePreview = false;
bool g_previewPending = false;
std::string g_previewMessage = "Preview unavailable: set iPhone host and token, then Test.";
std::string g_host;
std::string g_token;
SwellPanelCallbacks g_callbacks;
HWND g_setupWindow = nullptr;
HWND g_manageWindow = nullptr;

int lookIndexForID(const char *lookID) {
  if (!lookID || !lookID[0]) {
    return 0;
  }
  for (int i = 0; i < static_cast<int>(sizeof(kLookOptions) / sizeof(kLookOptions[0])); ++i) {
    if (strcmp(kLookOptions[i].id, lookID) == 0) {
      return i;
    }
  }
  return 0;
}

void syncSetupFields() {
  if (!g_setupWindow) {
    return;
  }
  setDlgItemText(g_setupWindow, kSetupHostField, g_host.c_str());
  setDlgItemText(g_setupWindow, kSetupTokenField, g_token.c_str());
}

void captureSetupFields() {
  if (!g_setupWindow) {
    return;
  }
  char text[256] = {};
  if (getDlgItemText(g_setupWindow, kSetupHostField, text, sizeof(text))) {
    g_host = text;
  }
  if (getDlgItemText(g_setupWindow, kSetupTokenField, text, sizeof(text))) {
    g_token = text;
  }
}

void showSetupWindow(HWND parent);
void showManageWindow(HWND parent);

void updatePlaceholderPreviewFrame() {
  g_previewFrame.resize(static_cast<size_t>(g_previewWidth * g_previewHeight));
  const uint32_t background = 0xffd6d6d6u;
  const uint32_t border = 0xff777777u;
  for (int y = 0; y < g_previewHeight; ++y) {
    for (int x = 0; x < g_previewWidth; ++x) {
      const bool edge = x < 2 || y < 2 || x >= g_previewWidth - 2 || y >= g_previewHeight - 2;
      g_previewFrame[static_cast<size_t>(y * g_previewWidth + x)] = edge ? border : background;
    }
  }
}

void paintPreview(HWND hwnd) {
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
    if (!g_usingLivePreview && !g_previewMessage.empty()) {
      RECT textRect = {margin + 16, controlsHeight + 16, client.right - margin - 16, client.bottom - margin - 16};
      drawText(hdc, g_previewMessage.c_str(), &textRect, DT_CENTER | DT_VCENTER | DT_WORDBREAK);
    }
  }
  endPaint(hwnd, &paint);
}

static LRESULT setupWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  (void)lParam;
  if (msg == WM_CLOSE) {
    captureSetupFields();
    showWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (msg == WM_DESTROY) {
    if (g_setupWindow == hwnd) {
      captureSetupFields();
      g_setupWindow = nullptr;
    }
    return 0;
  }
  if (msg == WM_COMMAND) {
    const int controlID = LOWORD(wParam);
    if (controlID == kSetupDiscoverButton) {
      captureSetupFields();
      if (g_callbacks.discover) {
        g_callbacks.discover(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kSetupPairButton) {
      captureSetupFields();
      if (g_callbacks.pair) {
        g_callbacks.pair(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kSetupTestButton) {
      captureSetupFields();
      if (g_callbacks.testConnection) {
        g_callbacks.testConnection(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kSetupCloseButton) {
      captureSetupFields();
      showWindow(hwnd, SW_HIDE);
      return 0;
    }
  }
  return 0;
}

static LRESULT manageWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  (void)lParam;
  if (msg == WM_CLOSE) {
    showWindow(hwnd, SW_HIDE);
    return 0;
  }
  if (msg == WM_DESTROY) {
    if (g_manageWindow == hwnd) {
      g_manageWindow = nullptr;
    }
    return 0;
  }
  if (msg == WM_COMMAND) {
    const int controlID = LOWORD(wParam);
    if (controlID == kManagePendingButton) {
      if (g_callbacks.restorePending) {
        g_callbacks.restorePending(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kManageDeleteAllButton) {
      if (g_callbacks.deleteAllPending) {
        g_callbacks.deleteAllPending(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kManageCloseButton) {
      showWindow(hwnd, SW_HIDE);
      return 0;
    }
  }
  return 0;
}

static LRESULT swellProbeWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  (void)lParam;
  if (msg == WM_PAINT) {
    paintPreview(hwnd);
    return 0;
  }
  if (msg == WM_DESTROY) {
    return 0;
  }
  if (msg == WM_COMMAND) {
    const int controlID = LOWORD(wParam);
    if (controlID == kSetupButton) {
      showSetupWindow(hwnd);
      if (g_callbacks.setup) {
        g_callbacks.setup(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kManageButton) {
      showManageWindow(hwnd);
      return 0;
    }
    if (controlID == kPreviousLookButton) {
      if (g_callbacks.previousLook) {
        g_callbacks.previousLook(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kNextLookButton) {
      if (g_callbacks.nextLook) {
        g_callbacks.nextLook(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kLookCombo) {
      const int selection = comboGetCurSel(hwnd, kLookCombo);
      if (selection >= 0 && selection < static_cast<int>(sizeof(kLookOptions) / sizeof(kLookOptions[0])) && g_callbacks.selectLook) {
        g_callbacks.selectLook(g_callbacks.context, kLookOptions[selection].id);
      }
      return 0;
    }
  }
  return 0;
}

void showSetupWindow(HWND parent) {
  if (!g_setupWindow) {
    g_setupWindow = createDialog(nullptr, nullptr, parent, reinterpret_cast<DLGPROC>(setupWindowProc), 0);
    if (!g_setupWindow) {
      return;
    }
    makeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, g_setupWindow, false, false);
    makeLabel(0, "Host", -1, 12, 118, 80, 18, 0);
    makeEditField(kSetupHostField, 96, 116, 300, 22, 0);
    makeButton(0, "Discover", kSetupDiscoverButton, 404, 116, 82, 24, 0);
    makeLabel(0, "Token", -1, 12, 84, 80, 18, 0);
    makeEditField(kSetupTokenField, 96, 82, 390, 22, 0);
    makeLabel(0, "Pair code", -1, 12, 50, 80, 18, 0);
    makeEditField(kSetupPairingCodeField, 96, 48, 180, 22, 0);
    makeButton(0, "Pair", kSetupPairButton, 284, 48, 70, 24, 0);
    makeButton(0, "Test", kSetupTestButton, 362, 48, 70, 24, 0);
    makeButton(0, "Close", kSetupCloseButton, 416, 12, 70, 24, 0);
  }
  syncSetupFields();
  showWindow(g_setupWindow, SW_SHOW);
}

void showManageWindow(HWND parent) {
  if (!g_manageWindow) {
    g_manageWindow = createDialog(nullptr, nullptr, parent, reinterpret_cast<DLGPROC>(manageWindowProc), 0);
    if (!g_manageWindow) {
      return;
    }
    makeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, g_manageWindow, false, false);
    makeLabel(0, "Manage recordings stored on the paired iPhone.", -1, 12, 86, 360, 18, 0);
    makeButton(0, "Pending Videos...", kManagePendingButton, 12, 50, 150, 26, 0);
    makeButton(0, "Delete All", kManageDeleteAllButton, 172, 50, 110, 26, 0);
    makeButton(0, "Close", kManageCloseButton, 302, 12, 70, 24, 0);
  }
  showWindow(g_manageWindow, SW_SHOW);
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
  updatePlaceholderPreviewFrame();
  makeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, panel, false, false);
  makeButton(0, "Setup", kSetupButton, 448, 101, 86, 24, 0);
  makeButton(0, "Manage Recordings", kManageButton, 542, 101, 126, 24, 0);
  makeButton(0, "Prev", kPreviousLookButton, 12, 49, 52, 24, 0);
  makeButton(0, "Next", kNextLookButton, 616, 49, 52, 24, 0);
  makeCombo(kLookCombo, 70, 49, 540, 200, CBS_DROPDOWNLIST);
  for (const auto &look : kLookOptions) {
    comboAddString(panel, kLookCombo, look.title);
  }
  comboSetCurSel(panel, kLookCombo, 0);
  makeLabel(0, "Format: SWELL production panel", kFormatLabel, 12, 29, 656, 18, 0);
  makeLabel(0, "Video disabled", kStatusLabel, 12, 9, 600, 18, 0);
  invalidateRect(panel, nullptr, false);
  return panel;
}

void updateSwellPanelProbe(HWND panel, const char *status, const char *format, const char *host, const char *token) {
  if (!panel) {
    return;
  }
  setDlgItemText(panel, kStatusLabel, status ? status : "Video disabled");
  if (format) {
    setDlgItemText(panel, kFormatLabel, format);
  }
  g_host = host ? host : "";
  g_token = token ? token : "";
  syncSetupFields();
  if (!g_usingLivePreview) {
    g_previewMessage = status && status[0] ? status : "Preview unavailable";
    updatePlaceholderPreviewFrame();
  }
  invalidateRect(panel, nullptr, false);
}

void setSwellPanelLook(HWND panel, const char *lookID) {
  if (!panel) {
    return;
  }
  comboSetCurSel(panel, kLookCombo, lookIndexForID(lookID));
}

SwellPanelSettings swellPanelSettings(HWND panel) {
  SwellPanelSettings settings;
  if (!panel) {
    return settings;
  }
  if (g_setupWindow) {
    captureSetupFields();
    getDlgItemText(g_setupWindow, kSetupPairingCodeField, settings.pairingCode, sizeof(settings.pairingCode));
  }
  snprintf(settings.host, sizeof(settings.host), "%s", g_host.c_str());
  snprintf(settings.token, sizeof(settings.token), "%s", g_token.c_str());
  return settings;
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
  g_previewMessage.clear();
  invalidateRect(panel, nullptr, false);
}

void setSwellPanelPreviewPending(HWND panel, const char *reason) {
  if (!panel) {
    return;
  }
  g_usingLivePreview = false;
  g_previewPending = true;
  g_previewMessage = reason && reason[0] ? reason : "Preview connecting...";
  updatePlaceholderPreviewFrame();
  invalidateRect(panel, nullptr, false);
}

} // namespace reashoot::platform::swell
