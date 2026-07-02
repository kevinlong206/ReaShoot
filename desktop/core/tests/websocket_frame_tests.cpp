#include "reaphone/websocket.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::string bytes(std::initializer_list<int> values) {
  std::string result;
  result.reserve(values.size());
  for (const int value : values) {
    result.push_back(static_cast<char>(static_cast<unsigned char>(value)));
  }
  return result;
}

void buildsHandshakeRequestMatchingHelper() {
  const std::string request =
      reaphone::buildWebSocketHandshakeRequest("phone.local", 8787, "/control", "abc123");
  const std::string expected =
      "GET /control HTTP/1.1\r\n"
      "Host: phone.local:8787\r\n"
      "Upgrade: websocket\r\n"
      "Connection: Upgrade\r\n"
      "Sec-WebSocket-Key: abc123\r\n"
      "Sec-WebSocket-Version: 13\r\n"
      "\r\n";
  require(request == expected, "handshake request should mirror the macOS helper");
}

void encodesMaskedTextFramePerRfc6455Example() {
  // RFC 6455 section 5.7: a single masked frame containing "Hello".
  const std::array<std::uint8_t, 4> mask = {0x37, 0xfa, 0x21, 0x3d};
  const std::string frame = reaphone::encodeClientTextFrame("Hello", mask);
  const std::string expected =
      bytes({0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58});
  require(frame == expected, "masked text frame should match the RFC 6455 example");
}

void encodesExtendedLengthWithSixteenBitHeader() {
  const std::string payload(130, 'x');
  const std::array<std::uint8_t, 4> mask = {0, 0, 0, 0};
  const std::string frame = reaphone::encodeClientTextFrame(payload, mask);

  require(static_cast<unsigned char>(frame[0]) == 0x81, "fin+text opcode expected");
  require(static_cast<unsigned char>(frame[1]) == (0x80 | 126), "extended length marker expected");
  require(static_cast<unsigned char>(frame[2]) == 0x00, "high length byte expected");
  require(static_cast<unsigned char>(frame[3]) == 130, "low length byte expected");
  // Zero mask leaves the payload unchanged after the 4-byte mask key.
  require(frame.size() == 4 + 4 + payload.size(), "frame size should account for header, mask, payload");
  require(frame.compare(8, payload.size(), payload) == 0, "payload should follow the mask key");
}

void rejectsOversizedPayload() {
  const std::string payload(0x10000, 'y');
  const std::array<std::uint8_t, 4> mask = {0, 0, 0, 0};
  bool threw = false;
  try {
    (void)reaphone::encodeClientTextFrame(payload, mask);
  } catch (const std::length_error &) {
    threw = true;
  }
  require(threw, "payloads over 16-bit length should throw");
}

void decodesShortServerTextFrame() {
  const std::string buffer = bytes({0x81, 0x05, 'H', 'e', 'l', 'l', 'o'});
  const reaphone::WebSocketFrame frame = reaphone::decodeServerTextFrame(buffer);
  require(frame.complete, "complete short frame should decode");
  require(frame.payload == "Hello", "payload should decode");
  require(frame.consumed == buffer.size(), "consumed should cover the whole frame");
}

void decodesExtendedServerTextFrame() {
  std::string buffer = bytes({0x81, 0x7e, 0x00, 0xc8}); // 200-byte payload
  const std::string payload(200, 'z');
  buffer += payload;
  const reaphone::WebSocketFrame frame = reaphone::decodeServerTextFrame(buffer);
  require(frame.complete, "extended frame should decode");
  require(frame.payload == payload, "extended payload should decode");
  require(frame.consumed == buffer.size(), "consumed should cover header and payload");
}

void reportsIncompleteFrames() {
  require(!reaphone::decodeServerTextFrame("").complete, "empty buffer is incomplete");
  require(!reaphone::decodeServerTextFrame(bytes({0x81})).complete, "one byte is incomplete");
  require(!reaphone::decodeServerTextFrame(bytes({0x81, 0x05, 'H', 'i'})).complete,
          "short payload is incomplete");
  require(!reaphone::decodeServerTextFrame(bytes({0x81, 0x7e, 0x00})).complete,
          "missing extended length byte is incomplete");
}

void reportsConsumedForPipelinedBytes() {
  std::string buffer = bytes({0x81, 0x02, 'o', 'k'});
  buffer += "LEFTOVER";
  const reaphone::WebSocketFrame frame = reaphone::decodeServerTextFrame(buffer);
  require(frame.complete, "leading frame should decode");
  require(frame.payload == "ok", "leading payload should decode");
  require(frame.consumed == 4, "consumed should exclude pipelined trailing bytes");
  require(buffer.substr(frame.consumed) == "LEFTOVER", "caller can keep trailing bytes");
}

void rejectsNonTextAndOversizedFrames() {
  bool threw = false;
  try {
    (void)reaphone::decodeServerTextFrame(bytes({0x82, 0x00})); // binary opcode
  } catch (const std::invalid_argument &) {
    threw = true;
  }
  require(threw, "binary opcode should be rejected");

  threw = false;
  try {
    (void)reaphone::decodeServerTextFrame(bytes({0x88, 0x00})); // close opcode
  } catch (const std::invalid_argument &) {
    threw = true;
  }
  require(threw, "close opcode should be rejected");

  threw = false;
  try {
    (void)reaphone::decodeServerTextFrame(bytes({0x81, 0x7f})); // 64-bit length marker
  } catch (const std::invalid_argument &) {
    threw = true;
  }
  require(threw, "64-bit length marker should be rejected");
}

} // namespace

int main() {
  try {
    buildsHandshakeRequestMatchingHelper();
    encodesMaskedTextFramePerRfc6455Example();
    encodesExtendedLengthWithSixteenBitHeader();
    rejectsOversizedPayload();
    decodesShortServerTextFrame();
    decodesExtendedServerTextFrame();
    reportsIncompleteFrames();
    reportsConsumedForPipelinedBytes();
    rejectsNonTextAndOversizedFrames();
  } catch (const std::exception &error) {
    std::cerr << "websocket_frame_tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
