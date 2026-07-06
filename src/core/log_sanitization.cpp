#include "log_sanitization.h"

#include <sstream>

namespace reashoot::core {

std::string redactedText(std::string value) {
  const std::vector<std::string> prefixes = {"token=", "code=", "pairingCode="};
  for (const std::string &prefix : prefixes) {
    std::string::size_type position = 0;
    while ((position = value.find(prefix, position)) != std::string::npos) {
      const std::string::size_type valueStart = position + prefix.size();
      std::string::size_type valueEnd = value.find_first_of(" \t\r\n", valueStart);
      if (valueEnd == std::string::npos) {
        valueEnd = value.size();
      }
      value.replace(valueStart, valueEnd - valueStart, "REDACTED");
      position = valueStart + 8;
    }
  }
  return value;
}

std::string redactedArguments(const std::vector<std::string> &arguments) {
  std::ostringstream stream;
  bool redactNext = false;
  for (size_t index = 0; index < arguments.size(); ++index) {
    if (index > 0) {
      stream << ' ';
    }
    if (redactNext) {
      stream << "REDACTED";
      redactNext = false;
      continue;
    }
    stream << redactedText(arguments[index]);
    if (arguments[index] == "--token" || arguments[index] == "--code") {
      redactNext = true;
    }
  }
  return stream.str();
}

std::string redactedSettingsSummary(const RemoteCameraSettings &settings) {
  std::ostringstream stream;
  stream << "host=" << settings.host
         << " controlPort=" << settings.controlPort
         << " httpPort=" << settings.httpPort
         << " token=" << (settings.token.empty() ? "empty" : "present")
         << " profile=" << settings.resolution << "/" << settings.fps
         << " orientation=" << settings.orientation
         << " aspect=" << settings.aspect
         << " lens=" << settings.lens
         << " zoom=" << settings.zoom
         << " look=" << settings.look;
  return stream.str();
}

} // namespace reashoot::core
