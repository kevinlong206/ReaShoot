#ifndef _WIN32
#error "webrtc_receiver_libwebrtc.cpp is only intended for Windows builds."
#endif

#include "webrtc_receiver_libwebrtc.h"

#include "reashoot/webrtc_sdp.h"

// libwebrtc (webrtc-sdk) C++ wrapper API. Confined to this translation unit.
#include "libwebrtc.h"
#include "rtc_ice_candidate.h"
#include "rtc_media_track.h"
#include "rtc_mediaconstraints.h"
#include "rtc_peerconnection.h"
#include "rtc_peerconnection_factory.h"
#include "rtc_rtp_receiver.h"
#include "rtc_rtp_transceiver.h"
#include "rtc_video_frame.h"
#include "rtc_video_renderer.h"
#include "rtc_video_track.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <future>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace reashoot {

namespace lw = libwebrtc;

namespace {

using namespace std::chrono_literals;

// libwebrtc's global threads/SSL are process-wide. Initialize lazily on first
// use and tear down explicitly on plugin unload.
std::mutex g_globalMutex;
bool g_globalInitialized = false;

void ensureGlobalInit() {
  std::lock_guard<std::mutex> lock(g_globalMutex);
  if (!g_globalInitialized) {
    lw::LibWebRTC::Initialize();
    g_globalInitialized = true;
  }
}

} // namespace

void shutdownLibWebRTC() {
  std::lock_guard<std::mutex> lock(g_globalMutex);
  if (g_globalInitialized) {
    lw::LibWebRTC::Terminate();
    g_globalInitialized = false;
  }
}

struct LibWebRTCReceiver::Impl
    : public lw::RTCPeerConnectionObserver,
      public lw::RTCVideoRenderer<lw::scoped_refptr<lw::RTCVideoFrame>> {
  IPreviewRenderer *renderer = nullptr;
  SignalHandler onSignal;
  std::atomic<bool> running{false};

  lw::scoped_refptr<lw::RTCPeerConnectionFactory> factory;
  lw::scoped_refptr<lw::RTCPeerConnection> peer;
  lw::scoped_refptr<lw::RTCVideoTrack> videoTrack;

  std::thread worker;
  std::mutex mutex;
  std::condition_variable cv;
  bool localDescriptionSet = false;
  bool localDescriptionFailed = false;
  bool remoteDescriptionSet = false;
  std::string localOfferSdp;
  std::vector<WebRTCSignal> pendingLocalCandidates;

  std::vector<std::uint8_t> frameScratch; // reused BGRA buffer (decoder thread)

  ~Impl() override { teardown(); }

  void begin() {
    if (running.exchange(true)) {
      return;
    }
    {
      std::lock_guard<std::mutex> lock(mutex);
      localDescriptionSet = false;
      localDescriptionFailed = false;
      remoteDescriptionSet = false;
      localOfferSdp.clear();
      pendingLocalCandidates.clear();
    }

    ensureGlobalInit();
    factory = lw::LibWebRTC::CreateRTCPeerConnectionFactory();
    if (!factory || !factory->Initialize()) {
      running = false;
      return;
    }

    lw::RTCConfiguration config;
    config.sdp_semantics = lw::SdpSemantics::kUnifiedPlan;
    config.offer_to_receive_audio = false;
    config.offer_to_receive_video = true;

    lw::scoped_refptr<lw::RTCMediaConstraints> constraints =
        lw::RTCMediaConstraints::Create();
    peer = factory->Create(config, constraints);
    if (!peer) {
      running = false;
      return;
    }
    peer->RegisterRTCPeerConnectionObserver(this);

    // Recv-only video transceiver so the offer requests the iPhone's stream.
    lw::scoped_refptr<lw::RTCRtpTransceiverInit> init =
        lw::RTCRtpTransceiverInit::Create(
            lw::RTCRtpTransceiverDirection::kRecvOnly,
            lw::vector<lw::string>(),
            lw::vector<lw::scoped_refptr<lw::RTCRtpEncodingParameters>>());
    peer->AddTransceiver(lw::RTCMediaType::VIDEO, init);

    Impl *self = this;
    peer->CreateOffer(
        [self](const lw::string sdp, const lw::string type) {
          self->onOfferCreated(sdp.std_string(), type.std_string());
        },
        [self](const char *error) {
          self->onLocalDescriptionResult(false);
          (void)error;
        },
        constraints);

    worker = std::thread([self] { self->negotiationWorker(); });
  }

  void onOfferCreated(std::string sdp, std::string type) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      localOfferSdp = sdp;
    }
    if (!peer) {
      onLocalDescriptionResult(false);
      return;
    }
    Impl *self = this;
    peer->SetLocalDescription(
        sdp, type, [self] { self->onLocalDescriptionResult(true); },
        [self](const char *error) {
          self->onLocalDescriptionResult(false);
          (void)error;
        });
  }

  void onLocalDescriptionResult(bool ok) {
    {
      std::lock_guard<std::mutex> lock(mutex);
      localDescriptionSet = ok;
      localDescriptionFailed = !ok;
    }
    cv.notify_all();
  }

  std::string fetchLocalDescription() {
    if (!peer) {
      return {};
    }
    auto promise = std::make_shared<std::promise<std::string>>();
    std::future<std::string> future = promise->get_future();
    peer->GetLocalDescription(
        [promise](const char *sdp, const char *type) {
          (void)type;
          promise->set_value(sdp ? std::string(sdp) : std::string());
        },
        [promise](const char *error) {
          (void)error;
          promise->set_value(std::string());
        });
    if (future.wait_for(2s) == std::future_status::ready) {
      return future.get();
    }
    return {};
  }

  void negotiationWorker() {
    {
      std::unique_lock<std::mutex> lock(mutex);
      cv.wait_for(lock, 3s,
                  [this] { return localDescriptionSet || localDescriptionFailed; });
      if (!localDescriptionSet) {
        return;
      }
    }

    // Wait briefly for ICE gathering so the offer carries local candidates
    // inline (mirrors the macOS 3s gathering budget).
    const auto deadline = std::chrono::steady_clock::now() + 3s;
    while (running && peer &&
           peer->ice_gathering_state() != lw::RTCIceGatheringStateComplete &&
           std::chrono::steady_clock::now() < deadline) {
      std::this_thread::sleep_for(50ms);
    }
    if (!running || !peer) {
      return;
    }

    std::string offer = fetchLocalDescription();
    if (offer.empty()) {
      std::lock_guard<std::mutex> lock(mutex);
      offer = localOfferSdp;
    }
    if (offer.empty()) {
      return;
    }

    SignalHandler handler;
    {
      std::lock_guard<std::mutex> lock(mutex);
      handler = onSignal;
    }
    if (handler) {
      WebRTCSignal signal;
      signal.type = WebRTCSignal::Type::Offer;
      signal.payload = offer;
      handler(signal);
    }
  }

  void applyRemoteAnswer(const std::string &sdp) {
    if (!peer) {
      return;
    }
    Impl *self = this;
    peer->SetRemoteDescription(
        sdp, "answer", [self] { self->onRemoteDescriptionSet(); },
        [self](const char *error) { (void)error; });
  }

  void onRemoteDescriptionSet() {
    std::vector<WebRTCSignal> flush;
    SignalHandler handler;
    {
      std::lock_guard<std::mutex> lock(mutex);
      remoteDescriptionSet = true;
      flush.swap(pendingLocalCandidates);
      handler = onSignal;
    }
    if (handler) {
      for (const WebRTCSignal &candidate : flush) {
        handler(candidate);
      }
    }
  }

  void addRemoteCandidate(const WebRTCSignal &signal) {
    if (peer) {
      peer->AddCandidate(signal.mid, signal.mlineIndex, signal.payload);
    }
  }

  void attachTrack(lw::scoped_refptr<lw::RTCMediaTrack> track) {
    if (!track) {
      return;
    }
    if (track->kind().std_string() != "video") {
      return;
    }
    lw::RTCVideoTrack *raw = static_cast<lw::RTCVideoTrack *>(track.get());
    if (videoTrack) {
      videoTrack->RemoveRenderer(this);
    }
    videoTrack = raw;
    videoTrack->AddRenderer(this);
  }

  void teardown() {
    running = false;
    cv.notify_all();
    if (worker.joinable()) {
      worker.join();
    }
    if (videoTrack) {
      videoTrack->RemoveRenderer(this);
      videoTrack = nullptr;
    }
    if (peer) {
      peer->DeRegisterRTCPeerConnectionObserver();
      peer->Close();
      if (factory) {
        factory->Delete(peer);
      }
      peer = nullptr;
    }
    factory = nullptr;
  }

  // --- RTCVideoRenderer ---
  void OnFrame(lw::scoped_refptr<lw::RTCVideoFrame> frame) override {
    IPreviewRenderer *target = renderer;
    if (!frame || !target) {
      return;
    }
    const int width = frame->width();
    const int height = frame->height();
    if (width <= 0 || height <= 0) {
      return;
    }
    const int stride = width * 4;
    frameScratch.resize(static_cast<std::size_t>(stride) * height);
    frame->ConvertToARGB(lw::RTCVideoFrame::Type::kBGRA, frameScratch.data(), stride,
                         width, height);
    VideoFrame out;
    out.width = width;
    out.height = height;
    out.stride = stride;
    out.data = frameScratch.data();
    target->renderFrame(out);
  }

  // --- RTCPeerConnectionObserver ---
  void OnSignalingState(lw::RTCSignalingState) override {}
  void OnPeerConnectionState(lw::RTCPeerConnectionState) override {}
  void OnIceGatheringState(lw::RTCIceGatheringState) override {}
  void OnIceConnectionState(lw::RTCIceConnectionState) override {}

  void OnIceCandidate(lw::scoped_refptr<lw::RTCIceCandidate> candidate) override {
    if (!candidate) {
      return;
    }
    WebRTCSignal signal;
    signal.type = WebRTCSignal::Type::Candidate;
    signal.payload = candidate->candidate().std_string();
    signal.mid = candidate->sdp_mid().std_string();
    signal.mlineIndex = candidate->sdp_mline_index();

    SignalHandler handler;
    bool emitNow = false;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (remoteDescriptionSet) {
        emitNow = true;
        handler = onSignal;
      } else {
        pendingLocalCandidates.push_back(signal);
      }
    }
    if (emitNow && handler) {
      handler(signal);
    }
  }

  void OnAddStream(lw::scoped_refptr<lw::RTCMediaStream>) override {}
  void OnRemoveStream(lw::scoped_refptr<lw::RTCMediaStream>) override {}
  void OnDataChannel(lw::scoped_refptr<lw::RTCDataChannel>) override {}
  void OnRenegotiationNeeded() override {}

  void OnTrack(lw::scoped_refptr<lw::RTCRtpTransceiver> transceiver) override {
    if (!transceiver) {
      return;
    }
    lw::scoped_refptr<lw::RTCRtpReceiver> receiver = transceiver->receiver();
    if (receiver) {
      attachTrack(receiver->track());
    }
  }

  void OnAddTrack(lw::vector<lw::scoped_refptr<lw::RTCMediaStream>> streams,
                  lw::scoped_refptr<lw::RTCRtpReceiver> receiver) override {
    (void)streams;
    if (receiver) {
      attachTrack(receiver->track());
    }
  }

  void OnRemoveTrack(lw::scoped_refptr<lw::RTCRtpReceiver>) override {}
};

LibWebRTCReceiver::LibWebRTCReceiver() : impl_(std::make_unique<Impl>()) {}

LibWebRTCReceiver::~LibWebRTCReceiver() = default;

void LibWebRTCReceiver::setRenderer(IPreviewRenderer *renderer) {
  impl_->renderer = renderer;
}

void LibWebRTCReceiver::start(SignalHandler onSignal) {
  impl_->onSignal = std::move(onSignal);
  impl_->begin();
}

void LibWebRTCReceiver::handleRemoteSignal(const WebRTCSignal &signal) {
  switch (signal.type) {
  case WebRTCSignal::Type::Answer:
    impl_->applyRemoteAnswer(signal.payload);
    break;
  case WebRTCSignal::Type::Candidate:
    impl_->addRemoteCandidate(signal);
    break;
  case WebRTCSignal::Type::Offer:
    break; // ReaShoot is the offerer; a remote offer is unexpected.
  }
}

void LibWebRTCReceiver::stop() {
  impl_->teardown();
  if (impl_->renderer) {
    impl_->renderer->clear();
  }
}

bool LibWebRTCReceiver::isRunning() const { return impl_->running.load(); }

} // namespace reashoot
