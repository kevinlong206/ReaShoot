#pragma once

#include "../../desktop/desktop_integration_api.h"

#include <atomic>
#include <functional>
#include <memory>
#include <string>

namespace reashoot::app::mac {

using IntegrationRequestHandler = std::function<reashoot::desktop::IntegrationHttpResponse(const reashoot::desktop::IntegrationHttpRequest &)>;
using IntegrationEventSnapshotProvider = std::function<std::string()>;

class ReaShootMacIntegrationServer {
public:
  ReaShootMacIntegrationServer();
  ~ReaShootMacIntegrationServer();

  ReaShootMacIntegrationServer(const ReaShootMacIntegrationServer &) = delete;
  ReaShootMacIntegrationServer &operator=(const ReaShootMacIntegrationServer &) = delete;

  bool start(const std::string &token,
             IntegrationRequestHandler handler,
             IntegrationEventSnapshotProvider eventSnapshotProvider,
             std::string *errorMessage);
  void stop();

  int port() const { return port_; }
  const std::string &token() const { return token_; }

private:
  class Impl;
  std::unique_ptr<Impl> impl_;
  int port_ = 0;
  std::string token_;
};

std::string loadOrCreateIntegrationToken();
void writeIntegrationRegistration(int port, const std::string &token);
void removeIntegrationRegistration();

} // namespace reashoot::app::mac
