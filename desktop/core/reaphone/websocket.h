#pragma once

#include "reaphone/http_headers.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace reaphone {

std::string webSocketAcceptKey(std::string_view clientKey);
bool isWebSocketSwitchingProtocolsResponse(const HttpHeaders &headers, std::string_view clientKey);

// Builds the client WebSocket upgrade request, mirroring the macOS helper
// ControlClient handshake (GET <path> HTTP/1.1 with Upgrade/Connection/Key/Version).
std::string buildWebSocketHandshakeRequest(std::string_view host, int port,
                                           std::string_view path, std::string_view key);

// Encodes a single masked client text frame (FIN + text opcode), mirroring the
// macOS helper: 7-bit length, or a 16-bit extended length for payloads >= 126.
// The macOS helper never emits 64-bit lengths, so payloads larger than 0xFFFF
// throw std::length_error instead of silently truncating.
std::string encodeClientTextFrame(std::string_view payload,
                                  const std::array<std::uint8_t, 4> &mask);

// Result of attempting to decode a single server text frame from a buffer.
struct WebSocketFrame {
  bool complete = false;    // true when a full frame was available in the buffer
  std::string payload;      // decoded payload, valid only when complete
  std::size_t consumed = 0; // bytes consumed from the buffer, valid only when complete
};

// Decodes one server->client text frame, mirroring the macOS helper receiveFrame:
// requires a text opcode (low nibble 0x1) and a 7-bit or 16-bit length. Returns
// complete=false when more bytes are needed. Throws std::invalid_argument for
// frames the helper rejects as unexpected (non-text opcode or 64-bit length).
WebSocketFrame decodeServerTextFrame(std::string_view bytes);

} // namespace reaphone
