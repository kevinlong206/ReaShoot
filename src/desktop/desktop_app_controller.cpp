#include "desktop_app_controller.h"

#include <algorithm>
#include <utility>

namespace reashoot::desktop {

void DesktopAppController::setHost(std::string host) {
  host_ = std::move(host);
}

void DesktopAppController::setToken(std::string token) {
  token_ = std::move(token);
}

void DesktopAppController::setRecording(bool recording) {
  recording_ = recording;
}

void DesktopAppController::setPreviewRunning(bool running) {
  previewRunning_ = running;
}

void DesktopAppController::setPreviewDesired(bool desired) {
  previewDesired_ = desired;
}

std::string DesktopAppController::connectionStatusText() const {
  const std::string host = hasHost() ? host_ : "No iPhone selected";
  const std::string pairing = hasToken() ? "Paired" : "Not paired";
  return "iPhone: " + host + " - " + pairing;
}

std::string DesktopAppController::previewEmptyMessage() const {
  return reashoot::desktop::previewEmptyMessage(previewRunning_, hasHost(), hasToken());
}

DesktopButtonState DesktopAppController::buttonState() const {
  DesktopButtonState state;
  state.recordTitle = recordButtonTitle(recording_);
  state.previewTitle = previewButtonTitle(previewRunning_);
  state.recordEnabled = true;
  return state;
}

PreviewRetryDecision DesktopAppController::retryDecision(const core::CommandResult &result, int attempt, int maxAttempts) const {
  PreviewRetryDecision decision;
  if (!previewDesired_ || !isTransientConnectionFailure(result) || attempt >= maxAttempts) {
    return decision;
  }
  decision.shouldRetry = true;
  decision.nextAttempt = attempt + 1;
  decision.delaySeconds = std::min<double>(10.0, 1.5 * static_cast<double>(decision.nextAttempt));
  decision.statusText = "No stream from phone. Retrying in " + std::to_string(static_cast<int>(decision.delaySeconds + 0.5)) + " seconds...";
  decision.previewMessage = decision.statusText;
  return decision;
}

} // namespace reashoot::desktop
