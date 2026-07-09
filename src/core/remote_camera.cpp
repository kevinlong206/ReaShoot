#include "remote_camera.h"

#include <cstdlib>
#include <utility>

namespace reashoot::core {

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
  return helper_.run(command, commandArguments(settings, command, extraArguments));
}

std::shared_ptr<AsyncCommandHandle> RemoteCameraController::runAsync(const RemoteCameraSettings &settings,
                                                                      const std::string &command,
                                                                      const std::vector<std::string> &extraArguments,
                                                                      ProgressCallback progress,
                                                                      CompletionCallback completion) {
  return helper_.runAsync(command,
                          commandArguments(settings, command, extraArguments),
                          std::move(progress),
                          std::move(completion));
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
  return runAsync(settings,
                  "download-recording",
                  downloadArguments(settings, recording, downloadDirectory),
                  std::move(progress),
                  std::move(completion));
}

} // namespace reashoot::core
