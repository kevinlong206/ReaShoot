#pragma once

#include <string>

namespace reashoot::reaper {

std::string resourcePath();
std::string extState(const char *section, const char *key);
bool setExtState(const char *section, const char *key, const char *value, bool persist);
void refreshToolbar(int commandId);

} // namespace reashoot::reaper
