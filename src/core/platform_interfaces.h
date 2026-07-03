#pragma once

#include "helper_output_parser.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace reashoot::core {

struct CommandResult {
  int exitCode = 0;
  std::string output;
  std::string errorMessage;
};

using ProgressCallback = std::function<void(const std::string &)>;
using CompletionCallback = std::function<void(CommandResult)>;

class AsyncCommandHandle {
public:
  virtual ~AsyncCommandHandle() = default;
  virtual bool isRunning() const = 0;
  virtual int processIdentifier() const = 0;
  virtual void terminate() = 0;
};

class HelperProcess {
public:
  virtual ~HelperProcess() = default;
  virtual CommandResult run(const std::string &command, const std::vector<std::string> &arguments) = 0;
  virtual std::shared_ptr<AsyncCommandHandle> runAsync(const std::string &command,
                                                       const std::vector<std::string> &arguments,
                                                       ProgressCallback progress,
                                                       CompletionCallback completion) = 0;
};

class PreviewRenderer {
public:
  virtual ~PreviewRenderer() = default;
  virtual void reset() = 0;
  virtual void renderAnnexBAccessUnit(const uint8_t *bytes, size_t length) = 0;
};

class MediaAudioReader {
public:
  virtual ~MediaAudioReader() = default;
  virtual std::vector<double> readMonoSamples(const std::string &path, double sourceStart, double duration, int sampleRate) = 0;
};

} // namespace reashoot::core
