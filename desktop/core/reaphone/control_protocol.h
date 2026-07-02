#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>

namespace reaphone {

inline constexpr int kProtocolVersion = 1;

enum class CommandType {
  Pair,
  ConfigureCapture,
  StartRecording,
  StopRecording,
  PrepareRecording,
  ListRecordings,
  TransferComplete,
  DeleteRecording,
  StartWebRTCPreview,
  AddWebRTCIceCandidate,
  StopWebRTCPreview,
  Ping,
};

// The rawValue string the macOS CommandType enum encodes to.
std::string_view commandTypeRawValue(CommandType type);

// Mirrors VideoSyncCore.CaptureProfile with the same defaults.
struct CaptureProfile {
  std::string resolution = "4K";
  int fps = 30;
  std::string orientation = "portrait";
  std::string aspectRatio = "9:16";
  std::string lens = "wide";
  double zoomFactor = 1.0;
  std::string look = "natural";
};

// Mirrors VideoSyncCore.ControlCommand. Optional fields are omitted from the
// encoded JSON when unset, matching Swift's synthesized encodeIfPresent; the
// non-optional requestID, type, protocolVersion, and metadata are always
// emitted (metadata as {} when empty).
struct ControlCommand {
  std::string requestID; // uppercase UUID string, as Swift encodes UUID
  CommandType type = CommandType::Ping;
  int protocolVersion = kProtocolVersion;
  std::optional<std::string> token;
  std::optional<std::string> pairingCode;
  std::optional<std::string> sessionID;
  std::optional<std::string> recordingID;
  std::optional<CaptureProfile> captureProfile;
  std::optional<std::string> webRTCOfferSDP;
  std::optional<std::string> webRTCIceCandidateSDP;
  std::optional<std::string> webRTCIceCandidateMid;
  std::optional<std::int32_t> webRTCIceCandidateMLineIndex;
  std::map<std::string, std::string> metadata;
};

// Encodes a control command to sorted-key JSON matching the macOS helper.
std::string encodeControlCommand(const ControlCommand &command);

} // namespace reaphone
