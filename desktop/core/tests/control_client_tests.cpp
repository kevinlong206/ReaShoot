#include "reaphone/windows/control_client.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

#include "loopback_ws_server.h"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

using LoopbackServer = reaphone::testing::LoopbackWebSocketServer;

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

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
