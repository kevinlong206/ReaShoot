#include "desktop_workflow.h"

#include "../core/helper_output_parser.h"

#include <chrono>
#include <cstdlib>
#include <sstream>

namespace reashoot::desktop {
namespace {

std::string fieldOrDefault(const core::FieldMap &fields, const std::string &key, const std::string &fallback) {
  const auto found = fields.find(key);
  return found == fields.end() || found->second.empty() ? fallback : found->second;
}

} // namespace

std::string defaultDownloadDirectory() {
#if defined(_WIN32)
  const char *profile = std::getenv("USERPROFILE");
  if (!profile || !profile[0]) {
    return "ReaShoot";
  }
  return std::string(profile) + "\\Videos\\ReaShoot";
#else
  const char *home = std::getenv("HOME");
  if (!home || !home[0]) {
    return "ReaShoot";
  }
  return std::string(home) + "/Movies/ReaShoot";
#endif
}

std::string makeSessionID() {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  const auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(now).count();
  return "desktop-" + std::to_string(millis);
}

std::vector<DiscoveredCamera> parseDiscoveredCameras(const std::string &output) {
  std::vector<DiscoveredCamera> cameras;
  std::stringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    if (line.rfind("device\t", 0) != 0) {
      continue;
    }
    const core::FieldMap fields = core::parseFields(line, '\t');
    const std::string host = fieldOrDefault(fields, "host", "");
    if (host.empty()) {
      continue;
    }
    DiscoveredCamera camera;
    camera.name = fieldOrDefault(fields, "name", "iPhone");
    camera.host = host;
    camera.controlPort = fieldOrDefault(fields, "controlPort", "8787");
    camera.httpPort = fieldOrDefault(fields, "httpPort", "8788");
    camera.paired = fieldOrDefault(fields, "paired", "false") == "true";
    cameras.push_back(camera);
  }
  return cameras;
}

std::vector<core::RemoteRecordingDescriptor> parseRecordingDescriptors(const std::string &output) {
  std::vector<core::RemoteRecordingDescriptor> recordings;
  for (const core::FieldMap &fields : core::parseRecordings(output)) {
    core::RemoteRecordingDescriptor recording = core::recordingDescriptorFromFields(fields);
    if (!recording.id.empty()) {
      recordings.push_back(recording);
    }
  }
  return recordings;
}

std::string discoveredCameraLabel(const DiscoveredCamera &camera) {
  std::string label = camera.name.empty() ? "iPhone" : camera.name;
  if (!camera.host.empty()) {
    label += " - " + camera.host;
  }
  if (camera.paired) {
    label += " (paired)";
  }
  return label;
}

core::PreviewStreamDescriptor parsePreviewDescriptor(const std::string &output) {
  std::stringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    if (line.rfind("preview\t", 0) == 0) {
      return core::previewStreamDescriptorFromFields(core::parseFields(line, '\t'));
    }
  }
  return {};
}

} // namespace reashoot::desktop
