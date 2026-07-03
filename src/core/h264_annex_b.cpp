#include "h264_annex_b.h"

namespace reashoot::core {

size_t h264StartCodeLengthAt(const uint8_t *bytes, size_t length, size_t offset) {
  if (!bytes) {
    return 0;
  }
  if (offset + 3 <= length && bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 1) {
    return 3;
  }
  if (offset + 4 <= length && bytes[offset] == 0 && bytes[offset + 1] == 0 && bytes[offset + 2] == 0 && bytes[offset + 3] == 1) {
    return 4;
  }
  return 0;
}

std::vector<H264NalUnit> splitAnnexB(const uint8_t *bytes, size_t length) {
  std::vector<H264NalUnit> units;
  if (!bytes || length == 0) {
    return units;
  }

  size_t offset = 0;
  while (offset < length) {
    size_t codeLength = 0;
    while (offset < length && (codeLength = h264StartCodeLengthAt(bytes, length, offset)) == 0) {
      ++offset;
    }
    if (offset >= length) {
      break;
    }
    const size_t naluStart = offset + codeLength;
    offset = naluStart;
    while (offset < length && h264StartCodeLengthAt(bytes, length, offset) == 0) {
      ++offset;
    }
    if (offset > naluStart) {
      units.push_back({naluStart, offset - naluStart, static_cast<uint8_t>(bytes[naluStart] & 0x1f)});
    }
  }
  return units;
}

} // namespace reashoot::core
