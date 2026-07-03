#include "reashoot/windows/control_client.h"

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

#include "reashoot/http_headers.h"
#include "reashoot/websocket.h"

#include <array>
#include <cstdint>
#include <random>
#include <stdexcept>
#include <string>
#include <string_view>

namespace reashoot {

namespace {

// RAII wrapper for WSAStartup/WSACleanup. Winsock reference counts these, so a
// per-call session nests safely with any Winsock use elsewhere in the process.
class WinsockSession {
public:
  WinsockSession() {
    WSADATA data{};
    const int status = WSAStartup(MAKEWORD(2, 2), &data);
    if (status != 0) {
      throw std::runtime_error("WSAStartup failed: " + std::to_string(status));
    }
  }
  ~WinsockSession() { WSACleanup(); }

  WinsockSession(const WinsockSession &) = delete;
  WinsockSession &operator=(const WinsockSession &) = delete;
};

class SocketHandle {
public:
  SocketHandle() = default;
  explicit SocketHandle(SOCKET socket) : socket_(socket) {}
  ~SocketHandle() { reset(); }

  SocketHandle(const SocketHandle &) = delete;
  SocketHandle &operator=(const SocketHandle &) = delete;

  SOCKET get() const { return socket_; }
  bool valid() const { return socket_ != INVALID_SOCKET; }

  void assign(SOCKET socket) {
    reset();
    socket_ = socket;
  }

  void reset() {
    if (socket_ != INVALID_SOCKET) {
      closesocket(socket_);
      socket_ = INVALID_SOCKET;
    }
  }

private:
  SOCKET socket_ = INVALID_SOCKET;
};

std::string lastWinsockError(std::string_view context) {
  return std::string(context) + " failed: WSA error " + std::to_string(WSAGetLastError());
}

// Fills a buffer with cryptographically-uninteresting but well-distributed
// random bytes for the handshake key and frame mask. The macOS helper uses
// UInt8.random; parity here is only about non-repeating masks, not secrecy.
template <std::size_t N>
std::array<std::uint8_t, N> randomBytes() {
  std::random_device device;
  std::array<std::uint8_t, N> bytes{};
  for (auto &byte : bytes) {
    byte = static_cast<std::uint8_t>(device() & 0xff);
  }
  return bytes;
}

void sendAll(SOCKET socket, std::string_view data) {
  std::size_t sent = 0;
  while (sent < data.size()) {
    const int chunk = ::send(socket, data.data() + sent,
                             static_cast<int>(data.size() - sent), 0);
    if (chunk == SOCKET_ERROR) {
      throw std::runtime_error(lastWinsockError("send"));
    }
    if (chunk == 0) {
      throw std::runtime_error("send: connection closed while writing");
    }
    sent += static_cast<std::size_t>(chunk);
  }
}

// Reads exactly the HTTP handshake response headers, returning the full header
// block plus any bytes already read past the terminating CRLFCRLF (the start of
// the first frame, if the server pipelined one).
std::string readHandshakeResponse(SOCKET socket, std::string &leftover) {
  std::string buffer;
  char chunk[1024];
  while (true) {
    const auto complete = completeHeaderLength(buffer);
    if (complete) {
      leftover = buffer.substr(*complete);
      return buffer.substr(0, *complete);
    }
    const int received = ::recv(socket, chunk, sizeof(chunk), 0);
    if (received == SOCKET_ERROR) {
      throw std::runtime_error(lastWinsockError("recv"));
    }
    if (received == 0) {
      throw std::runtime_error("handshake failed: connection closed before headers completed");
    }
    buffer.append(chunk, static_cast<std::size_t>(received));
  }
}

} // namespace

ControlClient::ControlClient(std::string host, int port, std::chrono::seconds timeout)
    : host_(std::move(host)), port_(port), timeout_(timeout) {}

ControlEvent ControlClient::send(const ControlCommand &command) {
  WinsockSession winsock;

  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;

  addrinfo *resolved = nullptr;
  const int status = getaddrinfo(host_.c_str(), std::to_string(port_).c_str(), &hints, &resolved);
  if (status != 0 || resolved == nullptr) {
    throw std::runtime_error("getaddrinfo failed: WSA error " + std::to_string(status));
  }

  SocketHandle socket;
  for (addrinfo *address = resolved; address != nullptr; address = address->ai_next) {
    SOCKET candidate = ::socket(address->ai_family, address->ai_socktype, address->ai_protocol);
    if (candidate == INVALID_SOCKET) {
      continue;
    }
    if (::connect(candidate, address->ai_addr, static_cast<int>(address->ai_addrlen)) == 0) {
      socket.assign(candidate);
      break;
    }
    closesocket(candidate);
  }
  freeaddrinfo(resolved);

  if (!socket.valid()) {
    throw std::runtime_error("connect failed: could not reach " + host_ + ":" + std::to_string(port_));
  }

  const DWORD timeoutMs = static_cast<DWORD>(timeout_.count() * 1000);
  setsockopt(socket.get(), SOL_SOCKET, SO_RCVTIMEO,
             reinterpret_cast<const char *>(&timeoutMs), sizeof(timeoutMs));
  setsockopt(socket.get(), SOL_SOCKET, SO_SNDTIMEO,
             reinterpret_cast<const char *>(&timeoutMs), sizeof(timeoutMs));

  const auto keyBytes = randomBytes<16>();
  const std::string key = base64Encode(keyBytes.data(), keyBytes.size());
  sendAll(socket.get(), buildWebSocketHandshakeRequest(host_, port_, "/control", key));

  std::string frameBuffer;
  const std::string responseHeaders = readHandshakeResponse(socket.get(), frameBuffer);
  const HttpHeaders headers = parseHttpHeaders(responseHeaders);
  if (!isWebSocketSwitchingProtocolsResponse(headers, key)) {
    throw std::runtime_error("WebSocket handshake failed: " + responseHeaders);
  }

  const std::string payload = encodeControlCommand(command);
  const auto mask = randomBytes<4>();
  sendAll(socket.get(), encodeClientTextFrame(payload, mask));

  char chunk[4096];
  while (true) {
    const WebSocketFrame frame = decodeServerTextFrame(frameBuffer);
    if (frame.complete) {
      return decodeControlEvent(frame.payload);
    }
    const int received = ::recv(socket.get(), chunk, sizeof(chunk), 0);
    if (received == SOCKET_ERROR) {
      throw std::runtime_error(lastWinsockError("recv"));
    }
    if (received == 0) {
      throw std::runtime_error("connection closed before a complete frame arrived");
    }
    frameBuffer.append(chunk, static_cast<std::size_t>(received));
  }
}

} // namespace reashoot

#endif // _WIN32
