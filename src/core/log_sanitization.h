#pragma once

#include "remote_camera.h"

#include <string>
#include <vector>

namespace reashoot::core {

std::string redactedText(std::string value);
std::string redactedArguments(const std::vector<std::string> &arguments);
std::string redactedSettingsSummary(const RemoteCameraSettings &settings);

} // namespace reashoot::core
