#include "desktop_integration_api.h"

#include <algorithm>

namespace reashoot::desktop {
namespace {

void addString(core::JsonValue::Object &object, const std::string &key, const std::string &value) {
  object.emplace(key, core::JsonValue(value));
}

void addBool(core::JsonValue::Object &object, const std::string &key, bool value) {
  object.emplace(key, core::JsonValue(value));
}

std::string lowerHeaderKey(std::string key) {
  std::transform(key.begin(), key.end(), key.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return key;
}

std::string queryValue(const std::string &query, const std::string &key) {
  size_t position = 0;
  while (position <= query.size()) {
    const size_t end = query.find('&', position);
    const std::string part = query.substr(position, end == std::string::npos ? std::string::npos : end - position);
    const size_t equals = part.find('=');
    if (equals != std::string::npos && part.substr(0, equals) == key) {
      return part.substr(equals + 1);
    }
    if (end == std::string::npos) {
      break;
    }
    position = end + 1;
  }
  return {};
}

} // namespace

core::JsonValue profileToJson(const core::RemoteCameraSettings &settings) {
  core::JsonValue::Object object;
  addString(object, "resolution", settings.resolution);
  addString(object, "fps", settings.fps);
  addString(object, "orientation", settings.orientation);
  addString(object, "aspect", settings.aspect);
  addString(object, "lens", settings.lens);
  addString(object, "zoom", settings.zoom);
  addString(object, "look", settings.look);
  addBool(object, "encodeLookAtRecordTime", settings.encodeLookAtRecordTime);
  return core::JsonValue(std::move(object));
}

void applyProfileJson(core::RemoteCameraSettings &settings, const core::JsonValue &json) {
  settings.resolution = json.stringValue("resolution", settings.resolution);
  settings.fps = json.stringValue("fps", settings.fps);
  settings.orientation = json.stringValue("orientation", settings.orientation);
  settings.aspect = json.stringValue("aspect", settings.aspect);
  settings.lens = json.stringValue("lens", settings.lens);
  settings.zoom = json.stringValue("zoom", settings.zoom);
  settings.look = json.stringValue("look", settings.look);
  settings.encodeLookAtRecordTime = json.boolValue("encodeLookAtRecordTime", settings.encodeLookAtRecordTime);
}

core::JsonValue recordingToJson(const core::RemoteCameraSettings &settings,
                                const core::RemoteRecordingDescriptor &recording) {
  core::JsonValue::Object object;
  addString(object, "id", recording.id);
  addString(object, "filename", recording.filename);
  addString(object, "byteCount", recording.byteCount);
  addString(object, "downloadPath", recording.downloadPath);
  addString(object, "checksum", recording.checksum);
  addString(object, "createdAt", recording.createdAt);
  addString(object, "thumbnailPath", recording.thumbnailPath);
  addString(object, "thumbnailUrl", recordingThumbnailURL(settings, recording));
  addString(object, "timestamp", recordingTimestampFallback(recording));
  return core::JsonValue(std::move(object));
}

core::JsonValue operationToJson(const IntegrationOperation &operation) {
  core::JsonValue::Object object;
  addString(object, "id", operation.id);
  addString(object, "type", operation.type);
  addString(object, "state", operation.state);
  addString(object, "message", operation.message);
  addString(object, "downloadedPath", operation.downloadedPath);
  if (!operation.recording.id.empty()) {
    object.emplace("recording", recordingToJson(core::RemoteCameraSettings{}, operation.recording));
  }
  return core::JsonValue(std::move(object));
}

core::JsonValue recordingsToJson(const core::RemoteCameraSettings &settings,
                                 const std::vector<core::RemoteRecordingDescriptor> &recordings) {
  core::JsonValue::Array array;
  array.reserve(recordings.size());
  for (const auto &recording : recordings) {
    array.push_back(recordingToJson(settings, recording));
  }
  return core::JsonValue(std::move(array));
}

core::JsonValue statusToJson(const IntegrationStatus &status) {
  core::JsonValue::Object object;
  addString(object, "apiVersion", kIntegrationApiVersion);
  addBool(object, "paired", status.paired);
  addBool(object, "previewRunning", status.previewRunning);
  addBool(object, "previewDesired", status.previewDesired);
  addBool(object, "recording", status.recording);
  addString(object, "host", status.host);
  addString(object, "message", status.message);
  object.emplace("profile", profileToJson(status.profile));
  return core::JsonValue(std::move(object));
}

IntegrationHttpResponse jsonResponse(int status, core::JsonValue::Object object) {
  IntegrationHttpResponse response;
  response.status = status;
  response.body = core::JsonValue(std::move(object)).serialize();
  return response;
}

IntegrationHttpResponse okResponse(core::JsonValue::Object object) {
  object.emplace("ok", core::JsonValue(true));
  return jsonResponse(200, std::move(object));
}

IntegrationHttpResponse acceptedResponse(const std::string &message) {
  core::JsonValue::Object object;
  object.emplace("ok", core::JsonValue(true));
  object.emplace("accepted", core::JsonValue(true));
  addString(object, "message", message);
  return jsonResponse(202, std::move(object));
}

IntegrationHttpResponse errorResponse(int status, const std::string &code, const std::string &message) {
  core::JsonValue::Object error;
  addString(error, "code", code);
  addString(error, "message", message);
  core::JsonValue::Object object;
  object.emplace("ok", core::JsonValue(false));
  object.emplace("error", core::JsonValue(std::move(error)));
  return jsonResponse(status, std::move(object));
}

bool constantTimeEquals(const std::string &left, const std::string &right) {
  if (left.empty() || right.empty()) {
    return false;
  }
  size_t diff = left.size() ^ right.size();
  const size_t count = std::max(left.size(), right.size());
  for (size_t index = 0; index < count; ++index) {
    const unsigned char a = index < left.size() ? static_cast<unsigned char>(left[index]) : 0;
    const unsigned char b = index < right.size() ? static_cast<unsigned char>(right[index]) : 0;
    diff |= a ^ b;
  }
  return diff == 0;
}

std::string bearerTokenFromRequest(const IntegrationHttpRequest &request) {
  for (const auto &header : request.headers) {
    if (lowerHeaderKey(header.first) == "authorization") {
      constexpr const char *prefix = "Bearer ";
      if (header.second.rfind(prefix, 0) == 0) {
        return header.second.substr(std::char_traits<char>::length(prefix));
      }
    }
  }
  return queryValue(request.query, "token");
}

bool requestHasValidToken(const IntegrationHttpRequest &request, const std::string &expectedToken) {
  return constantTimeEquals(bearerTokenFromRequest(request), expectedToken);
}

} // namespace reashoot::desktop
