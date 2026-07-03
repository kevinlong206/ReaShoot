#pragma once

#include "capture_profile.h"

#include <string>

namespace reashoot::core {

std::string friendlyStatusText(const std::string &status);
std::string previewStateText(bool previewStreamActive, bool previewStreamStarting);
std::string captureFormatText(const CaptureProfile &profile, bool previewStreamActive, bool previewStreamStarting);

} // namespace reashoot::core
