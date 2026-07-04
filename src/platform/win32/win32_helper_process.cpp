#include "win32_helper_process.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <atomic>
#include <mutex>
#include <sstream>
#include <thread>
#include <utility>
#include <vector>

namespace reashoot::platform::win32 {
namespace {

std::string quoteArgument(const std::string &argument) {
  if (argument.empty()) {
    return "\"\"";
  }
  const bool needsQuotes = argument.find_first_of(" \t\n\v\"") != std::string::npos;
  if (!needsQuotes) {
    return argument;
  }
  std::string quoted = "\"";
  size_t backslashes = 0;
  for (char ch : argument) {
    if (ch == '\\') {
      ++backslashes;
    } else if (ch == '"') {
      quoted.append(backslashes * 2 + 1, '\\');
      quoted.push_back(ch);
      backslashes = 0;
    } else {
      quoted.append(backslashes, '\\');
      quoted.push_back(ch);
      backslashes = 0;
    }
  }
  quoted.append(backslashes * 2, '\\');
  quoted.push_back('"');
  return quoted;
}

std::string commandLineFor(const std::string &executablePath, const std::vector<std::string> &arguments) {
  std::string commandLine = quoteArgument(executablePath);
  for (const std::string &argument : arguments) {
    commandLine.push_back(' ');
    commandLine += quoteArgument(argument);
  }
  return commandLine;
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
    } else {
      stream << arguments[index];
      if (arguments[index] == "--token") {
        redactNext = true;
      }
    }
  }
  return stream.str();
}

std::string redactedOutput(std::string output) {
  constexpr const char *prefix = "token=";
  size_t position = 0;
  while ((position = output.find(prefix, position)) != std::string::npos) {
    const size_t valueStart = position + std::char_traits<char>::length(prefix);
    size_t valueEnd = valueStart;
    while (valueEnd < output.size() && output[valueEnd] != ' ' && output[valueEnd] != '\t' &&
           output[valueEnd] != '\r' && output[valueEnd] != '\n') {
      ++valueEnd;
    }
    output.replace(valueStart, valueEnd - valueStart, "REDACTED");
    position = valueStart + std::char_traits<char>::length("REDACTED");
  }
  return output;
}

std::vector<std::string> commandArguments(const std::string &command, const std::vector<std::string> &arguments) {
  std::vector<std::string> allArguments;
  allArguments.reserve(arguments.size() + 1);
  allArguments.push_back(command);
  allArguments.insert(allArguments.end(), arguments.begin(), arguments.end());
  return allArguments;
}

struct AsyncState {
  std::atomic<bool> running{false};
  mutable std::mutex mutex;
  HANDLE process = nullptr;
  DWORD processID = 0;
};

class Win32AsyncCommandHandle final : public core::AsyncCommandHandle {
public:
  explicit Win32AsyncCommandHandle(std::shared_ptr<AsyncState> state) : state_(std::move(state)) {}

  bool isRunning() const override { return state_ && state_->running.load(); }

  int processIdentifier() const override {
    return state_ ? static_cast<int>(state_->processID) : 0;
  }

  void terminate() override {
    if (!state_) {
      return;
    }
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (state_->process && state_->running.load()) {
      TerminateProcess(state_->process, 1);
    }
  }

private:
  std::shared_ptr<AsyncState> state_;
};

class Win32HelperProcess final : public core::HelperProcess {
public:
  Win32HelperProcess(std::string executablePath, HelperLogCallback log)
      : executablePath_(std::move(executablePath)), log_(std::move(log)) {}

  core::CommandResult run(const std::string &command, const std::vector<std::string> &arguments) override {
    return runProcess(command, arguments, {});
  }

  std::shared_ptr<core::AsyncCommandHandle> runAsync(const std::string &command,
                                                     const std::vector<std::string> &arguments,
                                                     core::ProgressCallback progress,
                                                     core::CompletionCallback completion) override {
    auto state = std::make_shared<AsyncState>();
    auto handle = std::make_shared<Win32AsyncCommandHandle>(state);
    std::thread([this, state, command, arguments, progress = std::move(progress), completion = std::move(completion)]() mutable {
      core::CommandResult result = runProcess(command, arguments, std::move(progress), state);
      if (completion) {
        completion(std::move(result));
      }
    }).detach();
    return handle;
  }

private:
  bool isExecutable() const {
    const DWORD attributes = GetFileAttributesA(executablePath_.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
  }

  void log(const std::string &message) const {
    if (log_) {
      log_(message);
    }
  }

  core::CommandResult runProcess(const std::string &command,
                                 const std::vector<std::string> &arguments,
                                 core::ProgressCallback progress,
                                 std::shared_ptr<AsyncState> asyncState = {}) const {
    core::CommandResult result;
    if (!isExecutable()) {
      result.exitCode = -1;
      result.errorMessage = "The bundled reashoot-win helper is missing. Install it next to reaper_reashoot.dll.";
      return result;
    }

    std::vector<std::string> allArguments = commandArguments(command, arguments);
    log("helper start command=" + command + " args=" + redactedArguments(allArguments));

    SECURITY_ATTRIBUTES security = {};
    security.nLength = sizeof(security);
    security.bInheritHandle = TRUE;
    HANDLE readPipe = nullptr;
    HANDLE writePipe = nullptr;
    if (!CreatePipe(&readPipe, &writePipe, &security, 0)) {
      result.exitCode = -1;
      result.errorMessage = "Could not create helper output pipe.";
      return result;
    }
    SetHandleInformation(readPipe, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOA startup = {};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdOutput = writePipe;
    startup.hStdError = writePipe;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    PROCESS_INFORMATION process = {};
    std::string commandLine = commandLineFor(executablePath_, allArguments);
    const BOOL created = CreateProcessA(executablePath_.c_str(),
                                        commandLine.data(),
                                        nullptr,
                                        nullptr,
                                        TRUE,
                                        CREATE_NO_WINDOW,
                                        nullptr,
                                        nullptr,
                                        &startup,
                                        &process);
    CloseHandle(writePipe);
    if (!created) {
      CloseHandle(readPipe);
      result.exitCode = -1;
      result.errorMessage = "Could not launch reashoot-win helper.";
      return result;
    }

    if (asyncState) {
      std::lock_guard<std::mutex> lock(asyncState->mutex);
      asyncState->process = process.hProcess;
      asyncState->processID = process.dwProcessId;
      asyncState->running = true;
    }

    std::string pendingLine;
    char buffer[4096] = {};
    DWORD bytesRead = 0;
    while (ReadFile(readPipe, buffer, sizeof(buffer), &bytesRead, nullptr) && bytesRead > 0) {
      result.output.append(buffer, bytesRead);
      if (progress) {
        for (DWORD index = 0; index < bytesRead; ++index) {
          const char ch = buffer[index];
          if (ch == '\n') {
            if (!pendingLine.empty() && pendingLine.back() == '\r') {
              pendingLine.pop_back();
            }
            if (!pendingLine.empty()) {
              progress(pendingLine);
            }
            pendingLine.clear();
          } else {
            pendingLine.push_back(ch);
          }
        }
      }
    }
    if (progress && !pendingLine.empty()) {
      progress(pendingLine);
    }

    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD exitCode = 0;
    GetExitCodeProcess(process.hProcess, &exitCode);
    result.exitCode = static_cast<int>(exitCode);
    if (result.exitCode != 0 && result.output.empty()) {
      result.errorMessage = "reashoot-win failed.";
    }
    log("helper finish command=" + command + " status=" + std::to_string(result.exitCode) + " output=" + redactedOutput(result.output));

    if (asyncState) {
      std::lock_guard<std::mutex> lock(asyncState->mutex);
      asyncState->running = false;
      asyncState->process = nullptr;
    }
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(readPipe);
    return result;
  }

  std::string executablePath_;
  HelperLogCallback log_;
};

} // namespace

std::unique_ptr<core::HelperProcess> createHelperProcess(std::string executablePath, HelperLogCallback log) {
  return std::make_unique<Win32HelperProcess>(std::move(executablePath), std::move(log));
}

} // namespace reashoot::platform::win32
