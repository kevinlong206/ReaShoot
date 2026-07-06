#include "control_client.h"
#include "core/control_protocol.h"
#include "discovery.h"
#include "downloader.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <future>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace {

class CLIArguments {
public:
  CLIArguments(int argc, char **argv) : values_(argv, argv + argc) {}

  std::string command() const { return values_.size() > 1 ? values_[1] : "help"; }

  std::string valueAfter(const std::string &flag) const {
    for (size_t i = 0; i + 1 < values_.size(); ++i) {
      if (values_[i] == flag) {
        return values_[i + 1];
      }
    }
    return {};
  }

  int intAfter(const std::string &flag, int fallback) const {
    const std::string value = valueAfter(flag);
    return value.empty() ? fallback : std::atoi(value.c_str());
  }

  bool hasFlag(const std::string &flag) const {
    return std::find(values_.begin(), values_.end(), flag) != values_.end();
  }

private:
  std::vector<std::string> values_;
};

[[noreturn]] void fail(const std::string &message, int code = 1) {
  std::cerr << "error: " << message << "\n";
  std::exit(code);
}

std::string required(const CLIArguments &args, const std::string &flag) {
  std::string value = args.valueAfter(flag);
  if (value.empty()) {
    fail("missing required argument " + flag, 2);
  }
  return value;
}

void printHelp() {
  std::cout
      << "reashoot helper commands:\n"
      << "  discover [--timeout 3]\n"
      << "  pair --host HOST [--port 8787] [--client-name NAME]\n"
      << "  configure --host HOST [--port 8787] --token TOKEN [--resolution 4K] [--fps 30] [--orientation auto] [--aspect 9:16] [--lens wide] [--zoom 1.0] [--look natural]\n"
      << "  start --host HOST [--port 8787] --token TOKEN [--session SESSION]\n"
      << "  stop --host HOST [--port 8787] [--http-port 8788] --token TOKEN [--download-dir DIR] [--progress]\n"
      << "  stop-only --host HOST [--port 8787] --token TOKEN\n"
      << "  prepare-recording --host HOST [--port 8787] --token TOKEN --recording-id ID [--progress]\n"
      << "  download-recording --host HOST [--port 8787] [--http-port 8788] --token TOKEN --recording-id ID [--download-dir DIR] [--progress]\n"
      << "  list-recordings --host HOST [--port 8787] --token TOKEN\n"
      << "  delete-recording --host HOST [--port 8787] --token TOKEN --recording-id ID\n"
      << "  ping --host HOST [--port 8787] [--token TOKEN]\n"
      << "  start-preview --host HOST [--port 8787] --token TOKEN\n"
      << "  stop-preview --host HOST [--port 8787] --token TOKEN\n";
}

std::string defaultClientName() {
  const char *environmentName =
#ifdef _WIN32
      std::getenv("COMPUTERNAME");
#else
      std::getenv("HOSTNAME");
#endif
  if (environmentName && environmentName[0]) {
    return environmentName;
  }
#ifdef _WIN32
  char windowsName[MAX_COMPUTERNAME_LENGTH + 1] = {};
  DWORD size = sizeof(windowsName);
  if (GetComputerNameA(windowsName, &size) && windowsName[0]) {
    return windowsName;
  }
  return "Windows PC";
#else
  char buffer[256] = {};
  if (gethostname(buffer, sizeof(buffer) - 1) == 0 && buffer[0]) {
    return buffer;
  }
  return "Mac";
#endif
}

void runDiscovery(const CLIArguments &args) {
  const int timeout = args.intAfter("--timeout", 3);
  for (const auto &phone : reashoot::helper::discoverPhones(timeout)) {
    std::cout << "device"
              << "\tname=" << phone.name
              << "\thost=" << phone.host
              << "\tcontrolPort=" << phone.controlPort
              << "\thttpPort=" << phone.httpPort
              << "\tpaired=" << (phone.isPaired ? "true" : "false")
              << "\n";
  }
}

void printRecording(const reashoot::core::ProtocolRecording &recording) {
  std::cout << "recording"
            << "\tid=" << recording.id
            << "\tfilename=" << recording.filename
            << "\tbyteCount=" << recording.byteCount
            << "\tdownloadPath=" << recording.downloadPath;
  if (!recording.createdAt.empty()) {
    std::cout << "\tcreatedAt=" << recording.createdAt;
  }
  if (!recording.thumbnailPath.empty()) {
    std::cout << "\tthumbnailPath=" << recording.thumbnailPath;
  }
  if (!recording.checksumSHA256.empty()) {
    std::cout << "\tchecksum=" << recording.checksumSHA256;
  }
  std::cout << "\n";
}

void printPreview(const reashoot::core::ProtocolPreview &preview) {
  std::cout << "preview"
            << "\tcodec=" << preview.codec
            << "\ttransport=" << preview.transport
            << "\tstreamPath=" << preview.streamPath
            << "\tport=" << preview.port
            << "\twidth=" << preview.width
            << "\theight=" << preview.height
            << "\tfps=" << preview.fps
            << "\torientation=" << preview.orientation
            << "\n";
}

void printProgress(int64_t bytes, int64_t expected) {
  const int64_t total = std::max<int64_t>(expected, 0);
  const double percent = total > 0 ? std::min(100.0, (static_cast<double>(bytes) / static_cast<double>(total)) * 100.0) : 0.0;
  std::cerr.setf(std::ios::fixed);
  std::cerr.precision(1);
  std::cerr << "progress bytes=" << bytes << " total=" << total << " percent=" << percent << "\n";
}

void printEncodeProgress(double progress) {
  const double normalized = progress <= 1.0 ? progress * 100.0 : progress;
  const double percent = std::min(100.0, std::max(0.0, normalized));
  std::cerr.setf(std::ios::fixed);
  std::cerr.precision(1);
  std::cerr << "encode percent=" << percent << "\n";
}

void requireEventType(const reashoot::core::ProtocolEvent &event, const std::string &type) {
  if (event.type != type) {
    if (!event.message.empty()) {
      fail(event.message);
    }
    fail("Unexpected control event: " + event.type);
  }
}

void printCommandResult(const std::string &commandName, const reashoot::core::ProtocolEvent &event) {
  if (commandName == "pair") {
    requireEventType(event, "paired");
    if (event.token.empty()) {
      fail("Unexpected control event: " + event.type);
    }
    std::cout << "paired token=" << event.token << "\n";
  } else if (commandName == "configure") {
    requireEventType(event, "captureConfigured");
    std::cout << (event.message.empty() ? event.type : event.message) << "\n";
  } else if (commandName == "start") {
    requireEventType(event, "recordingStarted");
    std::cout << (event.message.empty() ? event.type : event.message) << "\n";
  } else if (commandName == "stop-only" || commandName == "prepare-recording") {
    requireEventType(event, commandName == "stop-only" ? "recordingStopped" : "recordingPrepared");
    if (!event.hasRecording) {
      fail("Unexpected control event: " + event.type);
    }
    printRecording(event.recording);
  } else if (commandName == "list-recordings") {
    requireEventType(event, "recordingsListed");
    for (const auto &recording : event.recordings) {
      printRecording(recording);
    }
  } else if (commandName == "delete-recording") {
    requireEventType(event, "recordingDeleted");
    std::cout << (event.message.empty() ? "recording deleted" : event.message) << "\n";
  } else if (commandName == "ping") {
    requireEventType(event, "pong");
    std::cout << (event.message.empty() ? event.type : event.message) << "\n";
  } else if (commandName == "start-preview") {
    requireEventType(event, "previewStarted");
    if (!event.hasPreview) {
      fail("Unexpected control event: " + event.type);
    }
    printPreview(event.preview);
  } else if (commandName == "stop-preview") {
    requireEventType(event, "previewStopped");
    std::cout << (event.message.empty() ? event.type : event.message) << "\n";
  }
}

reashoot::core::ProtocolCaptureProfile captureProfileFromArgs(const CLIArguments &args) {
  reashoot::core::ProtocolCaptureProfile profile;
  profile.resolution = args.valueAfter("--resolution").empty() ? profile.resolution : args.valueAfter("--resolution");
  profile.fps = args.intAfter("--fps", profile.fps);
  profile.orientation = args.valueAfter("--orientation").empty() ? profile.orientation : args.valueAfter("--orientation");
  profile.aspectRatio = args.valueAfter("--aspect").empty() ? profile.aspectRatio : args.valueAfter("--aspect");
  profile.lens = args.valueAfter("--lens").empty() ? profile.lens : args.valueAfter("--lens");
  profile.zoomFactor = args.valueAfter("--zoom").empty() ? profile.zoomFactor : std::atof(args.valueAfter("--zoom").c_str());
  profile.look = args.valueAfter("--look").empty() ? profile.look : args.valueAfter("--look");
  return profile;
}

reashoot::core::ProtocolCommand commandForArgs(const CLIArguments &args) {
  const std::string commandName = args.command();
  reashoot::core::ProtocolCommand command;
  if (commandName == "pair") {
    command.type = "pair";
    std::string clientName = args.valueAfter("--client-name");
    if (clientName.empty()) {
      clientName = defaultClientName();
    }
    command.metadata["clientName"] = clientName;
    const std::string legacyCode = args.valueAfter("--code");
    if (!legacyCode.empty()) {
      command.pairingCode = legacyCode;
    }
  } else if (commandName == "configure") {
    command.type = "configureCapture";
    command.token = required(args, "--token");
    command.captureProfile = captureProfileFromArgs(args);
    command.hasCaptureProfile = true;
  } else if (commandName == "start") {
    command.type = "startRecording";
    command.token = required(args, "--token");
    command.sessionID = args.valueAfter("--session");
  } else if (commandName == "stop" || commandName == "stop-only") {
    command.type = "stopRecording";
    command.token = required(args, "--token");
  } else if (commandName == "prepare-recording") {
    command.type = "prepareRecording";
    command.token = required(args, "--token");
    command.recordingID = required(args, "--recording-id");
  } else if (commandName == "list-recordings") {
    command.type = "listRecordings";
    command.token = required(args, "--token");
  } else if (commandName == "delete-recording") {
    command.type = "deleteRecording";
    command.token = required(args, "--token");
    command.recordingID = required(args, "--recording-id");
  } else if (commandName == "ping") {
    command.type = "ping";
    command.token = args.valueAfter("--token");
  } else if (commandName == "start-preview") {
    command.type = "startPreview";
    command.token = required(args, "--token");
  } else if (commandName == "stop-preview") {
    command.type = "stopPreview";
    command.token = required(args, "--token");
  } else {
    fail("unsupported C++ helper command skeleton: " + commandName, 2);
  }
  return command;
}

reashoot::core::ProtocolRecording prepareRecording(const reashoot::helper::ControlClient &client,
                                                   const std::string &token,
                                                   const std::string &recordingID) {
  reashoot::core::ProtocolCommand command;
  command.requestID = reashoot::helper::randomUUID();
  command.type = "prepareRecording";
  command.token = token;
  command.recordingID = recordingID;
  const reashoot::core::ProtocolEvent event = client.send(command);
  requireEventType(event, "recordingPrepared");
  if (!event.hasRecording) {
    fail("Unexpected control event: " + event.type);
  }
  return event.recording;
}

reashoot::core::ProtocolRecording prepareRecordingWithProgress(const reashoot::helper::ControlClient &client,
                                                               const reashoot::helper::ControlClient &progressClient,
                                                               const std::string &token,
                                                               const std::string &recordingID,
                                                               bool reportProgress) {
  auto preparation = std::async(std::launch::async, [&client, &token, &recordingID]() {
    return prepareRecording(client, token, recordingID);
  });
  int lastTenths = -1;
  while (preparation.wait_for(std::chrono::milliseconds(250)) != std::future_status::ready) {
    if (!reportProgress) {
      continue;
    }
    try {
      reashoot::core::ProtocolCommand ping;
      ping.requestID = reashoot::helper::randomUUID();
      ping.type = "ping";
      ping.token = token;
      const reashoot::core::ProtocolEvent event = progressClient.send(ping);
      if (event.hasCaptureProgress && (event.captureStatus == "encoding" || event.captureStatus == "applyingLook")) {
        const double normalized = event.captureProgress <= 1.0 ? event.captureProgress * 100.0 : event.captureProgress;
        const int tenths = static_cast<int>(std::max(0.0, std::min(100.0, normalized)) * 10.0);
        if (tenths != lastTenths) {
          lastTenths = tenths;
          printEncodeProgress(event.captureProgress);
        }
      }
    } catch (const std::exception &) {
    }
  }
  return preparation.get();
}

void acknowledgeTransfer(const reashoot::helper::ControlClient &client,
                         const std::string &token,
                         const std::string &recordingID) {
  reashoot::core::ProtocolCommand command;
  command.requestID = reashoot::helper::randomUUID();
  command.type = "transferComplete";
  command.token = token;
  command.recordingID = recordingID;
  const reashoot::core::ProtocolEvent event = client.send(command);
  requireEventType(event, "transferAcknowledged");
}

reashoot::helper::DownloadProgress progressCallbackForArgs(const CLIArguments &args) {
  return args.hasFlag("--progress") ? printProgress : [](int64_t, int64_t) {};
}

void runDownloadRecording(const CLIArguments &args,
                          const reashoot::helper::ControlClient &client,
                          const std::string &host,
                          const std::string &token) {
  const int httpPort = args.intAfter("--http-port", 8788);
  const int controlPort = args.intAfter("--port", 8787);
  const std::string recordingID = required(args, "--recording-id");
  const std::string directory = args.valueAfter("--download-dir").empty() ? "." : args.valueAfter("--download-dir");
  const reashoot::helper::ControlClient progressClient(host, controlPort, 5);
  const reashoot::core::ProtocolRecording recording =
      prepareRecordingWithProgress(client, progressClient, token, recordingID, args.hasFlag("--progress"));
  const std::string downloaded = reashoot::helper::downloadRecording(recording, host, httpPort, token, directory, progressCallbackForArgs(args));
  try {
    acknowledgeTransfer(client, token, recording.id);
  } catch (const std::exception &error) {
    std::cerr << "warning: downloaded file, but could not acknowledge transfer completion: " << error.what() << "\n";
  }
  std::cout << "downloaded " << downloaded << "\n";
}

void runStop(const CLIArguments &args,
             const reashoot::helper::ControlClient &client,
             const std::string &host,
             const std::string &token) {
  reashoot::core::ProtocolCommand stop;
  stop.requestID = reashoot::helper::randomUUID();
  stop.type = "stopRecording";
  stop.token = token;
  const reashoot::core::ProtocolEvent stopped = client.send(stop);
  requireEventType(stopped, "recordingStopped");
  if (!stopped.hasRecording) {
    fail("Unexpected control event: " + stopped.type);
  }
  const int httpPort = args.intAfter("--http-port", 8788);
  const int controlPort = args.intAfter("--port", 8787);
  const std::string directory = args.valueAfter("--download-dir").empty() ? "." : args.valueAfter("--download-dir");
  const reashoot::helper::ControlClient progressClient(host, controlPort, 5);
  const reashoot::core::ProtocolRecording prepared =
      prepareRecordingWithProgress(client, progressClient, token, stopped.recording.id, args.hasFlag("--progress"));
  const std::string downloaded = reashoot::helper::downloadRecording(prepared, host, httpPort, token, directory, progressCallbackForArgs(args));
  try {
    acknowledgeTransfer(client, token, prepared.id);
  } catch (const std::exception &error) {
    std::cerr << "warning: downloaded file, but could not acknowledge transfer completion: " << error.what() << "\n";
  }
  std::cout << "downloaded " << downloaded << "\n";
}

} // namespace

int main(int argc, char **argv) {
  try {
    CLIArguments args(argc, argv);
    const std::string command = args.command();
    if (command == "help" || command == "--help" || command == "-h") {
      printHelp();
      return 0;
    }
    if (command == "discover") {
      runDiscovery(args);
      return 0;
    }
    const std::string host = required(args, "--host");
    const int port = args.intAfter("--port", 8787);
    const bool canWaitForEncoding = command == "prepare-recording" || command == "download-recording" || command == "stop";
    const reashoot::helper::ControlClient client(host, port, canWaitForEncoding ? 900 : (command == "pair" ? 120 : 20));
    if (command == "download-recording") {
      runDownloadRecording(args, client, host, required(args, "--token"));
      return 0;
    }
    if (command == "stop") {
      runStop(args, client, host, required(args, "--token"));
      return 0;
    }
    if (command == "prepare-recording") {
      const reashoot::helper::ControlClient progressClient(host, port, 5);
      const reashoot::core::ProtocolRecording recording = prepareRecordingWithProgress(client,
                                                                                      progressClient,
                                                                                      required(args, "--token"),
                                                                                      required(args, "--recording-id"),
                                                                                      args.hasFlag("--progress"));
      printRecording(recording);
      return 0;
    }
    reashoot::core::ProtocolCommand protocolCommand = commandForArgs(args);
    protocolCommand.requestID = reashoot::helper::randomUUID();
    const reashoot::core::ProtocolEvent event = client.send(protocolCommand);
    printCommandResult(command, event);
    return 0;
  } catch (const std::exception &error) {
    fail(error.what());
  }
}
