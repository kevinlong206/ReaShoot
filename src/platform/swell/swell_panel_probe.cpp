#include "reaper_plugin.h"

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
  SWELL_MakeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, parent, false, false);
  HWND panel = SWELL_CreateDialog(nullptr, "0", parent, reinterpret_cast<DLGPROC>(swellProbeWindowProc), 0);
  if (!panel) {
    return nullptr;
  }
  SWELL_MakeButton(0, "Setup", kSetupButton, 528, 101, 100, 24, 0);
  SWELL_MakeButton(0, "Pending...", kPendingButton, 312, 101, 104, 24, 0);
  SWELL_MakeButton(0, "Delete All", kDeleteAllButton, 424, 101, 96, 24, 0);
  SWELL_MakeEditField(kHostField, 12, 127, 296, 22, 0);
  SWELL_MakeEditField(kTokenField, 320, 127, 296, 22, 0);
  SWELL_MakeLabel(0, "Video disabled", kStatusLabel, 12, 9, 600, 18, 0);
  return panel;
}

} // namespace reashoot::platform::swell
