#include "../src/core/alignment_math.h"
#include "../src/core/capture_profile.h"
#include "../src/core/h264_annex_b.h"
#include "../src/core/helper_output_parser.h"
#include "../src/core/path_utils.h"
#include "../src/core/remote_camera.h"

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
  testCaptureProfileArguments();
  testRemoteCameraArguments();
  testH264AnnexB();
  testAlignmentMath();
  return 0;
}
