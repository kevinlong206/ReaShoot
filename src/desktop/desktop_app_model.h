#pragma once

#include "../core/remote_camera.h"

#include <string>
#include <vector>

namespace reashoot::desktop {

struct DesktopChoice {
  std::string title;
  std::string value;
};

struct DesktopSettings {
  std::string host;
  std::string downloadDirectory;
  std::string token;
  std::string resolution;
  std::string fps;
  std::string orientation;
  std::string aspect;
  std::string lens;
  std::string zoom;
  std::string look;
};

const std::vector<DesktopChoice> &resolutionChoices();
const std::vector<DesktopChoice> &fpsChoices();
const std::vector<DesktopChoice> &orientationChoices();
const std::vector<DesktopChoice> &aspectChoices();
const std::vector<DesktopChoice> &lensChoices();
const std::vector<DesktopChoice> &lookChoices();

std::string defaultResolution();
std::string defaultFps();
std::string defaultOrientation();
std::string defaultAspect();
std::string defaultLens();
std::string defaultZoom();
std::string defaultLook();

std::string recordButtonTitle(bool recording);
std::string previewButtonTitle(bool previewRunning);
std::string previewEmptyMessage(bool previewRunning, bool hasHost, bool hasToken);
std::string recordingTimestampFallback(const core::RemoteRecordingDescriptor &recording);
std::string recordingThumbnailURL(const core::RemoteCameraSettings &settings,
                                  const core::RemoteRecordingDescriptor &recording);

bool isTransientConnectionFailure(const std::string &message);
bool isTransientConnectionFailure(const core::CommandResult &result);

} // namespace reashoot::desktop
