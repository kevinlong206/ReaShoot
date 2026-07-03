#include "capture_profile.h"

namespace reashoot::core {

std::vector<std::string> captureProfileArguments(const CaptureProfile &profile) {
  return {
      "--token", profile.token,
      "--resolution", profile.resolution,
      "--fps", profile.fps,
      "--orientation", profile.orientation,
      "--aspect", profile.aspect,
      "--lens", profile.lens,
      "--zoom", profile.zoom,
      "--look", profile.look,
  };
}

} // namespace reashoot::core
