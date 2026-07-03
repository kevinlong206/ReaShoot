#include "reashoot/windows/process_runner.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <io.h>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

// Child mode: write a large amount to both stdout and stderr so the pipes fill,
// proving the parent drains both concurrently rather than deadlocking.
int runEmitChild() {
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stderr), _O_BINARY);
  const std::size_t total = 200000;
  const std::string outChunk(4096, 'O');
  const std::string errChunk(4096, 'E');
  std::size_t written = 0;
  while (written < total) {
    const std::size_t chunk = std::min<std::size_t>(4096, total - written);
    std::fwrite(outChunk.data(), 1, chunk, stdout);
    std::fwrite(errChunk.data(), 1, chunk, stderr);
    written += chunk;
  }
  std::fflush(stdout);
  std::fflush(stderr);
  return 3;
}

std::wstring selfPath() {
  std::wstring buffer(32768, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  buffer.resize(length);
  return buffer;
}

void quotesCommandLineArguments() {
  require(reashoot::buildWindowsCommandLine(L"prog", {}) == L"prog", "bare program name");
  require(reashoot::buildWindowsCommandLine(L"prog", {L"simple"}) == L"prog simple",
          "plain argument is not quoted");
  require(reashoot::buildWindowsCommandLine(L"prog", {L"hello world"}) == L"prog \"hello world\"",
          "argument with a space is quoted");
  require(reashoot::buildWindowsCommandLine(L"prog", {L""}) == L"prog \"\"",
          "empty argument is quoted");
  require(reashoot::buildWindowsCommandLine(L"C:\\Program Files\\a.exe", {}) ==
              L"\"C:\\Program Files\\a.exe\"",
          "executable with a space is quoted");
  require(reashoot::buildWindowsCommandLine(L"prog", {L"a\"b"}) == L"prog \"a\\\"b\"",
          "embedded quote is escaped");
}

void capturesConcurrentStdoutAndStderr() {
  const reashoot::ProcessResult result = reashoot::runProcess(selfPath(), {L"--emit-child"});
  require(result.started, "child should start");
  require(!result.timedOut, "child should not time out");
  require(result.exitCode == 3, "child exit code should propagate");
  require(result.standardOutput.size() == 200000, "all stdout bytes should be captured");
  require(result.standardError.size() == 200000, "all stderr bytes should be captured");
  require(result.standardOutput.find_first_not_of('O') == std::string::npos,
          "stdout content should be intact");
  require(result.standardError.find_first_not_of('E') == std::string::npos,
          "stderr content should be intact");
}

void reportsTimeout() {
  reashoot::ProcessOptions options;
  options.timeout = std::chrono::milliseconds(300);
  const reashoot::ProcessResult result =
      reashoot::runProcess(selfPath(), {L"--sleep-child"}, options);
  require(result.started, "sleeping child should start");
  require(result.timedOut, "slow child should be reported as timed out");
}

void reportsMissingExecutable() {
  const reashoot::ProcessResult result =
      reashoot::runProcess(L"C:\\this\\path\\does\\not\\exist_reashoot.exe", {});
  require(!result.started, "missing executable should not start");
}

} // namespace

int main(int argc, char **argv) {
  if (argc >= 2) {
    const std::string mode = argv[1];
    if (mode == "--emit-child") {
      return runEmitChild();
    }
    if (mode == "--sleep-child") {
      Sleep(10000);
      return 0;
    }
  }

  try {
    quotesCommandLineArguments();
    capturesConcurrentStdoutAndStderr();
    reportsTimeout();
    reportsMissingExecutable();
  } catch (const std::exception &error) {
    std::cerr << "process_tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
