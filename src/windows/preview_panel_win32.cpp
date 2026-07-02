#ifndef _WIN32
#error "preview_panel_win32.cpp is only intended for Windows builds."
#endif

#include "preview_panel_win32.h"

#include <algorithm>

namespace reaphone {

namespace {

constexpr wchar_t kWindowClassName[] = L"ReaPhoneVideoPreviewPanel";
constexpr wchar_t kWindowTitle[] = L"ReaPhoneVideo Preview";
constexpr wchar_t kPlaceholder[] = L"Waiting for WebRTC preview\u2026";
constexpr COLORREF kBackgroundColor = RGB(24, 24, 28);
constexpr COLORREF kPlaceholderColor = RGB(160, 160, 168);

bool g_classRegistered = false;

// Control identifiers for the strip's children.
enum ControlId : int {
  kIdHostEdit = 1001,
  kIdCodeEdit,
  kIdResolutionCombo,
  kIdFpsCombo,
  kIdDiscoverButton,
  kIdPairButton,
  kIdTestButton,
  kIdStartButton,
  kIdStopButton,
  kIdStatusLabel,
  kIdHostLabel,
  kIdCodeLabel,
};

// Control-strip layout metrics (device pixels at 96 DPI).
constexpr int kMargin = 8;
constexpr int kRowHeight = 24;
constexpr int kRowGap = 6;
constexpr int kLabelWidth = 84;
constexpr int kButtonWidth = 82;
constexpr int kComboWidth = 96;
constexpr int kStripHeight = kMargin + 4 * kRowHeight + 3 * kRowGap + kMargin;

std::wstring widenUtf8(const std::string &value) {
  if (value.empty()) {
    return {};
  }
  const int needed =
      MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(static_cast<std::size_t>(needed), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(), needed);
  return result;
}

std::string narrowUtf8(const std::wstring &value) {
  if (value.empty()) {
    return {};
  }
  const int needed = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
                                         nullptr, 0, nullptr, nullptr);
  std::string result(static_cast<std::size_t>(needed), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(), needed,
                      nullptr, nullptr);
  return result;
}

std::string controlText(HWND control) {
  if (control == nullptr) {
    return {};
  }
  const int length = GetWindowTextLengthW(control);
  if (length <= 0) {
    return {};
  }
  std::wstring buffer(static_cast<std::size_t>(length) + 1, L'\0');
  const int copied = GetWindowTextW(control, buffer.data(), length + 1);
  buffer.resize(static_cast<std::size_t>((std::max)(0, copied)));
  return narrowUtf8(buffer);
}

void applyGuiFont(HWND control) {
  if (control) {
    SendMessageW(control, WM_SETFONT,
                 reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
  }
}

} // namespace

void GdiPreviewRenderer::renderFrame(const VideoFrame &frame) {
  if (frame.data == nullptr || frame.width <= 0 || frame.height <= 0) {
    return;
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    width_ = frame.width;
    height_ = frame.height;
    pixels_.resize(static_cast<std::size_t>(frame.width) * static_cast<std::size_t>(frame.height) * 4);

    const int rowBytes = frame.width * 4;
    for (int y = 0; y < frame.height; ++y) {
      const std::uint8_t *src = frame.data + static_cast<std::size_t>(y) * frame.stride;
      std::uint8_t *dst = pixels_.data() + static_cast<std::size_t>(y) * rowBytes;
      std::copy(src, src + rowBytes, dst);
    }
    hasFrame_ = true;
  }

  if (window_) {
    InvalidateRect(window_, nullptr, FALSE);
  }
}

void GdiPreviewRenderer::clear() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    hasFrame_ = false;
    pixels_.clear();
    width_ = 0;
    height_ = 0;
  }
  if (window_) {
    InvalidateRect(window_, nullptr, FALSE);
  }
}

void GdiPreviewRenderer::paint(HWND hwnd, HDC dc, const RECT &videoArea) {
  (void)hwnd;
  const int areaWidth = videoArea.right - videoArea.left;
  const int areaHeight = videoArea.bottom - videoArea.top;

  RECT area = videoArea;
  HBRUSH background = CreateSolidBrush(kBackgroundColor);
  FillRect(dc, &area, background);
  DeleteObject(background);

  std::lock_guard<std::mutex> lock(mutex_);
  if (!hasFrame_ || pixels_.empty() || width_ <= 0 || height_ <= 0 || areaWidth <= 0 ||
      areaHeight <= 0) {
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, kPlaceholderColor);
    DrawTextW(dc, kPlaceholder, -1, &area, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    return;
  }

  // Letterbox the frame within the video area while preserving aspect ratio.
  const double scale =
      (std::min)(static_cast<double>(areaWidth) / width_, static_cast<double>(areaHeight) / height_);
  const int drawWidth = (std::max)(1, static_cast<int>(width_ * scale));
  const int drawHeight = (std::max)(1, static_cast<int>(height_ * scale));
  const int offsetX = videoArea.left + (areaWidth - drawWidth) / 2;
  const int offsetY = videoArea.top + (areaHeight - drawHeight) / 2;

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width_;
  info.bmiHeader.biHeight = -height_; // top-down
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  SetStretchBltMode(dc, HALFTONE);
  StretchDIBits(dc, offsetX, offsetY, drawWidth, drawHeight, 0, 0, width_, height_, pixels_.data(),
                &info, DIB_RGB_COLORS, SRCCOPY);
}

Win32PreviewPanel::Win32PreviewPanel(HINSTANCE instance) : instance_(instance) {}

Win32PreviewPanel::~Win32PreviewPanel() {
  if (window_) {
    DestroyWindow(window_);
    window_ = nullptr;
  }
}

void Win32PreviewPanel::registerClassOnce() {
  if (g_classRegistered) {
    return;
  }
  WNDCLASSEXW wc{};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = &Win32PreviewPanel::windowProc;
  wc.hInstance = instance_;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
  wc.lpszClassName = kWindowClassName;
  if (RegisterClassExW(&wc) != 0) {
    g_classRegistered = true;
  }
}

void Win32PreviewPanel::ensureWindow() {
  if (window_) {
    return;
  }
  registerClassOnce();

  window_ = CreateWindowExW(0, kWindowClassName, kWindowTitle, WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
                            760, 560, nullptr, nullptr, instance_, this);
  if (window_) {
    renderer_.setWindow(window_);
    createControls();
    RECT client{};
    GetClientRect(window_, &client);
    layoutControls(client.right - client.left);
  }
}

namespace {

HWND makeLabel(HWND parent, HINSTANCE instance, const wchar_t *text, int id) {
  HWND label = CreateWindowExW(0, L"STATIC", text, WS_CHILD | WS_VISIBLE | SS_LEFT, 0, 0, 0, 0, parent,
                               reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), instance, nullptr);
  applyGuiFont(label);
  return label;
}

HWND makeButton(HWND parent, HINSTANCE instance, const wchar_t *text, int id) {
  HWND button = CreateWindowExW(0, L"BUTTON", text, WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 0, 0, 0, 0,
                                parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)), instance,
                                nullptr);
  applyGuiFont(button);
  return button;
}

HWND makeEdit(HWND parent, HINSTANCE instance, int id) {
  HWND edit = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL, 0,
                              0, 0, 0, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                              instance, nullptr);
  applyGuiFont(edit);
  return edit;
}

HWND makeCombo(HWND parent, HINSTANCE instance, int id, const wchar_t *const *items, int count) {
  HWND combo = CreateWindowExW(0, L"COMBOBOX", L"", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST | WS_VSCROLL,
                               0, 0, 0, 0, parent, reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                               instance, nullptr);
  applyGuiFont(combo);
  for (int i = 0; i < count; ++i) {
    SendMessageW(combo, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(items[i]));
  }
  return combo;
}

} // namespace

void Win32PreviewPanel::createControls() {
  if (hostEdit_ != nullptr) {
    return;
  }

  makeLabel(window_, instance_, L"iPhone host:", kIdHostLabel);
  hostEdit_ = makeEdit(window_, instance_, kIdHostEdit);

  makeLabel(window_, instance_, L"Pairing code:", kIdCodeLabel);
  codeEdit_ = makeEdit(window_, instance_, kIdCodeEdit);
  discoverButton_ = makeButton(window_, instance_, L"Discover", kIdDiscoverButton);
  pairButton_ = makeButton(window_, instance_, L"Pair", kIdPairButton);
  testButton_ = makeButton(window_, instance_, L"Test", kIdTestButton);

  static const wchar_t *const kResolutions[] = {L"4K", L"1080p", L"720p"};
  static const wchar_t *const kFps[] = {L"24", L"30", L"60"};
  resolutionCombo_ = makeCombo(window_, instance_, kIdResolutionCombo, kResolutions, 3);
  fpsCombo_ = makeCombo(window_, instance_, kIdFpsCombo, kFps, 3);
  startButton_ = makeButton(window_, instance_, L"Start", kIdStartButton);
  stopButton_ = makeButton(window_, instance_, L"Stop", kIdStopButton);

  statusLabel_ = makeLabel(window_, instance_, L"Ready.", kIdStatusLabel);

  // Apply any values captured before the window existed.
  setInitialValues(initialValues_);
}

void Win32PreviewPanel::layoutControls(int clientWidth) {
  if (hostEdit_ == nullptr) {
    return;
  }

  const int labelY1 = kMargin + 3;
  const int rowY1 = kMargin;
  const int rowY2 = rowY1 + kRowHeight + kRowGap;
  const int rowY3 = rowY2 + kRowHeight + kRowGap;
  const int rowY4 = rowY3 + kRowHeight + kRowGap;

  const int fieldX = kMargin + kLabelWidth + kRowGap;
  const int right = clientWidth - kMargin;

  auto place = [](HWND control, int x, int y, int w, int h) {
    if (control) {
      MoveWindow(control, x, y, w, h, TRUE);
    }
  };

  // Row 1: host label + host edit (stretches to the right edge).
  place(GetDlgItem(window_, kIdHostLabel), kMargin, labelY1, kLabelWidth, kRowHeight);
  place(hostEdit_, fieldX, rowY1, (std::max)(80, right - fieldX), kRowHeight);

  // Pairing row: code edit + Discover/Pair/Test buttons on the right.
  place(GetDlgItem(window_, kIdCodeLabel), kMargin, rowY2 + 3, kLabelWidth, kRowHeight);
  const int buttonsWidth = 3 * kButtonWidth + 2 * kRowGap;
  const int codeWidth = (std::max)(80, right - buttonsWidth - kRowGap - fieldX);
  place(codeEdit_, fieldX, rowY2, codeWidth, kRowHeight);
  int bx = fieldX + codeWidth + kRowGap;
  place(discoverButton_, bx, rowY2, kButtonWidth, kRowHeight);
  bx += kButtonWidth + kRowGap;
  place(pairButton_, bx, rowY2, kButtonWidth, kRowHeight);
  bx += kButtonWidth + kRowGap;
  place(testButton_, bx, rowY2, kButtonWidth, kRowHeight);

  // Profile row: resolution + fps combos, Start/Stop on the right.
  place(resolutionCombo_, kMargin, rowY3, kComboWidth, kRowHeight * 6);
  place(fpsCombo_, kMargin + kComboWidth + kRowGap, rowY3, kComboWidth, kRowHeight * 6);
  const int startX = right - 2 * kButtonWidth - kRowGap;
  place(startButton_, startX, rowY3, kButtonWidth, kRowHeight);
  place(stopButton_, startX + kButtonWidth + kRowGap, rowY3, kButtonWidth, kRowHeight);

  // Status row spans the full width.
  place(statusLabel_, kMargin, rowY4 + 3, right - kMargin, kRowHeight);
}

PanelControls Win32PreviewPanel::readControls() const {
  PanelControls controls;
  controls.host = controlText(hostEdit_);
  controls.pairingCode = controlText(codeEdit_);
  controls.resolution = controlText(resolutionCombo_);
  controls.fps = controlText(fpsCombo_);
  return controls;
}

void Win32PreviewPanel::handleCommand(int controlId) {
  const PanelControls controls = readControls();
  switch (controlId) {
  case kIdDiscoverButton:
    if (callbacks_.onDiscover) {
      callbacks_.onDiscover(controls);
    }
    break;
  case kIdPairButton:
    if (callbacks_.onPair) {
      callbacks_.onPair(controls);
    }
    break;
  case kIdTestButton:
    if (callbacks_.onTest) {
      callbacks_.onTest(controls);
    }
    break;
  case kIdStartButton:
    if (callbacks_.onStart) {
      callbacks_.onStart(controls);
    }
    break;
  case kIdStopButton:
    if (callbacks_.onStop) {
      callbacks_.onStop(controls);
    }
    break;
  default:
    break;
  }
}

void Win32PreviewPanel::setInitialValues(const PanelControls &values) {
  initialValues_ = values;
  if (hostEdit_) {
    SetWindowTextW(hostEdit_, widenUtf8(values.host).c_str());
  }
  if (codeEdit_) {
    SetWindowTextW(codeEdit_, widenUtf8(values.pairingCode).c_str());
  }
  if (resolutionCombo_) {
    const std::wstring res = values.resolution.empty() ? L"1080p" : widenUtf8(values.resolution);
    SendMessageW(resolutionCombo_, CB_SELECTSTRING, static_cast<WPARAM>(-1),
                 reinterpret_cast<LPARAM>(res.c_str()));
  }
  if (fpsCombo_) {
    const std::wstring fps = values.fps.empty() ? L"30" : widenUtf8(values.fps);
    SendMessageW(fpsCombo_, CB_SELECTSTRING, static_cast<WPARAM>(-1),
                 reinterpret_cast<LPARAM>(fps.c_str()));
  }
}

void Win32PreviewPanel::setStatus(const std::string &message) {
  if (statusLabel_) {
    SetWindowTextW(statusLabel_, widenUtf8(message).c_str());
  }
}

void Win32PreviewPanel::show() {
  ensureWindow();
  if (window_) {
    ShowWindow(window_, SW_SHOW);
    UpdateWindow(window_);
  }
}

void Win32PreviewPanel::hide() {
  if (window_) {
    ShowWindow(window_, SW_HIDE);
  }
}

bool Win32PreviewPanel::isVisible() const {
  return window_ != nullptr && IsWindowVisible(window_) != FALSE;
}

void Win32PreviewPanel::setFloating(bool floating) {
  // The panel is presented as a floating top-level window today. REAPER docker
  // integration (DockWindowAddEx / DockWindowActivate) is tracked as follow-up;
  // the flag is preserved so callers and future docking share one state model.
  floating_ = floating;
}

bool Win32PreviewPanel::isFloating() const { return floating_; }

IPreviewRenderer *Win32PreviewPanel::renderer() { return window_ ? &renderer_ : nullptr; }

LRESULT CALLBACK Win32PreviewPanel::windowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
  if (message == WM_CREATE) {
    auto *create = reinterpret_cast<CREATESTRUCTW *>(lParam);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    return 0;
  }

  auto *panel = reinterpret_cast<Win32PreviewPanel *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

  switch (message) {
  case WM_PAINT: {
    PAINTSTRUCT ps{};
    HDC dc = BeginPaint(hwnd, &ps);
    if (panel) {
      RECT client{};
      GetClientRect(hwnd, &client);
      // Fill the control strip with the system face colour, then paint the
      // video area (below the strip) via the renderer.
      RECT strip = client;
      strip.bottom = (std::min)(client.bottom, static_cast<LONG>(kStripHeight));
      FillRect(dc, &strip, GetSysColorBrush(COLOR_BTNFACE));
      RECT videoArea = client;
      videoArea.top = (std::min)(client.bottom, static_cast<LONG>(kStripHeight));
      panel->renderer_.paint(hwnd, dc, videoArea);
    }
    EndPaint(hwnd, &ps);
    return 0;
  }
  case WM_COMMAND:
    if (panel && HIWORD(wParam) == BN_CLICKED) {
      panel->handleCommand(LOWORD(wParam));
      return 0;
    }
    break;
  case WM_SIZE:
    if (panel) {
      panel->layoutControls(LOWORD(lParam));
      InvalidateRect(hwnd, nullptr, FALSE);
    }
    return 0;
  case WM_ERASEBKGND:
    return 1; // handled in WM_PAINT to avoid flicker
  case WM_CLOSE:
    ShowWindow(hwnd, SW_HIDE); // hide instead of destroy so state is retained
    return 0;
  case WM_DESTROY:
    if (panel) {
      panel->window_ = nullptr;
      panel->renderer_.setWindow(nullptr);
    }
    return 0;
  default:
    break;
  }
  return DefWindowProcW(hwnd, message, wParam, lParam);
}

} // namespace reaphone
