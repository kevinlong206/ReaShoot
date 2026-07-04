#pragma once

#include "../../core/platform_interfaces.h"

#include <memory>

namespace reashoot::platform::win32 {

std::unique_ptr<core::PreviewRenderer> createH264PreviewRenderer(core::VideoFrameCallback frameHandler,
                                                                 core::DecoderStatusCallback decoderStatusHandler = {},
                                                                 int expectedWidth = 0,
                                                                 int expectedHeight = 0);

} // namespace reashoot::platform::win32
