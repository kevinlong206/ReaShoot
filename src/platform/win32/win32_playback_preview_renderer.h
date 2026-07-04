#pragma once

#include "../../core/ui_interfaces.h"

#include <memory>

namespace reashoot::platform::win32 {

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler);

} // namespace reashoot::platform::win32
