#include "reaphone/windows/control_client.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

#include "reaphone/http_headers.h"
#include "reaphone/websocket.h"

#include <cstdint>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

// A minimal single-connection loopback WebSocket server. It accepts one client,
// completes the RFC 6455 handshake using the core helpers, reads the client's
// masked command frame, hands the decoded payload to a responder, and writes the
// responder's reply back as an unmasked server text frame. When handshakeOk is
// false it instead replies 400 to exercise the client's failure path.
class LoopbackServer {
public:
  explicit LoopbackServer(std::function<std::string(const std::string &)> responder,
                          bool handshakeOk = true)
      : responder_(std::move(responder)), handshakeOk_(handshakeOk) {
    listener_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    require(listener_ != INVALID_SOCKET, "server socket");

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0; // ephemeral
    require(bind(listener_, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0, "server bind");
    require(listen(listener_, 1) == 0, "server listen");

    sockaddr_in bound{};
    int length = sizeof(bound);
    require(getsockname(listener_, reinterpret_cast<sockaddr *>(&bound), &length) == 0, "server getsockname");
    port_ = ntohs(bound.sin_port);

    thread_ = std::thread([this] { run(); });
  }

  ~LoopbackServer() {
    if (thread_.joinable()) {
      thread_.join();
    }
    if (listener_ != INVALID_SOCKET) {
      closesocket(listener_);
    }
  }

  int port() const { return port_; }
  const std::string &receivedCommand() const { return receivedCommand_; }

private:
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

  // Reads and unmasks one client text frame (payloads in this test stay < 126).
  static std::string readClientFrame(SOCKET socket) {
    const std::string header = recvExact(socket, 2);
    const auto opcode = static_cast<std::uint8_t>(header[0]) & 0x0f;
    require(opcode == 0x1, "server expected a text frame");
    const auto second = static_cast<std::uint8_t>(header[1]);
    const bool masked = (second & 0x80) != 0;
    std::size_t length = second & 0x7f;
    require(length < 126, "test frames stay under 126 bytes");
    require(masked, "client frames must be masked");
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
      require(chunk > 0, "server send");
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
      while (!reaphone::completeHeaderLength(request)) {
        char chunk[1024];
        const int received = recv(client, chunk, sizeof(chunk), 0);
        if (received <= 0) {
          closesocket(client);
          return;
        }
        request.append(chunk, static_cast<std::size_t>(received));
      }

      const reaphone::HttpHeaders headers = reaphone::parseHttpHeaders(request);
      const auto key = headers.value("sec-websocket-key");
      require(key.has_value(), "server saw Sec-WebSocket-Key");

      if (!handshakeOk_) {
        sendAll(client, "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n");
        closesocket(client);
        return;
      }

      std::string response = "HTTP/1.1 101 Switching Protocols\r\n";
      response += "Upgrade: websocket\r\n";
      response += "Connection: Upgrade\r\n";
      response += "Sec-WebSocket-Accept: " + reaphone::webSocketAcceptKey(*key) + "\r\n\r\n";
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

reaphone::ControlCommand pingCommand() {
  reaphone::ControlCommand command;
  command.requestID = "E1F2A3B4-0000-1111-2222-333344445555";
  command.type = reaphone::CommandType::Ping;
  return command;
}

void roundTripsPingToPong() {
  LoopbackServer server([](const std::string &) { return std::string("{\"type\":\"pong\"}"); });
  reaphone::ControlClient client("127.0.0.1", server.port());
  const reaphone::ControlEvent event = client.send(pingCommand());
  require(event.type == reaphone::EventType::Pong, "ping should yield a pong event");
}

void forwardsEncodedCommandToServer() {
  std::string captured;
  LoopbackServer server([&captured](const std::string &command) {
    captured = command;
    return std::string("{\"type\":\"pong\"}");
  });
  reaphone::ControlClient client("127.0.0.1", server.port());
  client.send(pingCommand());
  require(captured.find("\"type\":\"ping\"") != std::string::npos,
          "server should receive the encoded ping command");
  require(captured.find("\"requestID\":\"E1F2A3B4-0000-1111-2222-333344445555\"") != std::string::npos,
          "server should receive the command requestID");
}

void decodesErrorEventFromServer() {
  LoopbackServer server([](const std::string &) {
    return std::string("{\"type\":\"error\",\"message\":\"boom\"}");
  });
  reaphone::ControlClient client("127.0.0.1", server.port());
  const reaphone::ControlEvent event = client.send(pingCommand());
  require(event.type == reaphone::EventType::Error, "server error should decode to EventType::Error");
  require(event.message.has_value() && *event.message == "boom", "error message should decode");
}

void throwsWhenHandshakeRejected() {
  LoopbackServer server([](const std::string &) { return std::string(); }, /*handshakeOk=*/false);
  reaphone::ControlClient client("127.0.0.1", server.port());
  bool threw = false;
  try {
    client.send(pingCommand());
  } catch (const std::runtime_error &) {
    threw = true;
  }
  require(threw, "a non-101 handshake response should throw");
}

} // namespace

int main() {
  WSADATA data{};
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
    std::cerr << "control_client_tests failed: WSAStartup\n";
    return EXIT_FAILURE;
  }

  int result = EXIT_SUCCESS;
  try {
    roundTripsPingToPong();
    forwardsEncodedCommandToServer();
    decodesErrorEventFromServer();
    throwsWhenHandshakeRejected();
  } catch (const std::exception &error) {
    std::cerr << "control_client_tests failed: " << error.what() << '\n';
    result = EXIT_FAILURE;
  }

  WSACleanup();
  return result;
}
