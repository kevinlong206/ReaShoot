// video-sync-win: the Windows control helper CLI. It mirrors the macOS
// video-sync-mac tool (helper/Sources/video-sync-mac/VideoSyncMacCLI.swift) for
// the control-socket commands, driving the portable reaphone::ControlClient and
// printing the same line formats the REAPER plugin parses. Commands that need
// the media downloader or Bonjour discovery are not yet ported and report a
// clear error.

#include "reaphone/control_protocol.h"
#include "reaphone/windows/control_client.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <optional>
#include <random>
#include <sstream>
#include <string>
#include <vector>

namespace {

class Arguments {
public:
  explicit Arguments(int argc, char **argv) {
    for (int i = 0; i < argc; ++i) {
      values_.emplace_back(argv[i]);
    }
  }

  std::string command() const { return values_.size() > 1 ? values_[1] : "help"; }

  std::optional<std::string> value(const std::string &flag) const {
    for (std::size_t i = 0; i + 1 < values_.size(); ++i) {
      if (values_[i] == flag) {
        return values_[i + 1];
      }
    }
    return std::nullopt;
  }

  std::string value(const std::string &flag, const std::string &fallback) const {
    return value(flag).value_or(fallback);
  }

  int intValue(const std::string &flag, int fallback) const {
    if (const auto raw = value(flag)) {
      try {
        return std::stoi(*raw);
      } catch (const std::exception &) {
      }
    }
    return fallback;
  }

  double doubleValue(const std::string &flag, double fallback) const {
    if (const auto raw = value(flag)) {
      try {
        return std::stod(*raw);
      } catch (const std::exception &) {
      }
    }
    return fallback;
  }

  bool hasFlag(const std::string &flag) const {
    for (const auto &value : values_) {
      if (value == flag) {
        return true;
      }
    }
    return false;
  }

private:
  std::vector<std::string> values_;
};

// Terminates with the missing-argument diagnostic the macOS helper prints.
[[noreturn]] void missingArgument(const std::string &name) {
  std::fputs(("missing required argument " + name + "\n").c_str(), stderr);
  std::exit(2);
}

std::string require(const std::optional<std::string> &value, const std::string &name) {
  if (!value || value->empty()) {
    missingArgument(name);
  }
  return *value;
}

// Generates an uppercase 8-4-4-4-12 UUID string, matching how Swift encodes the
// synthesized ControlCommand.requestID.
std::string makeRequestID() {
  std::random_device device;
  std::array<std::uint8_t, 16> bytes{};
  for (auto &byte : bytes) {
    byte = static_cast<std::uint8_t>(device() & 0xff);
  }
  bytes[6] = static_cast<std::uint8_t>((bytes[6] & 0x0f) | 0x40); // version 4
  bytes[8] = static_cast<std::uint8_t>((bytes[8] & 0x3f) | 0x80); // variant

  static const char *digits = "0123456789ABCDEF";
  std::string uuid;
  uuid.reserve(36);
  for (std::size_t i = 0; i < bytes.size(); ++i) {
    if (i == 4 || i == 6 || i == 8 || i == 10) {
      uuid.push_back('-');
    }
    uuid.push_back(digits[(bytes[i] >> 4) & 0x0f]);
    uuid.push_back(digits[bytes[i] & 0x0f]);
  }
  return uuid;
}

reaphone::ControlCommand baseCommand(reaphone::CommandType type) {
  reaphone::ControlCommand command;
  command.requestID = makeRequestID();
  command.type = type;
  return command;
}

reaphone::ControlEvent send(const Arguments &args, const reaphone::ControlCommand &command,
                            std::chrono::seconds timeout = std::chrono::seconds{20}) {
  const std::string host = require(args.value("--host"), "--host");
  const int port = args.intValue("--port", 8787);
  reaphone::ControlClient client(host, port, timeout);
  return client.send(command);
}

// Reports an unexpected event the way the macOS helper's unexpectedEvent error
// does: the event message when present, otherwise a generic description.
[[noreturn]] void unexpectedEvent(const reaphone::ControlEvent &event) {
  const std::string message = event.message && !event.message->empty()
                                  ? *event.message
                                  : std::string("unexpected control event");
  std::fputs(("error: " + message + "\n").c_str(), stderr);
  std::exit(1);
}

void printRecording(const reaphone::RecordingDescriptor &recording) {
  std::ostringstream line;
  line << "recording"
       << "\tid=" << recording.id
       << "\tfilename=" << recording.filename
       << "\tbyteCount=" << recording.byteCount
       << "\tdownloadPath=" << recording.downloadPath;
  if (recording.checksumSHA256) {
    line << "\tchecksum=" << *recording.checksumSHA256;
  }
  std::cout << line.str() << '\n';
}

void printHelp() {
  std::cout << "video-sync-win commands:\n"
               "  pair --host HOST [--port 8787] --code CODE\n"
               "  configure --host HOST [--port 8787] --token TOKEN [--resolution 4K] [--fps 30]"
               " [--orientation portrait] [--aspect 9:16] [--lens wide] [--zoom 1.0] [--look natural]\n"
               "  start --host HOST [--port 8787] --token TOKEN [--session SESSION]\n"
               "  prepare-recording --host HOST [--port 8787] --token TOKEN --recording-id ID\n"
               "  stop-only --host HOST [--port 8787] --token TOKEN\n"
               "  list-recordings --host HOST [--port 8787] --token TOKEN\n"
               "  delete-recording --host HOST [--port 8787] --token TOKEN --recording-id ID\n"
               "  ping --host HOST [--port 8787] [--token TOKEN]\n"
               "  webrtc-answer --host HOST [--port 8787] --token TOKEN --offer-file PATH\n"
               "  webrtc-candidate --host HOST [--port 8787] --token TOKEN --candidate SDP [--mid MID] [--mline INDEX]\n"
               "  stop-webrtc --host HOST [--port 8787] --token TOKEN\n";
}

int run(const Arguments &args) {
  const std::string command = args.command();

  if (command == "pair") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::Pair);
    cmd.pairingCode = require(args.value("--code"), "--code");
    const reaphone::ControlEvent event = send(args, cmd);
    if (!event.token) {
      unexpectedEvent(event);
    }
    std::cout << "paired token=" << *event.token << '\n';
    return 0;
  }

  if (command == "ping") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::Ping);
    cmd.token = args.value("--token");
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::Pong) {
      unexpectedEvent(event);
    }
    std::cout << (event.message ? *event.message : std::string("pong")) << '\n';
    return 0;
  }

  if (command == "configure") {
    reaphone::CaptureProfile profile;
    profile.resolution = args.value("--resolution", "4K");
    profile.fps = args.intValue("--fps", 30);
    profile.orientation = args.value("--orientation", "portrait");
    profile.aspectRatio = args.value("--aspect", "9:16");
    profile.lens = args.value("--lens", "wide");
    profile.zoomFactor = args.doubleValue("--zoom", 1.0);
    profile.look = args.value("--look", "natural");

    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::ConfigureCapture);
    cmd.token = require(args.value("--token"), "--token");
    cmd.captureProfile = profile;
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::CaptureConfigured) {
      unexpectedEvent(event);
    }
    std::cout << (event.message ? *event.message : std::string("captureConfigured")) << '\n';
    return 0;
  }

  if (command == "start") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::StartRecording);
    cmd.token = require(args.value("--token"), "--token");
    cmd.sessionID = args.value("--session");
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::RecordingStarted) {
      unexpectedEvent(event);
    }
    std::cout << (event.message ? *event.message : std::string("recordingStarted")) << '\n';
    return 0;
  }

  if (command == "prepare-recording") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::PrepareRecording);
    cmd.token = require(args.value("--token"), "--token");
    cmd.recordingID = require(args.value("--recording-id"), "--recording-id");
    const reaphone::ControlEvent event = send(args, cmd, std::chrono::seconds{900});
    if (event.type != reaphone::EventType::RecordingPrepared || !event.recording) {
      unexpectedEvent(event);
    }
    printRecording(*event.recording);
    return 0;
  }

  if (command == "stop-only") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::StopRecording);
    cmd.token = require(args.value("--token"), "--token");
    const reaphone::ControlEvent event = send(args, cmd);
    if (!event.recording) {
      unexpectedEvent(event);
    }
    printRecording(*event.recording);
    return 0;
  }

  if (command == "list-recordings") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::ListRecordings);
    cmd.token = require(args.value("--token"), "--token");
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::RecordingsListed) {
      unexpectedEvent(event);
    }
    for (const reaphone::RecordingDescriptor &recording : event.recordings) {
      printRecording(recording);
    }
    return 0;
  }

  if (command == "delete-recording") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::DeleteRecording);
    cmd.token = require(args.value("--token"), "--token");
    cmd.recordingID = require(args.value("--recording-id"), "--recording-id");
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::RecordingDeleted) {
      unexpectedEvent(event);
    }
    std::cout << (event.message ? *event.message : std::string("recording deleted")) << '\n';
    return 0;
  }

  if (command == "webrtc-answer") {
    const std::string offerPath = require(args.value("--offer-file"), "--offer-file");
    std::ifstream stream(offerPath, std::ios::binary);
    if (!stream) {
      std::fputs(("error: could not read offer file " + offerPath + "\n").c_str(), stderr);
      return 1;
    }
    std::ostringstream contents;
    contents << stream.rdbuf();

    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::StartWebRTCPreview);
    cmd.token = require(args.value("--token"), "--token");
    cmd.webRTCOfferSDP = contents.str();
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::WebRTCPreviewAnswer || !event.webRTCAnswerSDP) {
      unexpectedEvent(event);
    }
    std::cout << *event.webRTCAnswerSDP << '\n';
    return 0;
  }

  if (command == "webrtc-candidate") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::AddWebRTCIceCandidate);
    cmd.token = require(args.value("--token"), "--token");
    cmd.webRTCIceCandidateSDP = require(args.value("--candidate"), "--candidate");
    cmd.webRTCIceCandidateMid = args.value("--mid");
    cmd.webRTCIceCandidateMLineIndex = static_cast<std::int32_t>(args.intValue("--mline", 0));
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::WebRTCIceCandidateAdded) {
      unexpectedEvent(event);
    }
    std::cout << (event.message ? *event.message : std::string("candidate accepted")) << '\n';
    return 0;
  }

  if (command == "stop-webrtc") {
    reaphone::ControlCommand cmd = baseCommand(reaphone::CommandType::StopWebRTCPreview);
    cmd.token = require(args.value("--token"), "--token");
    const reaphone::ControlEvent event = send(args, cmd);
    if (event.type != reaphone::EventType::WebRTCPreviewStopped) {
      unexpectedEvent(event);
    }
    std::cout << (event.message ? *event.message : std::string("webRTCPreviewStopped")) << '\n';
    return 0;
  }

  if (command == "help" || command == "--help" || command == "-h") {
    printHelp();
    return 0;
  }

  if (command == "discover" || command == "stop" || command == "download-recording") {
    std::fputs(("error: " + command + " is not yet supported in the Windows helper\n").c_str(), stderr);
    return 1;
  }

  printHelp();
  return 2;
}

} // namespace

int main(int argc, char **argv) {
  const Arguments args(argc, argv);
  try {
    return run(args);
  } catch (const std::exception &error) {
    std::fputs(("error: " + std::string(error.what()) + "\n").c_str(), stderr);
    return 1;
  }
}
