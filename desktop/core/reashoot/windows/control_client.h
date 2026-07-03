#pragma once

#include "reashoot/control_protocol.h"

#include <chrono>
#include <string>

namespace reashoot {

// A synchronous control-socket client mirroring the macOS helper ControlClient
// (helper/Sources/video-sync-mac/ControlClient.swift). Each send() opens a TCP
// connection, performs the WebSocket upgrade handshake, writes one masked text
// frame carrying the encoded command, reads one server text frame, decodes it
// into a ControlEvent, and closes the socket -- the same request/response cycle
// the Swift client performs.
//
// This is the Windows (Winsock) implementation. The class is declared on all
// platforms so portable callers can reference it, but the implementation is
// only compiled on Windows.
class ControlClient {
public:
  ControlClient(std::string host, int port, std::chrono::seconds timeout = std::chrono::seconds{20});

  // Connects, handshakes, sends the command, and returns the decoded event.
  // Throws std::runtime_error on any connection, handshake, or protocol
  // failure, and rethrows the std::invalid_argument decodeControlEvent raises
  // for malformed event JSON.
  ControlEvent send(const ControlCommand &command);

  const std::string &host() const { return host_; }
  int port() const { return port_; }

private:
  std::string host_;
  int port_;
  std::chrono::seconds timeout_;
};

} // namespace reashoot
