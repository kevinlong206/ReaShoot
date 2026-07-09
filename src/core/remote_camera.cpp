#include "remote_camera.h"

#include "camera_transport/control_client.h"
#include "camera_transport/discovery.h"
#include "camera_transport/downloader.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <future>
#include <sstream>
#include <thread>
#include <utility>

#ifdef __APPLE__
#include <dispatch/dispatch.h>
#endif

namespace reashoot::core {
namespace {

class ThreadAsyncCommandHandle final : public AsyncCommandHandle {
public:
  bool isRunning() const override { return running_.load(); }
  int processIdentifier() const override { return 0; }
  void terminate() override { terminated_.store(true); }
  bool isTerminated() const { return terminated_.load(); }
  void setRunning(bool running) { running_.store(running); }

private:
  std::atomic<bool> running_{true};
  std::atomic<bool> terminated_{false};
};

std::string valueAfter(const std::vector<std::string> &arguments, const std::string &flag) {
  for (size_t index = 0; index + 1 < arguments.size(); ++index) {
    if (arguments[index] == flag) {
      return arguments[index + 1];
    }
  }
  return {};
}

int intAfter(const std::vector<std::string> &arguments, const std::string &flag, int fallback) {
  const std::string value = valueAfter(arguments, flag);
  return value.empty() ? fallback : std::atoi(value.c_str());
}

int intFromText(const std::string &value, int fallback) {
  return value.empty() ? fallback : std::atoi(value.c_str());
}

std::string recordingLine(const ProtocolRecording &recording) {
  std::ostringstream stream;
  stream << "recording"
         << "\tid=" << recording.id
         << "\tfilename=" << recording.filename
         << "\tbyteCount=" << recording.byteCount
         << "\tdownloadPath=" << recording.downloadPath;
  if (!recording.createdAt.empty()) {
    stream << "\tcreatedAt=" << recording.createdAt;
  }
  if (!recording.thumbnailPath.empty()) {
    stream << "\tthumbnailPath=" << recording.thumbnailPath;
  }
  if (!recording.checksumSHA256.empty()) {
    stream << "\tchecksum=" << recording.checksumSHA256;
  }
  stream << "\n";
  return stream.str();
}

std::string previewLine(const ProtocolPreview &preview) {
  std::ostringstream stream;
  stream << "preview"
         << "\tcodec=" << preview.codec
         << "\ttransport=" << preview.transport
         << "\tstreamPath=" << preview.streamPath
         << "\tport=" << preview.port
         << "\twidth=" << preview.width
         << "\theight=" << preview.height
         << "\tfps=" << preview.fps
         << "\torientation=" << preview.orientation
         << "\tresolvedOrientation=" << preview.resolvedOrientation
         << "\tdisplayWidth=" << preview.displayWidth
         << "\tdisplayHeight=" << preview.displayHeight
         << "\tdisplayAspectRatio=" << preview.displayAspectRatio
         << "\tmetadataVersion=" << preview.metadataVersion
         << "\n";
  return stream.str();
}

std::string discoveryOutput(int timeoutSeconds) {
  std::ostringstream stream;
  for (const auto &phone : transport::discoverPhones(timeoutSeconds)) {
    stream << "device"
           << "\tname=" << phone.name
           << "\thost=" << phone.host
           << "\tcontrolPort=" << phone.controlPort
           << "\thttpPort=" << phone.httpPort
           << "\tpaired=" << (phone.isPaired ? "true" : "false")
           << "\n";
  }
  return stream.str();
}

ProtocolCaptureProfile protocolProfileFromSettings(const RemoteCameraSettings &settings) {
  ProtocolCaptureProfile profile;
  profile.resolution = settings.resolution.empty() ? profile.resolution : settings.resolution;
  profile.fps = intFromText(settings.fps, profile.fps);
  profile.orientation = settings.orientation.empty() ? profile.orientation : settings.orientation;
  profile.aspectRatio = settings.aspect.empty() ? profile.aspectRatio : settings.aspect;
  profile.lens = settings.lens.empty() ? profile.lens : settings.lens;
  profile.zoomFactor = settings.zoom.empty() ? profile.zoomFactor : std::atof(settings.zoom.c_str());
  profile.look = settings.look.empty() ? profile.look : settings.look;
  profile.encodeLookAtRecordTime = settings.encodeLookAtRecordTime;
  return profile;
}

ProtocolCommand commandFor(const RemoteCameraSettings &settings,
                           const std::string &commandName,
                           const std::vector<std::string> &arguments) {
  ProtocolCommand command;
  command.requestID = transport::randomUUID();
  if (commandName == "pair") {
    command.type = "pair";
    const std::string clientName = valueAfter(arguments, "--client-name");
    if (!clientName.empty()) {
      command.metadata["clientName"] = clientName;
    }
  } else if (commandName == "configure") {
    command.type = "configureCapture";
    command.token = settings.token;
    command.captureProfile = protocolProfileFromSettings(settings);
    command.hasCaptureProfile = true;
  } else if (commandName == "start") {
    command.type = "startRecording";
    command.token = settings.token;
    command.sessionID = valueAfter(arguments, "--session");
  } else if (commandName == "stop-only") {
    command.type = "stopRecording";
    command.token = settings.token;
  } else if (commandName == "list-recordings") {
    command.type = "listRecordings";
    command.token = settings.token;
  } else if (commandName == "delete-recording") {
    command.type = "deleteRecording";
    command.token = settings.token;
    command.recordingID = valueAfter(arguments, "--recording-id");
  } else if (commandName == "ping") {
    command.type = "ping";
    command.token = settings.token;
  } else if (commandName == "start-preview") {
    command.type = "startPreview";
    command.token = settings.token;
  } else if (commandName == "stop-preview") {
    command.type = "stopPreview";
    command.token = settings.token;
  } else if (commandName == "prepare-recording") {
    command.type = "prepareRecording";
    command.token = settings.token;
    command.recordingID = valueAfter(arguments, "--recording-id");
  } else {
    throw transport::TransportError("Unsupported iPhone command: " + commandName);
  }
  return command;
}

void requireEventType(const ProtocolEvent &event, const std::string &type) {
  if (event.type != type) {
    throw transport::TransportError(event.message.empty() ? ("Unexpected control event: " + event.type) : event.message);
  }
}

std::string outputForEvent(const std::string &commandName, const ProtocolEvent &event) {
  if (commandName == "pair") {
    requireEventType(event, "paired");
    if (event.token.empty()) {
      throw transport::TransportError("Pairing did not return a token.");
    }
    return "paired token=" + event.token + "\n";
  }
  if (commandName == "configure") {
    requireEventType(event, "captureConfigured");
    return (event.message.empty() ? event.type : event.message) + "\n";
  }
  if (commandName == "start") {
    requireEventType(event, "recordingStarted");
    return (event.message.empty() ? event.type : event.message) + "\n";
  }
  if (commandName == "stop-only" || commandName == "prepare-recording") {
    requireEventType(event, commandName == "stop-only" ? "recordingStopped" : "recordingPrepared");
    if (!event.hasRecording) {
      throw transport::TransportError("Recording response did not include recording details.");
    }
    return recordingLine(event.recording);
  }
  if (commandName == "list-recordings") {
    requireEventType(event, "recordingsListed");
    std::string output;
    for (const auto &recording : event.recordings) {
      output += recordingLine(recording);
    }
    return output;
  }
  if (commandName == "delete-recording") {
    requireEventType(event, "recordingDeleted");
    return (event.message.empty() ? "recording deleted" : event.message) + "\n";
  }
  if (commandName == "ping") {
    requireEventType(event, "pong");
    return (event.message.empty() ? event.type : event.message) + "\n";
  }
  if (commandName == "start-preview") {
    requireEventType(event, "previewStarted");
    if (!event.hasPreview) {
      throw transport::TransportError("Preview response did not include stream details.");
    }
    return previewLine(event.preview);
  }
  if (commandName == "stop-preview") {
    requireEventType(event, "previewStopped");
    return (event.message.empty() ? event.type : event.message) + "\n";
  }
  return {};
}

transport::ControlClient controlClientFor(const RemoteCameraSettings &settings, int timeoutSeconds = 20) {
  return transport::ControlClient(settings.host, intFromText(settings.controlPort, 8787), timeoutSeconds);
}

ProtocolRecording prepareRecording(const RemoteCameraSettings &settings,
                                   const std::string &recordingID,
                                   ProgressCallback progress) {
  const transport::ControlClient client = controlClientFor(settings, 900);
  const transport::ControlClient progressClient = controlClientFor(settings, 5);
  auto preparation = std::async(std::launch::async, [&client, token = settings.token, recordingID]() {
    ProtocolCommand command;
    command.requestID = transport::randomUUID();
    command.type = "prepareRecording";
    command.token = token;
    command.recordingID = recordingID;
    const ProtocolEvent event = client.send(command);
    requireEventType(event, "recordingPrepared");
    if (!event.hasRecording) {
      throw transport::TransportError("Prepare response did not include recording details.");
    }
    return event.recording;
  });

  int lastTenths = -1;
  while (preparation.wait_for(std::chrono::milliseconds(250)) != std::future_status::ready) {
    if (!progress) {
      continue;
    }
    try {
      ProtocolCommand ping;
      ping.requestID = transport::randomUUID();
      ping.type = "ping";
      ping.token = settings.token;
      const ProtocolEvent event = progressClient.send(ping);
      if (event.hasCaptureProgress && (event.captureStatus == "encoding" || event.captureStatus == "applyingLook")) {
        const double normalized = event.captureProgress <= 1.0 ? event.captureProgress * 100.0 : event.captureProgress;
        const int tenths = static_cast<int>((std::max)(0.0, (std::min)(100.0, normalized)) * 10.0);
        if (tenths != lastTenths) {
          lastTenths = tenths;
          std::ostringstream line;
          line.setf(std::ios::fixed);
          line.precision(1);
          line << "encode percent=" << (std::min)(100.0, (std::max)(0.0, normalized));
          progress(line.str());
        }
      }
    } catch (const std::exception &) {
    }
  }
  return preparation.get();
}

void acknowledgeTransfer(const RemoteCameraSettings &settings, const std::string &recordingID) {
  ProtocolCommand command;
  command.requestID = transport::randomUUID();
  command.type = "transferComplete";
  command.token = settings.token;
  command.recordingID = recordingID;
  const ProtocolEvent event = controlClientFor(settings).send(command);
  requireEventType(event, "transferAcknowledged");
}

void dispatchProgress(ProgressCallback progress, std::string line) {
  if (!progress) {
    return;
  }
#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    progress(line);
  });
#else
  progress(line);
#endif
}

void dispatchCompletion(CompletionCallback completion, CommandResult result) {
  if (!completion) {
    return;
  }
#ifdef __APPLE__
  dispatch_async(dispatch_get_main_queue(), ^{
    completion(std::move(result));
  });
#else
  completion(std::move(result));
#endif
}

} // namespace

CaptureProfile captureProfileFromSettings(const RemoteCameraSettings &settings) {
  return CaptureProfile{
      settings.token,
      settings.resolution,
      settings.fps,
      settings.orientation,
      settings.aspect,
      settings.lens,
      settings.zoom,
      settings.look,
      settings.encodeLookAtRecordTime,
  };
}

std::vector<std::string> commandArguments(const RemoteCameraSettings &settings,
                                          const std::string &command,
                                          const std::vector<std::string> &extraArguments) {
  std::vector<std::string> arguments;
  if (command != "discover") {
    arguments.insert(arguments.end(), {"--host", settings.host, "--port", settings.controlPort});
  }
  arguments.insert(arguments.end(), extraArguments.begin(), extraArguments.end());
  return arguments;
}

std::vector<std::string> configureArguments(const RemoteCameraSettings &settings) {
  return captureProfileArguments(captureProfileFromSettings(settings));
}

std::vector<std::string> startArguments(const RemoteCameraSettings &settings, const std::string &sessionID) {
  return {"--token", settings.token, "--session", sessionID};
}

std::vector<std::string> stopArguments(const RemoteCameraSettings &settings) {
  return tokenArguments(settings);
}

std::vector<std::string> tokenArguments(const RemoteCameraSettings &settings) {
  return {"--token", settings.token};
}

std::vector<std::string> recordingIDArguments(const RemoteCameraSettings &settings, const std::string &recordingID) {
  return {"--token", settings.token, "--recording-id", recordingID};
}

std::vector<std::string> downloadArguments(const RemoteCameraSettings &settings,
                                           const RemoteRecordingDescriptor &recording,
                                           const std::string &downloadDirectory) {
  std::vector<std::string> arguments = {
      "--http-port",
      settings.httpPort,
      "--token",
      settings.token,
      "--recording-id",
      recording.id,
      "--filename",
      recording.filename.empty() ? "recording.mov" : recording.filename,
      "--byte-count",
      recording.byteCount.empty() ? "0" : recording.byteCount,
      "--download-path",
      recording.downloadPath,
      "--download-dir",
      downloadDirectory,
      "--progress",
  };
  if (!recording.checksum.empty()) {
    arguments.insert(arguments.end(), {"--checksum", recording.checksum});
  }
  return arguments;
}

RemoteRecordingDescriptor recordingDescriptorFromFields(const FieldMap &fields) {
  RemoteRecordingDescriptor descriptor;
  auto value = [&fields](const char *key) -> std::string {
    auto it = fields.find(key);
    return it == fields.end() ? "" : it->second;
  };
  descriptor.id = value("id");
  descriptor.filename = value("filename");
  if (descriptor.filename.empty()) {
    descriptor.filename = "recording.mov";
  }
  descriptor.byteCount = value("byteCount");
  if (descriptor.byteCount.empty()) {
    descriptor.byteCount = "0";
  }
  descriptor.downloadPath = value("downloadPath");
  descriptor.checksum = value("checksum");
  descriptor.createdAt = value("createdAt");
  descriptor.thumbnailPath = value("thumbnailPath");
  return descriptor;
}

PreviewStreamDescriptor previewStreamDescriptorFromFields(const FieldMap &fields) {
  PreviewStreamDescriptor descriptor;
  auto value = [&fields](const char *key) -> std::string {
    auto it = fields.find(key);
    return it == fields.end() ? "" : it->second;
  };
  const std::string streamPath = value("streamPath");
  if (!streamPath.empty()) {
    descriptor.streamPath = streamPath;
  }
  const std::string portText = value("port");
  if (!portText.empty()) {
    const int port = std::atoi(portText.c_str());
    if (port > 0) {
      descriptor.port = port;
    }
  }
  const std::string widthText = value("width");
  if (!widthText.empty()) {
    const int width = std::atoi(widthText.c_str());
    if (width > 0) {
      descriptor.width = width;
    }
  }
  const std::string heightText = value("height");
  if (!heightText.empty()) {
    const int height = std::atoi(heightText.c_str());
    if (height > 0) {
      descriptor.height = height;
    }
  }
  const std::string fpsText = value("fps");
  if (!fpsText.empty()) {
    const int fps = std::atoi(fpsText.c_str());
    if (fps > 0) {
      descriptor.fps = fps;
    }
  }
  const std::string orientation = value("orientation");
  if (!orientation.empty()) {
    descriptor.orientation = orientation;
  }
  descriptor.resolvedOrientation = value("resolvedOrientation");
  const std::string displayWidthText = value("displayWidth");
  if (!displayWidthText.empty()) {
    const int displayWidth = std::atoi(displayWidthText.c_str());
    if (displayWidth > 0) {
      descriptor.displayWidth = displayWidth;
    }
  }
  const std::string displayHeightText = value("displayHeight");
  if (!displayHeightText.empty()) {
    const int displayHeight = std::atoi(displayHeightText.c_str());
    if (displayHeight > 0) {
      descriptor.displayHeight = displayHeight;
    }
  }
  descriptor.displayAspectRatio = value("displayAspectRatio");
  const std::string metadataVersionText = value("metadataVersion");
  if (!metadataVersionText.empty()) {
    const int metadataVersion = std::atoi(metadataVersionText.c_str());
    if (metadataVersion > 0) {
      descriptor.metadataVersion = metadataVersion;
    }
  }
  return descriptor;
}

CommandResult RemoteCameraController::run(const RemoteCameraSettings &settings,
                                          const std::string &command,
                                          const std::vector<std::string> &extraArguments) {
  try {
    if (command == "discover") {
      return {0, discoveryOutput(intAfter(extraArguments, "--timeout", 3)), ""};
    }
    const int timeout = command == "pair" ? 120 : (command == "prepare-recording" ? 900 : 20);
    const ProtocolEvent event = controlClientFor(settings, timeout).send(commandFor(settings, command, extraArguments));
    return {0, outputForEvent(command, event), ""};
  } catch (const std::exception &error) {
    return {1, "", error.what()};
  }
}

std::shared_ptr<AsyncCommandHandle> RemoteCameraController::runAsync(const RemoteCameraSettings &settings,
                                                                      const std::string &command,
                                                                      const std::vector<std::string> &extraArguments,
                                                                      ProgressCallback progress,
                                                                      CompletionCallback completion) {
  auto handle = std::make_shared<ThreadAsyncCommandHandle>();
  std::thread([this,
               handle,
               settings,
               command,
               extraArguments,
               progress = std::move(progress),
               completion = std::move(completion)]() mutable {
    (void)progress;
    CommandResult result = run(settings, command, extraArguments);
    handle->setRunning(false);
    if (!handle->isTerminated()) {
      dispatchCompletion(std::move(completion), std::move(result));
    }
  }).detach();
  return handle;
}

CommandResult RemoteCameraController::configure(const RemoteCameraSettings &settings) {
  return run(settings, "configure", configureArguments(settings));
}

CommandResult RemoteCameraController::start(const RemoteCameraSettings &settings, const std::string &sessionID) {
  return run(settings, "start", startArguments(settings, sessionID));
}

std::shared_ptr<AsyncCommandHandle> RemoteCameraController::stop(const RemoteCameraSettings &settings,
                                                                 CompletionCallback completion) {
  return runAsync(settings, "stop-only", stopArguments(settings), {}, std::move(completion));
}

std::shared_ptr<AsyncCommandHandle> RemoteCameraController::listRecordings(const RemoteCameraSettings &settings,
                                                                           CompletionCallback completion) {
  return runAsync(settings, "list-recordings", tokenArguments(settings), {}, std::move(completion));
}

std::shared_ptr<AsyncCommandHandle> RemoteCameraController::deleteRecording(const RemoteCameraSettings &settings,
                                                                            const std::string &recordingID,
                                                                            CompletionCallback completion) {
  return runAsync(settings, "delete-recording", recordingIDArguments(settings, recordingID), {}, std::move(completion));
}

std::shared_ptr<AsyncCommandHandle> RemoteCameraController::downloadRecording(const RemoteCameraSettings &settings,
                                                                              const RemoteRecordingDescriptor &recording,
                                                                              const std::string &downloadDirectory,
                                                                              ProgressCallback progress,
                                                                              CompletionCallback completion) {
  auto handle = std::make_shared<ThreadAsyncCommandHandle>();
  std::thread([handle,
               settings,
               recording,
               downloadDirectory,
               progress = std::move(progress),
               completion = std::move(completion)]() mutable {
    CommandResult result;
    try {
      const ProtocolRecording prepared = prepareRecording(settings, recording.id, [progress](const std::string &line) {
        dispatchProgress(progress, line);
      });
      const std::string downloaded = transport::downloadRecording(
          prepared,
          settings.host,
          intFromText(settings.httpPort, 8788),
          settings.token,
          downloadDirectory,
          [progress](int64_t bytes, int64_t total) {
            std::ostringstream line;
            line.setf(std::ios::fixed);
            line.precision(1);
            const int64_t expected = (std::max)(total, int64_t{0});
            const double percent = expected > 0
                                       ? (std::min)(100.0, (static_cast<double>(bytes) / static_cast<double>(expected)) * 100.0)
                                       : 0.0;
            line << "progress bytes=" << bytes << " total=" << expected << " percent=" << percent;
            dispatchProgress(progress, line.str());
          });
      try {
        acknowledgeTransfer(settings, prepared.id);
      } catch (const std::exception &) {
      }
      result.output = "downloaded " + downloaded + "\n";
    } catch (const std::exception &error) {
      result.exitCode = 1;
      result.errorMessage = error.what();
    }
    handle->setRunning(false);
    if (!handle->isTerminated()) {
      dispatchCompletion(std::move(completion), std::move(result));
    }
  }).detach();
  return handle;
}

} // namespace reashoot::core
