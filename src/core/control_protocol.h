#pragma once

#include "json_value.h"

#include <cstdint>
#include <string>
#include <vector>

namespace reashoot::core {

constexpr int kProtocolVersion = 1;

struct ProtocolCaptureProfile {
  std::string resolution = "4K";
  int fps = 30;
  std::string orientation = "auto";
  std::string aspectRatio = "9:16";
  std::string lens = "wide";
  double zoomFactor = 1.0;
  std::string look = "natural";
};

struct ProtocolRecording {
  std::string id;
  std::string filename;
  int64_t byteCount = 0;
  double durationSeconds = 0.0;
  bool hasDurationSeconds = false;
  std::string checksumSHA256;
  std::string downloadPath;
};

struct ProtocolPreview {
  std::string codec = "h264";
  std::string transport = "websocket";
  std::string streamPath = "/preview";
  int port = 8789;
  int width = 640;
  int height = 360;
  int fps = 12;
  std::string orientation = "portrait";
  bool requiresToken = true;
};

struct ProtocolCommand {
  std::string requestID;
  std::string type;
  int protocolVersion = kProtocolVersion;
  std::string token;
  std::string pairingCode;
  std::string sessionID;
  std::string recordingID;
  bool hasCaptureProfile = false;
  ProtocolCaptureProfile captureProfile;
};

struct ProtocolEvent {
  std::string requestID;
  std::string type;
  int protocolVersion = kProtocolVersion;
  std::string token;
  bool hasRecording = false;
  ProtocolRecording recording;
  std::vector<ProtocolRecording> recordings;
  bool hasPreview = false;
  ProtocolPreview preview;
  bool hasCaptureProfile = false;
  ProtocolCaptureProfile captureProfile;
  std::string captureStatus;
  double captureProgress = 0.0;
  bool hasCaptureProgress = false;
  std::string message;
};

std::string encodeCommandJson(const ProtocolCommand &command);
ProtocolEvent decodeEventJson(const std::string &json);

JsonValue captureProfileToJson(const ProtocolCaptureProfile &profile);
ProtocolCaptureProfile captureProfileFromJson(const JsonValue &json);
ProtocolRecording recordingFromJson(const JsonValue &json);
ProtocolPreview previewFromJson(const JsonValue &json);

} // namespace reashoot::core
