#include "reaphone/windows/helper_launcher.h"

#include <exception>
#include <string>
#include <string_view>

namespace reaphone {

namespace {

int parsePort(const std::string &value, int fallback) {
  if (value.empty()) {
    return fallback;
  }
  try {
    const int parsed = std::stoi(value);
    return parsed > 0 ? parsed : fallback;
  } catch (const std::exception &) {
    return fallback;
  }
}

// Iterates the newline-separated lines of an output blob (splitting on both
// "\r\n" and "\n"), invoking the callback for each line without its terminator.
template <typename Callback>
void forEachLine(std::string_view output, Callback &&callback) {
  std::size_t start = 0;
  while (start <= output.size()) {
    std::size_t end = output.find('\n', start);
    const std::size_t stop = end == std::string_view::npos ? output.size() : end;
    std::string_view line = output.substr(start, stop - start);
    if (!line.empty() && line.back() == '\r') {
      line.remove_suffix(1);
    }
    callback(line);
    if (end == std::string_view::npos) {
      break;
    }
    start = end + 1;
  }
}

} // namespace

HelperConnection makeConnection(const std::string &host,
                                const std::string &controlPort,
                                const std::string &httpPort) {
  HelperConnection connection;
  connection.host = host;
  connection.controlPort = parsePort(controlPort, 8787);
  connection.httpPort = parsePort(httpPort, 8788);
  return connection;
}

std::optional<std::string> parsePairedToken(std::string_view output) {
  constexpr std::string_view prefix = "paired token=";
  std::optional<std::string> token;
  forEachLine(output, [&](std::string_view line) {
    if (!token && line.substr(0, prefix.size()) == prefix) {
      token = std::string(line.substr(prefix.size()));
    }
  });
  return token;
}

std::map<std::string, std::string> fieldsFromHelperLine(std::string_view line) {
  std::map<std::string, std::string> fields;
  std::size_t start = 0;
  while (start <= line.size()) {
    const std::size_t tab = line.find('\t', start);
    const std::size_t stop = tab == std::string_view::npos ? line.size() : tab;
    const std::string_view part = line.substr(start, stop - start);
    const std::size_t equals = part.find('=');
    if (equals != std::string_view::npos && equals != 0) {
      fields.emplace(std::string(part.substr(0, equals)), std::string(part.substr(equals + 1)));
    }
    if (tab == std::string_view::npos) {
      break;
    }
    start = tab + 1;
  }
  return fields;
}

std::optional<std::map<std::string, std::string>> firstDeviceFields(std::string_view output) {
  std::optional<std::map<std::string, std::string>> result;
  forEachLine(output, [&](std::string_view line) {
    if (result || line.substr(0, 7) != "device\t") {
      return;
    }
    std::map<std::string, std::string> fields = fieldsFromHelperLine(line);
    const auto host = fields.find("host");
    if (host != fields.end() && !host->second.empty()) {
      result = std::move(fields);
    }
  });
  return result;
}

} // namespace reaphone

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace reaphone {

namespace {

std::wstring widen(std::string_view value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0);
  std::wstring wide(static_cast<std::size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      wide.data(), length);
  return wide;
}

} // namespace

std::vector<std::wstring> videoSyncArguments(std::string_view command,
                                             const HelperConnection &connection,
                                             const std::vector<std::wstring> &extraArguments) {
  std::vector<std::wstring> arguments;
  arguments.push_back(widen(command));
  if (command != "discover") {
    arguments.push_back(L"--host");
    arguments.push_back(widen(connection.host));
    arguments.push_back(L"--port");
    arguments.push_back(widen(std::to_string(connection.controlPort)));
  }
  arguments.insert(arguments.end(), extraArguments.begin(), extraArguments.end());
  return arguments;
}

ProcessResult runVideoSyncCommand(const std::wstring &helperExecutable,
                                  std::string_view command,
                                  const HelperConnection &connection,
                                  const std::vector<std::wstring> &extraArguments,
                                  const ProcessOptions &options) {
  return runProcess(helperExecutable, videoSyncArguments(command, connection, extraArguments), options);
}

} // namespace reaphone

#endif // _WIN32
