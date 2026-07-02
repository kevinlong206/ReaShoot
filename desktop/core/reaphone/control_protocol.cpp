#include "reaphone/control_protocol.h"

#include "reaphone/json.h"

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

} // namespace reaphone
