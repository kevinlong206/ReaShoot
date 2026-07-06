#import <Foundation/Foundation.h>

#include "mac_helper_process.h"

#include <sstream>
#include <utility>

namespace reashoot::platform::mac {
namespace {

NSString *stringFromStd(const std::string &value) {
  return [NSString stringWithUTF8String:value.c_str()] ?: @"";
}

std::string stdFromString(NSString *value) {
  return value.UTF8String ? value.UTF8String : "";
}

NSArray<NSString *> *argumentsArray(const std::vector<std::string> &arguments) {
  NSMutableArray<NSString *> *array = [NSMutableArray arrayWithCapacity:arguments.size()];
  for (const std::string &argument : arguments) {
    [array addObject:stringFromStd(argument)];
  }
  return array;
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
      if (arguments[index] == "--token" || arguments[index] == "--code") {
        redactNext = true;
      }
    }
  }
  return stream.str();
}

std::string outputString(NSData *data) {
  NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  return stdFromString(output ?: @"");
}

class MacAsyncCommandHandle final : public core::AsyncCommandHandle {
public:
  explicit MacAsyncCommandHandle(NSTask *task) : task_(task) {}

  bool isRunning() const override { return task_ && task_.running; }

  int processIdentifier() const override {
    return task_ ? static_cast<int>(task_.processIdentifier) : 0;
  }

  void terminate() override {
    if (task_ && task_.running) {
      [task_ terminate];
    }
  }

private:
  NSTask *__strong task_ = nil;
};

class MacHelperProcess final : public core::HelperProcess {
public:
  MacHelperProcess(std::string executablePath, HelperLogCallback log)
      : executablePath_(std::move(executablePath)), log_(std::move(log)) {}

  core::CommandResult run(const std::string &command, const std::vector<std::string> &arguments) override {
    core::CommandResult result;
    if (!isExecutable()) {
      result.exitCode = -1;
      result.errorMessage = "The bundled reashoot-mac helper is missing. Run make install again.";
      return result;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:stringFromStd(executablePath_)];
    task.arguments = argumentsArray(commandArguments(command, arguments));

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSFileHandle *readHandle = pipe.fileHandleForReading;
    NSMutableData *outputData = [NSMutableData data];
    readHandle.readabilityHandler = ^(NSFileHandle *handle) {
      NSData *chunk = handle.availableData;
      if (chunk.length == 0) {
        return;
      }
      @synchronized(outputData) {
        [outputData appendData:chunk];
      }
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
      readHandle.readabilityHandler = nil;
      result.exitCode = -1;
      result.errorMessage = stdFromString(launchError.localizedDescription ?: @"reashoot-mac failed to launch.");
      return result;
    }

    [task waitUntilExit];
    readHandle.readabilityHandler = nil;
    NSData *remainingData = [readHandle readDataToEndOfFile];
    @synchronized(outputData) {
      if (remainingData.length > 0) {
        [outputData appendData:remainingData];
      }
      result.output = outputString([outputData copy]);
    }
    result.exitCode = task.terminationStatus;
    if (result.exitCode != 0 && result.output.empty()) {
      result.errorMessage = "reashoot-mac failed.";
    }
    return result;
  }

  std::shared_ptr<core::AsyncCommandHandle> runAsync(const std::string &command,
                                                     const std::vector<std::string> &arguments,
                                                     core::ProgressCallback progress,
                                                     core::CompletionCallback completion) override {
    const std::string commandCopy = command;
    auto progressCallback = std::make_shared<core::ProgressCallback>(std::move(progress));
    auto completionCallback = std::make_shared<core::CompletionCallback>(std::move(completion));
    if (!isExecutable()) {
      dispatch_async(dispatch_get_main_queue(), ^{
        (*completionCallback)(core::CommandResult{-1, "", "The bundled reashoot-mac helper is missing. Run make install again."});
      });
      return nullptr;
    }

    std::vector<std::string> allArguments = commandArguments(commandCopy, arguments);
    log("helper async start command=" + commandCopy + " args=" + redactedArguments(allArguments));

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:stringFromStd(executablePath_)];
    task.arguments = argumentsArray(allArguments);

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    NSFileHandle *readHandle = pipe.fileHandleForReading;
    NSMutableData *outputData = [NSMutableData data];
    NSMutableString *pendingLine = [NSMutableString string];

    void (^consumeData)(NSData *) = ^(NSData *data) {
      if (data.length == 0) {
        return;
      }
      @synchronized(outputData) {
        [outputData appendData:data];
      }
      if (!*progressCallback) {
        return;
      }
      NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
      NSArray<NSString *> *parts = [chunk componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
      for (NSUInteger index = 0; index < parts.count; ++index) {
        NSString *part = parts[index];
        if (index == 0) {
          [pendingLine appendString:part];
        } else {
          NSString *line = [pendingLine copy];
          [pendingLine setString:part];
          if (line.length > 0) {
            std::string lineText = stdFromString(line);
            dispatch_async(dispatch_get_main_queue(), ^{
              (*progressCallback)(lineText);
            });
          }
        }
      }
    };

    readHandle.readabilityHandler = ^(NSFileHandle *handle) {
      consumeData(handle.availableData);
    };

    task.terminationHandler = ^(NSTask *finishedTask) {
      readHandle.readabilityHandler = nil;
      consumeData([readHandle readDataToEndOfFile]);
      if (*progressCallback && pendingLine.length > 0) {
        NSString *line = [pendingLine copy];
        [pendingLine setString:@""];
        std::string lineText = stdFromString(line);
        dispatch_async(dispatch_get_main_queue(), ^{
          (*progressCallback)(lineText);
        });
      }

      core::CommandResult result;
      NSData *data = nil;
      @synchronized(outputData) {
        data = [outputData copy];
      }
      result.output = outputString(data);
      result.exitCode = finishedTask.terminationStatus;
      if (result.exitCode != 0 && result.output.empty()) {
        result.errorMessage = "reashoot-mac failed.";
      }
      log("helper async finish command=" + commandCopy + " status=" + std::to_string(result.exitCode) + " output=" + result.output);
      dispatch_async(dispatch_get_main_queue(), ^{
        (*completionCallback)(result);
      });
    };

    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
      std::string message = stdFromString(launchError.localizedDescription ?: @"reashoot-mac failed to launch.");
      log("helper async launch failed command=" + commandCopy + " error=" + message);
      dispatch_async(dispatch_get_main_queue(), ^{
        (*completionCallback)(core::CommandResult{-1, "", message});
      });
      return nullptr;
    }
    return std::make_shared<MacAsyncCommandHandle>(task);
  }

private:
  bool isExecutable() const {
    return [[NSFileManager defaultManager] isExecutableFileAtPath:stringFromStd(executablePath_)];
  }

  std::vector<std::string> commandArguments(const std::string &command, const std::vector<std::string> &arguments) const {
    std::vector<std::string> allArguments;
    allArguments.reserve(arguments.size() + 1);
    allArguments.push_back(command);
    allArguments.insert(allArguments.end(), arguments.begin(), arguments.end());
    return allArguments;
  }

  void log(const std::string &message) const {
    if (log_) {
      log_(message);
    }
  }

  std::string executablePath_;
  HelperLogCallback log_;
};

} // namespace

std::unique_ptr<core::HelperProcess> createHelperProcess(std::string executablePath, HelperLogCallback log) {
  return std::make_unique<MacHelperProcess>(std::move(executablePath), std::move(log));
}

} // namespace reashoot::platform::mac
