#include "reashoot/windows/process_runner.h"

namespace reashoot {

namespace {

void appendQuotedArgument(std::wstring &commandLine, const std::wstring &argument) {
  // Unquoted is fine only when the argument is non-empty and has no delimiters.
  if (!argument.empty() && argument.find_first_of(L" \t\n\v\"") == std::wstring::npos) {
    commandLine += argument;
    return;
  }

  commandLine.push_back(L'"');
  for (auto it = argument.begin();; ++it) {
    unsigned backslashes = 0;
    while (it != argument.end() && *it == L'\\') {
      ++it;
      ++backslashes;
    }

    if (it == argument.end()) {
      // Escape trailing backslashes so they do not escape the closing quote.
      commandLine.append(static_cast<std::size_t>(backslashes) * 2, L'\\');
      break;
    } else if (*it == L'"') {
      // Escape backslashes and the embedded quote.
      commandLine.append(static_cast<std::size_t>(backslashes) * 2 + 1, L'\\');
      commandLine.push_back(*it);
    } else {
      commandLine.append(static_cast<std::size_t>(backslashes), L'\\');
      commandLine.push_back(*it);
    }
  }
  commandLine.push_back(L'"');
}

} // namespace

std::wstring buildWindowsCommandLine(const std::wstring &executable,
                                     const std::vector<std::wstring> &arguments) {
  std::wstring commandLine;
  appendQuotedArgument(commandLine, executable);
  for (const std::wstring &argument : arguments) {
    commandLine.push_back(L' ');
    appendQuotedArgument(commandLine, argument);
  }
  return commandLine;
}

} // namespace reashoot

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <thread>
#include <vector>

namespace reashoot {

namespace {

struct HandleCloser {
  HANDLE handle = nullptr;
  ~HandleCloser() {
    if (handle && handle != INVALID_HANDLE_VALUE) {
      CloseHandle(handle);
    }
  }
};

void drainPipe(HANDLE pipe, std::string *destination) {
  char buffer[4096];
  DWORD read = 0;
  while (ReadFile(pipe, buffer, sizeof(buffer), &read, nullptr) && read > 0) {
    destination->append(buffer, read);
  }
}

} // namespace

ProcessResult runProcess(const std::wstring &executable,
                         const std::vector<std::wstring> &arguments,
                         const ProcessOptions &options) {
  ProcessResult result;

  SECURITY_ATTRIBUTES inheritable{};
  inheritable.nLength = sizeof(inheritable);
  inheritable.bInheritHandle = TRUE;
  inheritable.lpSecurityDescriptor = nullptr;

  HANDLE outRead = nullptr;
  HANDLE outWrite = nullptr;
  HANDLE errRead = nullptr;
  HANDLE errWrite = nullptr;

  if (!CreatePipe(&outRead, &outWrite, &inheritable, 0)) {
    return result;
  }
  HandleCloser outReadCloser{outRead};
  HandleCloser outWriteCloser{outWrite};

  if (!CreatePipe(&errRead, &errWrite, &inheritable, 0)) {
    return result;
  }
  HandleCloser errReadCloser{errRead};
  HandleCloser errWriteCloser{errWrite};

  // The parent reads these ends, so they must not be inherited by the child.
  SetHandleInformation(outRead, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(errRead, HANDLE_FLAG_INHERIT, 0);

  // Give the child a real (empty) stdin so CRT startup does not choke.
  HANDLE nulInput = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                                &inheritable, OPEN_EXISTING, 0, nullptr);
  HandleCloser nulInputCloser{nulInput};

  STARTUPINFOW startupInfo{};
  startupInfo.cb = sizeof(startupInfo);
  startupInfo.dwFlags = STARTF_USESTDHANDLES;
  startupInfo.hStdInput = nulInput;
  startupInfo.hStdOutput = outWrite;
  startupInfo.hStdError = errWrite;

  std::wstring commandLine = buildWindowsCommandLine(executable, arguments);
  std::vector<wchar_t> mutableCommandLine(commandLine.begin(), commandLine.end());
  mutableCommandLine.push_back(L'\0');

  PROCESS_INFORMATION processInfo{};
  const BOOL created = CreateProcessW(
      executable.c_str(), mutableCommandLine.data(), nullptr, nullptr, TRUE,
      CREATE_NO_WINDOW, nullptr, nullptr, &startupInfo, &processInfo);
  if (!created) {
    return result;
  }
  result.started = true;

  // The parent must drop its copies of the write ends so the reader threads see
  // EOF once the child exits.
  CloseHandle(outWrite);
  outWriteCloser.handle = nullptr;
  CloseHandle(errWrite);
  errWriteCloser.handle = nullptr;

  std::thread outThread(drainPipe, outRead, &result.standardOutput);
  std::thread errThread(drainPipe, errRead, &result.standardError);

  const DWORD waitMilliseconds =
      options.timeout ? static_cast<DWORD>(options.timeout->count()) : INFINITE;
  if (WaitForSingleObject(processInfo.hProcess, waitMilliseconds) == WAIT_TIMEOUT) {
    result.timedOut = true;
    TerminateProcess(processInfo.hProcess, 1);
    WaitForSingleObject(processInfo.hProcess, INFINITE);
  }

  outThread.join();
  errThread.join();

  DWORD exitCode = 0;
  GetExitCodeProcess(processInfo.hProcess, &exitCode);
  result.exitCode = static_cast<int>(exitCode);

  CloseHandle(processInfo.hThread);
  CloseHandle(processInfo.hProcess);
  return result;
}

} // namespace reashoot

#endif // _WIN32
