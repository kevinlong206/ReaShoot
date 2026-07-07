#pragma once

#include "../core/remote_camera.h"

#include <string>
#include <vector>

namespace reashoot::desktop {

struct DiscoveredCamera {
  std::string name;
  std::string host;
  std::string controlPort = "8787";
  std::string httpPort = "8788";
  bool paired = false;
};

std::string defaultDownloadDirectory();
std::string makeSessionID();
std::vector<DiscoveredCamera> parseDiscoveredCameras(const std::string &output);
std::string discoveredCameraLabel(const DiscoveredCamera &camera);
std::vector<core::RemoteRecordingDescriptor> parseRecordingDescriptors(const std::string &output);
core::PreviewStreamDescriptor parsePreviewDescriptor(const std::string &output);

} // namespace reashoot::desktop
