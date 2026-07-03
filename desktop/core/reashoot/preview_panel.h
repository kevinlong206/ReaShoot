#pragma once

#include "reashoot/preview_renderer.h"

namespace reashoot {

// Portable preview-panel interface. Concrete implementations own a native
// surface (a Win32 child HWND today; SWELL/GTK later) and integrate with the
// host's docker/floating behaviour. The panel exposes an IPreviewRenderer that
// the WebRTC receiver draws into.
class IPreviewPanel {
public:
  virtual ~IPreviewPanel() = default;

  // Creates (if needed) and shows the panel.
  virtual void show() = 0;

  // Hides the panel without destroying it.
  virtual void hide() = 0;

  virtual bool isVisible() const = 0;

  // Switches between floating and docked presentation.
  virtual void setFloating(bool floating) = 0;

  virtual bool isFloating() const = 0;

  // Returns the renderer bound to this panel's surface, or nullptr if the panel
  // has not been created yet.
  virtual IPreviewRenderer *renderer() = 0;
};

} // namespace reashoot
