#include "reashoot_status.h"

#include <algorithm>
#include <cctype>

namespace reashoot::core {

namespace {

std::string lowercase(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
    return static_cast<char>(std::tolower(character));
  });
  return value;
}

} // namespace

std::string friendlyStatusText(const std::string &status) {
  const std::string normalized = lowercase(status);
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
