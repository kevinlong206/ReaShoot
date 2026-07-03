#include "reashoot/preview_renderer.h"
#include "reashoot/webrtc_receiver.h"

#include <cassert>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

void testNullRendererCounts() {
  reashoot::NullPreviewRenderer renderer;

  std::vector<std::uint8_t> pixels(4 * 2 * 3, 0);
  reashoot::VideoFrame frame;
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
  reashoot::StubWebRTCReceiver receiver;
  reashoot::NullPreviewRenderer renderer;
  receiver.setRenderer(&renderer);

  assert(!receiver.isRunning());

  std::vector<reashoot::WebRTCSignal> emitted;
  receiver.start([&](const reashoot::WebRTCSignal &signal) { emitted.push_back(signal); });

  assert(receiver.isRunning());
  assert(emitted.size() == 1);
  assert(emitted.front().type == reashoot::WebRTCSignal::Type::Offer);
  assert(emitted.front().payload == "stub-offer");
  assert(receiver.renderer() == &renderer);
}

void testStubReceiverRecordsRemoteSignal() {
  reashoot::StubWebRTCReceiver receiver;
  receiver.start(nullptr);

  reashoot::WebRTCSignal answer;
  answer.type = reashoot::WebRTCSignal::Type::Answer;
  answer.payload = "remote-answer";
  receiver.handleRemoteSignal(answer);

  assert(receiver.lastRemoteSignal().type == reashoot::WebRTCSignal::Type::Answer);
  assert(receiver.lastRemoteSignal().payload == "remote-answer");
}

void testStubReceiverStopClearsRenderer() {
  reashoot::StubWebRTCReceiver receiver;
  reashoot::NullPreviewRenderer renderer;
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
