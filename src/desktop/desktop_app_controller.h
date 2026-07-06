#pragma once

#include "desktop_app_model.h"

#include "../core/platform_interfaces.h"

#include <string>

namespace reashoot::desktop {

struct DesktopButtonState {
  std::string recordTitle;
  std::string previewTitle;
  bool recordEnabled = true;
};

struct PreviewRetryDecision {
  bool shouldRetry = false;
  int nextAttempt = 0;
  double delaySeconds = 0.0;
  std::string statusText;
  std::string previewMessage;
};

class DesktopAppController {
public:
  void setHost(std::string host);
  void setToken(std::string token);
  void setRecording(bool recording);
  void setPreviewRunning(bool running);
  void setPreviewDesired(bool desired);

  const std::string &host() const { return host_; }
  const std::string &token() const { return token_; }
  bool recording() const { return recording_; }
  bool previewRunning() const { return previewRunning_; }
  bool previewDesired() const { return previewDesired_; }
  bool hasHost() const { return !host_.empty(); }
  bool hasToken() const { return !token_.empty(); }
  bool canUsePhone() const { return hasHost() && hasToken(); }

  std::string connectionStatusText() const;
  std::string previewEmptyMessage() const;
  DesktopButtonState buttonState() const;
  PreviewRetryDecision retryDecision(const core::CommandResult &result, int attempt, int maxAttempts = 5) const;

private:
  std::string host_;
  std::string token_;
  bool recording_ = false;
  bool previewRunning_ = false;
  bool previewDesired_ = false;
};

} // namespace reashoot::desktop
