#pragma once

#include <mutex>
#include <string>

namespace reashoot {

// Host-neutral, thread-safe debug logger that appends timestamped lines to a
// file. Mirrors the macOS plugin's debugLog, which writes to a well-known temp
// path. The plugin picks the concrete path (e.g. %TEMP%\reashoot_debug.log)
// so this class stays free of platform assumptions and unit-testable.
class DebugLogger {
public:
  explicit DebugLogger(std::string filePath);

  // Appends "<timestamp> REAPER <message>\n" to the log file. Failures to open
  // the file are swallowed so logging never disrupts the host.
  void log(const std::string &message);

  const std::string &filePath() const { return filePath_; }

  // Returns the default log file path for the current platform,
  // e.g. "<temp>/reashoot_debug.log".
  static std::string defaultPath();

private:
  std::string filePath_;
  std::mutex mutex_;
};

} // namespace reashoot
