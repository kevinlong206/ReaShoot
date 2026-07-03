#include "reashoot/webrtc_sdp.h"

#include <map>

namespace reashoot {
namespace {

// Trims all trailing carriage returns so lines split on '\n' compare cleanly
// regardless of LF, CRLF, or the CR-doubled CRCRLF that Windows text-mode
// stdout produces when it re-translates already-CRLF SDP from the helper.
std::string trimTrailingCR(const std::string &line) {
  std::size_t end = line.size();
  while (end > 0 && line[end - 1] == '\r') {
    --end;
  }
  return line.substr(0, end);
}

bool startsWith(const std::string &value, const char *prefix) {
  const std::string p(prefix);
  return value.size() >= p.size() && value.compare(0, p.size(), p) == 0;
}

} // namespace

StrippedAnswer stripInlineIceCandidates(const std::string &answerSDP) {
  StrippedAnswer result;
  std::vector<std::string> keptLines;

  std::string currentMid;
  int currentMLineIndex = -1;

  // Candidate lines may appear before their section's "a=mid:" line (some
  // iOS/WebRTC stacks emit all candidates first), so remember which candidates
  // belonged to which m-line index and resolve their mid after the full parse.
  std::vector<std::size_t> candidateMLineIndex;
  std::map<int, std::string> midByMLineIndex;

  std::size_t start = 0;
  while (start <= answerSDP.size()) {
    std::size_t newline = answerSDP.find('\n', start);
    const bool last = newline == std::string::npos;
    std::string line = trimTrailingCR(
        answerSDP.substr(start, last ? std::string::npos : newline - start));
    start = last ? answerSDP.size() + 1 : newline + 1;

    if (line.empty()) {
      continue;
    }
    if (startsWith(line, "m=")) {
      currentMLineIndex += 1;
    }
    if (startsWith(line, "a=mid:")) {
      currentMid = line.substr(std::string("a=mid:").size());
      if (currentMLineIndex >= 0) {
        midByMLineIndex[currentMLineIndex] = currentMid;
      }
    }
    if (startsWith(line, "a=candidate:")) {
      WebRTCSignal candidate;
      candidate.type = WebRTCSignal::Type::Candidate;
      candidate.payload = line.substr(std::string("a=").size());
      candidate.mid = currentMid;
      candidate.mlineIndex = currentMLineIndex < 0 ? 0 : currentMLineIndex;
      candidateMLineIndex.push_back(result.candidates.size());
      result.candidates.push_back(std::move(candidate));
      continue;
    }
    if (startsWith(line, "a=end-of-candidates")) {
      continue;
    }
    keptLines.push_back(std::move(line));
  }

  // Resolve any candidate whose mid was still unknown when it was parsed
  // (candidate line preceded its "a=mid:" line) from the completed index map.
  for (std::size_t index : candidateMLineIndex) {
    WebRTCSignal &candidate = result.candidates[index];
    if (candidate.mid.empty()) {
      auto found = midByMLineIndex.find(candidate.mlineIndex);
      if (found != midByMLineIndex.end()) {
        candidate.mid = found->second;
      }
    }
  }

  std::string cleaned;
  for (const std::string &line : keptLines) {
    cleaned += line;
    cleaned += "\r\n";
  }
  result.sdp = std::move(cleaned);
  return result;
}

} // namespace reashoot
