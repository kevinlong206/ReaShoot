#pragma once

#include "reashoot/webrtc_receiver.h"

#include <string>
#include <vector>

namespace reashoot {

// Result of splitting a remote WebRTC answer into a candidate-free session
// description plus the ICE candidates that were carried inline.
struct StrippedAnswer {
  std::string sdp;                      // cleaned SDP, CRLF-terminated
  std::vector<WebRTCSignal> candidates; // extracted inline ICE candidates
};

// Removes inline "a=candidate:" (and "a=end-of-candidates") lines from a WebRTC
// answer SDP, returning the cleaned SDP plus the extracted candidates as
// WebRTCSignal::Candidate entries. This mirrors the macOS
// -webRTCAnswerSDPByRemovingInlineCandidates: helper: the iPhone's LiveKit
// answer may include inline candidates that libwebrtc's parser rejects, so the
// desktop strips them and adds them separately via addIceCandidate.
StrippedAnswer stripInlineIceCandidates(const std::string &answerSDP);

} // namespace reashoot
