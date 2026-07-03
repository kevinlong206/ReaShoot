#pragma once

#ifndef _WIN32
#error "webrtc_receiver_libwebrtc.h is only intended for Windows builds."
#endif

#include "reashoot/webrtc_receiver.h"

#include <memory>

namespace reashoot {

// Real WebRTC preview receiver backed by the webrtc-sdk/libwebrtc prebuilt.
//
// REAPER is the recv-only offerer: start() negotiates a peer connection, creates
// an offer (waiting briefly for ICE gathering), and emits it via the
// SignalHandler for the host to relay to the iPhone over the control WebSocket.
// The host feeds the iPhone's answer and ICE candidates back through
// handleRemoteSignal(). Decoded video frames are converted to BGRA and pushed to
// the attached IPreviewRenderer.
//
// The libwebrtc headers are intentionally kept out of this header (pimpl) so the
// plugin translation unit can construct the receiver without pulling in the
// wrapper's declarations.
class LibWebRTCReceiver : public IWebRTCReceiver {
public:
  LibWebRTCReceiver();
  ~LibWebRTCReceiver() override;

  LibWebRTCReceiver(const LibWebRTCReceiver &) = delete;
  LibWebRTCReceiver &operator=(const LibWebRTCReceiver &) = delete;

  void setRenderer(IPreviewRenderer *renderer) override;
  void start(SignalHandler onSignal) override;
  void handleRemoteSignal(const WebRTCSignal &signal) override;
  void stop() override;
  bool isRunning() const override;

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// Releases libwebrtc's global threads/SSL. Safe to call even if the receiver was
// never started. Intended for plugin unload.
void shutdownLibWebRTC();

} // namespace reashoot
