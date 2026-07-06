#include "desktop_app_model.h"

#include <algorithm>
#include <cctype>
#include <regex>
#include <sstream>

namespace reashoot::desktop {
namespace {

std::string lowercase(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

const std::vector<DesktopChoice> kResolutionChoices = {
    {"4K", "4K"},
    {"1080p", "1080p"},
    {"720p", "720p"},
};

const std::vector<DesktopChoice> kFpsChoices = {
    {"30", "30"},
    {"24", "24"},
    {"60", "60"},
};

const std::vector<DesktopChoice> kOrientationChoices = {
    {"auto", "auto"},
    {"portrait", "portrait"},
    {"landscape", "landscape"},
};

const std::vector<DesktopChoice> kAspectChoices = {
    {"9:16", "9:16"},
    {"16:9", "16:9"},
    {"4:3", "4:3"},
    {"1:1", "1:1"},
};

const std::vector<DesktopChoice> kLensChoices = {
    {"wide", "wide"},
    {"ultrawide", "ultrawide"},
    {"telephoto", "telephoto"},
};

const std::vector<DesktopChoice> kLookChoices = {
    {"Natural", "natural"},
    {"Warm Vintage", "warmVintage"},
    {"Cool Blue", "coolBlue"},
    {"High Contrast B&W", "highContrastBW"},
    {"Faded Film", "fadedFilm"},
    {"Dream Glow", "dreamGlow"},
    {"Noir", "noir"},
    {"Saturated Pop", "saturatedPop"},
    {"Bleach Bypass", "bleachBypass"},
    {"Sepia", "sepia"},
    {"Instant Photo", "instantPhoto"},
    {"Chrome", "chrome"},
    {"Tonal", "tonal"},
    {"Silvertone", "silvertone"},
    {"Dramatic Warm", "dramaticWarm"},
    {"Dramatic Cool", "dramaticCool"},
    {"Soft Matte", "softMatte"},
    {"Comic Book", "comicBook"},
    {"VHS", "vhs"},
    {"Music Video Pop", "musicVideoPop"},
};

} // namespace

const std::vector<DesktopChoice> &resolutionChoices() { return kResolutionChoices; }
const std::vector<DesktopChoice> &fpsChoices() { return kFpsChoices; }
const std::vector<DesktopChoice> &orientationChoices() { return kOrientationChoices; }
const std::vector<DesktopChoice> &aspectChoices() { return kAspectChoices; }
const std::vector<DesktopChoice> &lensChoices() { return kLensChoices; }
const std::vector<DesktopChoice> &lookChoices() { return kLookChoices; }

std::string defaultResolution() { return "4K"; }
std::string defaultFps() { return "30"; }
std::string defaultOrientation() { return "auto"; }
std::string defaultAspect() { return "9:16"; }
std::string defaultLens() { return "wide"; }
std::string defaultZoom() { return "1.0"; }
std::string defaultLook() { return "natural"; }

std::string recordButtonTitle(bool recording) {
  return recording ? "Stop Recording" : "Start Recording";
}

std::string previewButtonTitle(bool previewRunning) {
  return previewRunning ? "Stop Preview" : "Start Preview";
}

std::string previewEmptyMessage(bool previewRunning, bool hasHost, bool hasToken) {
  if (previewRunning) {
    return "Waiting for video from iPhone...";
  }
  if (!hasHost) {
    return "No iPhone selected.";
  }
  if (!hasToken) {
    return "No paired iPhone.";
  }
  return "Preview stopped.";
}

std::string recordingTimestampFallback(const core::RemoteRecordingDescriptor &recording) {
  if (!recording.createdAt.empty()) {
    return recording.createdAt;
  }
  static const std::regex timestampPattern("([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z)");
  std::smatch match;
  if (std::regex_search(recording.id, match, timestampPattern) && match.size() > 1) {
    std::string timestamp = match[1].str();
    for (size_t index = 11; index < 19 && index < timestamp.size(); ++index) {
      if (timestamp[index] == '-') {
        timestamp[index] = ':';
      }
    }
    return timestamp;
  }
  return "Unknown time";
}

std::string recordingThumbnailURL(const core::RemoteCameraSettings &settings,
                                  const core::RemoteRecordingDescriptor &recording) {
  if (settings.host.empty() || settings.token.empty() || recording.thumbnailPath.empty()) {
    return {};
  }
  std::ostringstream url;
  url << "http://" << settings.host << ':' << settings.httpPort;
  if (recording.thumbnailPath.front() != '/') {
    url << '/';
  }
  url << recording.thumbnailPath << "?token=" << settings.token;
  return url.str();
}

bool isTransientConnectionFailure(const std::string &message) {
  const std::string normalized = lowercase(message);
  return normalized.find("could not connect") != std::string::npos ||
         normalized.find("no route to host") != std::string::npos ||
         normalized.find("network is unreachable") != std::string::npos ||
         normalized.find("connection reset") != std::string::npos ||
         normalized.find("connection refused") != std::string::npos ||
         normalized.find("timed out") != std::string::npos;
}

bool isTransientConnectionFailure(const core::CommandResult &result) {
  return isTransientConnectionFailure(result.errorMessage.empty() ? result.output : result.errorMessage);
}

} // namespace reashoot::desktop
