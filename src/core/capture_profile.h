#pragma once

#include <string>
#include <vector>

namespace reashoot::core {

struct CaptureProfile {
  std::string token;
  std::string resolution;
  std::string fps;
  std::string orientation;
  std::string aspect;
  std::string lens;
  std::string zoom;
  std::string look;
  bool encodeLookAtRecordTime = false;
};

std::vector<std::string> captureProfileArguments(const CaptureProfile &profile);

} // namespace reashoot::core
