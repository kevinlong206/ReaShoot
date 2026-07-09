#include "capture_profile.h"

namespace reashoot::core {

std::vector<std::string> captureProfileArguments(const CaptureProfile &profile) {
  std::vector<std::string> arguments = {
      "--token", profile.token,
      "--resolution", profile.resolution,
      "--fps", profile.fps,
      "--orientation", profile.orientation,
      "--aspect", profile.aspect,
      "--lens", profile.lens,
      "--zoom", profile.zoom,
      "--look", profile.look,
  };
  if (profile.encodeLookAtRecordTime) {
    arguments.push_back("--encode-look-at-record-time");
  }
  return arguments;
}

} // namespace reashoot::core
