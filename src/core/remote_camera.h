#pragma once

#include "capture_profile.h"
#include "helper_output_parser.h"
#include "platform_interfaces.h"

#include <memory>
#include <string>
#include <vector>

namespace reashoot::core {

struct RemoteCameraSettings {
  std::string host;
  std::string controlPort = "8787";
  std::string httpPort = "8788";
  std::string token;
  std::string resolution = "4K";
  std::string fps = "30";
  std::string orientation = "portrait";
  std::string aspect = "9:16";
  std::string lens = "wide";
  std::string zoom = "1.0";
  std::string look = "natural";
};

struct RemoteRecordingDescriptor {
  std::string id;
  std::string filename = "recording.mov";
  std::string byteCount = "0";
  std::string downloadPath;
  std::string checksum;
};

struct PreviewStreamDescriptor {
  std::string streamPath = "/preview";
  int port = 8789;
};

CaptureProfile captureProfileFromSettings(const RemoteCameraSettings &settings);
std::vector<std::string> commandArguments(const RemoteCameraSettings &settings,
                                          const std::string &command,
                                          const std::vector<std::string> &extraArguments = {});
std::vector<std::string> configureArguments(const RemoteCameraSettings &settings);
std::vector<std::string> startArguments(const RemoteCameraSettings &settings, const std::string &sessionID);
std::vector<std::string> stopArguments(const RemoteCameraSettings &settings);
std::vector<std::string> tokenArguments(const RemoteCameraSettings &settings);
std::vector<std::string> recordingIDArguments(const RemoteCameraSettings &settings, const std::string &recordingID);
std::vector<std::string> downloadArguments(const RemoteCameraSettings &settings,
                                           const RemoteRecordingDescriptor &recording,
                                           const std::string &downloadDirectory);
RemoteRecordingDescriptor recordingDescriptorFromFields(const FieldMap &fields);
PreviewStreamDescriptor previewStreamDescriptorFromFields(const FieldMap &fields);

class RemoteCameraController {
public:
  explicit RemoteCameraController(HelperProcess &helper) : helper_(helper) {}

  CommandResult run(const RemoteCameraSettings &settings,
                    const std::string &command,
                    const std::vector<std::string> &extraArguments = {});
  std::shared_ptr<AsyncCommandHandle> runAsync(const RemoteCameraSettings &settings,
                                               const std::string &command,
                                               const std::vector<std::string> &extraArguments,
                                               ProgressCallback progress,
                                               CompletionCallback completion);

  CommandResult configure(const RemoteCameraSettings &settings);
  CommandResult start(const RemoteCameraSettings &settings, const std::string &sessionID);
  std::shared_ptr<AsyncCommandHandle> stop(const RemoteCameraSettings &settings, CompletionCallback completion);
  std::shared_ptr<AsyncCommandHandle> listRecordings(const RemoteCameraSettings &settings, CompletionCallback completion);
  std::shared_ptr<AsyncCommandHandle> deleteRecording(const RemoteCameraSettings &settings,
                                                       const std::string &recordingID,
                                                       CompletionCallback completion);
  std::shared_ptr<AsyncCommandHandle> downloadRecording(const RemoteCameraSettings &settings,
                                                         const RemoteRecordingDescriptor &recording,
                                                         const std::string &downloadDirectory,
                                                         ProgressCallback progress,
                                                         CompletionCallback completion);

private:
  HelperProcess &helper_;
};

} // namespace reashoot::core
