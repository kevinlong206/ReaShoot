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

void GdiPreviewRenderer::paint(HWND hwnd, HDC dc) {
  RECT client{};
  GetClientRect(hwnd, &client);
  const int clientWidth = client.right - client.left;
  const int clientHeight = client.bottom - client.top;

  HBRUSH background = CreateSolidBrush(kBackgroundColor);
  FillRect(dc, &client, background);
  DeleteObject(background);

  std::lock_guard<std::mutex> lock(mutex_);
  if (!hasFrame_ || pixels_.empty() || width_ <= 0 || height_ <= 0) {
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, kPlaceholderColor);
    DrawTextW(dc, kPlaceholder, -1, &client, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    return;
  }

  // Letterbox the frame while preserving aspect ratio.
  const double scale =
      (std::min)(static_cast<double>(clientWidth) / width_, static_cast<double>(clientHeight) / height_);
  const int drawWidth = (std::max)(1, static_cast<int>(width_ * scale));
  const int drawHeight = (std::max)(1, static_cast<int>(height_ * scale));
  const int offsetX = (clientWidth - drawWidth) / 2;
  const int offsetY = (clientHeight - drawHeight) / 2;

  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = width_;
  info.bmiHeader.biHeight = -height_; // top-down
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  SetStretchBltMode(dc, HALFTONE);
  StretchDIBits(dc, offsetX, offsetY, drawWidth, drawHeight, 0, 0, width_, height_, pixels_.data(), &info,
                DIB_RGB_COLORS, SRCCOPY);
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
                            640, 360, nullptr, nullptr, instance_, this);
  if (window_) {
    renderer_.setWindow(window_);
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
      panel->renderer_.paint(hwnd, dc);
    }
    EndPaint(hwnd, &ps);
    return 0;
  }
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
