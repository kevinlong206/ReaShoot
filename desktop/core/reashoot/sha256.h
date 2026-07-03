#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace reashoot {

// Incremental SHA-256 hasher producing the lowercase hex digest used by the
// macOS helper's VideoSyncCore.Checksum, so downloaded-file checksums match.
class Sha256 {
public:
  Sha256();

  void update(const std::uint8_t *data, std::size_t size);
  void update(std::string_view data);

  // Returns the 64-character lowercase hex digest and resets the hasher.
  std::string finalizeHex();

private:
  void processBlock(const std::uint8_t *block);

  std::array<std::uint32_t, 8> state_{};
  std::array<std::uint8_t, 64> buffer_{};
  std::size_t bufferLength_ = 0;
  std::uint64_t totalLength_ = 0;
};

// Convenience helper hashing a single buffer.
std::string sha256Hex(std::string_view data);

} // namespace reashoot
