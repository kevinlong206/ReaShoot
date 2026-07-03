#include "reashoot_controller.h"

namespace reashoot::core {

void ReaShootController::setVideoEnabled(bool enabled) {
  videoEnabled_ = enabled;
  followEnabled_ = enabled;
}

std::string ReaShootController::followStatusText() const {
  if (!videoEnabled_) {
    return "Video disabled";
  }
  return std::string("Video enabled; transport follow ") + (followEnabled_ ? "on" : "off");
}

} // namespace reashoot::core

