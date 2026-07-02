#pragma once

#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

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

enum class EventType {
  Paired,
  CaptureConfigured,
  RecordingStarted,
  RecordingStopped,
  RecordingPrepared,
  RecordingsListed,
  TransferAcknowledged,
  RecordingDeleted,
  WebRTCPreviewAnswer,
  WebRTCIceCandidateAdded,
  WebRTCPreviewStopped,
  Pong,
  Error,
  Unknown, // an event type this build does not recognize
};

// Maps an EventType rawValue string to the enum, or std::nullopt when unknown.
std::optional<EventType> eventTypeFromRawValue(std::string_view rawValue);

// Mirrors VideoSyncCore.RecordingDescriptor.
struct RecordingDescriptor {
  std::string id;
  std::string filename;
  std::int64_t byteCount = 0;
  std::optional<double> durationSeconds;
  std::optional<std::string> checksumSHA256;
  std::string downloadPath;
};

// Mirrors VideoSyncCore.PreviewDescriptor with the same defaults.
struct PreviewDescriptor {
  std::string snapshotPath = "/preview.jpg";
  std::string streamPath = "/preview.mjpg";
  std::string binaryStreamPath = "/preview.bin";
  int maximumDimension = 640;
  double approximateFrameRate = 12.0;
};

// Mirrors VideoSyncCore.ControlEvent. Decoding is lenient (a client consuming
// iPhone events): present fields are populated, absent optional fields stay
// empty, and an unrecognized type maps to EventType::Unknown.
struct ControlEvent {
  std::optional<std::string> requestID;
  EventType type = EventType::Unknown;
  int protocolVersion = kProtocolVersion;
  std::optional<std::string> token;
  std::optional<RecordingDescriptor> recording;
  std::vector<RecordingDescriptor> recordings;
  std::optional<PreviewDescriptor> preview;
  std::optional<CaptureProfile> captureProfile;
  std::optional<std::string> captureStatus;
  std::optional<double> captureProgress;
  std::optional<std::string> webRTCAnswerSDP;
  std::optional<std::string> message;
};

// Decodes a control event from JSON. Throws std::invalid_argument on malformed
// JSON or when the required "type" field is missing or not a string.
ControlEvent decodeControlEvent(std::string_view json);

} // namespace reaphone
