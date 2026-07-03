#include "../src/core/alignment_math.h"
#include "../src/core/capture_profile.h"
#include "../src/core/control_protocol.h"
#include "../src/core/h264_annex_b.h"
#include "../src/core/helper_output_parser.h"
#include "../src/core/path_utils.h"
#include "../src/core/remote_camera.h"
#include "../src/core/reashoot_controller.h"
#include "../src/core/reashoot_status.h"
#include "../src/core/ui_interfaces.h"

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
         "iPhone authorization failed: reset pairing on the iPhone, enter the new code in Setup, then Pair again.");
  assert(friendlyStatusText("error: Invalid pairing code.") ==
         "Invalid pairing code: check the six-digit code on the iPhone and press Pair again.");
  assert(friendlyStatusText("control socket: connection closed") ==
         "iPhone connection closed. If you reset pairing, enter the current code and Pair again.");
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
  command.hasCaptureProfile = true;
  command.captureProfile.resolution = "1080p";
  command.captureProfile.fps = 30;
  command.captureProfile.look = "warmVintage";
  const std::string commandJson = encodeCommandJson(command);
  JsonValue encoded = parseJson(commandJson);
  assert(encoded.stringValue("type") == "configureCapture");
  assert(encoded.stringValue("token") == "secret");
  assert(encoded.find("metadata")->asObject().empty());
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
  testJsonValue();
  testControlProtocol();
  testH264AnnexB();
  testAlignmentMath();
  return 0;
}
