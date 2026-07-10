#pragma once

#include "../core/json_value.h"
#include "../core/remote_camera.h"

#include <functional>
#include <stdexcept>
#include <string>
#include <vector>

namespace reashoot::desktop {

class DesktopApiError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

struct DesktopApiRegistration {
  std::string host = "127.0.0.1";
  int port = 0;
  std::string token;
  std::string baseUrl;
  std::string appPath;
};

struct DesktopApiClientOptions {
  int connectTimeoutSeconds = 10;
  int launchWaitAttempts = 40;
  int launchWaitMilliseconds = 500;
  int recordingStartAttempts = 60;
  int recordingStartWaitMilliseconds = 500;
  int operationAttempts = 600;
  int operationWaitMilliseconds = 1000;
};

using DesktopApiProgressCallback = std::function<void(const std::string &)>;

class DesktopApiClient {
public:
  explicit DesktopApiClient(DesktopApiClientOptions options = {});

  static std::string registrationPath();
  static bool loadRegistration(DesktopApiRegistration &registration);
  static void launchDesktopApp(const std::string &appPath = {});

  std::string request(const std::string &method, const std::string &path, const std::string &body = {});
  void startRecording();
  std::string stopRecordingAndDownload(const std::string &downloadDirectory, DesktopApiProgressCallback progress = {});

  // Ensures the ReaShoot desktop app is running and its API is reachable,
  // launching it if necessary. Throws DesktopApiError if it cannot be reached.
  void ensureDesktopAppRunning();
  // Stops the active recording without downloading it, leaving it on the phone,
  // and returns the resulting recording descriptor.
  core::RemoteRecordingDescriptor stopRecording();
  // Downloads a previously stopped recording by id and returns its local path.
  std::string downloadRecording(const std::string &recordingID,
                               const std::string &downloadDirectory,
                               DesktopApiProgressCallback progress = {});
  // Deletes a recording from the phone by id.
  void deleteRecording(const std::string &recordingID);
  std::vector<core::RemoteRecordingDescriptor> listRecordings();

 private:
  DesktopApiRegistration loadOrStartRegistration() const;
  std::string performRequest(const DesktopApiRegistration &registration,
                            const std::string &method,
                            const std::string &path,
                            const std::string &body) const;
  void waitUntilRecordingStarted();
  core::RemoteRecordingDescriptor waitForStoppedRecording(const std::vector<std::string> &knownIDsBeforeStop);
  std::string waitForDownloadedOperation(const std::string &operationID, DesktopApiProgressCallback progress);

  DesktopApiClientOptions options_;
};

std::string desktopDownloadBody(const std::string &downloadDirectory);
std::string desktopOperationIDFromResponse(const std::string &body);

} // namespace reashoot::desktop
