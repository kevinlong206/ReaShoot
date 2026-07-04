#include "reashoot_status.h"

#include <algorithm>
#include <cctype>
#include <string>

namespace reashoot::core {

namespace {

std::string lowercase(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
    return static_cast<char>(std::tolower(character));
  });
  return value;
}

std::string controlConnectionHelp(const std::string &status) {
  std::string detail;
  const size_t colon = status.find(':');
  if (colon != std::string::npos && colon + 1 < status.size()) {
    detail = status.substr(colon + 1);
    while (!detail.empty() && std::isspace(static_cast<unsigned char>(detail.front()))) {
      detail.erase(detail.begin());
    }
  }

  std::string message =
      "Could not connect to the iPhone control socket. Make sure the ReaShoot iOS app is open in the foreground, "
      "the iPhone is unlocked, and the phone and this computer are on the same Wi-Fi network. Then try Reconnect. "
      "If the iPhone shows a new pairing code or you recently reset pairing, pair again from Setup.";
  if (!detail.empty()) {
    message += " Details: " + detail;
  }
  return message;
}

} // namespace

std::string friendlyStatusText(const std::string &status) {
  const std::string normalized = lowercase(status);
  if (normalized.find("control socket") != std::string::npos &&
      (normalized.find("could not connect") != std::string::npos ||
       normalized.find("connection refused") != std::string::npos ||
       normalized.find("timed out") != std::string::npos ||
       normalized.find("connection closed") != std::string::npos ||
       normalized.find("getaddrinfo") != std::string::npos)) {
    return controlConnectionHelp(status);
  }
  if (normalized.find("unauthorized") != std::string::npos) {
    return "iPhone authorization failed: reset pairing on the iPhone, enter the new code in Setup, then Pair again.";
  }
  if (normalized.find("invalid pairing code") != std::string::npos) {
    return "Invalid pairing code: check the six-digit code on the iPhone and press Pair again.";
  }
  if (normalized.find("connection closed") != std::string::npos) {
    return "iPhone connection closed. If you reset pairing, enter the current code and Pair again.";
  }
  return status;
}

std::string previewStateText(bool previewStreamActive, bool previewStreamStarting) {
  if (previewStreamActive) {
    return "H.264 preview";
  }
  if (previewStreamStarting) {
    return "preview connecting";
  }
  return "preview idle";
}

std::string captureFormatText(const CaptureProfile &profile, bool previewStreamActive, bool previewStreamStarting) {
  return "iPhone Wi-Fi: " + profile.resolution + " " + profile.fps + " fps, " +
         profile.orientation + ", " + profile.aspect + ", " + profile.lens + " lens, " +
         profile.zoom + "x, look " + profile.look + ", " +
         previewStateText(previewStreamActive, previewStreamStarting);
}

} // namespace reashoot::core
