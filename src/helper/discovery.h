#pragma once

#include <string>
#include <vector>

namespace reashoot::helper {

struct DiscoveredPhone {
  std::string name;
  std::string host;
  int controlPort = 8787;
  int httpPort = 8788;
  bool isPaired = false;
};

std::vector<DiscoveredPhone> discoverPhones(int timeoutSeconds);

} // namespace reashoot::helper
