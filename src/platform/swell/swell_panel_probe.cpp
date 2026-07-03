#include "swell_panel_probe.h"

#include "swell_runtime.h"

namespace reashoot::platform::swell {

enum ControlID {
  kSetupButton = 1001,
  kPendingButton = 1002,
  kDeleteAllButton = 1003,
  kHostField = 1004,
  kTokenField = 1005,
  kStatusLabel = 1006,
};

static LRESULT swellProbeWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  (void)lParam;
  if (msg == WM_COMMAND) {
    const int controlID = LOWORD(wParam);
    if (controlID == kSetupButton || controlID == kPendingButton || controlID == kDeleteAllButton) {
      return 0;
    }
  }
  return 0;
}

HWND createSwellPanelProbe(HWND parent) {
  if (!initializeSwellRuntime()) {
    return nullptr;
  }
  HWND panel = createDialog(nullptr, nullptr, parent, reinterpret_cast<DLGPROC>(swellProbeWindowProc), 0);
  if (!panel) {
    return nullptr;
  }
  makeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, panel, false, false);
  makeButton(0, "Setup", kSetupButton, 528, 101, 100, 24, 0);
  makeButton(0, "Pending...", kPendingButton, 312, 101, 104, 24, 0);
  makeButton(0, "Delete All", kDeleteAllButton, 424, 101, 96, 24, 0);
  makeEditField(kHostField, 12, 127, 296, 22, 0);
  makeEditField(kTokenField, 320, 127, 296, 22, 0);
  makeLabel(0, "Format: SWELL prototype", -1, 12, 29, 600, 18, 0);
  makeLabel(0, "Video disabled", kStatusLabel, 12, 9, 600, 18, 0);
  return panel;
}

void updateSwellPanelProbe(HWND panel, const char *status, const char *host, const char *token) {
  if (!panel) {
    return;
  }
  setDlgItemText(panel, kStatusLabel, status ? status : "Video disabled");
  setDlgItemText(panel, kHostField, host ? host : "");
  setDlgItemText(panel, kTokenField, token ? token : "");
}

} // namespace reashoot::platform::swell
