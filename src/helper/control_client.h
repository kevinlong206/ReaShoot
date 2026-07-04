#pragma once

#include "core/control_protocol.h"
#include "socket_utils.h"

#include <cstdint>
#include <stdexcept>
#include <string>

namespace reashoot::helper {

class HelperError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

class ControlClient {
public:
  ControlClient(std::string host, int port, int timeoutSeconds = 20);
  reashoot::core::ProtocolEvent send(const reashoot::core::ProtocolCommand &command) const;

private:
  SocketHandle openSocket() const;
  void performHandshake(SocketHandle socket) const;
  void sendFrame(SocketHandle socket, const std::string &payload) const;
  std::string receiveFrame(SocketHandle socket) const;

  std::string host_;
  int port_ = 8787;
  int timeoutSeconds_ = 20;
};

std::string webSocketAcceptForKey(const std::string &key);
std::string randomWebSocketKey();
std::string randomUUID();

} // namespace reashoot::helper
