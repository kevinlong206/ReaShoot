#include "swell_panel_probe.h"

#include "swell_runtime.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <string>
#include <vector>

namespace reashoot::platform::swell {

enum ControlID {
  kSetupButton = 1001,
  kManageButton = 1002,
  kDockToggleButton = 1003,
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
  kSetupResolutionCombo = 1108,
  kSetupFPSCombo = 1109,
  kSetupOrientationCombo = 1110,
  kSetupLensCombo = 1111,
  kManagePendingButton = 1201,
  kManageDeleteAllButton = 1202,
  kManageCloseButton = 1203,
};

struct LookOption {
  const char *title;
  const char *id;
};

struct ComboOption {
  const char *title;
  const char *value;
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

const ComboOption kResolutionOptions[] = {
    {"4K", "4K"},
    {"1080p", "1080p"},
    {"720p", "720p"},
};

const ComboOption kFPSOptions[] = {
    {"24", "24"},
    {"30", "30"},
    {"60", "60"},
};

const ComboOption kOrientationOptions[] = {
    {"Auto at Record Start", "auto"},
    {"Portrait", "portrait"},
    {"Landscape Left", "landscapeLeft"},
    {"Landscape Right", "landscapeRight"},
};

const ComboOption kLensOptions[] = {
    {"Wide", "wide"},
    {"Ultra Wide", "ultrawide"},
    {"Telephoto", "telephoto"},
};

std::vector<uint32_t> g_previewFrame;
int g_previewWidth = 320;
int g_previewHeight = 180;
// Shared preview layout metrics. The controls occupy the top band of the panel
// and the decoded video is drawn below them. Keep paintPreview and the
// per-frame invalidate in setSwellPanelPreviewFrame in sync via these.
constexpr int kPreviewMargin = 12;
constexpr int kPreviewControlsHeight = 150;
#ifdef _WIN32
constexpr int kLookComboHeight = 140;
#else
constexpr int kLookComboHeight = 26;
#endif
bool g_usingLivePreview = false;
bool g_previewPending = false;
std::string g_previewMessage = "Preview unavailable: discover the iPhone, enter its pairing code, then Pair or Reconnect.";
std::string g_host;
std::string g_token;
std::string g_resolution = "4K";
std::string g_fps = "30";
std::string g_orientation = "auto";
std::string g_lens = "wide";
SwellPanelCallbacks g_callbacks;
HWND g_setupWindow = nullptr;
HWND g_manageWindow = nullptr;
HWND g_dragWindow = nullptr;
HFONT g_statusFont = nullptr;
POINT g_dragStartCursor = {};
RECT g_dragStartWindow = {};

int paddedTextWidth(const char *text, int padding, int minimum) {
  return (std::max)(minimum, measureTextWidth(text) + padding);
}

int maxTextWidth(std::initializer_list<const char *> labels) {
  int width = 0;
  for (const char *label : labels) {
    width = (std::max)(width, measureTextWidth(label));
  }
  return width;
}

void moveControl(HWND parent, int controlID, int x, int y, int width, int height) {
  HWND control = getDlgItem(parent, controlID);
  if (control) {
    setWindowPos(control, nullptr, x, y, width, height, SWP_NOZORDER | SWP_NOACTIVATE);
  }
}

struct SetupLayout {
  int margin = 12;
  int labelGap = 12;
  int columnGap = 28;
  int labelHeight = 20;
  int rowHeight = 26;
  int leftLabelWidth = 0;
  int leftControlX = 0;
  int leftControlWidth = 250;
  int rightLabelX = 0;
  int rightLabelWidth = 0;
  int rightControlX = 0;
  int rightControlWidth = 220;
  int contentWidth = 0;
  int windowWidth = 0;

  SetupLayout() {
    leftLabelWidth = (std::max)(128, maxTextWidth({"Host", "Pair code", "Resolution", "Orientation"}) + 18);
    rightLabelWidth = (std::max)(84, maxTextWidth({"FPS", "Lens"}) + 18);
    leftControlX = margin + leftLabelWidth + labelGap;
    rightLabelX = leftControlX + leftControlWidth + columnGap;
    rightControlX = rightLabelX + rightLabelWidth + labelGap;
    contentWidth = rightControlX + rightControlWidth + margin;
    windowWidth = contentWidth + 36;
  }
};

void layoutPreviewPanel(HWND panel) {
  if (!panel) {
    return;
  }
  RECT client = {};
  if (!getClientRect(panel, &client)) {
    return;
  }
  const int clientWidth = static_cast<int>(client.right - client.left);
  const int margin = 12;
  const int gap = 8;
  const int statusWidth = (std::max)(1, clientWidth - (margin * 2));

  const int manageWidth = paddedTextWidth("Manage Recordings", 34, 180);
  const int setupWidth = paddedTextWidth("Setup", 34, 92);
  const int dockWidth = paddedTextWidth("Dock/Undock", 34, 130);
  const int manageX = (std::max)(margin, clientWidth - margin - manageWidth);
  const int setupX = (std::max)(margin, manageX - gap - setupWidth);
  const int dockX = (std::max)(margin, setupX - gap - dockWidth);
  moveControl(panel, kDockToggleButton, dockX, 112, dockWidth, 26);
  moveControl(panel, kSetupButton, setupX, 112, setupWidth, 26);
  moveControl(panel, kManageButton, manageX, 112, manageWidth, 26);

  const int prevWidth = paddedTextWidth("Prev", 28, 56);
  const int nextWidth = paddedTextWidth("Next", 28, 56);
  const int prevX = margin;
  const int nextX = (std::max)(prevX + prevWidth + gap + 180 + gap, clientWidth - margin - nextWidth);
  const int comboX = prevX + prevWidth + gap;
  const int comboWidth = (std::max)(180, nextX - gap - comboX);
  moveControl(panel, kPreviousLookButton, prevX, 60, prevWidth, 26);
  moveControl(panel, kLookCombo, comboX, 60, comboWidth, kLookComboHeight);
  moveControl(panel, kNextLookButton, nextX, 60, nextWidth, 26);
  moveControl(panel, kFormatLabel, margin, 36, statusWidth, 20);
  moveControl(panel, kStatusLabel, margin, 7, statusWidth, 26);
}

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

template <size_t Count>
int optionIndexForValue(const ComboOption (&options)[Count], const char *value) {
  if (!value || !value[0]) {
    return 0;
  }
  for (int i = 0; i < static_cast<int>(Count); ++i) {
    if (strcmp(options[i].value, value) == 0 || strcmp(options[i].title, value) == 0) {
      return i;
    }
  }
  return 0;
}

template <size_t Count>
const char *optionValueForSelection(const ComboOption (&options)[Count], int selection) {
  if (selection < 0 || selection >= static_cast<int>(Count)) {
    return options[0].value;
  }
  return options[selection].value;
}

template <size_t Count>
void addOptions(HWND parent, int controlID, const ComboOption (&options)[Count]) {
  for (const auto &option : options) {
    comboAddString(parent, controlID, option.title);
  }
}

void syncSetupFields() {
  if (!g_setupWindow) {
    return;
  }
  setDlgItemText(g_setupWindow, kSetupHostField, g_host.c_str());
  comboSetCurSel(g_setupWindow, kSetupResolutionCombo, optionIndexForValue(kResolutionOptions, g_resolution.c_str()));
  comboSetCurSel(g_setupWindow, kSetupFPSCombo, optionIndexForValue(kFPSOptions, g_fps.c_str()));
  comboSetCurSel(g_setupWindow, kSetupOrientationCombo, optionIndexForValue(kOrientationOptions, g_orientation.c_str()));
  comboSetCurSel(g_setupWindow, kSetupLensCombo, optionIndexForValue(kLensOptions, g_lens.c_str()));
}

void captureSetupFields() {
  if (!g_setupWindow) {
    return;
  }
  char text[256] = {};
  if (getDlgItemText(g_setupWindow, kSetupHostField, text, sizeof(text))) {
    g_host = text;
  }
  g_resolution = optionValueForSelection(kResolutionOptions, comboGetCurSel(g_setupWindow, kSetupResolutionCombo));
  g_fps = optionValueForSelection(kFPSOptions, comboGetCurSel(g_setupWindow, kSetupFPSCombo));
  g_orientation = optionValueForSelection(kOrientationOptions, comboGetCurSel(g_setupWindow, kSetupOrientationCombo));
  g_lens = optionValueForSelection(kLensOptions, comboGetCurSel(g_setupWindow, kSetupLensCombo));
}

void showSetupWindow();
void showManageWindow();

void applyStatusFont(HWND panel) {
  if (!panel) {
    return;
  }
  if (!g_statusFont) {
    g_statusFont = createFont(18, FW_BOLD, "");
  }
  if (g_statusFont) {
    sendMessage(getDlgItem(panel, kStatusLabel), WM_SETFONT, reinterpret_cast<WPARAM>(g_statusFont), 1);
  }
}

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
    HDC paintDC = hdc;
#ifdef _WIN32
    HDC memoryDC = CreateCompatibleDC(hdc);
    HBITMAP memoryBitmap = nullptr;
    HGDIOBJ oldBitmap = nullptr;
    const int clientWidth = static_cast<int>(client.right - client.left);
    const int clientHeight = static_cast<int>(client.bottom - client.top);
    if (memoryDC && clientWidth > 0 && clientHeight > 0) {
      memoryBitmap = CreateCompatibleBitmap(hdc, clientWidth, clientHeight);
      if (memoryBitmap) {
        oldBitmap = SelectObject(memoryDC, memoryBitmap);
        paintDC = memoryDC;
      }
    }
#else
    const int clientWidth = static_cast<int>(client.right - client.left);
    const int clientHeight = static_cast<int>(client.bottom - client.top);
#endif
    fillDialogBackground(paintDC, &client, 0);
    const int margin = kPreviewMargin;
    const int controlsHeight = kPreviewControlsHeight;
    const int width = (std::max)(1, clientWidth - margin * 2);
    const int height = (std::max)(1, clientHeight - controlsHeight - margin);
    if (!g_previewFrame.empty()) {
      int targetWidth = width;
      int targetHeight = height;
      const double sourceAspect = g_previewWidth > 0 && g_previewHeight > 0 ? static_cast<double>(g_previewWidth) / static_cast<double>(g_previewHeight) : 16.0 / 9.0;
      const double availableAspect = static_cast<double>(width) / static_cast<double>(height);
      if (availableAspect > sourceAspect) {
        targetWidth = (std::max)(1, static_cast<int>(targetHeight * sourceAspect));
      } else {
        targetHeight = (std::max)(1, static_cast<int>(targetWidth / sourceAspect));
      }
      const int targetX = margin + (width - targetWidth) / 2;
      const int targetY = controlsHeight + (height - targetHeight) / 2;
      drawFrame(paintDC, targetX, targetY, targetWidth, targetHeight, g_previewFrame.data(), g_previewWidth, g_previewHeight);
    }
    if (!g_usingLivePreview && !g_previewMessage.empty()) {
      RECT textRect = {margin + 16, controlsHeight + 16, client.right - margin - 16, client.bottom - margin - 16};
      drawText(paintDC, g_previewMessage.c_str(), &textRect, DT_CENTER | DT_VCENTER | DT_WORDBREAK);
    }
#ifdef _WIN32
    if (paintDC == memoryDC) {
      BitBlt(hdc, 0, 0, clientWidth, clientHeight, memoryDC, 0, 0, SRCCOPY);
    }
    if (oldBitmap) {
      SelectObject(memoryDC, oldBitmap);
    }
    if (memoryBitmap) {
      DeleteObject(memoryBitmap);
    }
    if (memoryDC) {
      DeleteDC(memoryDC);
    }
#endif
  }
  endPaint(hwnd, &paint);
}

void paintPopup(HWND hwnd, const char *title) {
  PAINTSTRUCT paint = {};
  HDC hdc = beginPaint(hwnd, &paint);
  if (!hdc) {
    return;
  }

  RECT client = {};
  if (getClientRect(hwnd, &client)) {
    fillDialogBackground(hdc, &client, 0);
    RECT header = {0, 0, client.right - client.left, 30};
    fillDialogBackground(hdc, &header, 1);
    RECT titleRect = {12, 6, client.right - 12, 28};
    drawText(hdc, title, &titleRect, DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  }
  endPaint(hwnd, &paint);
}

int lParamY(LPARAM lParam) {
  return static_cast<int>(static_cast<int16_t>((static_cast<uintptr_t>(lParam) >> 16) & 0xffff));
}

bool handlePopupDrag(HWND hwnd, UINT msg, LPARAM lParam) {
  if (msg == WM_NCHITTEST) {
    RECT windowRect = {};
    if (getWindowRect(hwnd, &windowRect)) {
      const int screenY = lParamY(lParam);
      if (screenY >= windowRect.top && screenY <= windowRect.top + 30) {
        return true;
      }
    }
  }
  if (msg == WM_LBUTTONDOWN && lParamY(lParam) <= 30) {
    g_dragWindow = hwnd;
    getCursorPos(&g_dragStartCursor);
    getWindowRect(hwnd, &g_dragStartWindow);
    setCapture(hwnd);
    return true;
  }
  if (msg == WM_MOUSEMOVE && g_dragWindow == hwnd) {
    POINT cursor = {};
    getCursorPos(&cursor);
    const int dx = cursor.x - g_dragStartCursor.x;
    const int dy = cursor.y - g_dragStartCursor.y;
    setWindowPos(hwnd,
                 nullptr,
                 g_dragStartWindow.left + dx,
                 g_dragStartWindow.top + dy,
                 g_dragStartWindow.right - g_dragStartWindow.left,
                 g_dragStartWindow.bottom - g_dragStartWindow.top,
                 0);
    return true;
  }
  if (msg == WM_LBUTTONUP && g_dragWindow == hwnd) {
    g_dragWindow = nullptr;
    releaseCapture();
    return true;
  }
  return false;
}

void configurePopupWindow(HWND hwnd, const char *title, int x, int y, int width, int height) {
  setDlgItemText(hwnd, 0, title);
  const LONG_PTR style = getWindowLong(hwnd, GWL_STYLE);
  setWindowLong(hwnd, GWL_STYLE, style | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME);
  setWindowPos(hwnd, nullptr, x, y, width, height, 0);
}

static LRESULT setupWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  (void)lParam;
  if (msg == WM_PAINT) {
    paintPopup(hwnd, "ReaShoot Setup");
    return 0;
  }
  if (msg == WM_ERASEBKGND) {
    return 1;
  }
  if (msg == WM_NCHITTEST) {
    RECT windowRect = {};
    if (getWindowRect(hwnd, &windowRect)) {
      const int screenY = lParamY(lParam);
      if (screenY >= windowRect.top && screenY <= windowRect.top + 30) {
        return HTCAPTION;
      }
    }
  }
  if (handlePopupDrag(hwnd, msg, lParam)) {
    return 0;
  }
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
    if (controlID == kSetupResolutionCombo || controlID == kSetupFPSCombo || controlID == kSetupOrientationCombo ||
        controlID == kSetupLensCombo) {
      captureSetupFields();
      if (g_callbacks.profileChanged) {
        g_callbacks.profileChanged(g_callbacks.context);
      }
      return 0;
    }
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
  if (msg == WM_PAINT) {
    paintPopup(hwnd, "ReaShoot Recordings");
    return 0;
  }
  if (msg == WM_ERASEBKGND) {
    return 1;
  }
  if (msg == WM_NCHITTEST) {
    RECT windowRect = {};
    if (getWindowRect(hwnd, &windowRect)) {
      const int screenY = lParamY(lParam);
      if (screenY >= windowRect.top && screenY <= windowRect.top + 30) {
        return HTCAPTION;
      }
    }
  }
  if (handlePopupDrag(hwnd, msg, lParam)) {
    return 0;
  }
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
  if (msg == kDrainQueuedWorkMessage) {
    if (g_callbacks.drainQueuedWork) {
      g_callbacks.drainQueuedWork(g_callbacks.context);
    }
    return 1;
  }
  if (msg == WM_PAINT) {
    paintPreview(hwnd);
    return 0;
  }
  if (msg == WM_ERASEBKGND) {
    return 1;
  }
  if (msg == WM_SIZE) {
    layoutPreviewPanel(hwnd);
    invalidateRect(hwnd, nullptr, false);
    return 0;
  }
  if (msg == WM_CLOSE) {
    showWindow(hwnd, SW_HIDE);
    if (g_callbacks.closed) {
      g_callbacks.closed(g_callbacks.context);
    }
    return 0;
  }
  if (msg == WM_DESTROY) {
    return 0;
  }
  if (msg == WM_COMMAND) {
    const int controlID = LOWORD(wParam);
    if (controlID == kSetupButton) {
      showSetupWindow();
      if (g_callbacks.setup) {
        g_callbacks.setup(g_callbacks.context);
      }
      return 0;
    }
    if (controlID == kManageButton) {
      showManageWindow();
      return 0;
    }
    if (controlID == kDockToggleButton) {
      if (g_callbacks.toggleDock) {
        g_callbacks.toggleDock(g_callbacks.context);
      }
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

void showSetupWindow() {
  if (!g_setupWindow) {
    g_setupWindow = createDialog(nullptr, nullptr, nullptr, reinterpret_cast<DLGPROC>(setupWindowProc), 0);
    if (!g_setupWindow) {
      return;
    }
    makeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, g_setupWindow, false, false);
    SetupLayout layout;
    configurePopupWindow(g_setupWindow, "ReaShoot Setup", 200, 200, layout.windowWidth, 280);
    const int discoverWidth = paddedTextWidth("Discover", 34, 120);
    const int pairWidth = paddedTextWidth("Pair", 34, 76);
    const int reconnectWidth = paddedTextWidth("Reconnect", 34, 222);
    const int closeWidth = paddedTextWidth("Close", 34, 76);
    const int fullRowControlWidth = layout.contentWidth - layout.leftControlX - discoverWidth - layout.labelGap - layout.margin;
    const int pairCodeWidth = layout.contentWidth - layout.leftControlX - pairWidth - reconnectWidth - (layout.labelGap * 2) - layout.margin;
    makeLabel(0, "Host", -1, layout.margin, 194, layout.leftLabelWidth, layout.labelHeight, 0);
    makeEditField(kSetupHostField, layout.leftControlX, 192, fullRowControlWidth, layout.rowHeight, 0);
    makeButton(0, "Discover", kSetupDiscoverButton, layout.leftControlX + fullRowControlWidth + layout.labelGap, 192, discoverWidth, layout.rowHeight, 0);
    makeLabel(0, "Pair code", -1, layout.margin, 156, layout.leftLabelWidth, layout.labelHeight, 0);
    makeEditField(kSetupPairingCodeField, layout.leftControlX, 154, pairCodeWidth, layout.rowHeight, 0);
    makeButton(0, "Pair", kSetupPairButton, layout.leftControlX + pairCodeWidth + layout.labelGap, 154, pairWidth, layout.rowHeight, 0);
    makeButton(0, "Reconnect", kSetupTestButton, layout.leftControlX + pairCodeWidth + layout.labelGap + pairWidth + layout.labelGap, 154, reconnectWidth, layout.rowHeight, 0);
    makeLabel(0, "Resolution", -1, layout.margin, 116, layout.leftLabelWidth, layout.labelHeight, 0);
    makeCombo(kSetupResolutionCombo, layout.leftControlX, 112, layout.leftControlWidth, 140, CBS_DROPDOWNLIST);
    addOptions(g_setupWindow, kSetupResolutionCombo, kResolutionOptions);
    makeLabel(0, "FPS", -1, layout.rightLabelX, 116, layout.rightLabelWidth, layout.labelHeight, 0);
    makeCombo(kSetupFPSCombo, layout.rightControlX, 112, layout.rightControlWidth, 140, CBS_DROPDOWNLIST);
    addOptions(g_setupWindow, kSetupFPSCombo, kFPSOptions);
    makeLabel(0, "Orientation", -1, layout.margin, 78, layout.leftLabelWidth, layout.labelHeight, 0);
    makeCombo(kSetupOrientationCombo, layout.leftControlX, 74, layout.leftControlWidth, 140, CBS_DROPDOWNLIST);
    addOptions(g_setupWindow, kSetupOrientationCombo, kOrientationOptions);
    makeLabel(0, "Lens", -1, layout.rightLabelX, 78, layout.rightLabelWidth, layout.labelHeight, 0);
    makeCombo(kSetupLensCombo, layout.rightControlX, 74, layout.rightControlWidth, 140, CBS_DROPDOWNLIST);
    addOptions(g_setupWindow, kSetupLensCombo, kLensOptions);
    makeButton(0, "Close", kSetupCloseButton, layout.contentWidth - layout.margin - closeWidth, 12, closeWidth, layout.rowHeight, 0);
  }
  syncSetupFields();
  setWindowPos(g_setupWindow, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
  showWindow(g_setupWindow, SW_SHOW);
}

void showManageWindow() {
  if (!g_manageWindow) {
    g_manageWindow = createDialog(nullptr, nullptr, nullptr, reinterpret_cast<DLGPROC>(manageWindowProc), 0);
    if (!g_manageWindow) {
      return;
    }
    makeSetCurParms(1.0f, 1.0f, 0.0f, 0.0f, g_manageWindow, false, false);
    const int margin = 12;
    const int gap = 10;
    const int pendingWidth = paddedTextWidth("Pending Videos...", 34, 170);
    const int deleteWidth = paddedTextWidth("Delete All", 34, 120);
    const int closeWidth = paddedTextWidth("Close", 34, 76);
    const int contentWidth = (std::max)(420, margin + pendingWidth + gap + deleteWidth + gap + closeWidth + margin);
    configurePopupWindow(g_manageWindow, "ReaShoot Recordings", 240, 240, contentWidth + 36, 150);
    makeLabel(0, "Manage recordings stored on the paired iPhone.", -1, margin, 82, contentWidth - (margin * 2), 20, 0);
    makeButton(0, "Pending Videos...", kManagePendingButton, margin, 46, pendingWidth, 26, 0);
    makeButton(0, "Delete All", kManageDeleteAllButton, margin + pendingWidth + gap, 46, deleteWidth, 26, 0);
    makeButton(0, "Close", kManageCloseButton, contentWidth - margin - closeWidth, 12, closeWidth, 26, 0);
  }
  setWindowPos(g_manageWindow, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
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
  makeButton(0, "Setup", kSetupButton, 0, 0, 92, 26, 0);
  makeButton(0, "Manage Recordings", kManageButton, 0, 0, 180, 26, 0);
  makeButton(0, "Dock/Undock", kDockToggleButton, 0, 0, 130, 26, 0);
  makeButton(0, "Prev", kPreviousLookButton, 0, 0, 56, 26, 0);
  makeButton(0, "Next", kNextLookButton, 0, 0, 56, 26, 0);
  makeCombo(kLookCombo, 0, 0, 528, kLookComboHeight, CBS_DROPDOWNLIST);
  for (const auto &look : kLookOptions) {
    comboAddString(panel, kLookCombo, look.title);
  }
  comboSetCurSel(panel, kLookCombo, 0);
  makeLabel(0, "ReaShoot camera preview", kFormatLabel, 0, 0, 656, 20, 0);
  makeLabel(0, "Video disabled", kStatusLabel, 0, 0, 656, 26, 0);
  applyStatusFont(panel);
  layoutPreviewPanel(panel);
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

void updateSwellPanelProfile(HWND panel, const char *resolution, const char *fps, const char *orientation, const char *lens) {
  if (!panel) {
    return;
  }
  g_resolution = resolution && resolution[0] ? resolution : "4K";
  g_fps = fps && fps[0] ? fps : "30";
  g_orientation = orientation && orientation[0] ? orientation : "auto";
  g_lens = lens && lens[0] ? lens : "wide";
  syncSetupFields();
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
  snprintf(settings.resolution, sizeof(settings.resolution), "%s", g_resolution.c_str());
  snprintf(settings.fps, sizeof(settings.fps), "%s", g_fps.c_str());
  snprintf(settings.orientation, sizeof(settings.orientation), "%s", g_orientation.c_str());
  snprintf(settings.lens, sizeof(settings.lens), "%s", g_lens.c_str());
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
  // Invalidate only the video region (below the controls), not the whole panel.
  // Repainting the full client every frame made the docked panel's child
  // controls flicker at playback frame rate ("blinking window"); the controls
  // are static and self-painting, so leave their band untouched.
  RECT client = {};
  if (getClientRect(panel, &client) && (client.bottom - client.top) > kPreviewControlsHeight) {
    RECT videoRegion = {client.left, client.top + kPreviewControlsHeight, client.right, client.bottom};
    invalidateRect(panel, &videoRegion, false);
  } else {
    invalidateRect(panel, nullptr, false);
  }
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
