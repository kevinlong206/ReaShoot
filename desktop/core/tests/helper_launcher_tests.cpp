#include "reashoot/windows/helper_launcher.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include "loopback_ws_server.h"

#include <chrono>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using reashoot::testing::LoopbackWebSocketServer;

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

// The helper exe is built next to this test binary in the same output directory.
std::wstring helperExecutablePath() {
  std::wstring buffer(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  buffer.resize(length);
  const std::size_t slash = buffer.find_last_of(L"\\/");
  const std::wstring directory = slash == std::wstring::npos ? std::wstring() : buffer.substr(0, slash + 1);
  return directory + L"video-sync-win.exe";
}

reashoot::ProcessOptions withTimeout() {
  reashoot::ProcessOptions options;
  options.timeout = std::chrono::seconds{30};
  return options;
}

void buildsArgumentsMirroringPlugin() {
  reashoot::HelperConnection connection;
  connection.host = "phone";
  connection.controlPort = 8787;

  const std::vector<std::wstring> ping =
      reashoot::videoSyncArguments("ping", connection, {L"--token", L"abc"});
  const std::vector<std::wstring> expectedPing = {L"ping",  L"--host",  L"phone", L"--port",
                                                  L"8787",  L"--token", L"abc"};
  require(ping == expectedPing, "ping arguments should include host/port then extras");

  const std::vector<std::wstring> discover =
      reashoot::videoSyncArguments("discover", connection, {L"--timeout", L"3"});
  const std::vector<std::wstring> expectedDiscover = {L"discover", L"--timeout", L"3"};
  require(discover == expectedDiscover, "discover should omit host/port");
}

void parsesPairedToken() {
  require(reashoot::parsePairedToken("noise\r\npaired token=TOK-1\r\nmore") == "TOK-1",
          "paired token should be parsed from stdout");
  require(!reashoot::parsePairedToken("pong\nrecording\tid=1").has_value(),
          "absent paired line should yield nullopt");
}

void parsesDownloadedPath() {
  require(reashoot::parseDownloadedPath("progress bytes=1\r\ndownloaded C:\\rec\\a.mov\r\n") ==
              "C:\\rec\\a.mov",
          "downloaded path should be parsed from stdout");
  require(reashoot::parseDownloadedPath("downloaded first.mov\ndownloaded second.mov") == "second.mov",
          "last downloaded path should win");
  require(!reashoot::parseDownloadedPath("pong").has_value(),
          "absent downloaded line should yield nullopt");
}

void parsesDeviceFields() {
  const std::string output =
      "searching\ndevice\tname=iPhone\thost=1.2.3.4\tcontrolPort=8787\thttpPort=8788\n";
  const auto fields = reashoot::firstDeviceFields(output);
  require(fields.has_value(), "a device line should be found");
  require(fields->at("host") == "1.2.3.4", "device host should parse");
  require(fields->at("name") == "iPhone", "device name should parse");
  require(fields->at("controlPort") == "8787", "device controlPort should parse");
  require(!reashoot::firstDeviceFields("no devices here").has_value(),
          "no device line should yield nullopt");
}

void launchesHelperPairEndToEnd() {
  LoopbackWebSocketServer server([](const std::string &command) {
    return command.find("\"type\":\"pair\"") != std::string::npos
               ? std::string("{\"type\":\"paired\",\"token\":\"tok-xyz\"}")
               : std::string("{\"type\":\"error\",\"message\":\"unexpected\"}");
  });

  reashoot::HelperConnection connection;
  connection.host = "127.0.0.1";
  connection.controlPort = server.port();

  const reashoot::ProcessResult result = reashoot::runVideoSyncCommand(
      helperExecutablePath(), "pair", connection, {L"--code", L"1234"}, withTimeout());

  require(result.started, "helper should start");
  require(!result.timedOut, "helper should not time out");
  require(result.exitCode == 0, "helper pair should exit cleanly");
  require(reashoot::parsePairedToken(result.standardOutput) == "tok-xyz",
          "helper stdout should report the paired token");
  require(server.receivedCommand().find("\"pairingCode\":\"1234\"") != std::string::npos,
          "helper should forward the pairing code to the phone");
}

void launchesHelperPingEndToEnd() {
  LoopbackWebSocketServer server(
      [](const std::string &) { return std::string("{\"type\":\"pong\"}"); });

  reashoot::HelperConnection connection;
  connection.host = "127.0.0.1";
  connection.controlPort = server.port();

  const reashoot::ProcessResult result =
      reashoot::runVideoSyncCommand(helperExecutablePath(), "ping", connection, {}, withTimeout());

  require(result.started, "helper should start");
  require(result.exitCode == 0, "helper ping should exit cleanly");
  require(result.standardOutput.find("pong") != std::string::npos,
          "helper stdout should report pong");
}

void reportsConnectionFailure() {
  reashoot::HelperConnection connection;
  connection.host = "127.0.0.1";
  connection.controlPort = 1; // virtually always refused

  const reashoot::ProcessResult result =
      reashoot::runVideoSyncCommand(helperExecutablePath(), "ping", connection, {}, withTimeout());

  require(result.started, "helper should start even when the phone is unreachable");
  require(result.exitCode != 0, "helper should exit non-zero on connection failure");
  require(result.standardError.find("error:") != std::string::npos,
          "helper should print an error on connection failure");
}

void reportsMissingArgument() {
  reashoot::HelperConnection connection;
  connection.host = "127.0.0.1";
  connection.controlPort = 1;

  const reashoot::ProcessResult result =
      reashoot::runVideoSyncCommand(helperExecutablePath(), "pair", connection, {}, withTimeout());

  require(result.started, "helper should start");
  require(result.exitCode == 2, "missing required argument should exit with code 2");
  require(result.standardError.find("missing required argument --code") != std::string::npos,
          "helper should name the missing argument");
}

} // namespace

int main() {
  WSADATA data{};
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
    std::cerr << "helper_launcher_tests failed: WSAStartup\n";
    return EXIT_FAILURE;
  }

  int result = EXIT_SUCCESS;
  try {
    buildsArgumentsMirroringPlugin();
    parsesPairedToken();
    parsesDownloadedPath();
    parsesDeviceFields();
    launchesHelperPairEndToEnd();
    launchesHelperPingEndToEnd();
    reportsConnectionFailure();
    reportsMissingArgument();
  } catch (const std::exception &error) {
    std::cerr << "helper_launcher_tests failed: " << error.what() << '\n';
    result = EXIT_FAILURE;
  }

  WSACleanup();
  return result;
}
