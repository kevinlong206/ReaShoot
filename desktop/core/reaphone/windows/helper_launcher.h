#pragma once

#include "reaphone/windows/process_runner.h"

#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace reaphone {

// Connection details shared by every helper invocation, mirroring the globals
// the macOS plugin threads through videoSyncArgumentsForCommand.
struct HelperConnection {
  std::string host;
  int controlPort = 8787;
  int httpPort = 8788;
};

// Builds the helper CLI argument vector, mirroring the macOS plugin's
// videoSyncArgumentsForCommand: the command first, then --host/--port (omitted
// only for "discover"), then the caller's extra arguments (token, code, etc.).
std::vector<std::wstring> videoSyncArguments(std::string_view command,
                                             const HelperConnection &connection,
                                             const std::vector<std::wstring> &extraArguments = {});

// Launches the helper CLI at helperExecutable for the given command, returning
// the raw ProcessResult (stdout/stderr/exit code). The helper is resolved by
// exact path, matching the process adapter's no-PATH-search behaviour.
ProcessResult runVideoSyncCommand(const std::wstring &helperExecutable,
                                  std::string_view command,
                                  const HelperConnection &connection,
                                  const std::vector<std::wstring> &extraArguments = {},
                                  const ProcessOptions &options = {});

// Parses "paired token=..." from helper stdout, mirroring the macOS plugin's
// pairIPhone. Returns the token from the first matching line, or nullopt.
std::optional<std::string> parsePairedToken(std::string_view output);

// Splits a tab-delimited "key=value" helper line into fields, mirroring the
// macOS plugin's fieldsFromHelperLine (parts with no '=' or a leading '=' are
// skipped).
std::map<std::string, std::string> fieldsFromHelperLine(std::string_view line);

// Returns the fields of the first "device\t..." line whose host is non-empty,
// mirroring the macOS plugin's applyFirstDiscoveredIPhoneFromOutput.
std::optional<std::map<std::string, std::string>> firstDeviceFields(std::string_view output);

} // namespace reaphone
