#pragma once

#include "../../core/platform_interfaces.h"

#include <memory>

namespace reashoot::platform::mac {

std::unique_ptr<core::MediaAudioReader> createMediaAudioReader();

} // namespace reashoot::platform::mac
