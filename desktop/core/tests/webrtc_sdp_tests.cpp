#include "reashoot/webrtc_sdp.h"

#include <cassert>
#include <iostream>

namespace {

void testStripsCandidateLines() {
  const std::string answer =
      "v=0\r\n"
      "o=- 1 2 IN IP4 127.0.0.1\r\n"
      "s=-\r\n"
      "m=video 9 UDP/TLS/RTP/SAVPF 96\r\n"
      "a=mid:0\r\n"
      "a=candidate:1 1 udp 2122260223 192.168.1.5 51000 typ host\r\n"
      "a=candidate:2 1 udp 2122194687 10.0.0.7 51002 typ host\r\n"
      "a=end-of-candidates\r\n"
      "a=recvonly\r\n";

  reashoot::StrippedAnswer stripped = reashoot::stripInlineIceCandidates(answer);

  // No candidate/end-of-candidates lines survive in the cleaned SDP.
  assert(stripped.sdp.find("a=candidate:") == std::string::npos);
  assert(stripped.sdp.find("a=end-of-candidates") == std::string::npos);
  // Kept lines are preserved and CRLF terminated.
  assert(stripped.sdp.find("a=mid:0\r\n") != std::string::npos);
  assert(stripped.sdp.find("a=recvonly\r\n") != std::string::npos);

  assert(stripped.candidates.size() == 2);
  for (const auto &candidate : stripped.candidates) {
    assert(candidate.type == reashoot::WebRTCSignal::Type::Candidate);
    assert(candidate.mid == "0");
    assert(candidate.mlineIndex == 0);
    // The leading "a=" is removed so the payload starts with "candidate:".
    assert(candidate.payload.rfind("candidate:", 0) == 0);
  }
  assert(stripped.candidates[0].payload.find("192.168.1.5") != std::string::npos);
}

void testMLineIndexTracksMultipleSections() {
  const std::string answer =
      "v=0\r\n"
      "m=audio 9 UDP/TLS/RTP/SAVPF 111\r\n"
      "a=mid:audio\r\n"
      "a=candidate:1 1 udp 100 192.168.1.5 40000 typ host\r\n"
      "m=video 9 UDP/TLS/RTP/SAVPF 96\r\n"
      "a=mid:video\r\n"
      "a=candidate:2 1 udp 100 192.168.1.5 40002 typ host\r\n";

  reashoot::StrippedAnswer stripped = reashoot::stripInlineIceCandidates(answer);
  assert(stripped.candidates.size() == 2);
  assert(stripped.candidates[0].mid == "audio");
  assert(stripped.candidates[0].mlineIndex == 0);
  assert(stripped.candidates[1].mid == "video");
  assert(stripped.candidates[1].mlineIndex == 1);
}

void testHandlesLFOnlyAndNoCandidates() {
  const std::string answer = "v=0\no=- 1 2 IN IP4 127.0.0.1\nm=video 9 RTP 96\na=recvonly\n";
  reashoot::StrippedAnswer stripped = reashoot::stripInlineIceCandidates(answer);
  assert(stripped.candidates.empty());
  // Output is normalized to CRLF regardless of the LF-only input.
  assert(stripped.sdp.find("v=0\r\n") != std::string::npos);
  assert(stripped.sdp.find("a=recvonly\r\n") != std::string::npos);
}

void testNormalizesDoubledCarriageReturns() {
  // Windows text-mode stdout re-translates the helper's already-CRLF SDP,
  // producing CRCRLF line endings that libwebrtc's parser rejects. The cleaner
  // must collapse them to a single CRLF and strip the stray CR from candidate
  // payloads.
  const std::string answer =
      "v=0\r\r\n"
      "o=- 1 2 IN IP4 127.0.0.1\r\r\n"
      "m=video 9 UDP/TLS/RTP/SAVPF 96\r\r\n"
      "a=group:BUNDLE 0\r\r\n"
      "a=mid:0\r\r\n"
      "a=candidate:1 1 udp 2122260223 192.168.1.5 51000 typ host\r\r\n"
      "a=recvonly\r\r\n";

  reashoot::StrippedAnswer stripped = reashoot::stripInlineIceCandidates(answer);

  // No doubled carriage returns survive anywhere in the cleaned SDP.
  assert(stripped.sdp.find("\r\r") == std::string::npos);
  assert(stripped.sdp.find("v=0\r\n") != std::string::npos);
  assert(stripped.sdp.find("a=group:BUNDLE 0\r\n") != std::string::npos);
  assert(stripped.sdp.find("a=mid:0\r\n") != std::string::npos);
  assert(stripped.sdp.find("a=recvonly\r\n") != std::string::npos);

  // The candidate payload is free of any trailing carriage return.
  assert(stripped.candidates.size() == 1);
  assert(stripped.candidates[0].payload.find('\r') == std::string::npos);
  assert(stripped.candidates[0].payload.rfind("candidate:", 0) == 0);
}

void testResolvesMidWhenCandidatesPrecedeMidLine() {
  // Some iOS/WebRTC stacks emit every a=candidate line before the section's
  // a=mid line. The parser must still associate candidates with the correct
  // mid (resolved after the full parse), not leave them blank.
  const std::string answer =
      "v=0\r\n"
      "a=group:BUNDLE 0\r\n"
      "m=video 50795 UDP/TLS/RTP/SAVPF 109\r\n"
      "a=candidate:489139435 1 udp 2122194687 10.0.0.103 50795 typ host\r\n"
      "a=candidate:3817699455 1 tcp 1518214911 10.0.0.103 52998 typ host tcptype passive\r\n"
      "a=mid:0\r\n"
      "a=recvonly\r\n";

  reashoot::StrippedAnswer stripped = reashoot::stripInlineIceCandidates(answer);
  assert(stripped.candidates.size() == 2);
  for (const auto &candidate : stripped.candidates) {
    assert(candidate.mid == "0");
    assert(candidate.mlineIndex == 0);
  }
  // The mid line itself is retained in the cleaned SDP.
  assert(stripped.sdp.find("a=mid:0\r\n") != std::string::npos);
}

} // namespace

int main() {
  testStripsCandidateLines();
  testMLineIndexTracksMultipleSections();
  testHandlesLFOnlyAndNoCandidates();
  testNormalizesDoubledCarriageReturns();
  testResolvesMidWhenCandidatesPrecedeMidLine();
  std::cout << "webrtc_sdp_tests passed\n";
  return 0;
}
