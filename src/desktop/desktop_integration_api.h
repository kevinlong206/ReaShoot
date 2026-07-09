#pragma once

#include "desktop_app_model.h"

#include "../core/json_value.h"
#include "../core/remote_camera.h"

#include <map>
#include <string>
#include <vector>

namespace reashoot::desktop {

constexpr const char *kIntegrationApiVersion = "v1";

struct IntegrationStatus {
  bool paired = false;
  bool previewRunning = false;
  bool previewDesired = false;
  bool recording = false;
  std::string host;
  std::string message;
  core::RemoteCameraSettings profile;
};

struct IntegrationOperation {
  std::string id;
  std::string type;
  std::string state = "idle";
  std::string message;
  std::string downloadedPath;
  core::RemoteRecordingDescriptor recording;
};

struct IntegrationHttpRequest {
  std::string method;
  std::string path;
  std::string query;
  std::map<std::string, std::string> headers;
  std::string body;
};

struct IntegrationHttpResponse {
  int status = 200;
  std::string contentType = "application/json";
  std::map<std::string, std::string> headers;
  std::string body;
};

core::JsonValue profileToJson(const core::RemoteCameraSettings &settings);
void applyProfileJson(core::RemoteCameraSettings &settings, const core::JsonValue &json);
core::JsonValue recordingToJson(const core::RemoteCameraSettings &settings,
                                const core::RemoteRecordingDescriptor &recording);
core::JsonValue recordingsToJson(const core::RemoteCameraSettings &settings,
                                 const std::vector<core::RemoteRecordingDescriptor> &recordings);
core::JsonValue statusToJson(const IntegrationStatus &status);
core::JsonValue operationToJson(const IntegrationOperation &operation);

IntegrationHttpResponse jsonResponse(int status, core::JsonValue::Object object);
IntegrationHttpResponse okResponse(core::JsonValue::Object object = {});
IntegrationHttpResponse acceptedResponse(const std::string &message);
IntegrationHttpResponse errorResponse(int status, const std::string &code, const std::string &message);

bool constantTimeEquals(const std::string &left, const std::string &right);
std::string bearerTokenFromRequest(const IntegrationHttpRequest &request);
bool requestHasValidToken(const IntegrationHttpRequest &request, const std::string &expectedToken);

} // namespace reashoot::desktop
