#include "reaphone/preview_renderer.h"
#include "reaphone/webrtc_receiver.h"

#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

void testNullRendererCounts() {
  reaphone::NullPreviewRenderer renderer;

  std::vector<std::uint8_t> pixels(4 * 2 * 3, 0);
  reaphone::VideoFrame frame;
  frame.width = 4;
  frame.height = 3;
  frame.stride = 16;
  frame.data = pixels.data();

  renderer.renderFrame(frame);
  renderer.renderFrame(frame);
  renderer.clear();

  assert(renderer.frameCount == 2);
  assert(renderer.clearCount == 1);
  assert(renderer.lastWidth == 4);
  assert(renderer.lastHeight == 3);
}

void testStubReceiverEmitsOfferOnStart() {
  reaphone::StubWebRTCReceiver receiver;
  reaphone::NullPreviewRenderer renderer;
  receiver.setRenderer(&renderer);

  assert(!receiver.isRunning());

  std::vector<reaphone::WebRTCSignal> emitted;
  receiver.start([&](const reaphone::WebRTCSignal &signal) { emitted.push_back(signal); });

  assert(receiver.isRunning());
  assert(emitted.size() == 1);
  assert(emitted.front().type == reaphone::WebRTCSignal::Type::Offer);
  assert(emitted.front().payload == "stub-offer");
  assert(receiver.renderer() == &renderer);
}

void testStubReceiverRecordsRemoteSignal() {
  reaphone::StubWebRTCReceiver receiver;
  receiver.start(nullptr);

  reaphone::WebRTCSignal answer;
  answer.type = reaphone::WebRTCSignal::Type::Answer;
  answer.payload = "remote-answer";
  receiver.handleRemoteSignal(answer);

  assert(receiver.lastRemoteSignal().type == reaphone::WebRTCSignal::Type::Answer);
  assert(receiver.lastRemoteSignal().payload == "remote-answer");
}

void testStubReceiverStopClearsRenderer() {
  reaphone::StubWebRTCReceiver receiver;
  reaphone::NullPreviewRenderer renderer;
  receiver.setRenderer(&renderer);

  receiver.start(nullptr);
  receiver.stop();

  assert(!receiver.isRunning());
  assert(renderer.clearCount == 1);
}

} // namespace

int main() {
  testNullRendererCounts();
  testStubReceiverEmitsOfferOnStart();
  testStubReceiverRecordsRemoteSignal();
  testStubReceiverStopClearsRenderer();
  std::cout << "preview_tests passed\n";
  return 0;
}
