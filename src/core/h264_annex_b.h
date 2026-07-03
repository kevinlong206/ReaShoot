#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace reashoot::core {

struct H264NalUnit {
  size_t offset = 0;
  size_t size = 0;
  uint8_t type = 0;
};

size_t h264StartCodeLengthAt(const uint8_t *bytes, size_t length, size_t offset);
std::vector<H264NalUnit> splitAnnexB(const uint8_t *bytes, size_t length);

} // namespace reashoot::core
