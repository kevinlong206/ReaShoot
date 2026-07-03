#pragma once

#include "core/control_protocol.h"

#include <functional>
#include <string>

namespace reashoot::helper {

using DownloadProgress = std::function<void(int64_t bytes, int64_t total)>;

std::string downloadRecording(const reashoot::core::ProtocolRecording &recording,
                              const std::string &host,
                              int httpPort,
                              const std::string &token,
                              const std::string &destinationDirectory,
                              DownloadProgress progress);

} // namespace reashoot::helper
