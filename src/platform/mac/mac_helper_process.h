#pragma once

#include "../../core/platform_interfaces.h"

#include <functional>
#include <memory>
#include <string>

namespace reashoot::platform::mac {

using HelperLogCallback = std::function<void(const std::string &)>;

std::unique_ptr<core::HelperProcess> createHelperProcess(std::string executablePath, HelperLogCallback log);

} // namespace reashoot::platform::mac
