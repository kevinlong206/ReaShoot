#pragma once

#include <string>

namespace reashoot::core {

class ReaShootController {
public:
  bool videoEnabled() const { return videoEnabled_; }
  bool followEnabled() const { return followEnabled_; }

  void setVideoEnabled(bool enabled);
  void setFollowEnabled(bool enabled) { followEnabled_ = enabled; }
  std::string followStatusText() const;

private:
  bool videoEnabled_ = false;
  bool followEnabled_ = true;
};

} // namespace reashoot::core

