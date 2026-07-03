#pragma once

#include <string>

namespace reashoot::core {

bool hasPathExtension(const std::string &path, const std::string &extension);
bool isVideoPath(const std::string &path);
std::string directoryName(const std::string &path);
std::string baseNameWithoutExtension(const std::string &path);
std::string timestampString();

} // namespace reashoot::core
