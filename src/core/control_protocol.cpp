#include "control_protocol.h"

namespace reashoot::core {
namespace {

void putString(JsonValue::Object &object, const std::string &key, const std::string &value) {
  if (!value.empty()) {
    object.emplace(key, JsonValue(value));
  }
}

JsonValue metadataToJson(const std::map<std::string, std::string> &metadata) {
  JsonValue::Object object;
  for (const auto &[key, value] : metadata) {
    if (!key.empty() && !value.empty()) {
      object.emplace(key, JsonValue(value));
    }
  }
  return JsonValue(std::move(object));
}

} // namespace

JsonValue captureProfileToJson(const ProtocolCaptureProfile &profile) {
  JsonValue::Object object;
  object.emplace("aspectRatio", JsonValue(profile.aspectRatio));
  object.emplace("fps", JsonValue(static_cast<double>(profile.fps)));
  object.emplace("lens", JsonValue(profile.lens));
  object.emplace("look", JsonValue(profile.look));
  object.emplace("orientation", JsonValue(profile.orientation));
  object.emplace("resolution", JsonValue(profile.resolution));
  object.emplace("zoomFactor", JsonValue(profile.zoomFactor));
  return JsonValue(std::move(object));
}

ProtocolCaptureProfile captureProfileFromJson(const JsonValue &json) {
  ProtocolCaptureProfile profile;
  profile.resolution = json.stringValue("resolution", profile.resolution);
  profile.fps = json.intValue("fps", profile.fps);
  profile.orientation = json.stringValue("orientation", profile.orientation);
  profile.aspectRatio = json.stringValue("aspectRatio", profile.aspectRatio);
  profile.lens = json.stringValue("lens", profile.lens);
  profile.zoomFactor = json.numberValue("zoomFactor", profile.zoomFactor);
  profile.look = json.stringValue("look", profile.look);
  return profile;
}

ProtocolRecording recordingFromJson(const JsonValue &json) {
  ProtocolRecording recording;
  recording.id = json.stringValue("id");
  recording.filename = json.stringValue("filename");
  recording.byteCount = json.int64Value("byteCount");
  recording.downloadPath = json.stringValue("downloadPath");
  recording.checksumSHA256 = json.stringValue("checksumSHA256");
  recording.createdAt = json.stringValue("createdAt");
  recording.thumbnailPath = json.stringValue("thumbnailPath");
  if (json.find("durationSeconds")) {
    recording.durationSeconds = json.numberValue("durationSeconds");
    recording.hasDurationSeconds = true;
  }
  return recording;
}

ProtocolPreview previewFromJson(const JsonValue &json) {
  ProtocolPreview preview;
  preview.codec = json.stringValue("codec", preview.codec);
  preview.transport = json.stringValue("transport", preview.transport);
  preview.streamPath = json.stringValue("streamPath", preview.streamPath);
  preview.port = json.intValue("port", preview.port);
  preview.width = json.intValue("width", preview.width);
  preview.height = json.intValue("height", preview.height);
  preview.fps = json.intValue("fps", preview.fps);
  preview.orientation = json.stringValue("orientation", preview.orientation);
  preview.resolvedOrientation = json.stringValue("resolvedOrientation", preview.resolvedOrientation);
  preview.displayWidth = json.intValue("displayWidth", preview.displayWidth);
  preview.displayHeight = json.intValue("displayHeight", preview.displayHeight);
  preview.displayAspectRatio = json.stringValue("displayAspectRatio", preview.displayAspectRatio);
  preview.metadataVersion = json.intValue("metadataVersion", preview.metadataVersion);
  preview.requiresToken = json.boolValue("requiresToken", preview.requiresToken);
  return preview;
}

std::string encodeCommandJson(const ProtocolCommand &command) {
  JsonValue::Object object;
  if (command.hasCaptureProfile) {
    object.emplace("captureProfile", captureProfileToJson(command.captureProfile));
  }
  putString(object, "pairingCode", command.pairingCode);
  object.emplace("metadata", metadataToJson(command.metadata));
  object.emplace("protocolVersion", JsonValue(static_cast<double>(command.protocolVersion)));
  putString(object, "recordingID", command.recordingID);
  putString(object, "requestID", command.requestID);
  putString(object, "sessionID", command.sessionID);
  putString(object, "token", command.token);
  object.emplace("type", JsonValue(command.type));
  return JsonValue(std::move(object)).serialize();
}

ProtocolEvent decodeEventJson(const std::string &json) {
  const JsonValue root = parseJson(json);
  ProtocolEvent event;
  event.requestID = root.stringValue("requestID");
  event.type = root.stringValue("type");
  event.protocolVersion = root.intValue("protocolVersion", kProtocolVersion);
  event.token = root.stringValue("token");
  event.captureStatus = root.stringValue("captureStatus");
  event.message = root.stringValue("message");
  if (root.find("captureProgress")) {
    event.captureProgress = root.numberValue("captureProgress");
    event.hasCaptureProgress = true;
  }
  if (const JsonValue *recording = root.find("recording"); recording && !recording->isNull()) {
    event.recording = recordingFromJson(*recording);
    event.hasRecording = true;
  }
  if (const JsonValue *recordings = root.find("recordings"); recordings && recordings->type() == JsonValue::Type::Array) {
    for (const JsonValue &recording : recordings->asArray()) {
      event.recordings.push_back(recordingFromJson(recording));
    }
  }
  if (const JsonValue *preview = root.find("preview"); preview && !preview->isNull()) {
    event.preview = previewFromJson(*preview);
    event.hasPreview = true;
  }
  if (const JsonValue *profile = root.find("captureProfile"); profile && !profile->isNull()) {
    event.captureProfile = captureProfileFromJson(*profile);
    event.hasCaptureProfile = true;
  }
  return event;
}

} // namespace reashoot::core
