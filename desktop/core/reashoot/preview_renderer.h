#pragma once

#include <cstdint>

namespace reashoot {

// A single decoded video frame handed to a renderer. Pixel data is tightly
// coupled to neither Direct3D nor any platform surface, keeping the renderer
// abstraction portable (matrix: "Do not couple signaling to Direct3D").
struct VideoFrame {
  int width = 0;
  int height = 0;
  int stride = 0;            // bytes per row
  const std::uint8_t *data = nullptr; // BGRA8888 top-down
};

// Portable renderer interface. The live-preview (WebRTC) receiver pushes frames
// here; concrete implementations draw into a native surface (Win32/GDI today,
// Direct3D/Metal/GTK later).
class IPreviewRenderer {
public:
  virtual ~IPreviewRenderer() = default;

  // Draws the frame. Implementations must copy any data they need to retain;
  // frame.data is only valid for the duration of the call.
  virtual void renderFrame(const VideoFrame &frame) = 0;

  // Clears the surface to its idle/placeholder state.
  virtual void clear() = 0;
};

// Non-drawing renderer used for tests and as a safe default before a native
// surface is attached. Records what it was asked to do.
class NullPreviewRenderer : public IPreviewRenderer {
public:
  void renderFrame(const VideoFrame &frame) override {
    ++frameCount;
    lastWidth = frame.width;
    lastHeight = frame.height;
  }

  void clear() override { ++clearCount; }

  int frameCount = 0;
  int clearCount = 0;
  int lastWidth = 0;
  int lastHeight = 0;
};

} // namespace reashoot
