#pragma once

#include "../../core/platform_interfaces.h"

#include <memory>

namespace reashoot::platform::win32 {

std::unique_ptr<core::PreviewStreamClient> createPreviewStreamClient();

} // namespace reashoot::platform::win32
