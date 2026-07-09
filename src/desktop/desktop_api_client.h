#pragma once

#include "../core/json_value.h"

#include <functional>
#include <stdexcept>
#include <string>

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

private:
  DesktopApiRegistration loadOrStartRegistration() const;
  std::string performRequest(const DesktopApiRegistration &registration,
                             const std::string &method,
                             const std::string &path,
                             const std::string &body) const;
  void waitUntilRecordingStarted();
  std::string waitForDownloadedOperation(const std::string &operationID, DesktopApiProgressCallback progress);

  DesktopApiClientOptions options_;
};

std::string desktopDownloadBody(const std::string &downloadDirectory);
std::string desktopOperationIDFromResponse(const std::string &body);

} // namespace reashoot::desktop
