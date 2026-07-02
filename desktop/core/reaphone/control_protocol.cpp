#include "reaphone/control_protocol.h"

#include "reaphone/json.h"

#include <stdexcept>

namespace reaphone {

std::string_view commandTypeRawValue(CommandType type) {
  switch (type) {
  case CommandType::Pair:
    return "pair";
  case CommandType::ConfigureCapture:
    return "configureCapture";
  case CommandType::StartRecording:
    return "startRecording";
  case CommandType::StopRecording:
    return "stopRecording";
  case CommandType::PrepareRecording:
    return "prepareRecording";
  case CommandType::ListRecordings:
    return "listRecordings";
  case CommandType::TransferComplete:
    return "transferComplete";
  case CommandType::DeleteRecording:
    return "deleteRecording";
  case CommandType::StartWebRTCPreview:
    return "startWebRTCPreview";
  case CommandType::AddWebRTCIceCandidate:
    return "addWebRTCIceCandidate";
  case CommandType::StopWebRTCPreview:
    return "stopWebRTCPreview";
  case CommandType::Ping:
    return "ping";
  }
  return "ping";
}

namespace {

json::Value encodeCaptureProfile(const CaptureProfile &profile) {
  json::Value value = json::Value::object();
  value.set("resolution", json::Value::string(profile.resolution));
  value.set("fps", json::Value::integer(profile.fps));
  value.set("orientation", json::Value::string(profile.orientation));
  value.set("aspectRatio", json::Value::string(profile.aspectRatio));
  value.set("lens", json::Value::string(profile.lens));
  value.set("zoomFactor", json::Value::real(profile.zoomFactor));
  value.set("look", json::Value::string(profile.look));
  return value;
}

} // namespace

std::string encodeControlCommand(const ControlCommand &command) {
  json::Value root = json::Value::object();

  // Always-present, non-optional fields.
  root.set("requestID", json::Value::string(command.requestID));
  root.set("type", json::Value::string(std::string(commandTypeRawValue(command.type))));
  root.set("protocolVersion", json::Value::integer(command.protocolVersion));

  json::Value metadata = json::Value::object();
  for (const auto &[key, value] : command.metadata) {
    metadata.set(key, json::Value::string(value));
  }
  root.set("metadata", std::move(metadata));

  // Optional fields, omitted when unset (mirrors Swift encodeIfPresent).
  if (command.token) {
    root.set("token", json::Value::string(*command.token));
  }
  if (command.pairingCode) {
    root.set("pairingCode", json::Value::string(*command.pairingCode));
  }
  if (command.sessionID) {
    root.set("sessionID", json::Value::string(*command.sessionID));
  }
  if (command.recordingID) {
    root.set("recordingID", json::Value::string(*command.recordingID));
  }
  if (command.captureProfile) {
    root.set("captureProfile", encodeCaptureProfile(*command.captureProfile));
  }
  if (command.webRTCOfferSDP) {
    root.set("webRTCOfferSDP", json::Value::string(*command.webRTCOfferSDP));
  }
  if (command.webRTCIceCandidateSDP) {
    root.set("webRTCIceCandidateSDP", json::Value::string(*command.webRTCIceCandidateSDP));
  }
  if (command.webRTCIceCandidateMid) {
    root.set("webRTCIceCandidateMid", json::Value::string(*command.webRTCIceCandidateMid));
  }
  if (command.webRTCIceCandidateMLineIndex) {
    root.set("webRTCIceCandidateMLineIndex",
             json::Value::integer(*command.webRTCIceCandidateMLineIndex));
  }

  return root.dump();
}

std::optional<EventType> eventTypeFromRawValue(std::string_view rawValue) {
  if (rawValue == "paired") return EventType::Paired;
  if (rawValue == "captureConfigured") return EventType::CaptureConfigured;
  if (rawValue == "recordingStarted") return EventType::RecordingStarted;
  if (rawValue == "recordingStopped") return EventType::RecordingStopped;
  if (rawValue == "recordingPrepared") return EventType::RecordingPrepared;
  if (rawValue == "recordingsListed") return EventType::RecordingsListed;
  if (rawValue == "transferAcknowledged") return EventType::TransferAcknowledged;
  if (rawValue == "recordingDeleted") return EventType::RecordingDeleted;
  if (rawValue == "webRTCPreviewAnswer") return EventType::WebRTCPreviewAnswer;
  if (rawValue == "webRTCIceCandidateAdded") return EventType::WebRTCIceCandidateAdded;
  if (rawValue == "webRTCPreviewStopped") return EventType::WebRTCPreviewStopped;
  if (rawValue == "pong") return EventType::Pong;
  if (rawValue == "error") return EventType::Error;
  return std::nullopt;
}

namespace {

std::optional<std::string> optionalString(const json::Value &object, const std::string &key) {
  const json::Value *value = object.find(key);
  if (value && value->isString()) {
    return value->asString();
  }
  return std::nullopt;
}

std::optional<double> optionalDouble(const json::Value &object, const std::string &key) {
  const json::Value *value = object.find(key);
  if (value && value->isNumber()) {
    return value->asDouble();
  }
  return std::nullopt;
}

RecordingDescriptor decodeRecording(const json::Value &object) {
  RecordingDescriptor recording;
  if (const auto id = optionalString(object, "id")) {
    recording.id = *id;
  }
  if (const auto filename = optionalString(object, "filename")) {
    recording.filename = *filename;
  }
  if (const json::Value *byteCount = object.find("byteCount"); byteCount && byteCount->isNumber()) {
    recording.byteCount = byteCount->asInt();
  }
  recording.durationSeconds = optionalDouble(object, "durationSeconds");
  recording.checksumSHA256 = optionalString(object, "checksumSHA256");
  if (const auto downloadPath = optionalString(object, "downloadPath")) {
    recording.downloadPath = *downloadPath;
  }
  return recording;
}

PreviewDescriptor decodePreview(const json::Value &object) {
  PreviewDescriptor preview;
  if (const auto snapshotPath = optionalString(object, "snapshotPath")) {
    preview.snapshotPath = *snapshotPath;
  }
  if (const auto streamPath = optionalString(object, "streamPath")) {
    preview.streamPath = *streamPath;
  }
  if (const auto binaryStreamPath = optionalString(object, "binaryStreamPath")) {
    preview.binaryStreamPath = *binaryStreamPath;
  }
  if (const json::Value *maxDim = object.find("maximumDimension"); maxDim && maxDim->isNumber()) {
    preview.maximumDimension = static_cast<int>(maxDim->asInt());
  }
  if (const auto frameRate = optionalDouble(object, "approximateFrameRate")) {
    preview.approximateFrameRate = *frameRate;
  }
  return preview;
}

CaptureProfile decodeCaptureProfile(const json::Value &object) {
  CaptureProfile profile;
  if (const auto resolution = optionalString(object, "resolution")) {
    profile.resolution = *resolution;
  }
  if (const json::Value *fps = object.find("fps"); fps && fps->isNumber()) {
    profile.fps = static_cast<int>(fps->asInt());
  }
  if (const auto orientation = optionalString(object, "orientation")) {
    profile.orientation = *orientation;
  }
  if (const auto aspectRatio = optionalString(object, "aspectRatio")) {
    profile.aspectRatio = *aspectRatio;
  }
  if (const auto lens = optionalString(object, "lens")) {
    profile.lens = *lens;
  }
  if (const auto zoomFactor = optionalDouble(object, "zoomFactor")) {
    profile.zoomFactor = *zoomFactor;
  }
  if (const auto look = optionalString(object, "look")) {
    profile.look = *look;
  }
  return profile;
}

} // namespace

ControlEvent decodeControlEvent(std::string_view json) {
  const json::Value root = json::parse(json);
  if (!root.isObject()) {
    throw std::invalid_argument("control event must be a JSON object");
  }

  const json::Value *typeValue = root.find("type");
  if (!typeValue || !typeValue->isString()) {
    throw std::invalid_argument("control event is missing a string \"type\"");
  }

  ControlEvent event;
  event.type = eventTypeFromRawValue(typeValue->asString()).value_or(EventType::Unknown);
  event.requestID = optionalString(root, "requestID");
  if (const json::Value *version = root.find("protocolVersion"); version && version->isNumber()) {
    event.protocolVersion = static_cast<int>(version->asInt());
  }
  event.token = optionalString(root, "token");

  if (const json::Value *recording = root.find("recording"); recording && recording->isObject()) {
    event.recording = decodeRecording(*recording);
  }
  if (const json::Value *recordings = root.find("recordings"); recordings && recordings->isArray()) {
    for (const json::Value &item : recordings->items()) {
      if (item.isObject()) {
        event.recordings.push_back(decodeRecording(item));
      }
    }
  }
  if (const json::Value *preview = root.find("preview"); preview && preview->isObject()) {
    event.preview = decodePreview(*preview);
  }
  if (const json::Value *profile = root.find("captureProfile"); profile && profile->isObject()) {
    event.captureProfile = decodeCaptureProfile(*profile);
  }
  event.captureStatus = optionalString(root, "captureStatus");
  event.captureProgress = optionalDouble(root, "captureProgress");
  event.webRTCAnswerSDP = optionalString(root, "webRTCAnswerSDP");
  event.message = optionalString(root, "message");

  return event;
}

} // namespace reaphone
