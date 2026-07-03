#pragma once

#include "reashoot/preview_renderer.h"

#include <functional>
#include <string>

namespace reashoot {

// A WebRTC signaling message exchanged with the iPhone over the authenticated
// control WebSocket. WebRTC is the ONLY supported preview transport; MJPEG or
// other fallbacks are intentionally not modelled here.
struct WebRTCSignal {
  enum class Type { Offer, Answer, Candidate };

  Type type = Type::Offer;
  std::string payload;  // SDP for Offer/Answer, candidate string for Candidate
  std::string mid;      // media stream identification (candidates)
  int mlineIndex = 0;   // sdpMLineIndex (candidates)
};

// Portable desktop WebRTC receiver abstraction. It negotiates a peer connection,
// decodes the incoming iPhone video track, and pushes frames to an
// IPreviewRenderer. Signaling payloads are relayed verbatim through the existing
// control WebSocket by the caller, so this stays free of any transport or
// platform (Direct3D/Metal) coupling.
class IWebRTCReceiver {
public:
  using SignalHandler = std::function<void(const WebRTCSignal &)>;

  virtual ~IWebRTCReceiver() = default;

  // Sets the renderer that decoded frames are delivered to. May be nullptr.
  virtual void setRenderer(IPreviewRenderer *renderer) = 0;

  // Begins negotiation. Local signals (offer, ICE candidates) are delivered to
  // onSignal for the caller to relay to the iPhone.
  virtual void start(SignalHandler onSignal) = 0;

  // Feeds a remote signal (answer, ICE candidate) received from the iPhone.
  virtual void handleRemoteSignal(const WebRTCSignal &signal) = 0;

  // Tears down the peer connection and stops delivering frames.
  virtual void stop() = 0;

  virtual bool isRunning() const = 0;
};

// Placeholder receiver wiring up the control flow without a real peer
// connection. Full libwebrtc integration (decode + native render) is out of
// scope for the initial Windows port and tracked as follow-up work; this stub
// keeps the plugin/action wiring testable in the meantime.
//
// Behaviour: start() emits a synthetic offer signal and marks itself running;
// handleRemoteSignal() records the last remote signal; stop() clears state and
// asks the renderer to clear. It never produces real video frames.
class StubWebRTCReceiver : public IWebRTCReceiver {
public:
  void setRenderer(IPreviewRenderer *renderer) override { renderer_ = renderer; }

  void start(SignalHandler onSignal) override {
    running_ = true;
    signalHandler_ = std::move(onSignal);
    if (signalHandler_) {
      WebRTCSignal offer;
      offer.type = WebRTCSignal::Type::Offer;
      offer.payload = "stub-offer";
      signalHandler_(offer);
    }
  }

  void handleRemoteSignal(const WebRTCSignal &signal) override { lastRemoteSignal_ = signal; }

  void stop() override {
    running_ = false;
    signalHandler_ = nullptr;
    if (renderer_) {
      renderer_->clear();
    }
  }

  bool isRunning() const override { return running_; }

  IPreviewRenderer *renderer() const { return renderer_; }
  const WebRTCSignal &lastRemoteSignal() const { return lastRemoteSignal_; }

private:
  IPreviewRenderer *renderer_ = nullptr;
  SignalHandler signalHandler_;
  WebRTCSignal lastRemoteSignal_;
  bool running_ = false;
};

} // namespace reashoot
