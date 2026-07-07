// ReaShoot standalone desktop app for Windows.
//
// Native Win32 (Windows SDK) frontend over the shared cross-platform
// controller/state layer in src/core and src/desktop. Mirrors the macOS
// standalone app (src/app/mac/ReaShootDesktopApp.mm): live preview, host
// discovery/manual entry, request-based pairing, capture settings, start/stop
// recording, a "Videos on iPhone" manager, and download-destination selection.
//
// UI/platform concerns (window layout, dark theme, GDI blit, registry
// settings, file dialogs, main-thread dispatch, timers) live here; all
// workflow logic is delegated to the shared reashoot_desktop_core library.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <commctrl.h>
#include <dwmapi.h>
#include <objbase.h>
#include <shellapi.h>
#include <uxtheme.h>
#include <windowsx.h>

#include "ReaShootWin32Support.h"

#include "../../core/helper_output_parser.h"
#include "../../core/log_sanitization.h"
#include "../../core/remote_camera.h"
#include "../../desktop/desktop_app_controller.h"
#include "../../desktop/desktop_app_model.h"
#include "../../desktop/desktop_workflow.h"
#include "../../platform/win32/win32_h264_preview_renderer.h"
#include "../../platform/win32/win32_helper_process.h"
#include "../../platform/win32/win32_preview_stream_client.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <functional>
#include <memory>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "uxtheme.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "ole32.lib")

// Request Common Controls v6 so themed controls / ListView visual styles are
// available without an external .manifest file.
#pragma comment(                                                                                   \
    linker,                                                                                        \
    "\"/manifestdependency:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

using reashoot::core::redactedArguments;
using reashoot::core::redactedSettingsSummary;
using reashoot::core::redactedText;
using reashoot::win32app::debugLog;
using reashoot::win32app::narrow;
using reashoot::win32app::widen;

namespace {

// -------------------------------------------------------------------------
// Theme palette (dark Fluent-ish).
// -------------------------------------------------------------------------
constexpr COLORREF kWindowBg = RGB(32, 32, 32);
constexpr COLORREF kControlBg = RGB(43, 43, 43);
constexpr COLORREF kButtonBg = RGB(58, 58, 58);
constexpr COLORREF kButtonPressedBg = RGB(46, 46, 46);
constexpr COLORREF kButtonDisabledBg = RGB(40, 40, 40);
constexpr COLORREF kButtonBorder = RGB(85, 85, 85);
constexpr COLORREF kAccent = RGB(0, 120, 215);
constexpr COLORREF kAccentPressed = RGB(0, 99, 177);
constexpr COLORREF kRecordRed = RGB(214, 45, 45);
constexpr COLORREF kRecordRedDim = RGB(140, 25, 25);
constexpr COLORREF kText = RGB(240, 240, 240);
constexpr COLORREF kTextSecondary = RGB(170, 170, 170);
constexpr COLORREF kTextDisabled = RGB(120, 120, 120);

// -------------------------------------------------------------------------
// Control identifiers.
// -------------------------------------------------------------------------
enum ControlId : int {
  IDC_BTN_PREVIEW = 1001,
  IDC_BTN_RECORD,
  IDC_BTN_VIDEOS,
  IDC_BTN_SETUP,
  IDC_LBL_CONNECTION,
  IDC_LBL_STATUS,

  IDC_EDIT_HOST = 1100,
  IDC_BTN_DISCOVER,
  IDC_LBL_PAIRED,
  IDC_BTN_PAIR,
  IDC_EDIT_DOWNLOAD,
  IDC_BTN_CHOOSE,
  IDC_CMB_RES,
  IDC_CMB_FPS,
  IDC_CMB_ORIENT,
  IDC_CMB_ASPECT,
  IDC_CMB_LENS,
  IDC_EDIT_ZOOM,
  IDC_CMB_LOOK,
  IDC_BTN_SETUP_CLOSE,

  IDC_LBL_IPHONE = 1150,
  IDC_LBL_PAIRING,
  IDC_LBL_DOWNLOADS,
  IDC_LBL_RES,
  IDC_LBL_FPS,
  IDC_LBL_ORIENT,
  IDC_LBL_ASPECT,
  IDC_LBL_LENS,
  IDC_LBL_ZOOM,
  IDC_LBL_LOOK,

  IDC_VIDEO_LIST = 1200,
  IDC_BTN_REFRESH,
  IDC_BTN_DL_SEL,
  IDC_BTN_DEL_SEL,

  IDC_CHOOSER_LIST = 1300,
  IDC_BTN_CHOOSE_OK,
  IDC_BTN_CHOOSE_CANCEL,
};

constexpr UINT WM_APP_DISPATCH = WM_APP + 1;
constexpr UINT WM_APP_PREVIEW_FRAME = WM_APP + 2;
constexpr UINT_PTR kBlinkTimerId = 1;

const wchar_t *const kMainClass = L"ReaShootMainWindow";
const wchar_t *const kPreviewClass = L"ReaShootPreviewPanel";
const wchar_t *const kSetupClass = L"ReaShootSetupWindow";
const wchar_t *const kVideosClass = L"ReaShootVideosWindow";
const wchar_t *const kChooserClass = L"ReaShootChooserWindow";

int scaled(HWND hwnd, int value) {
  const int dpi = static_cast<int>(GetDpiForWindow(hwnd));
  return MulDiv(value, dpi > 0 ? dpi : 96, 96);
}

// Resizes a window so its client area is (clientWidth x clientHeight) logical
// pixels scaled to the window's DPI. Window sizes are created at fixed pixel
// values, but all interior layout metrics are DPI-scaled; without this the
// content overflows a fixed-size window on high-DPI displays.
void sizeClientScaled(HWND hwnd, int clientWidth, int clientHeight) {
  const UINT dpi = GetDpiForWindow(hwnd);
  const UINT effectiveDpi = dpi > 0 ? dpi : 96;
  RECT rect = {0, 0, MulDiv(clientWidth, static_cast<int>(effectiveDpi), 96),
               MulDiv(clientHeight, static_cast<int>(effectiveDpi), 96)};
  const DWORD style = static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_STYLE));
  const DWORD exStyle = static_cast<DWORD>(GetWindowLongPtrW(hwnd, GWL_EXSTYLE));
  AdjustWindowRectExForDpi(&rect, style, FALSE, exStyle, effectiveDpi);
  SetWindowPos(hwnd, nullptr, 0, 0, rect.right - rect.left, rect.bottom - rect.top, SWP_NOMOVE | SWP_NOZORDER);
}

void applyDarkTitleBar(HWND hwnd) {
  BOOL dark = TRUE;
  DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
}

// -------------------------------------------------------------------------
// Preview panel: paints the latest decoded BGRA frame (top-down, stride =
// width*4) with an aspect-fit letterbox, or an empty-state message.
// -------------------------------------------------------------------------
class PreviewPanel {
public:
  void attach(HWND hwnd) { hwnd_ = hwnd; }
  HWND hwnd() const { return hwnd_; }

  void setFrame(const reashoot::core::VideoFrame &frame) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pixels_ = frame.pixels;
      width_ = frame.width;
      height_ = frame.height;
      stride_ = frame.strideBytes;
    }
    requestRepaint();
  }

  void clear(const std::wstring &message) {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      pixels_.clear();
      width_ = height_ = stride_ = 0;
      emptyMessage_ = message;
    }
    requestRepaint();
  }

  void setEmptyMessage(const std::wstring &message) {
    bool empty = false;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      emptyMessage_ = message;
      empty = pixels_.empty();
    }
    if (empty) {
      requestRepaint();
    }
  }

  void onFrameMessage() { repaintPending_.store(false); }

  void paint(HDC windowDc, const RECT &client) {
    std::lock_guard<std::mutex> lock(mutex_);
    const int clientWidth = client.right - client.left;
    const int clientHeight = client.bottom - client.top;
    if (clientWidth <= 0 || clientHeight <= 0) {
      return;
    }

    // Double-buffer: compose black background + frame into an off-screen DC and
    // blit once, so the black fill never flashes between paints.
    HDC hdc = CreateCompatibleDC(windowDc);
    HBITMAP buffer = CreateCompatibleBitmap(windowDc, clientWidth, clientHeight);
    HBITMAP previousBitmap = static_cast<HBITMAP>(SelectObject(hdc, buffer));

    RECT local = {0, 0, clientWidth, clientHeight};
    HBRUSH black = CreateSolidBrush(RGB(0, 0, 0));
    FillRect(hdc, &local, black);
    DeleteObject(black);

    if (pixels_.empty() || width_ <= 0 || height_ <= 0 || stride_ <= 0) {
      std::wstring message = emptyMessage_.empty() ? L"No preview stream." : emptyMessage_;
      SetBkMode(hdc, TRANSPARENT);
      SetTextColor(hdc, kTextSecondary);
      DrawTextW(hdc, message.c_str(), -1, &local, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_WORD_ELLIPSIS);
    } else {
      const double imageAspect = static_cast<double>(width_) / static_cast<double>(height_);
      const double viewAspect = static_cast<double>(clientWidth) / std::max(clientHeight, 1);
      int drawWidth = clientWidth;
      int drawHeight = clientHeight;
      if (imageAspect > viewAspect) {
        drawHeight = static_cast<int>(clientWidth / imageAspect);
      } else {
        drawWidth = static_cast<int>(clientHeight * imageAspect);
      }
      const int drawX = (clientWidth - drawWidth) / 2;
      const int drawY = (clientHeight - drawHeight) / 2;

      BITMAPINFO info = {};
      info.bmiHeader.biSize = sizeof(info.bmiHeader);
      info.bmiHeader.biWidth = width_;
      info.bmiHeader.biHeight = -height_; // top-down (renderer emits top-down frames)
      info.bmiHeader.biPlanes = 1;
      info.bmiHeader.biBitCount = 32;
      info.bmiHeader.biCompression = BI_RGB;
      const int previousMode = SetStretchBltMode(hdc, HALFTONE);
      SetBrushOrgEx(hdc, 0, 0, nullptr);
      StretchDIBits(hdc, drawX, drawY, drawWidth, drawHeight, 0, 0, width_, height_, pixels_.data(), &info,
                    DIB_RGB_COLORS, SRCCOPY);
      SetStretchBltMode(hdc, previousMode);
    }

    BitBlt(windowDc, 0, 0, clientWidth, clientHeight, hdc, 0, 0, SRCCOPY);
    SelectObject(hdc, previousBitmap);
    DeleteObject(buffer);
    DeleteDC(hdc);
  }

private:
  void requestRepaint() {
    if (hwnd_ && !repaintPending_.exchange(true)) {
      PostMessageW(hwnd_, WM_APP_PREVIEW_FRAME, 0, 0);
    }
  }

  HWND hwnd_ = nullptr;
  std::mutex mutex_;
  std::vector<uint8_t> pixels_;
  int width_ = 0;
  int height_ = 0;
  int stride_ = 0;
  std::wstring emptyMessage_ = L"No paired iPhone.";
  std::atomic<bool> repaintPending_{false};
};

} // namespace

// ===========================================================================
// App
// ===========================================================================
class ReaShootApp {
public:
  int run(HINSTANCE instance, bool debug);

private:
  // Window creation ---------------------------------------------------------
  bool registerClasses(HINSTANCE instance);
  void createMainWindow(HINSTANCE instance);
  void createSetupWindow(HINSTANCE instance);
  void createVideosWindowIfNeeded();
  void layoutMain();
  void layoutSetup();
  void layoutVideos();

  // Window procedures -------------------------------------------------------
  static LRESULT CALLBACK mainProc(HWND, UINT, WPARAM, LPARAM);
  static LRESULT CALLBACK previewProc(HWND, UINT, WPARAM, LPARAM);
  static LRESULT CALLBACK setupProc(HWND, UINT, WPARAM, LPARAM);
  static LRESULT CALLBACK videosProc(HWND, UINT, WPARAM, LPARAM);
  static LRESULT CALLBACK chooserProc(HWND, UINT, WPARAM, LPARAM);
  LRESULT handleMain(HWND, UINT, WPARAM, LPARAM);
  LRESULT handleSetup(HWND, UINT, WPARAM, LPARAM);
  LRESULT handleVideos(HWND, UINT, WPARAM, LPARAM);
  LRESULT handleChooser(HWND, UINT, WPARAM, LPARAM);

  // Main-thread dispatch ----------------------------------------------------
  void postToMain(std::function<void()> work);
  void postDelayed(double seconds, std::function<void()> work);
  void drainMainQueue();
  reashoot::core::CompletionCallback onMain(std::function<void(reashoot::core::CommandResult)> fn);
  reashoot::core::ProgressCallback onMainProgress(std::function<void(std::string)> fn);

  // Settings / defaults -----------------------------------------------------
  void loadDefaults();
  void saveDefaults();
  reashoot::core::RemoteCameraSettings settings();

  // Status / buttons --------------------------------------------------------
  void setStatus(const std::wstring &status);
  void setStatusFromResult(const reashoot::core::CommandResult &result, const std::wstring &fallback);
  void updateButtons();
  void updateConnectionStatusLabels();
  void updatePreviewEmptyState();
  void syncControllerState();
  bool requireHostAndToken();

  // Workflows ---------------------------------------------------------------
  void runCommand(const std::wstring &status,
                  const reashoot::core::RemoteCameraSettings &settings,
                  const std::string &command,
                  const std::vector<std::string> &arguments,
                  std::function<void(reashoot::core::CommandResult)> completion);
  void discoverPhone();
  void applyDiscoveredCamera(const reashoot::desktop::DiscoveredCamera &camera);
  int chooseCameraIndex(const std::vector<reashoot::desktop::DiscoveredCamera> &cameras);
  void pairPhone();
  void profileSelectionChanged();
  void togglePreview();
  void toggleRecording();
  void startPreview();
  void startPreviewWithRetry(int attempt, bool automatic);
  void schedulePreviewRetryAfterFailure(const reashoot::core::CommandResult &result,
                                        int attempt,
                                        bool automatic,
                                        const std::wstring &fallback);
  void stopPreview();
  void autoStartPreviewIfPossible();
  void startRecording();
  void stopRecording();
  void promptForRecording(const reashoot::core::RemoteRecordingDescriptor &recording);
  void downloadRecording(const reashoot::core::RemoteRecordingDescriptor &recording);
  void deleteRecording(const std::string &recordingID);
  void chooseDownloadFolder();

  // Videos manager ----------------------------------------------------------
  void showPhoneVideos();
  void refreshPhoneVideos();
  void renderPhoneVideos();
  void downloadSelectedVideo();
  void deleteSelectedVideo();

  // Helpers -----------------------------------------------------------------
  std::string editText(HWND edit) const;
  void setEditText(HWND edit, const std::string &value);
  static std::wstring byteCountText(const reashoot::core::RemoteRecordingDescriptor &recording);
  std::wstring timestampText(const reashoot::core::RemoteRecordingDescriptor &recording);
  void drawOwnerButton(const DRAWITEMSTRUCT *draw);

  HINSTANCE instance_ = nullptr;
  HWND main_ = nullptr;
  HWND setup_ = nullptr;
  HWND videos_ = nullptr;
  HFONT font_ = nullptr;
  HFONT fontBold_ = nullptr;
  HBRUSH windowBrush_ = nullptr;
  HBRUSH controlBrush_ = nullptr;

  PreviewPanel preview_;
  HWND previewPanel_ = nullptr;

  // Setup controls.
  HWND hostEdit_ = nullptr;
  HWND downloadEdit_ = nullptr;
  HWND zoomEdit_ = nullptr;
  HWND pairedLabel_ = nullptr;
  HWND resCombo_ = nullptr;
  HWND fpsCombo_ = nullptr;
  HWND orientCombo_ = nullptr;
  HWND aspectCombo_ = nullptr;
  HWND lensCombo_ = nullptr;
  HWND lookCombo_ = nullptr;

  // Main controls.
  HWND previewButton_ = nullptr;
  HWND recordButton_ = nullptr;
  HWND videosButton_ = nullptr;
  HWND setupButton_ = nullptr;
  HWND connectionLabel_ = nullptr;
  HWND statusLabel_ = nullptr;

  // Videos controls.
  HWND videoList_ = nullptr;

  // Modal discovery chooser.
  HWND chooser_ = nullptr;
  HWND chooserList_ = nullptr;
  int chooserResult_ = -1;
  bool chooserDone_ = false;

  std::unique_ptr<reashoot::core::HelperProcess> helper_;
  std::unique_ptr<reashoot::core::RemoteCameraController> camera_;
  std::unique_ptr<reashoot::core::PreviewStreamClient> previewClient_;
  std::unique_ptr<reashoot::core::PreviewRenderer> previewRenderer_;
  reashoot::core::PreviewStreamDescriptor previewDescriptor_;
  std::shared_ptr<reashoot::core::AsyncCommandHandle> activeCommand_;
  reashoot::desktop::DesktopAppController controller_;

  std::string pairingToken_;
  std::vector<reashoot::core::RemoteRecordingDescriptor> phoneVideos_;
  bool recording_ = false;
  bool recordBlinkOn_ = true;
  bool previewRunning_ = false;
  bool previewDesired_ = false;
  bool setupSized_ = false;
  bool videosSized_ = false;
  uint64_t previewAccessUnits_ = 0;
  uint64_t previewFrames_ = 0;

  std::mutex queueMutex_;
  std::queue<std::function<void()>> queue_;
  std::atomic<bool> wakePending_{false};
};

namespace {
ReaShootApp *g_app = nullptr;
} // namespace

// ---------------------------------------------------------------------------
// Small control factories.
// ---------------------------------------------------------------------------
namespace {

void themeControl(HWND control, const wchar_t *theme) { SetWindowTheme(control, theme, nullptr); }

HWND makeLabel(HWND parent, int id, const wchar_t *text, DWORD extra = 0) {
  return CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE | SS_LEFT | extra, 0, 0, 0, 0, parent,
                         reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
}

HWND makeButton(HWND parent, int id, const wchar_t *text) {
  return CreateWindowExW(0, L"BUTTON", text, WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW, 0, 0, 0, 0, parent,
                         reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
}

HWND makeEdit(HWND parent, int id, const wchar_t *placeholder) {
  HWND edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | ES_AUTOHSCROLL, 0, 0,
                              0, 0, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
  themeControl(edit, L"DarkMode_CFD");
  if (placeholder && placeholder[0]) {
    SendMessageW(edit, EM_SETCUEBANNER, TRUE, reinterpret_cast<LPARAM>(placeholder));
  }
  return edit;
}

HWND makeCombo(HWND parent, int id, const std::vector<reashoot::desktop::DesktopChoice> &choices) {
  HWND combo = CreateWindowExW(0, L"COMBOBOX", L"", WS_CHILD | WS_VISIBLE | WS_TABSTOP | CBS_DROPDOWNLIST | WS_VSCROLL,
                               0, 0, 0, 0, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), nullptr, nullptr);
  themeControl(combo, L"DarkMode_CFD");
  for (const auto &choice : choices) {
    SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(widen(choice.title).c_str()));
  }
  return combo;
}

void selectComboValue(HWND combo,
                      const std::vector<reashoot::desktop::DesktopChoice> &choices,
                      const std::string &value,
                      const std::string &fallback) {
  const std::string &target = value.empty() ? fallback : value;
  int fallbackIndex = 0;
  for (size_t index = 0; index < choices.size(); ++index) {
    if (choices[index].value == target || choices[index].title == target) {
      SendMessageW(combo, CB_SETCURSEL, static_cast<WPARAM>(index), 0);
      return;
    }
    if (choices[index].value == fallback) {
      fallbackIndex = static_cast<int>(index);
    }
  }
  SendMessageW(combo, CB_SETCURSEL, static_cast<WPARAM>(fallbackIndex), 0);
}

std::string selectedComboValue(HWND combo,
                               const std::vector<reashoot::desktop::DesktopChoice> &choices,
                               const std::string &fallback) {
  const LRESULT index = SendMessageW(combo, CB_GETCURSEL, 0, 0);
  if (index >= 0 && static_cast<size_t>(index) < choices.size()) {
    return choices[static_cast<size_t>(index)].value;
  }
  return fallback;
}

void setLabelText(HWND label, const std::wstring &text) { SetWindowTextW(label, text.c_str()); }

} // namespace

// ---------------------------------------------------------------------------
// ReaShootApp implementation.
// ---------------------------------------------------------------------------
std::string ReaShootApp::editText(HWND edit) const {
  const int length = GetWindowTextLengthW(edit);
  if (length <= 0) {
    return {};
  }
  std::wstring buffer(static_cast<size_t>(length) + 1, L'\0');
  GetWindowTextW(edit, buffer.data(), length + 1);
  buffer.resize(static_cast<size_t>(length));
  return narrow(buffer);
}

void ReaShootApp::setEditText(HWND edit, const std::string &value) { SetWindowTextW(edit, widen(value).c_str()); }

int ReaShootApp::run(HINSTANCE instance, bool debug) {
  instance_ = instance;
  g_app = this;
  reashoot::win32app::initializeDebugLogging(debug);

  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  INITCOMMONCONTROLSEX icc = {sizeof(icc), ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES};
  InitCommonControlsEx(&icc);

  windowBrush_ = CreateSolidBrush(kWindowBg);
  controlBrush_ = CreateSolidBrush(kControlBg);

  NONCLIENTMETRICSW metrics = {sizeof(metrics)};
  SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, sizeof(metrics), &metrics, 0);
  LOGFONTW logFont = metrics.lfMessageFont;
  wcscpy_s(logFont.lfFaceName, L"Segoe UI Variable Text");
  font_ = CreateFontIndirectW(&logFont);
  logFont.lfWeight = FW_SEMIBOLD;
  fontBold_ = CreateFontIndirectW(&logFont);

  if (!registerClasses(instance)) {
    return 1;
  }
  createMainWindow(instance);
  createSetupWindow(instance);

  // Services. The preview panel must exist before the renderer captures it.
  const std::string helperPath = reashoot::win32app::helperExecutablePath();
  debugLog("Application starting. helper=" + helperPath);
  helper_ = reashoot::platform::win32::createHelperProcess(
      helperPath, [](const std::string &message) { debugLog("helper: " + redactedText(message)); });
  camera_ = std::make_unique<reashoot::core::RemoteCameraController>(*helper_);
  previewClient_ = reashoot::platform::win32::createPreviewStreamClient();
  previewRenderer_ = reashoot::platform::win32::createH264PreviewRenderer(
      [this](const reashoot::core::VideoFrame &frame) {
        ++previewFrames_;
        if (previewFrames_ == 1 || previewFrames_ % 30 == 0) {
          debugLog("preview frame #" + std::to_string(previewFrames_) + " " + std::to_string(frame.width) + "x" +
                   std::to_string(frame.height) + " stride=" + std::to_string(frame.strideBytes) +
                   " bytes=" + std::to_string(frame.pixels.size()));
        }
        preview_.setFrame(frame);
      },
      [this](const reashoot::core::DecoderStatus &status) {
        debugLog(std::string("preview decoder: ") + (status.hardwareAccelerated ? "hw" : "sw") + " " + status.system);
      });

  loadDefaults();
  updateButtons();
  updatePreviewEmptyState();
  setStatus(L"Ready. Open ReaShoot on your iPhone, then discover or enter its host.");

  ShowWindow(main_, SW_SHOW);
  // Size to the DPI of the monitor the window actually landed on. GetDpiForWindow
  // is only reliable once the window is realized/shown, so do this after Show.
  sizeClientScaled(main_, 880, 690);
  UpdateWindow(main_);
  autoStartPreviewIfPossible();

  MSG msg;
  while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
    if ((setup_ && IsDialogMessageW(setup_, &msg)) || (videos_ && IsDialogMessageW(videos_, &msg)) ||
        (main_ && IsDialogMessageW(main_, &msg))) {
      continue;
    }
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }
  return 0;
}

bool ReaShootApp::registerClasses(HINSTANCE instance) {
  WNDCLASSEXW mainClass = {sizeof(mainClass)};
  mainClass.lpfnWndProc = &ReaShootApp::mainProc;
  mainClass.hInstance = instance;
  mainClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  mainClass.hbrBackground = windowBrush_;
  mainClass.lpszClassName = kMainClass;
  mainClass.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
  if (!RegisterClassExW(&mainClass)) {
    return false;
  }

  WNDCLASSEXW previewClass = {sizeof(previewClass)};
  previewClass.lpfnWndProc = &ReaShootApp::previewProc;
  previewClass.hInstance = instance;
  previewClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  previewClass.hbrBackground = reinterpret_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  previewClass.lpszClassName = kPreviewClass;
  RegisterClassExW(&previewClass);

  WNDCLASSEXW setupClass = {sizeof(setupClass)};
  setupClass.lpfnWndProc = &ReaShootApp::setupProc;
  setupClass.hInstance = instance;
  setupClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  setupClass.hbrBackground = windowBrush_;
  setupClass.lpszClassName = kSetupClass;
  RegisterClassExW(&setupClass);

  WNDCLASSEXW videosClass = {sizeof(videosClass)};
  videosClass.lpfnWndProc = &ReaShootApp::videosProc;
  videosClass.hInstance = instance;
  videosClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  videosClass.hbrBackground = windowBrush_;
  videosClass.lpszClassName = kVideosClass;
  RegisterClassExW(&videosClass);

  WNDCLASSEXW chooserClass = {sizeof(chooserClass)};
  chooserClass.lpfnWndProc = &ReaShootApp::chooserProc;
  chooserClass.hInstance = instance;
  chooserClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  chooserClass.hbrBackground = windowBrush_;
  chooserClass.lpszClassName = kChooserClass;
  RegisterClassExW(&chooserClass);
  return true;
}

void ReaShootApp::createMainWindow(HINSTANCE instance) {
  main_ = CreateWindowExW(0, kMainClass, L"ReaShoot", WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT,
                          CW_USEDEFAULT, 900, 720, nullptr, nullptr, instance, nullptr);
  applyDarkTitleBar(main_);

  previewPanel_ =
      CreateWindowExW(0, kPreviewClass, L"", WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, main_, nullptr, instance, nullptr);
  preview_.attach(previewPanel_);
  SetWindowLongPtrW(previewPanel_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(&preview_));

  previewButton_ = makeButton(main_, IDC_BTN_PREVIEW, L"Start Preview");
  recordButton_ = makeButton(main_, IDC_BTN_RECORD, L"Start Recording");
  videosButton_ = makeButton(main_, IDC_BTN_VIDEOS, L"Videos on iPhone");
  setupButton_ = makeButton(main_, IDC_BTN_SETUP, L"Setup...");
  connectionLabel_ = makeLabel(main_, IDC_LBL_CONNECTION, L"Not paired", SS_ENDELLIPSIS);
  statusLabel_ = makeLabel(main_, IDC_LBL_STATUS, L"", SS_ENDELLIPSIS);

  for (HWND control : {previewButton_, recordButton_, videosButton_, setupButton_, connectionLabel_, statusLabel_}) {
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
  }
  layoutMain();
}

void ReaShootApp::createSetupWindow(HINSTANCE instance) {
  setup_ = CreateWindowExW(0, kSetupClass, L"ReaShoot Setup", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_THICKFRAME,
                           CW_USEDEFAULT, CW_USEDEFAULT, 780, 360, main_, nullptr, instance, nullptr);
  applyDarkTitleBar(setup_);

  makeLabel(setup_, IDC_LBL_IPHONE, L"iPhone");
  hostEdit_ = makeEdit(setup_, IDC_EDIT_HOST, L"kevin-long-iphone.local or IP address");
  makeButton(setup_, IDC_BTN_DISCOVER, L"Discover");
  makeLabel(setup_, IDC_LBL_PAIRING, L"Pairing");
  pairedLabel_ = makeLabel(setup_, IDC_LBL_PAIRED, L"Not paired");
  makeButton(setup_, IDC_BTN_PAIR, L"Pair");

  makeLabel(setup_, IDC_LBL_DOWNLOADS, L"Downloads");
  downloadEdit_ = makeEdit(setup_, IDC_EDIT_DOWNLOAD, L"Download folder");
  makeButton(setup_, IDC_BTN_CHOOSE, L"Choose...");

  makeLabel(setup_, IDC_LBL_RES, L"Resolution");
  resCombo_ = makeCombo(setup_, IDC_CMB_RES, reashoot::desktop::resolutionChoices());
  makeLabel(setup_, IDC_LBL_FPS, L"FPS");
  fpsCombo_ = makeCombo(setup_, IDC_CMB_FPS, reashoot::desktop::fpsChoices());
  makeLabel(setup_, IDC_LBL_ORIENT, L"Orientation");
  orientCombo_ = makeCombo(setup_, IDC_CMB_ORIENT, reashoot::desktop::orientationChoices());

  makeLabel(setup_, IDC_LBL_ASPECT, L"Aspect");
  aspectCombo_ = makeCombo(setup_, IDC_CMB_ASPECT, reashoot::desktop::aspectChoices());
  makeLabel(setup_, IDC_LBL_LENS, L"Lens");
  lensCombo_ = makeCombo(setup_, IDC_CMB_LENS, reashoot::desktop::lensChoices());
  makeLabel(setup_, IDC_LBL_ZOOM, L"Zoom");
  zoomEdit_ = makeEdit(setup_, IDC_EDIT_ZOOM, L"1.0");

  makeLabel(setup_, IDC_LBL_LOOK, L"Look");
  lookCombo_ = makeCombo(setup_, IDC_CMB_LOOK, reashoot::desktop::lookChoices());
  makeButton(setup_, IDC_BTN_SETUP_CLOSE, L"Close");

  EnumChildWindows(
      setup_,
      [](HWND child, LPARAM param) -> BOOL {
        SendMessageW(child, WM_SETFONT, param, TRUE);
        return TRUE;
      },
      reinterpret_cast<LPARAM>(font_));
  layoutSetup();
}

void ReaShootApp::createVideosWindowIfNeeded() {
  if (videos_) {
    return;
  }
  videos_ = CreateWindowExW(0, kVideosClass, L"Videos on iPhone", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                            760, 520, main_, nullptr, instance_, nullptr);
  applyDarkTitleBar(videos_);

  makeLabel(videos_, 0, L"Videos stored on the iPhone");
  makeButton(videos_, IDC_BTN_REFRESH, L"Refresh");
  makeButton(videos_, IDC_BTN_DL_SEL, L"Download");
  makeButton(videos_, IDC_BTN_DEL_SEL, L"Delete");

  videoList_ = CreateWindowExW(WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
                               WS_CHILD | WS_VISIBLE | WS_TABSTOP | LVS_REPORT | LVS_SINGLESEL | LVS_SHOWSELALWAYS, 0, 0,
                               0, 0, videos_, reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_VIDEO_LIST)), instance_,
                               nullptr);
  themeControl(videoList_, L"DarkMode_Explorer");
  ListView_SetExtendedListViewStyle(videoList_, LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER);
  ListView_SetBkColor(videoList_, kControlBg);
  ListView_SetTextBkColor(videoList_, kControlBg);
  ListView_SetTextColor(videoList_, kText);

  LVCOLUMNW column = {};
  column.mask = LVCF_TEXT | LVCF_WIDTH;
  struct ColumnSpec {
    const wchar_t *title;
    int width;
  };
  const ColumnSpec columns[] = {{L"File", 320}, {L"Recorded", 220}, {L"Size", 120}};
  for (int index = 0; index < 3; ++index) {
    column.pszText = const_cast<wchar_t *>(columns[index].title);
    column.cx = scaled(videos_, columns[index].width);
    ListView_InsertColumn(videoList_, index, &column);
  }

  EnumChildWindows(
      videos_,
      [](HWND child, LPARAM param) -> BOOL {
        SendMessageW(child, WM_SETFONT, param, TRUE);
        return TRUE;
      },
      reinterpret_cast<LPARAM>(font_));
  layoutVideos();
}

// ---------------------------------------------------------------------------
// Layout.
// ---------------------------------------------------------------------------
void ReaShootApp::layoutMain() {
  RECT client;
  GetClientRect(main_, &client);
  const int margin = scaled(main_, 12);
  const int spacing = scaled(main_, 8);
  const int buttonHeight = scaled(main_, 34);
  const int labelHeight = scaled(main_, 20);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;

  const int bottomBlock = buttonHeight + spacing + labelHeight + spacing + labelHeight + margin;
  const int previewHeight = std::max(scaled(main_, 120), height - bottomBlock - margin - spacing);
  MoveWindow(previewPanel_, margin, margin, std::max(0, width - 2 * margin), previewHeight, TRUE);

  int y = margin + previewHeight + spacing;
  const int buttonWidth = std::max(scaled(main_, 120), (width - 2 * margin - 3 * spacing) / 4);
  int x = margin;
  for (HWND button : {previewButton_, recordButton_, videosButton_, setupButton_}) {
    MoveWindow(button, x, y, buttonWidth, buttonHeight, TRUE);
    x += buttonWidth + spacing;
  }
  y += buttonHeight + spacing;
  MoveWindow(connectionLabel_, margin, y, width - 2 * margin, labelHeight, TRUE);
  y += labelHeight + spacing;
  MoveWindow(statusLabel_, margin, y, width - 2 * margin, labelHeight, TRUE);
  InvalidateRect(main_, nullptr, TRUE);
}

void ReaShootApp::layoutSetup() {
  RECT client;
  GetClientRect(setup_, &client);
  const int margin = scaled(setup_, 16);
  const int rowHeight = scaled(setup_, 28);
  const int gap = scaled(setup_, 8);
  const int labelWidth = scaled(setup_, 84);
  const int width = client.right - client.left;
  int y = margin;

  const int contentWidth = width - 2 * margin;
  const int buttonWidth = scaled(setup_, 96);
  const int x = margin;

  auto placeLabel = [&](int id, int px, int py) {
    MoveWindow(GetDlgItem(setup_, id), px, py + (rowHeight - scaled(setup_, 18)) / 2, labelWidth, scaled(setup_, 18),
               TRUE);
  };

  // Row: iPhone host + Discover.
  placeLabel(IDC_LBL_IPHONE, x, y);
  MoveWindow(GetDlgItem(setup_, IDC_EDIT_HOST), x + labelWidth, y, contentWidth - labelWidth - buttonWidth - gap,
             rowHeight, TRUE);
  MoveWindow(GetDlgItem(setup_, IDC_BTN_DISCOVER), width - margin - buttonWidth, y, buttonWidth, rowHeight, TRUE);
  y += rowHeight + gap;

  // Row: pairing status + Pair.
  placeLabel(IDC_LBL_PAIRING, x, y);
  MoveWindow(GetDlgItem(setup_, IDC_LBL_PAIRED), x + labelWidth, y + (rowHeight - scaled(setup_, 18)) / 2,
             contentWidth - labelWidth - buttonWidth - gap, scaled(setup_, 18), TRUE);
  MoveWindow(GetDlgItem(setup_, IDC_BTN_PAIR), width - margin - buttonWidth, y, buttonWidth, rowHeight, TRUE);
  y += rowHeight + gap;

  // Row: downloads + Choose.
  placeLabel(IDC_LBL_DOWNLOADS, x, y);
  MoveWindow(GetDlgItem(setup_, IDC_EDIT_DOWNLOAD), x + labelWidth, y, contentWidth - labelWidth - buttonWidth - gap,
             rowHeight, TRUE);
  MoveWindow(GetDlgItem(setup_, IDC_BTN_CHOOSE), width - margin - buttonWidth, y, buttonWidth, rowHeight, TRUE);
  y += rowHeight + gap;

  // Rows of three (label + field) cells each.
  const int cellWidth = (contentWidth - 2 * gap) / 3;
  const int fieldWidth = cellWidth - labelWidth - gap;
  auto placeTriple = [&](int labelA, HWND a, int labelB, HWND b, int labelC, HWND c) {
    const int labelIds[3] = {labelA, labelB, labelC};
    HWND items[3] = {a, b, c};
    for (int i = 0; i < 3; ++i) {
      if (!items[i]) {
        continue;
      }
      const int cellX = margin + i * (cellWidth + gap);
      placeLabel(labelIds[i], cellX, y);
      MoveWindow(items[i], cellX + labelWidth, y, fieldWidth, rowHeight, TRUE);
    }
    y += rowHeight + gap;
  };
  placeTriple(IDC_LBL_RES, resCombo_, IDC_LBL_FPS, fpsCombo_, IDC_LBL_ORIENT, orientCombo_);
  placeTriple(IDC_LBL_ASPECT, aspectCombo_, IDC_LBL_LENS, lensCombo_, IDC_LBL_ZOOM, zoomEdit_);
  placeTriple(IDC_LBL_LOOK, lookCombo_, 0, nullptr, 0, nullptr);

  MoveWindow(GetDlgItem(setup_, IDC_BTN_SETUP_CLOSE), width - margin - buttonWidth, y, buttonWidth, rowHeight, TRUE);
  InvalidateRect(setup_, nullptr, TRUE);
}

void ReaShootApp::layoutVideos() {
  if (!videos_) {
    return;
  }
  RECT client;
  GetClientRect(videos_, &client);
  const int margin = scaled(videos_, 12);
  const int rowHeight = scaled(videos_, 30);
  const int gap = scaled(videos_, 8);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;
  const int buttonWidth = scaled(videos_, 110);

  MoveWindow(GetDlgItem(videos_, IDC_BTN_REFRESH), width - margin - buttonWidth, margin, buttonWidth, rowHeight, TRUE);
  const int listTop = margin + rowHeight + gap;
  const int actionsTop = height - margin - rowHeight;
  MoveWindow(videoList_, margin, listTop, width - 2 * margin, std::max(rowHeight, actionsTop - listTop - gap), TRUE);

  MoveWindow(GetDlgItem(videos_, IDC_BTN_DL_SEL), margin, actionsTop, buttonWidth, rowHeight, TRUE);
  MoveWindow(GetDlgItem(videos_, IDC_BTN_DEL_SEL), margin + buttonWidth + gap, actionsTop, buttonWidth, rowHeight,
             TRUE);
  InvalidateRect(videos_, nullptr, TRUE);
}

// ---------------------------------------------------------------------------
// Main-thread dispatch.
// ---------------------------------------------------------------------------
void ReaShootApp::postToMain(std::function<void()> work) {
  {
    std::lock_guard<std::mutex> lock(queueMutex_);
    queue_.push(std::move(work));
  }
  if (main_ && !wakePending_.exchange(true)) {
    PostMessageW(main_, WM_APP_DISPATCH, 0, 0);
  }
}

void ReaShootApp::postDelayed(double seconds, std::function<void()> work) {
  const int ms = std::max(0, static_cast<int>(seconds * 1000.0));
  std::thread([this, ms, work = std::move(work)]() mutable {
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
    postToMain(std::move(work));
  }).detach();
}

void ReaShootApp::drainMainQueue() {
  wakePending_.store(false);
  std::queue<std::function<void()>> local;
  {
    std::lock_guard<std::mutex> lock(queueMutex_);
    std::swap(local, queue_);
  }
  while (!local.empty()) {
    auto work = std::move(local.front());
    local.pop();
    if (work) {
      work();
    }
  }
}

reashoot::core::CompletionCallback ReaShootApp::onMain(std::function<void(reashoot::core::CommandResult)> fn) {
  return [this, fn = std::move(fn)](reashoot::core::CommandResult result) mutable {
    postToMain([fn, result = std::move(result)]() mutable { fn(std::move(result)); });
  };
}

reashoot::core::ProgressCallback ReaShootApp::onMainProgress(std::function<void(std::string)> fn) {
  return [this, fn = std::move(fn)](const std::string &line) mutable {
    postToMain([fn, line]() mutable { fn(line); });
  };
}

// ---------------------------------------------------------------------------
// Settings.
// ---------------------------------------------------------------------------
void ReaShootApp::loadDefaults() {
  using namespace reashoot::win32app;
  const std::string host = settingsGet("host");
  setEditText(hostEdit_, host);
  std::string download = settingsGet("downloadDirectory");
  if (download.empty()) {
    download = reashoot::desktop::defaultDownloadDirectory();
  }
  setEditText(downloadEdit_, download);
  std::string zoom = settingsGet("zoom");
  if (zoom.empty()) {
    zoom = reashoot::desktop::defaultZoom();
  }
  setEditText(zoomEdit_, zoom);
  selectComboValue(resCombo_, reashoot::desktop::resolutionChoices(), settingsGet("resolution"),
                   reashoot::desktop::defaultResolution());
  selectComboValue(fpsCombo_, reashoot::desktop::fpsChoices(), settingsGet("fps"), reashoot::desktop::defaultFps());
  selectComboValue(orientCombo_, reashoot::desktop::orientationChoices(), settingsGet("orientation"),
                   reashoot::desktop::defaultOrientation());
  selectComboValue(aspectCombo_, reashoot::desktop::aspectChoices(), settingsGet("aspect"),
                   reashoot::desktop::defaultAspect());
  selectComboValue(lensCombo_, reashoot::desktop::lensChoices(), settingsGet("lens"),
                   reashoot::desktop::defaultLens());
  selectComboValue(lookCombo_, reashoot::desktop::lookChoices(), settingsGet("look"),
                   reashoot::desktop::defaultLook());
  pairingToken_ = settingsGet("pairingToken");
  updateConnectionStatusLabels();
  debugLog(std::string("Loaded defaults host=") + host + " token=" + (pairingToken_.empty() ? "empty" : "present"));
}

void ReaShootApp::saveDefaults() {
  using namespace reashoot::win32app;
  settingsSet("host", editText(hostEdit_));
  settingsSet("downloadDirectory", editText(downloadEdit_));
  settingsSet("zoom", editText(zoomEdit_));
  settingsSet("resolution", selectedComboValue(resCombo_, reashoot::desktop::resolutionChoices(),
                                               reashoot::desktop::defaultResolution()));
  settingsSet("fps", selectedComboValue(fpsCombo_, reashoot::desktop::fpsChoices(), reashoot::desktop::defaultFps()));
  settingsSet("orientation", selectedComboValue(orientCombo_, reashoot::desktop::orientationChoices(),
                                                reashoot::desktop::defaultOrientation()));
  settingsSet("aspect",
              selectedComboValue(aspectCombo_, reashoot::desktop::aspectChoices(), reashoot::desktop::defaultAspect()));
  settingsSet("lens",
              selectedComboValue(lensCombo_, reashoot::desktop::lensChoices(), reashoot::desktop::defaultLens()));
  settingsSet("look",
              selectedComboValue(lookCombo_, reashoot::desktop::lookChoices(), reashoot::desktop::defaultLook()));
  if (pairingToken_.empty()) {
    settingsRemove("pairingToken");
  } else {
    settingsSet("pairingToken", pairingToken_);
  }
  updateConnectionStatusLabels();
}

reashoot::core::RemoteCameraSettings ReaShootApp::settings() {
  reashoot::core::RemoteCameraSettings s;
  s.host = editText(hostEdit_);
  s.token = pairingToken_;
  s.resolution =
      selectedComboValue(resCombo_, reashoot::desktop::resolutionChoices(), reashoot::desktop::defaultResolution());
  s.fps = selectedComboValue(fpsCombo_, reashoot::desktop::fpsChoices(), reashoot::desktop::defaultFps());
  s.orientation = selectedComboValue(orientCombo_, reashoot::desktop::orientationChoices(),
                                     reashoot::desktop::defaultOrientation());
  s.aspect = selectedComboValue(aspectCombo_, reashoot::desktop::aspectChoices(), reashoot::desktop::defaultAspect());
  s.lens = selectedComboValue(lensCombo_, reashoot::desktop::lensChoices(), reashoot::desktop::defaultLens());
  s.zoom = editText(zoomEdit_);
  s.look = selectedComboValue(lookCombo_, reashoot::desktop::lookChoices(), reashoot::desktop::defaultLook());
  return s;
}

// ---------------------------------------------------------------------------
// Status / buttons.
// ---------------------------------------------------------------------------
void ReaShootApp::setStatus(const std::wstring &status) {
  setLabelText(statusLabel_, status);
  debugLog("Status: " + narrow(status));
}

void ReaShootApp::setStatusFromResult(const reashoot::core::CommandResult &result, const std::wstring &fallback) {
  if (result.exitCode == 0) {
    setStatus(fallback);
    return;
  }
  std::string message = result.errorMessage.empty() ? result.output : result.errorMessage;
  if (message.empty()) {
    message = "Command failed.";
  }
  setStatus(widen(message));
}

void ReaShootApp::syncControllerState() {
  controller_.setHost(editText(hostEdit_));
  controller_.setToken(pairingToken_);
  controller_.setRecording(recording_);
  controller_.setPreviewRunning(previewRunning_);
  controller_.setPreviewDesired(previewDesired_);
}

void ReaShootApp::updateButtons() {
  syncControllerState();
  const reashoot::desktop::DesktopButtonState state = controller_.buttonState();
  EnableWindow(recordButton_, state.recordEnabled);
  SetWindowTextW(previewButton_, widen(state.previewTitle).c_str());
  SetWindowTextW(recordButton_, widen(state.recordTitle).c_str());
  if (recording_) {
    SetTimer(main_, kBlinkTimerId, 600, nullptr);
  } else {
    KillTimer(main_, kBlinkTimerId);
    recordBlinkOn_ = true;
  }
  InvalidateRect(previewButton_, nullptr, TRUE);
  InvalidateRect(recordButton_, nullptr, TRUE);
}

void ReaShootApp::updateConnectionStatusLabels() {
  syncControllerState();
  if (pairedLabel_) {
    setLabelText(pairedLabel_, controller_.hasToken() ? L"Paired" : L"Not paired");
  }
  setLabelText(connectionLabel_, widen(controller_.connectionStatusText()));
  updatePreviewEmptyState();
}

void ReaShootApp::updatePreviewEmptyState() {
  syncControllerState();
  preview_.setEmptyMessage(widen(controller_.previewEmptyMessage()));
}

bool ReaShootApp::requireHostAndToken() {
  if (editText(hostEdit_).empty()) {
    setStatus(L"Enter or discover an iPhone host first.");
    preview_.clear(L"No iPhone selected.");
    return false;
  }
  if (pairingToken_.empty()) {
    setStatus(L"Pair with the iPhone first.");
    preview_.clear(L"No paired iPhone.");
    return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Command runner.
// ---------------------------------------------------------------------------
void ReaShootApp::runCommand(const std::wstring &status,
                             const reashoot::core::RemoteCameraSettings &s,
                             const std::string &command,
                             const std::vector<std::string> &arguments,
                             std::function<void(reashoot::core::CommandResult)> completion) {
  setStatus(status);
  debugLog("Command start command=" + command + " args=" + redactedArguments(arguments) +
           " settings=" + redactedSettingsSummary(s));
  activeCommand_ = camera_->runAsync(s, command, arguments, {}, onMain(std::move(completion)));
}

// ---------------------------------------------------------------------------
// Discovery / pairing.
// ---------------------------------------------------------------------------
void ReaShootApp::discoverPhone() {
  reashoot::core::RemoteCameraSettings s = settings();
  runCommand(L"Discovering iPhones...", s, "discover", {"--timeout", "3"},
             [this](reashoot::core::CommandResult result) {
               if (result.exitCode != 0) {
                 setStatusFromResult(result, L"Discovery failed.");
                 return;
               }
               const auto cameras = reashoot::desktop::parseDiscoveredCameras(result.output);
               if (cameras.empty()) {
                 setStatus(L"No iPhone found. Enter the host or IP address manually.");
                 return;
               }
               if (cameras.size() == 1) {
                 applyDiscoveredCamera(cameras.front());
                 return;
               }
               const int index = chooseCameraIndex(cameras);
               if (index < 0) {
                 setStatus(L"Discovery canceled. No iPhone selected.");
                 return;
               }
               applyDiscoveredCamera(cameras[static_cast<size_t>(index)]);
             });
}

void ReaShootApp::applyDiscoveredCamera(const reashoot::desktop::DiscoveredCamera &camera) {
  setEditText(hostEdit_, camera.host);
  saveDefaults();
  setStatus(widen("Selected " + camera.name + " at " + camera.host));
  if (previewDesired_ && !pairingToken_.empty() && !previewRunning_) {
    startPreviewWithRetry(0, true);
  }
}

int ReaShootApp::chooseCameraIndex(const std::vector<reashoot::desktop::DiscoveredCamera> &cameras) {
  HWND owner = (setup_ && IsWindowVisible(setup_)) ? setup_ : main_;
  const int margin = scaled(owner, 14);
  const int rowHeight = scaled(owner, 32);
  const int listItemHeight = scaled(owner, 20);
  const int width = scaled(owner, 460);
  const int visibleRows = std::min<int>(static_cast<int>(cameras.size()), 8);
  const int labelHeight = scaled(owner, 20);
  const int listHeight = std::max(listItemHeight * 3, listItemHeight * visibleRows) + scaled(owner, 8);
  const int height = margin + labelHeight + scaled(owner, 6) + listHeight + scaled(owner, 12) + rowHeight + margin +
                     scaled(owner, 34); // + caption slack

  chooser_ = CreateWindowExW(WS_EX_DLGMODALFRAME, kChooserClass, L"Select iPhone",
                             WS_POPUPWINDOW | WS_CAPTION | WS_VISIBLE, CW_USEDEFAULT, CW_USEDEFAULT, width, height,
                             owner, nullptr, instance_, nullptr);
  applyDarkTitleBar(chooser_);

  HWND prompt = CreateWindowExW(0, L"STATIC", L"Multiple iPhones were found. Choose one:",
                                WS_CHILD | WS_VISIBLE | SS_LEFT, margin, margin, width - 2 * margin, labelHeight,
                                chooser_, nullptr, instance_, nullptr);
  const int listTop = margin + labelHeight + scaled(owner, 6);
  chooserList_ = CreateWindowExW(WS_EX_CLIENTEDGE, L"LISTBOX", L"",
                                 WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL | LBS_NOTIFY | LBS_HASSTRINGS, margin,
                                 listTop, width - 2 * margin, listHeight, chooser_,
                                 reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_CHOOSER_LIST)), instance_, nullptr);
  themeControl(chooserList_, L"DarkMode_Explorer");
  for (const auto &camera : cameras) {
    SendMessageW(chooserList_, LB_ADDSTRING, 0,
                 reinterpret_cast<LPARAM>(widen(reashoot::desktop::discoveredCameraLabel(camera)).c_str()));
  }
  SendMessageW(chooserList_, LB_SETCURSEL, 0, 0);

  const int buttonWidth = scaled(owner, 100);
  const int buttonsY = listTop + listHeight + scaled(owner, 12);
  HWND cancel = CreateWindowExW(0, L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                                width - margin - buttonWidth, buttonsY, buttonWidth, rowHeight, chooser_,
                                reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_BTN_CHOOSE_CANCEL)), instance_,
                                nullptr);
  HWND ok = CreateWindowExW(0, L"BUTTON", L"Select", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_OWNERDRAW,
                            width - 2 * margin - 2 * buttonWidth, buttonsY, buttonWidth, rowHeight, chooser_,
                            reinterpret_cast<HMENU>(static_cast<INT_PTR>(IDC_BTN_CHOOSE_OK)), instance_, nullptr);
  for (HWND control : {prompt, chooserList_, ok, cancel}) {
    SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font_), TRUE);
  }

  // Center over the owner window.
  RECT ownerRect;
  GetWindowRect(owner, &ownerRect);
  RECT chooserRect;
  GetWindowRect(chooser_, &chooserRect);
  const int chooserWidth = chooserRect.right - chooserRect.left;
  const int chooserHeight = chooserRect.bottom - chooserRect.top;
  const int x = ownerRect.left + ((ownerRect.right - ownerRect.left) - chooserWidth) / 2;
  const int y = ownerRect.top + ((ownerRect.bottom - ownerRect.top) - chooserHeight) / 2;
  SetWindowPos(chooser_, nullptr, x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER);

  chooserDone_ = false;
  chooserResult_ = -1;
  EnableWindow(owner, FALSE);
  ShowWindow(chooser_, SW_SHOW);
  SetForegroundWindow(chooser_);
  SetFocus(chooserList_);

  MSG msg;
  while (!chooserDone_) {
    const BOOL got = GetMessageW(&msg, nullptr, 0, 0);
    if (got == 0) {
      PostQuitMessage(static_cast<int>(msg.wParam)); // app is quitting
      chooserResult_ = -1;
      break;
    }
    if (got == -1) {
      break;
    }
    if (IsDialogMessageW(chooser_, &msg)) {
      continue;
    }
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  EnableWindow(owner, TRUE);
  DestroyWindow(chooser_);
  chooser_ = nullptr;
  chooserList_ = nullptr;
  SetForegroundWindow(owner);
  return chooserResult_;
}

void ReaShootApp::pairPhone() {
  if (editText(hostEdit_).empty()) {
    setStatus(L"Enter or discover an iPhone host first.");
    return;
  }
  const std::string clientName = reashoot::win32app::localComputerName();
  reashoot::core::RemoteCameraSettings s = settings();
  runCommand(L"Pairing request sent. Accept it on the iPhone.", s, "pair", {"--client-name", clientName},
             [this](reashoot::core::CommandResult result) {
               if (result.exitCode != 0) {
                 setStatusFromResult(result, L"Pairing failed.");
                 return;
               }
               reashoot::core::FieldMap fields = reashoot::core::parseFields(result.output, ' ');
               auto token = fields.find("token");
               if (token == fields.end() || token->second.empty()) {
                 setStatus(L"Pairing response did not include a token.");
                 return;
               }
               pairingToken_ = token->second;
               updateConnectionStatusLabels();
               saveDefaults();
               setStatus(L"Paired with iPhone.");
               previewDesired_ = true;
               startPreviewWithRetry(0, true);
             });
}

void ReaShootApp::profileSelectionChanged() {
  saveDefaults();
  if (!previewRunning_) {
    return;
  }
  if (!requireHostAndToken()) {
    return;
  }
  reashoot::core::RemoteCameraSettings s = settings();
  runCommand(L"Applying capture settings...", s, "configure", reashoot::core::configureArguments(s),
             [this](reashoot::core::CommandResult result) {
               if (result.exitCode != 0) {
                 schedulePreviewRetryAfterFailure(result, 0, true, L"Could not apply capture settings.");
                 return;
               }
               setStatus(L"Preview streaming.");
             });
}

// ---------------------------------------------------------------------------
// Preview.
// ---------------------------------------------------------------------------
void ReaShootApp::togglePreview() {
  if (previewRunning_) {
    stopPreview();
  } else {
    previewDesired_ = true;
    startPreview();
  }
}

void ReaShootApp::startPreview() { startPreviewWithRetry(0, false); }

void ReaShootApp::startPreviewWithRetry(int attempt, bool automatic) {
  if (!requireHostAndToken()) {
    return;
  }
  saveDefaults();
  reashoot::core::RemoteCameraSettings s = settings();
  preview_.clear(L"Connecting to iPhone preview...");
  runCommand(L"Configuring preview...", s, "configure", reashoot::core::configureArguments(s),
             [this, attempt, automatic](reashoot::core::CommandResult configureResult) {
               if (configureResult.exitCode != 0) {
                 schedulePreviewRetryAfterFailure(configureResult, attempt, automatic, L"Configure failed.");
                 return;
               }
               reashoot::core::RemoteCameraSettings previewSettings = settings();
               runCommand(L"Starting preview...", previewSettings, "start-preview",
                          reashoot::core::tokenArguments(previewSettings),
                          [this, attempt, automatic](reashoot::core::CommandResult result) {
                            if (result.exitCode != 0) {
                              schedulePreviewRetryAfterFailure(result, attempt, automatic, L"Preview failed.");
                              return;
                            }
                            previewDescriptor_ = reashoot::desktop::parsePreviewDescriptor(result.output);
                            reashoot::core::PreviewStreamRequest request;
                            request.host = editText(hostEdit_);
                            request.port = previewDescriptor_.port;
                            request.path = previewDescriptor_.streamPath;
                            request.token = pairingToken_;
                            previewRenderer_->reset();
                            previewAccessUnits_ = 0;
                            previewFrames_ = 0;
                            const bool started = previewClient_->start(
                                request,
                                [this](std::vector<uint8_t> data) {
                                  ++previewAccessUnits_;
                                  if (previewAccessUnits_ == 1 || previewAccessUnits_ % 30 == 0) {
                                    debugLog("preview access unit #" + std::to_string(previewAccessUnits_) +
                                             " bytes=" + std::to_string(data.size()));
                                  }
                                  previewRenderer_->renderAnnexBAccessUnit(data.data(), data.size());
                                },
                                [this]() {
                                  postToMain([this]() {
                                    previewRunning_ = true;
                                    updateButtons();
                                    preview_.setEmptyMessage(L"Waiting for video from iPhone...");
                                    setStatus(L"Preview streaming.");
                                  });
                                },
                                [this](const std::string &message) {
                                  postToMain([this, message]() {
                                    previewRunning_ = false;
                                    previewRenderer_->reset();
                                    preview_.clear(L"No stream from phone.");
                                    updateButtons();
                                    setStatus(widen(message));
                                    if (previewDesired_) {
                                      reashoot::core::CommandResult transient;
                                      transient.exitCode = 1;
                                      transient.output = message;
                                      schedulePreviewRetryAfterFailure(transient, 0, true, L"Preview stream failed.");
                                    }
                                  });
                                });
                            if (!started) {
                              preview_.clear(L"Could not open preview stream.");
                              setStatus(L"Could not open preview stream.");
                            }
                          });
             });
}

void ReaShootApp::schedulePreviewRetryAfterFailure(const reashoot::core::CommandResult &result,
                                                   int attempt,
                                                   bool automatic,
                                                   const std::wstring &fallback) {
  syncControllerState();
  const reashoot::desktop::PreviewRetryDecision retry = controller_.retryDecision(result, attempt);
  if (!retry.shouldRetry) {
    std::string message = result.errorMessage.empty() ? result.output : result.errorMessage;
    preview_.clear(message.empty() ? fallback : widen(message));
    setStatusFromResult(result, fallback);
    return;
  }
  const int nextAttempt = retry.nextAttempt;
  preview_.clear(widen(retry.statusText));
  setStatus(widen(retry.statusText));
  postDelayed(retry.delaySeconds, [this, nextAttempt, automatic]() {
    if (previewDesired_ && !previewRunning_) {
      startPreviewWithRetry(nextAttempt, automatic);
    }
  });
}

void ReaShootApp::stopPreview() {
  previewDesired_ = false;
  previewClient_->stop();
  previewRenderer_->reset();
  previewRunning_ = false;
  preview_.clear(L"Preview stopped.");
  updateButtons();
  reashoot::core::RemoteCameraSettings s = settings();
  if (!s.host.empty() && !s.token.empty()) {
    activeCommand_ = camera_->runAsync(s, "stop-preview", reashoot::core::tokenArguments(s), {},
                                       onMain([](reashoot::core::CommandResult) {}));
  }
  setStatus(L"Preview stopped.");
}

void ReaShootApp::autoStartPreviewIfPossible() {
  if (pairingToken_.empty()) {
    return;
  }
  previewDesired_ = true;
  if (editText(hostEdit_).empty()) {
    discoverPhone();
    return;
  }
  postDelayed(0.8, [this]() {
    if (previewDesired_ && !previewRunning_) {
      startPreviewWithRetry(0, true);
    }
  });
}

// ---------------------------------------------------------------------------
// Recording.
// ---------------------------------------------------------------------------
void ReaShootApp::toggleRecording() {
  if (recording_) {
    stopRecording();
  } else {
    startRecording();
  }
}

void ReaShootApp::startRecording() {
  if (!requireHostAndToken()) {
    return;
  }
  saveDefaults();
  reashoot::core::RemoteCameraSettings s = settings();
  runCommand(L"Configuring iPhone...", s, "configure", reashoot::core::configureArguments(s),
             [this](reashoot::core::CommandResult configureResult) {
               if (configureResult.exitCode != 0) {
                 setStatusFromResult(configureResult, L"Configure failed.");
                 return;
               }
               reashoot::core::RemoteCameraSettings startSettings = settings();
               const std::string sessionID = reashoot::desktop::makeSessionID();
               runCommand(L"Starting recording...", startSettings, "start",
                          reashoot::core::startArguments(startSettings, sessionID),
                          [this](reashoot::core::CommandResult startResult) {
                            if (startResult.exitCode != 0) {
                              setStatusFromResult(startResult, L"Start failed.");
                              return;
                            }
                            recording_ = true;
                            updateButtons();
                            setStatus(L"Recording on iPhone.");
                          });
             });
}

void ReaShootApp::stopRecording() {
  if (!requireHostAndToken()) {
    return;
  }
  reashoot::core::RemoteCameraSettings s = settings();
  setStatus(L"Stopping iPhone recording...");
  activeCommand_ = camera_->stop(s, onMain([this](reashoot::core::CommandResult result) {
    recording_ = false;
    updateButtons();
    if (result.exitCode != 0) {
      setStatusFromResult(result, L"Stop failed.");
      return;
    }
    auto recordings = reashoot::desktop::parseRecordingDescriptors(result.output);
    if (recordings.empty()) {
      setStatus(L"Recording stopped, but no recording descriptor was returned.");
      return;
    }
    promptForRecording(recordings.front());
  }));
}

void ReaShootApp::promptForRecording(const reashoot::core::RemoteRecordingDescriptor &recording) {
  const std::wstring text = L"Download or delete " + widen(recording.filename) + L"?\n\nYes = Download, No = Delete.";
  const int response = MessageBoxW(main_, text.c_str(), L"Recording stopped", MB_YESNOCANCEL | MB_ICONQUESTION);
  if (response == IDYES) {
    downloadRecording(recording);
  } else if (response == IDNO) {
    deleteRecording(recording.id);
  } else {
    setStatus(L"Recording remains pending on the iPhone.");
  }
}

void ReaShootApp::downloadRecording(const reashoot::core::RemoteRecordingDescriptor &recording) {
  reashoot::core::RemoteCameraSettings s = settings();
  std::string downloadDirectory = editText(downloadEdit_);
  if (downloadDirectory.empty()) {
    downloadDirectory = reashoot::desktop::defaultDownloadDirectory();
    setEditText(downloadEdit_, downloadDirectory);
  }
  setStatus(L"Downloading iPhone video...");
  activeCommand_ = camera_->downloadRecording(
      s, recording, downloadDirectory, onMainProgress([this](std::string line) {
        const std::string status = reashoot::core::progressStatusText(line);
        if (!status.empty()) {
          setStatus(widen(status));
        }
      }),
      onMain([this](reashoot::core::CommandResult result) {
        if (result.exitCode != 0) {
          setStatusFromResult(result, L"Download failed.");
          return;
        }
        const std::string path = reashoot::core::parseDownloadedPath(result.output);
        if (path.empty()) {
          setStatus(L"Download completed.");
          return;
        }
        reashoot::win32app::revealInExplorer(path);
        setStatus(widen("Downloaded " + path));
      }));
}

void ReaShootApp::deleteRecording(const std::string &recordingID) {
  reashoot::core::RemoteCameraSettings s = settings();
  setStatus(L"Deleting iPhone recording...");
  activeCommand_ = camera_->deleteRecording(s, recordingID, onMain([this](reashoot::core::CommandResult result) {
    setStatusFromResult(result, L"Recording deleted.");
  }));
}

void ReaShootApp::chooseDownloadFolder() {
  const std::string chosen = reashoot::win32app::chooseDirectory(setup_, editText(downloadEdit_));
  if (!chosen.empty()) {
    setEditText(downloadEdit_, chosen);
    saveDefaults();
  }
}

// ---------------------------------------------------------------------------
// Videos manager.
// ---------------------------------------------------------------------------
void ReaShootApp::showPhoneVideos() {
  createVideosWindowIfNeeded();
  ShowWindow(videos_, SW_SHOW);
  if (!videosSized_) {
    sizeClientScaled(videos_, 740, 500);
    videosSized_ = true;
  }
  SetForegroundWindow(videos_);
  refreshPhoneVideos();
}

void ReaShootApp::refreshPhoneVideos() {
  if (!requireHostAndToken()) {
    return;
  }
  reashoot::core::RemoteCameraSettings s = settings();
  setStatus(L"Checking videos on iPhone...");
  activeCommand_ = camera_->listRecordings(s, onMain([this](reashoot::core::CommandResult result) {
    if (result.exitCode != 0) {
      setStatusFromResult(result, L"Could not list recordings.");
      return;
    }
    phoneVideos_ = reashoot::desktop::parseRecordingDescriptors(result.output);
    renderPhoneVideos();
    setStatus(phoneVideos_.empty() ? L"No videos on the iPhone." : L"Videos on iPhone refreshed.");
  }));
}

std::wstring ReaShootApp::byteCountText(const reashoot::core::RemoteRecordingDescriptor &recording) {
  double bytes = static_cast<double>(std::atoll(recording.byteCount.c_str()));
  const wchar_t *units[] = {L"B", L"KB", L"MB", L"GB", L"TB"};
  int unit = 0;
  while (bytes >= 1024.0 && unit < 4) {
    bytes /= 1024.0;
    ++unit;
  }
  wchar_t buffer[64];
  swprintf_s(buffer, unit == 0 ? L"%.0f %s" : L"%.1f %s", bytes, units[unit]);
  return buffer;
}

std::wstring ReaShootApp::timestampText(const reashoot::core::RemoteRecordingDescriptor &recording) {
  if (!recording.createdAt.empty()) {
    return widen(recording.createdAt);
  }
  return widen(reashoot::desktop::recordingTimestampFallback(recording));
}

void ReaShootApp::renderPhoneVideos() {
  if (!videoList_) {
    return;
  }
  ListView_DeleteAllItems(videoList_);
  for (size_t index = 0; index < phoneVideos_.size(); ++index) {
    const auto &recording = phoneVideos_[index];
    std::wstring filename = widen(recording.filename);
    LVITEMW item = {};
    item.mask = LVIF_TEXT | LVIF_PARAM;
    item.iItem = static_cast<int>(index);
    item.lParam = static_cast<LPARAM>(index);
    item.pszText = filename.data();
    ListView_InsertItem(videoList_, &item);
    std::wstring timestamp = timestampText(recording);
    std::wstring size = byteCountText(recording);
    ListView_SetItemText(videoList_, static_cast<int>(index), 1, timestamp.data());
    ListView_SetItemText(videoList_, static_cast<int>(index), 2, size.data());
  }
}

void ReaShootApp::downloadSelectedVideo() {
  const int index = ListView_GetNextItem(videoList_, -1, LVNI_SELECTED);
  if (index < 0 || static_cast<size_t>(index) >= phoneVideos_.size()) {
    setStatus(L"Select a video to download.");
    return;
  }
  downloadRecording(phoneVideos_[static_cast<size_t>(index)]);
}

void ReaShootApp::deleteSelectedVideo() {
  const int index = ListView_GetNextItem(videoList_, -1, LVNI_SELECTED);
  if (index < 0 || static_cast<size_t>(index) >= phoneVideos_.size()) {
    setStatus(L"Select a video to delete.");
    return;
  }
  const auto recording = phoneVideos_[static_cast<size_t>(index)];
  const std::wstring text = L"Delete " + widen(recording.filename) + L" from the iPhone?";
  if (MessageBoxW(videos_, text.c_str(), L"Delete video from iPhone?", MB_YESNO | MB_ICONWARNING) != IDYES) {
    return;
  }
  reashoot::core::RemoteCameraSettings s = settings();
  setStatus(L"Deleting iPhone video...");
  activeCommand_ = camera_->deleteRecording(s, recording.id, onMain([this](reashoot::core::CommandResult result) {
    setStatusFromResult(result, L"Video deleted from iPhone.");
    if (result.exitCode == 0) {
      refreshPhoneVideos();
    }
  }));
}

// ---------------------------------------------------------------------------
// Owner-drawn buttons.
// ---------------------------------------------------------------------------
void ReaShootApp::drawOwnerButton(const DRAWITEMSTRUCT *draw) {
  const bool pressed = (draw->itemState & ODS_SELECTED) != 0;
  const bool disabled = (draw->itemState & ODS_DISABLED) != 0;
  const int id = static_cast<int>(draw->CtlID);

  COLORREF background = pressed ? kButtonPressedBg : kButtonBg;
  COLORREF textColor = kText;
  if (id == IDC_BTN_RECORD && recording_) {
    background = recordBlinkOn_ ? kRecordRed : kRecordRedDim;
    textColor = RGB(255, 255, 255);
  } else if (id == IDC_BTN_PREVIEW || id == IDC_BTN_DISCOVER || id == IDC_BTN_PAIR || id == IDC_BTN_CHOOSE_OK) {
    background = pressed ? kAccentPressed : kAccent;
    textColor = RGB(255, 255, 255);
  }
  if (disabled) {
    background = kButtonDisabledBg;
    textColor = kTextDisabled;
  }

  RECT rect = draw->rcItem;
  HBRUSH brush = CreateSolidBrush(background);
  FillRect(draw->hDC, &rect, brush);
  DeleteObject(brush);
  HBRUSH border = CreateSolidBrush(kButtonBorder);
  FrameRect(draw->hDC, &rect, border);
  DeleteObject(border);

  wchar_t text[128] = {};
  GetWindowTextW(draw->hwndItem, text, static_cast<int>(std::size(text)));
  SetBkMode(draw->hDC, TRANSPARENT);
  SetTextColor(draw->hDC, textColor);
  HFONT previous = reinterpret_cast<HFONT>(SelectObject(draw->hDC, fontBold_ ? fontBold_ : font_));
  DrawTextW(draw->hDC, text, -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
  SelectObject(draw->hDC, previous);
  if (draw->itemState & ODS_FOCUS) {
    RECT focus = rect;
    InflateRect(&focus, -scaled(draw->hwndItem, 3), -scaled(draw->hwndItem, 3));
    DrawFocusRect(draw->hDC, &focus);
  }
}

// ---------------------------------------------------------------------------
// Window procedures.
// ---------------------------------------------------------------------------
LRESULT CALLBACK ReaShootApp::mainProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (g_app) {
    return g_app->handleMain(hwnd, msg, wParam, lParam);
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT ReaShootApp::handleMain(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  switch (msg) {
    case WM_APP_DISPATCH:
      drainMainQueue();
      return 0;
    case WM_SIZE:
      layoutMain();
      return 0;
    case WM_GETMINMAXINFO: {
      auto *info = reinterpret_cast<MINMAXINFO *>(lParam);
      info->ptMinTrackSize.x = scaled(hwnd, 640);
      info->ptMinTrackSize.y = scaled(hwnd, 520);
      return 0;
    }
    case WM_DPICHANGED: {
      const RECT *suggested = reinterpret_cast<const RECT *>(lParam);
      SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, suggested->right - suggested->left,
                   suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_TIMER:
      if (wParam == kBlinkTimerId && recording_) {
        recordBlinkOn_ = !recordBlinkOn_;
        InvalidateRect(recordButton_, nullptr, TRUE);
      }
      return 0;
    case WM_CTLCOLORSTATIC: {
      HDC dc = reinterpret_cast<HDC>(wParam);
      SetTextColor(dc, reinterpret_cast<HWND>(lParam) == connectionLabel_ ? kTextSecondary : kText);
      SetBkColor(dc, kWindowBg);
      return reinterpret_cast<LRESULT>(windowBrush_);
    }
    case WM_DRAWITEM:
      drawOwnerButton(reinterpret_cast<const DRAWITEMSTRUCT *>(lParam));
      return TRUE;
    case WM_COMMAND:
      switch (LOWORD(wParam)) {
        case IDC_BTN_PREVIEW:
          togglePreview();
          return 0;
        case IDC_BTN_RECORD:
          toggleRecording();
          return 0;
        case IDC_BTN_VIDEOS:
          showPhoneVideos();
          return 0;
        case IDC_BTN_SETUP:
          saveDefaults();
          ShowWindow(setup_, SW_SHOW);
          if (!setupSized_) {
            sizeClientScaled(setup_, 780, 340);
            setupSized_ = true;
          }
          SetForegroundWindow(setup_);
          return 0;
      }
      return 0;
    case WM_CLOSE:
      DestroyWindow(hwnd);
      return 0;
    case WM_DESTROY:
      if (previewClient_) {
        previewClient_->stop();
      }
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT CALLBACK ReaShootApp::previewProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  auto *panel = reinterpret_cast<PreviewPanel *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (msg) {
    case WM_APP_PREVIEW_FRAME:
      if (panel) {
        panel->onFrameMessage();
        InvalidateRect(hwnd, nullptr, FALSE);
      }
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      RECT client;
      GetClientRect(hwnd, &client);
      if (panel) {
        panel->paint(hdc, client);
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT CALLBACK ReaShootApp::setupProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (g_app) {
    return g_app->handleSetup(hwnd, msg, wParam, lParam);
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT ReaShootApp::handleSetup(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  switch (msg) {
    case WM_SIZE:
      layoutSetup();
      return 0;
    case WM_GETMINMAXINFO: {
      auto *info = reinterpret_cast<MINMAXINFO *>(lParam);
      info->ptMinTrackSize.x = scaled(hwnd, 620);
      info->ptMinTrackSize.y = scaled(hwnd, 320);
      return 0;
    }
    case WM_DPICHANGED: {
      const RECT *suggested = reinterpret_cast<const RECT *>(lParam);
      SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, suggested->right - suggested->left,
                   suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_CTLCOLORSTATIC: {
      HDC dc = reinterpret_cast<HDC>(wParam);
      SetTextColor(dc, kText);
      SetBkColor(dc, kWindowBg);
      return reinterpret_cast<LRESULT>(windowBrush_);
    }
    case WM_CTLCOLOREDIT:
    case WM_CTLCOLORLISTBOX: {
      HDC dc = reinterpret_cast<HDC>(wParam);
      SetTextColor(dc, kText);
      SetBkColor(dc, kControlBg);
      return reinterpret_cast<LRESULT>(controlBrush_);
    }
    case WM_DRAWITEM:
      drawOwnerButton(reinterpret_cast<const DRAWITEMSTRUCT *>(lParam));
      return TRUE;
    case WM_COMMAND:
      switch (LOWORD(wParam)) {
        case IDC_BTN_DISCOVER:
          discoverPhone();
          return 0;
        case IDC_BTN_PAIR:
          pairPhone();
          return 0;
        case IDC_BTN_CHOOSE:
          chooseDownloadFolder();
          return 0;
        case IDC_BTN_SETUP_CLOSE:
          saveDefaults();
          ShowWindow(hwnd, SW_HIDE);
          return 0;
        case IDC_EDIT_ZOOM:
          if (HIWORD(wParam) == EN_KILLFOCUS) {
            profileSelectionChanged();
          }
          return 0;
        case IDC_CMB_RES:
        case IDC_CMB_FPS:
        case IDC_CMB_ORIENT:
        case IDC_CMB_ASPECT:
        case IDC_CMB_LENS:
        case IDC_CMB_LOOK:
          if (HIWORD(wParam) == CBN_SELCHANGE) {
            profileSelectionChanged();
          }
          return 0;
      }
      return 0;
    case WM_CLOSE:
      saveDefaults();
      ShowWindow(hwnd, SW_HIDE);
      return 0;
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT CALLBACK ReaShootApp::videosProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (g_app) {
    return g_app->handleVideos(hwnd, msg, wParam, lParam);
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT ReaShootApp::handleVideos(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  switch (msg) {
    case WM_SIZE:
      layoutVideos();
      return 0;
    case WM_GETMINMAXINFO: {
      auto *info = reinterpret_cast<MINMAXINFO *>(lParam);
      info->ptMinTrackSize.x = scaled(hwnd, 560);
      info->ptMinTrackSize.y = scaled(hwnd, 360);
      return 0;
    }
    case WM_DPICHANGED: {
      const RECT *suggested = reinterpret_cast<const RECT *>(lParam);
      SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, suggested->right - suggested->left,
                   suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_CTLCOLORSTATIC: {
      HDC dc = reinterpret_cast<HDC>(wParam);
      SetTextColor(dc, kText);
      SetBkColor(dc, kWindowBg);
      return reinterpret_cast<LRESULT>(windowBrush_);
    }
    case WM_DRAWITEM:
      drawOwnerButton(reinterpret_cast<const DRAWITEMSTRUCT *>(lParam));
      return TRUE;
    case WM_NOTIFY: {
      auto *header = reinterpret_cast<NMHDR *>(lParam);
      if (header->idFrom == IDC_VIDEO_LIST && header->code == NM_DBLCLK) {
        downloadSelectedVideo();
      }
      return 0;
    }
    case WM_COMMAND:
      switch (LOWORD(wParam)) {
        case IDC_BTN_REFRESH:
          refreshPhoneVideos();
          return 0;
        case IDC_BTN_DL_SEL:
          downloadSelectedVideo();
          return 0;
        case IDC_BTN_DEL_SEL:
          deleteSelectedVideo();
          return 0;
      }
      return 0;
    case WM_CLOSE:
      ShowWindow(hwnd, SW_HIDE);
      return 0;
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Discovery chooser window.
// ---------------------------------------------------------------------------
LRESULT CALLBACK ReaShootApp::chooserProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (g_app) {
    return g_app->handleChooser(hwnd, msg, wParam, lParam);
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

LRESULT ReaShootApp::handleChooser(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  auto finish = [this](int result) {
    chooserResult_ = result;
    chooserDone_ = true;
  };
  switch (msg) {
    case WM_CTLCOLORSTATIC: {
      HDC dc = reinterpret_cast<HDC>(wParam);
      SetTextColor(dc, kText);
      SetBkColor(dc, kWindowBg);
      return reinterpret_cast<LRESULT>(windowBrush_);
    }
    case WM_CTLCOLORLISTBOX: {
      HDC dc = reinterpret_cast<HDC>(wParam);
      SetTextColor(dc, kText);
      SetBkColor(dc, kControlBg);
      return reinterpret_cast<LRESULT>(controlBrush_);
    }
    case WM_DRAWITEM:
      drawOwnerButton(reinterpret_cast<const DRAWITEMSTRUCT *>(lParam));
      return TRUE;
    case WM_COMMAND:
      switch (LOWORD(wParam)) {
        case IDC_BTN_CHOOSE_OK:
          finish(static_cast<int>(SendMessageW(chooserList_, LB_GETCURSEL, 0, 0)));
          return 0;
        case IDC_BTN_CHOOSE_CANCEL:
          finish(-1);
          return 0;
        case IDC_CHOOSER_LIST:
          if (HIWORD(wParam) == LBN_DBLCLK) {
            finish(static_cast<int>(SendMessageW(chooserList_, LB_GETCURSEL, 0, 0)));
          }
          return 0;
      }
      return 0;
    case WM_CLOSE:
      finish(-1);
      return 0;
  }
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

// ---------------------------------------------------------------------------
// Entry point.
// ---------------------------------------------------------------------------
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR commandLine, int) {
  bool debug = false;
  if (commandLine && (wcsstr(commandLine, L"-debug") || wcsstr(commandLine, L"--debug"))) {
    debug = true;
  }
  ReaShootApp app;
  return app.run(instance, debug);
}
