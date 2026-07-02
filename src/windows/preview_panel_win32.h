#pragma once

#ifndef _WIN32
#error "preview_panel_win32.h is only intended for Windows builds."
#endif

#include "reaphone/preview_panel.h"
#include "reaphone/preview_renderer.h"

#include <windows.h>

#include <cstdint>
#include <mutex>
#include <vector>

namespace reaphone {

// GDI-backed preview renderer. Stores the most recent frame as a top-down BGRA
// DIB and blits it (letterboxed) on WM_PAINT. Thread-safe: frames may arrive on
// a decoder thread while WM_PAINT runs on the UI thread.
class GdiPreviewRenderer : public IPreviewRenderer {
public:
  void renderFrame(const VideoFrame &frame) override;
  void clear() override;

  // Paints the current frame (or an idle placeholder) into the device context.
  void paint(HWND hwnd, HDC dc);

  void setWindow(HWND hwnd) { window_ = hwnd; }

private:
  std::mutex mutex_;
  std::vector<std::uint8_t> pixels_;
  int width_ = 0;
  int height_ = 0;
  bool hasFrame_ = false;
  HWND window_ = nullptr;
};

// Win32 preview panel skeleton. Owns a top-level (floating) window today; REAPER
// docker integration is tracked as follow-up (the interface already models
// floating vs docked). WebRTC frame rendering is not yet wired — the panel shows
// an idle placeholder until a receiver is attached to renderer().
class Win32PreviewPanel : public IPreviewPanel {
public:
  explicit Win32PreviewPanel(HINSTANCE instance);
  ~Win32PreviewPanel() override;

  void show() override;
  void hide() override;
  bool isVisible() const override;
  void setFloating(bool floating) override;
  bool isFloating() const override;
  IPreviewRenderer *renderer() override;

private:
  static LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam);
  void ensureWindow();
  void registerClassOnce();

  HINSTANCE instance_ = nullptr;
  HWND window_ = nullptr;
  bool floating_ = true;
  GdiPreviewRenderer renderer_;
};

} // namespace reaphone
