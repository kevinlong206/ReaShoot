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
  // Invoked when the user toggles dock/float via the panel's Dock button, with
  // the new floating state, so the host can persist the preference.
  std::function<void(bool /*floating*/)> onFloatingChanged;
  // Invoked when the user toggles always-on-top via the panel's pin control.
  std::function<void(bool /*alwaysOnTop*/)> onAlwaysOnTopChanged;
  // Invoked when the floating window is closed by the user (stop the preview).
  std::function<void()> onClosed;
};

// REAPER docker integration hooks. Injected by the plugin TU (which owns the
// REAPER SDK) so this file stays SDK-free. dockAdd docks the supplied child
// window into REAPER's docker and activates it; dockRemove undocks it.
struct DockHooks {
  std::function<void(HWND)> dockAdd;
  std::function<void(HWND)> dockRemove;
};

// Win32 preview panel. Mirrors the macOS docker model: a reparentable WS_CHILD
// "content" window hosts the control strip (host, pairing PIN, Discover/Pair/
// Test, resolution/fps, Start/Stop, Dock, always-on-top pin, and a status line)
// above the video area. That content window is either docked into REAPER's
// docker (default) or reparented into an owned top-level float host window that
// supports always-on-top. WebRTC is the only preview transport.
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

  // Provides the REAPER docker hooks (docking requires the REAPER SDK, which
  // lives in the plugin TU). Call before show().
  void setDockHooks(DockHooks hooks) { dockHooks_ = std::move(hooks); }

  // Pre-fills the editable controls (call before show()).
  void setInitialValues(const PanelControls &values);

  // Sets whether the floating window stays above other windows. Only takes
  // visible effect while floating; the preference is retained across dock/float.
  void setAlwaysOnTop(bool alwaysOnTop);
  bool isAlwaysOnTop() const { return alwaysOnTop_; }

  // Updates the status line (safe to call repeatedly; UI thread only).
  void setStatus(const std::string &message);

  // Native window handle for the content window (or nullptr before creation),
  // used by the host to route REAPER keystrokes to the control-strip edits and
  // as the child handle handed to the REAPER docker.
  HWND nativeHandle() const { return content_; }

private:
  static LRESULT CALLBACK contentProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam);
  static LRESULT CALLBACK floatProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam);
  void ensureWindows();
  void registerClassesOnce();
  void createControls();
  void layoutControls(int clientWidth);
  PanelControls readControls() const;
  void handleCommand(int controlId);
  void applyPresentation();   // Shows content per current mode (docked/floating).
  void showFloating();
  void hideFloating();
  void updateDockButtonText();
  void applyTopmost();

  HINSTANCE instance_ = nullptr;
  HWND floatWindow_ = nullptr; // Top-level host used while floating.
  HWND content_ = nullptr;     // WS_CHILD; hosts controls + video, gets docked.
  HWND hostEdit_ = nullptr;
  HWND codeEdit_ = nullptr;
  HWND resolutionCombo_ = nullptr;
  HWND fpsCombo_ = nullptr;
  HWND discoverButton_ = nullptr;
  HWND pairButton_ = nullptr;
  HWND testButton_ = nullptr;
  HWND startButton_ = nullptr;
  HWND stopButton_ = nullptr;
  HWND dockButton_ = nullptr;
  HWND pinCheck_ = nullptr;
  HWND statusLabel_ = nullptr;
  bool floating_ = false;      // Default: docked into REAPER's docker.
  bool alwaysOnTop_ = false;
  bool shown_ = false;
  PanelControls initialValues_;
  PanelCallbacks callbacks_;
  DockHooks dockHooks_;
  GdiPreviewRenderer renderer_;
};

} // namespace reashoot
