#include "../src/core/alignment_math.h"
#include "../src/core/capture_profile.h"
#include "../src/core/control_protocol.h"
#include "../src/core/h264_annex_b.h"
#include "../src/core/helper_output_parser.h"
#include "../src/core/log_sanitization.h"
#include "../src/core/path_utils.h"
#include "../src/core/remote_camera.h"
#include "../src/core/reashoot_controller.h"
#include "../src/core/reashoot_status.h"
#include "../src/core/ui_interfaces.h"
#include "../src/desktop/desktop_app_controller.h"
#include "../src/desktop/desktop_app_model.h"
#include "../src/desktop/desktop_integration_api.h"
#include "../src/desktop/desktop_workflow.h"

#include <cassert>
#include <cmath>
#include <string>
#include <vector>

using namespace reashoot::core;

void testPathUtils() {
  assert(hasPathExtension("Take.MOV", ".mov"));
  assert(isVideoPath("/tmp/a.mp4"));
  assert(directoryName("/tmp/project/song.rpp") == "/tmp/project");
  assert(baseNameWithoutExtension("/tmp/My Song!.rpp") == "My_Song_");
}

void testHelperParsing() {
  FieldMap fields = parseFields("recording\tid=abc\tfilename=take.mov\tbyteCount=42", '\t');
  assert(fields["id"] == "abc");
  assert(fields["filename"] == "take.mov");
  FieldMap windowsFields = parseFields("paired token=abc123\r", ' ');
  assert(windowsFields["token"] == "abc123");
  assert(parseDownloadedPath("downloaded C:\\tmp\\take.mov\r\n") == "C:\\tmp\\take.mov");
  assert(parseDownloadedPath("progress bytes=1\ndownloaded /tmp/take.mov\n") == "/tmp/take.mov");
  std::vector<FieldMap> recordings = parseRecordings("recording\tid=one\nrecording\tid=two\n");
  assert(recordings.size() == 2);
  assert(recordings[1]["id"] == "two");
  FieldMap device = parseFirstDevice("device\tname=iPhone\thost=phone.local\tcontrolPort=8787\n");
  assert(device["host"] == "phone.local");
  assert(progressStatusText("encode percent=42") == "Encoding iPhone look: 42%");
  assert(progressStatusText("encode") == "");
  assert(progressStatusText("encode ") == "Encoding iPhone look");
  assert(progressStatusText("progress percent=7") == "Downloading iPhone video: 7%");
  assert(progressStatusText("progress bytes=8 total=10") == "Downloading iPhone video: 8/10 bytes");
  assert(progressStatusText("ignored line") == "");
}

void testFriendlyStatusText() {
  assert(friendlyStatusText("Unauthorized") ==
         "iPhone authorization failed: reset pairing on the iPhone, then Pair again and accept the request on the iPhone.");
  assert(friendlyStatusText("error: Invalid pairing code.") ==
         "Pairing failed: press Pair again and accept the request on the iPhone.");
  assert(friendlyStatusText("Could not connect to the control socket: connection refused") ==
         "Could not connect to the iPhone control socket. Make sure the ReaShoot iOS app is open in the foreground, "
         "the iPhone is unlocked, and the phone and this computer are on the same Wi-Fi network. Then try Reconnect. "
         "If you recently reset pairing, pair again and accept the request on the iPhone. Details: connection refused");
  assert(friendlyStatusText("ReaShoot live video") == "ReaShoot live video");
  CaptureProfile profile{"", "4K", "30", "auto", "9:16", "wide", "1.0", "natural"};
  assert(previewStateText(false, false) == "preview idle");
  assert(previewStateText(false, true) == "preview connecting");
  assert(previewStateText(true, false) == "H.264 preview");
  assert(captureFormatText(profile, true, false) ==
         "iPhone Wi-Fi: 4K 30 fps, auto, 9:16, wide lens, 1.0x, look natural, H.264 preview");
}

void testReaShootControllerState() {
  ReaShootController controller;
  assert(!controller.videoEnabled());
  assert(controller.followEnabled());
  assert(controller.followStatusText() == "Video disabled");
  controller.setVideoEnabled(true);
  assert(controller.videoEnabled());
  assert(controller.followEnabled());
  assert(controller.followStatusText() == "Video enabled; transport follow on");
  controller.setFollowEnabled(false);
  assert(controller.videoEnabled());
  assert(!controller.followEnabled());
  assert(controller.followStatusText() == "Video enabled; transport follow off");
  controller.setVideoEnabled(false);
  assert(!controller.videoEnabled());
  assert(!controller.followEnabled());
  assert(controller.followStatusText() == "Video disabled");
}

void testCaptureProfileArguments() {
  CaptureProfile profile{"tok", "4K", "30", "portrait", "9:16", "wide", "1.0", "natural"};
  std::vector<std::string> args = captureProfileArguments(profile);
  assert(args.size() == 16);
  assert(args[0] == "--token");
  assert(args[1] == "tok");
  assert(args[14] == "--look");
  assert(args[15] == "natural");
}

void testRemoteCameraArguments() {
  RemoteCameraSettings settings;
  settings.host = "iphone.local";
  settings.controlPort = "8787";
  settings.httpPort = "8788";
  settings.token = "secret";
  settings.resolution = "1080p";
  settings.fps = "60";

  std::vector<std::string> configure = commandArguments(settings, "configure", configureArguments(settings));
  assert(configure.size() == 20);
  assert(configure[0] == "--host");
  assert(configure[1] == "iphone.local");
  assert(configure[2] == "--port");
  assert(configure[3] == "8787");
  assert(configure[4] == "--token");
  assert(configure[5] == "secret");
  assert(configure[7] == "1080p");

  std::vector<std::string> discover = commandArguments(settings, "discover", {"--timeout", "3"});
  assert(discover.size() == 2);
  assert(discover[0] == "--timeout");

  RemoteRecordingDescriptor recording;
  recording.id = "abc";
  std::vector<std::string> download = downloadArguments(settings, recording, "/tmp");
  assert(download[0] == "--http-port");
  assert(download[1] == "8788");
  assert(download[5] == "abc");
  assert(download[7] == "recording.mov");

  PreviewStreamDescriptor defaultPreview = previewStreamDescriptorFromFields({});
  assert(defaultPreview.streamPath == "/preview");
  assert(defaultPreview.port == 8789);
  FieldMap previewFields = parseFields("streamPath=/custom port=8799", ' ');
  PreviewStreamDescriptor customPreview = previewStreamDescriptorFromFields(previewFields);
  assert(customPreview.streamPath == "/custom");
  assert(customPreview.port == 8799);
  FieldMap invalidPreviewFields = parseFields("streamPath= port=-1", ' ');
  PreviewStreamDescriptor invalidPreview = previewStreamDescriptorFromFields(invalidPreviewFields);
  assert(invalidPreview.streamPath == "/preview");
  assert(invalidPreview.port == 8789);
}

void testLogSanitization() {
  assert(redactedText("paired token=secret\n") == "paired token=REDACTED\n");
  assert(redactedText("pairingCode=123456 code=abcdef token=secret") == "pairingCode=REDACTED code=REDACTED token=REDACTED");
  std::vector<std::string> args = {"configure", "--token", "secret", "--look", "natural"};
  assert(redactedArguments(args) == "configure --token REDACTED --look natural");
  RemoteCameraSettings settings;
  settings.host = "iphone.local";
  settings.token = "secret";
  settings.resolution = "4K";
  settings.fps = "30";
  settings.orientation = "auto";
  settings.aspect = "9:16";
  settings.lens = "wide";
  settings.zoom = "1.0";
  settings.look = "natural";
  const std::string summary = redactedSettingsSummary(settings);
  assert(summary.find("token=present") != std::string::npos);
  assert(summary.find("secret") == std::string::npos);
}

void testDesktopWorkflowParsing() {
  const auto cameras = reashoot::desktop::parseDiscoveredCameras(
      "noise\n"
      "device\tname=Kevin iPhone\thost=phone.local\tcontrolPort=8787\thttpPort=8788\tpaired=true\n"
      "device\tname=No Host\n");
  assert(cameras.size() == 1);
  assert(cameras[0].name == "Kevin iPhone");
  assert(cameras[0].host == "phone.local");
  assert(cameras[0].controlPort == "8787");
  assert(cameras[0].httpPort == "8788");
  assert(cameras[0].paired);

  const auto recordings = reashoot::desktop::parseRecordingDescriptors(
      "recording\tid=one\tfilename=take.mov\tbyteCount=42\tdownloadPath=/recordings/one\tchecksum=abc\n"
      "recording\tfilename=missing-id.mov\n");
  assert(recordings.size() == 1);
  assert(recordings[0].id == "one");
  assert(recordings[0].filename == "take.mov");
  assert(recordings[0].byteCount == "42");
  assert(recordings[0].downloadPath == "/recordings/one");
  assert(recordings[0].checksum == "abc");

  const PreviewStreamDescriptor preview = reashoot::desktop::parsePreviewDescriptor(
      "preview\tcodec=h264\ttransport=websocket\tstreamPath=/custom-preview\tport=8799\n");
  assert(preview.streamPath == "/custom-preview");
  assert(preview.port == 8799);

  assert(!reashoot::desktop::makeSessionID().empty());
  assert(reashoot::desktop::defaultDownloadDirectory().find("ReaShoot") != std::string::npos);
}

void testDesktopAppModel() {
  using namespace reashoot::desktop;
  assert(defaultResolution() == "4K");
  assert(defaultFps() == "30");
  assert(defaultOrientation() == "auto");
  assert(defaultAspect() == "9:16");
  assert(defaultLens() == "wide");
  assert(defaultZoom() == "1.0");
  assert(defaultLook() == "natural");
  assert(resolutionChoices().size() == 3);
  assert(lookChoices().size() >= 20);
  assert(lookChoices().front().title == "Natural");
  assert(lookChoices().front().value == "natural");
  assert(recordButtonTitle(false) == "Start Recording");
  assert(recordButtonTitle(true) == "Stop Recording");
  assert(previewButtonTitle(false) == "Start Preview");
  assert(previewButtonTitle(true) == "Stop Preview");
  assert(previewEmptyMessage(false, false, false) == "No iPhone selected.");
  assert(previewEmptyMessage(false, true, false) == "No paired iPhone.");
  assert(previewEmptyMessage(false, true, true) == "Preview stopped.");
  assert(previewEmptyMessage(true, true, true) == "Waiting for video from iPhone...");
  assert(isTransientConnectionFailure("Details: Connection reset by peer"));
  assert(isTransientConnectionFailure("No route to host"));
  assert(!isTransientConnectionFailure("Unauthorized"));
  CommandResult result;
  result.exitCode = 1;
  result.errorMessage = "connection refused";
  assert(isTransientConnectionFailure(result));

  RemoteCameraSettings settings;
  settings.host = "iphone.local";
  settings.httpPort = "8798";
  settings.token = "secret";
  RemoteRecordingDescriptor recording;
  recording.id = "clip-2026-07-05T12-34-56Z";
  recording.thumbnailPath = "/recordings/abc/thumbnail";
  assert(recordingTimestampFallback(recording) == "2026-07-05T12:34:56Z");
  assert(recordingThumbnailURL(settings, recording) == "http://iphone.local:8798/recordings/abc/thumbnail?token=secret");
  recording.createdAt = "2026-07-05T19:22:00Z";
  assert(recordingTimestampFallback(recording) == "2026-07-05T19:22:00Z");
  settings.token.clear();
  assert(recordingThumbnailURL(settings, recording).empty());
}

void testDesktopAppController() {
  reashoot::desktop::DesktopAppController controller;
  assert(controller.connectionStatusText() == "iPhone: No iPhone selected - Not paired");
  assert(controller.previewEmptyMessage() == "No iPhone selected.");
  assert(controller.buttonState().recordTitle == "Start Recording");
  assert(controller.buttonState().previewTitle == "Start Preview");

  controller.setHost("iphone.local");
  assert(controller.connectionStatusText() == "iPhone: iphone.local - Not paired");
  assert(controller.previewEmptyMessage() == "No paired iPhone.");
  controller.setToken("secret");
  assert(controller.canUsePhone());
  assert(controller.connectionStatusText() == "iPhone: iphone.local - Paired");
  assert(controller.previewEmptyMessage() == "Preview stopped.");

  controller.setPreviewDesired(true);
  controller.setPreviewRunning(true);
  controller.setRecording(true);
  assert(controller.previewEmptyMessage() == "Waiting for video from iPhone...");
  assert(controller.buttonState().recordTitle == "Stop Recording");
  assert(controller.buttonState().previewTitle == "Stop Preview");

  CommandResult transient;
  transient.exitCode = 1;
  transient.errorMessage = "No route to host";
  reashoot::desktop::PreviewRetryDecision retry = controller.retryDecision(transient, 0);
  assert(retry.shouldRetry);
  assert(retry.nextAttempt == 1);
  assert(retry.delaySeconds > 1.0);
  assert(retry.statusText.find("Retrying") != std::string::npos);

  CommandResult authFailure;
  authFailure.exitCode = 1;
  authFailure.errorMessage = "Unauthorized";
  assert(!controller.retryDecision(authFailure, 0).shouldRetry);
  controller.setPreviewDesired(false);
  assert(!controller.retryDecision(transient, 0).shouldRetry);
}

void testDesktopIntegrationApiModels() {
  using namespace reashoot::desktop;
  RemoteCameraSettings settings;
  settings.host = "iphone.local";
  settings.httpPort = "8798";
  settings.token = "phone-token";
  settings.resolution = "1080p";
  settings.fps = "60";
  settings.look = "warmVintage";

  JsonValue profile = profileToJson(settings);
  assert(profile.stringValue("resolution") == "1080p");
  assert(profile.stringValue("fps") == "60");
  assert(profile.stringValue("look") == "warmVintage");

  RemoteCameraSettings updated = settings;
  applyProfileJson(updated, parseJson(R"({"resolution":"4K","fps":"30","zoom":"2.0"})"));
  assert(updated.resolution == "4K");
  assert(updated.fps == "30");
  assert(updated.zoom == "2.0");
  assert(updated.look == "warmVintage");

  RemoteRecordingDescriptor recording;
  recording.id = "clip-2026-07-05T12-34-56Z";
  recording.filename = "take.mov";
  recording.byteCount = "42";
  recording.thumbnailPath = "/recordings/clip/thumbnail";
  JsonValue recordingJson = recordingToJson(settings, recording);
  assert(recordingJson.stringValue("filename") == "take.mov");
  assert(recordingJson.stringValue("timestamp") == "2026-07-05T12:34:56Z");
  assert(recordingJson.stringValue("thumbnailUrl") == "http://iphone.local:8798/recordings/clip/thumbnail?token=phone-token");

  IntegrationStatus status;
  status.paired = true;
  status.previewRunning = true;
  status.host = "iphone.local";
  status.message = "Preview streaming.";
  status.profile = settings;
  JsonValue statusJson = statusToJson(status);
  assert(statusJson.stringValue("apiVersion") == "v1");
  assert(statusJson.boolValue("paired"));
  assert(statusJson.find("profile")->stringValue("resolution") == "1080p");

  IntegrationHttpRequest request;
  request.headers["Authorization"] = "Bearer secret";
  assert(requestHasValidToken(request, "secret"));
  assert(!requestHasValidToken(request, "other"));
  request.headers.clear();
  request.query = "token=secret";
  assert(requestHasValidToken(request, "secret"));
  assert(errorResponse(401, "unauthorized", "Nope").status == 401);
  assert(acceptedResponse("Queued").status == 202);
}

void testJsonValue() {
  JsonValue value = parseJson(R"({"name":"phone","port":8787,"flags":[true,false],"nested":{"x":"y"}})");
  assert(value.stringValue("name") == "phone");
  assert(value.intValue("port") == 8787);
  assert(value.find("flags")->asArray().size() == 2);
  assert(value.find("nested")->stringValue("x") == "y");
  assert(parseJson(value.serialize()).stringValue("name") == "phone");
}

void testControlProtocol() {
  ProtocolCommand command;
  command.requestID = "00000000-0000-0000-0000-000000000001";
  command.type = "configureCapture";
  command.token = "secret";
  command.metadata["clientName"] = "Test Mac";
  command.hasCaptureProfile = true;
  command.captureProfile.resolution = "1080p";
  command.captureProfile.fps = 30;
  command.captureProfile.look = "warmVintage";
  const std::string commandJson = encodeCommandJson(command);
  JsonValue encoded = parseJson(commandJson);
  assert(encoded.stringValue("type") == "configureCapture");
  assert(encoded.stringValue("token") == "secret");
  assert(encoded.find("metadata")->stringValue("clientName") == "Test Mac");
  assert(encoded.find("captureProfile")->stringValue("look") == "warmVintage");

  const std::string eventJson = R"({
    "type":"recordingsListed",
    "protocolVersion":1,
    "recordings":[
      {"id":"one","filename":"take.mov","byteCount":42,"checksumSHA256":"abc","downloadPath":"/recordings/one"},
      {"id":"two","filename":"take2.mov","byteCount":84,"downloadPath":"/recordings/two"}
    ],
    "preview":{"codec":"h264","transport":"websocket","streamPath":"/preview","port":8789,"width":640,"height":360,"fps":12,"orientation":"portrait","requiresToken":true}
  })";
  ProtocolEvent event = decodeEventJson(eventJson);
  assert(event.type == "recordingsListed");
  assert(event.recordings.size() == 2);
  assert(event.recordings[0].checksumSHA256 == "abc");
  assert(event.hasPreview);
  assert(event.preview.port == 8789);

  ProtocolEvent oldProfileEvent = decodeEventJson(R"({"type":"captureConfigured","captureProfile":{"resolution":"4K"}})");
  assert(oldProfileEvent.hasCaptureProfile);
  assert(oldProfileEvent.captureProfile.fps == 30);
  assert(oldProfileEvent.captureProfile.orientation == "auto");
  assert(oldProfileEvent.captureProfile.look == "natural");
}

void testH264AnnexB() {
  const uint8_t bytes[] = {
      0, 0, 0, 1, 0x67, 1, 2,
      0, 0, 1, 0x68, 3,
      0, 0, 0, 1, 0x65, 4, 5,
  };
  std::vector<H264NalUnit> units = splitAnnexB(bytes, sizeof(bytes));
  assert(units.size() == 3);
  assert(units[0].type == 7);
  assert(units[1].type == 8);
  assert(units[2].type == 5);
  assert(units[2].size == 3);
}

void testAlignmentMath() {
  std::vector<double> a = normalizedEnvelope({0.0, 1.0, 0.0});
  std::vector<double> b = normalizedEnvelope({0.0, 1.0, 0.0});
  assert(!a.empty());
  assert(!b.empty());
  double score = normalizedCorrelationAtLag(a, b, 0, 2);
  assert(score > 0.99);
  std::vector<TransientPeak> peaks = strongestTransientPeaks({0.0, 1.0, 0.0, 0.5, 0.0}, 10.0);
  assert(!peaks.empty());
  assert(peaks.front().index == 1);
}

int main() {
  testPathUtils();
  testHelperParsing();
  testFriendlyStatusText();
  testReaShootControllerState();
  testCaptureProfileArguments();
  testRemoteCameraArguments();
  testLogSanitization();
  testDesktopWorkflowParsing();
  testDesktopAppModel();
  testDesktopAppController();
  testDesktopIntegrationApiModels();
  testJsonValue();
  testControlProtocol();
  testH264AnnexB();
  testAlignmentMath();
  return 0;
}
