#pragma once

#include "../../core/ui_interfaces.h"

#include <memory>

namespace reashoot::platform::mac {

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler,
                                                             core::PlaybackDecoderStatusCallback decoderStatusHandler = {});

} // namespace reashoot::platform::mac
