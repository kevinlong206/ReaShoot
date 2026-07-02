#pragma once

#include <chrono>
#include <optional>
#include <string>
#include <vector>

namespace reaphone {

// Result of launching a child process and draining its output.
struct ProcessResult {
  bool started = false;   // false when the process could not be launched
  bool timedOut = false;  // true when the timeout elapsed and the child was killed
  int exitCode = 0;       // process exit code (or the kill code on timeout)
  std::string standardOutput;
  std::string standardError;
};

struct ProcessOptions {
  // When set, the child is terminated after this duration and timedOut is set.
  std::optional<std::chrono::milliseconds> timeout;
};

// Builds a Windows command line from an executable and argument list, applying
// the CommandLineToArgvW quoting rules so arguments with spaces or quotes round
// trip correctly. Pure string logic; exposed for testing.
std::wstring buildWindowsCommandLine(const std::wstring &executable,
                                     const std::vector<std::wstring> &arguments);

// Launches executable with the given arguments, hidden (no console window),
// concurrently draining stdout and stderr to avoid pipe-buffer deadlocks. The
// helper is looked up by the exact executable path (UTF-16), not via PATH.
ProcessResult runProcess(const std::wstring &executable,
                         const std::vector<std::wstring> &arguments,
                         const ProcessOptions &options = {});

} // namespace reaphone
