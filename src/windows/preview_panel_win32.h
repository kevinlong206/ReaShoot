#pragma once

#ifndef _WIN32
#error "preview_panel_win32.h is only intended for Windows builds."
#endif

#include "reashoot/preview_panel.h"
#include "reashoot/preview_renderer.h"

#include <windows.h>

#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace reashoot {

// GDI-backed preview renderer. Stores the most recent frame as a top-down BGRA
// DIB and blits it (letterboxed) on WM_PAINT. Thread-safe: frames may arrive on
// a decoder thread while WM_PAINT runs on the UI thread.
class GdiPreviewRenderer : public IPreviewRenderer {
public:
  void renderFrame(const VideoFrame &frame) override;
  void clear() override;

  // Paints the current frame (or an idle placeholder) into the device context,
  // confined to the supplied video area (the rest of the client hosts controls).
  void paint(HWND hwnd, HDC dc, const RECT &videoArea);

  void setWindow(HWND hwnd) { window_ = hwnd; }

private:
  std::mutex mutex_;
  std::vector<std::uint8_t> pixels_;
  int width_ = 0;
  int height_ = 0;
  bool hasFrame_ = false;
  HWND window_ = nullptr;
};

// Current values of the panel's editable controls, passed to callbacks so the
// host (the plugin TU) can persist settings and drive the helper.
struct PanelControls {
  std::string host;
  std::string pairingCode;
  std::string resolution;
  std::string fps;
};

// Host callbacks invoked (on the UI thread) when the user activates a control.
// Any may be empty. The host is responsible for updating the status line via
// Win32PreviewPanel::setStatus (typically routed through the plugin's report()).
struct PanelCallbacks {
  std::function<void(const PanelControls &)> onPair;
  std::function<void(const PanelControls &)> onTest;
  std::function<void(const PanelControls &)> onDiscover;
  std::function<void(const PanelControls &)> onStart;
  std::function<void(const PanelControls &)> onStop;
};

// Win32 preview panel. Owns a top-level (floating) window that hosts a macOS-
// style control strip (host, pairing code, Discover/Pair/Test, resolution/fps,
// Start/Stop, and a status line) above a video area. REAPER docker integration
// is tracked as follow-up (the interface already models floating vs docked).
// WebRTC frame rendering is not yet wired — the video area shows an idle
// placeholder until a receiver is attached to renderer().
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

  // Wires the control-strip buttons to host logic.
  void setCallbacks(PanelCallbacks callbacks) { callbacks_ = std::move(callbacks); }

  // Pre-fills the editable controls (call before show()).
  void setInitialValues(const PanelControls &values);

  // Updates the status line (safe to call repeatedly; UI thread only).
  void setStatus(const std::string &message);

  // Native window handle (or nullptr before the window is created), used by the
  // host to route REAPER keystrokes to the control-strip edit fields.
  HWND nativeHandle() const { return window_; }

private:
  static LRESULT CALLBACK windowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam);
  void ensureWindow();
  void registerClassOnce();
  void createControls();
  void layoutControls(int clientWidth);
  PanelControls readControls() const;
  void handleCommand(int controlId);

  HINSTANCE instance_ = nullptr;
  HWND window_ = nullptr;
  HWND hostEdit_ = nullptr;
  HWND codeEdit_ = nullptr;
  HWND resolutionCombo_ = nullptr;
  HWND fpsCombo_ = nullptr;
  HWND discoverButton_ = nullptr;
  HWND pairButton_ = nullptr;
  HWND testButton_ = nullptr;
  HWND startButton_ = nullptr;
  HWND stopButton_ = nullptr;
  HWND statusLabel_ = nullptr;
  bool floating_ = true;
  PanelControls initialValues_;
  PanelCallbacks callbacks_;
  GdiPreviewRenderer renderer_;
};

} // namespace reashoot
