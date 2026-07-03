#pragma once

// A minimal single-connection loopback WebSocket server for tests. It accepts
// one client, completes the RFC 6455 handshake using the reashoot core helpers,
// reads the client's masked command frame, hands the decoded payload to a
// responder, and writes the responder's reply back as an unmasked server text
// frame. When handshakeOk is false it replies 400 instead, to exercise client
// failure paths. Winsock must already be initialised by the caller (WSAStartup).

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

#include <algorithm>
#include <cstdint>
#include <functional>
#include <stdexcept>
#include <string>
#include <thread>

namespace reashoot {
namespace testing {

class LoopbackWebSocketServer {
public:
  explicit LoopbackWebSocketServer(std::function<std::string(const std::string &)> responder,
                                   bool handshakeOk = true)
      : responder_(std::move(responder)), handshakeOk_(handshakeOk) {
    listener_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    check(listener_ != INVALID_SOCKET, "server socket");

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0; // ephemeral
    check(bind(listener_, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0, "server bind");
    check(listen(listener_, 1) == 0, "server listen");

    sockaddr_in bound{};
    int length = sizeof(bound);
    check(getsockname(listener_, reinterpret_cast<sockaddr *>(&bound), &length) == 0, "server getsockname");
    port_ = ntohs(bound.sin_port);

    thread_ = std::thread([this] { run(); });
  }

  ~LoopbackWebSocketServer() {
    if (thread_.joinable()) {
      thread_.join();
    }
    if (listener_ != INVALID_SOCKET) {
      closesocket(listener_);
    }
  }

  LoopbackWebSocketServer(const LoopbackWebSocketServer &) = delete;
  LoopbackWebSocketServer &operator=(const LoopbackWebSocketServer &) = delete;

  int port() const { return port_; }
  const std::string &receivedCommand() const { return receivedCommand_; }

private:
  static void check(bool condition, const char *message) {
    if (!condition) {
      throw std::runtime_error(message);
    }
  }

  static std::string recvExact(SOCKET socket, std::size_t count) {
    std::string buffer;
    buffer.reserve(count);
    char chunk[1024];
    while (buffer.size() < count) {
      const int want = static_cast<int>((std::min)(sizeof(chunk), count - buffer.size()));
      const int received = recv(socket, chunk, want, 0);
      if (received <= 0) {
        throw std::runtime_error("server recvExact: connection closed");
      }
      buffer.append(chunk, static_cast<std::size_t>(received));
    }
    return buffer;
  }

  // Reads and unmasks one client text frame (payloads in these tests stay < 126).
  static std::string readClientFrame(SOCKET socket) {
    const std::string header = recvExact(socket, 2);
    const auto opcode = static_cast<std::uint8_t>(header[0]) & 0x0f;
    check(opcode == 0x1, "server expected a text frame");
    const auto second = static_cast<std::uint8_t>(header[1]);
    const bool masked = (second & 0x80) != 0;
    const std::size_t length = second & 0x7f;
    check(length < 126, "test frames stay under 126 bytes");
    check(masked, "client frames must be masked");
    const std::string mask = recvExact(socket, 4);
    std::string payload = recvExact(socket, length);
    for (std::size_t i = 0; i < payload.size(); ++i) {
      payload[i] = static_cast<char>(static_cast<std::uint8_t>(payload[i]) ^
                                     static_cast<std::uint8_t>(mask[i % 4]));
    }
    return payload;
  }

  static std::string encodeServerFrame(const std::string &payload) {
    std::string frame;
    frame.push_back(static_cast<char>(0x81));
    frame.push_back(static_cast<char>(payload.size() & 0x7f));
    frame.append(payload);
    return frame;
  }

  static void sendAll(SOCKET socket, const std::string &data) {
    std::size_t sent = 0;
    while (sent < data.size()) {
      const int chunk = send(socket, data.data() + sent, static_cast<int>(data.size() - sent), 0);
      check(chunk > 0, "server send");
      sent += static_cast<std::size_t>(chunk);
    }
  }

  void run() {
    SOCKET client = accept(listener_, nullptr, nullptr);
    if (client == INVALID_SOCKET) {
      return;
    }

    try {
      std::string request;
      while (!completeHeaderLength(request)) {
        char chunk[1024];
        const int received = recv(client, chunk, sizeof(chunk), 0);
        if (received <= 0) {
          closesocket(client);
          return;
        }
        request.append(chunk, static_cast<std::size_t>(received));
      }

      const HttpHeaders headers = parseHttpHeaders(request);
      const auto key = headers.value("sec-websocket-key");
      check(key.has_value(), "server saw Sec-WebSocket-Key");

      if (!handshakeOk_) {
        sendAll(client, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n");
        closesocket(client);
        return;
      }

      std::string response = "HTTP/1.1 101 Switching Protocols\r\n";
      response += "Upgrade: websocket\r\n";
      response += "Connection: Upgrade\r\n";
      response += "Sec-WebSocket-Accept: " + webSocketAcceptKey(*key) + "\r\n\r\n";
      sendAll(client, response);

      receivedCommand_ = readClientFrame(client);
      sendAll(client, encodeServerFrame(responder_(receivedCommand_)));
    } catch (const std::exception &) {
      // Leave the socket to close; the client surfaces the failure.
    }
    closesocket(client);
  }

  std::function<std::string(const std::string &)> responder_;
  bool handshakeOk_;
  SOCKET listener_ = INVALID_SOCKET;
  int port_ = 0;
  std::string receivedCommand_;
  std::thread thread_;
};

} // namespace testing
} // namespace reashoot
