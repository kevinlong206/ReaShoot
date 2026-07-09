#include "checksum.h"

#include "control_client.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace reashoot::transport {
namespace {

uint32_t rotr(uint32_t value, int bits) {
  return (value >> bits) | (value << (32 - bits));
}

constexpr uint32_t kSha256Constants[] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

struct Sha256State {
  uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  std::array<uint8_t, 64> block = {};
  size_t blockLength = 0;
  uint64_t totalBytes = 0;
};

void processBlock(Sha256State &state, const uint8_t *block) {
  uint32_t w[64] = {};
  for (int i = 0; i < 16; ++i) {
    const size_t offset = static_cast<size_t>(i * 4);
    w[i] = (static_cast<uint32_t>(block[offset]) << 24) |
           (static_cast<uint32_t>(block[offset + 1]) << 16) |
           (static_cast<uint32_t>(block[offset + 2]) << 8) |
           static_cast<uint32_t>(block[offset + 3]);
  }
  for (int i = 16; i < 64; ++i) {
    const uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
    const uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }

  uint32_t a = state.h[0], b = state.h[1], c = state.h[2], d = state.h[3];
  uint32_t e = state.h[4], f = state.h[5], g = state.h[6], hh = state.h[7];
  for (int i = 0; i < 64; ++i) {
    const uint32_t s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    const uint32_t ch = (e & f) ^ ((~e) & g);
    const uint32_t temp1 = hh + s1 + ch + kSha256Constants[i] + w[i];
    const uint32_t s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    const uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
    const uint32_t temp2 = s0 + maj;
    hh = g;
    g = f;
    f = e;
    e = d + temp1;
    d = c;
    c = b;
    b = a;
    a = temp1 + temp2;
  }
  state.h[0] += a;
  state.h[1] += b;
  state.h[2] += c;
  state.h[3] += d;
  state.h[4] += e;
  state.h[5] += f;
  state.h[6] += g;
  state.h[7] += hh;
}

void update(Sha256State &state, const uint8_t *data, size_t length) {
  state.totalBytes += length;
  size_t offset = 0;
  while (offset < length) {
    const size_t count = std::min(state.block.size() - state.blockLength, length - offset);
    std::copy(data + offset, data + offset + count, state.block.data() + state.blockLength);
    state.blockLength += count;
    offset += count;
    if (state.blockLength == state.block.size()) {
      processBlock(state, state.block.data());
      state.blockLength = 0;
    }
  }
}

std::string finishHex(Sha256State &state) {
  const uint64_t bitLength = state.totalBytes * 8;
  state.block[state.blockLength++] = 0x80;
  if (state.blockLength > 56) {
    while (state.blockLength < state.block.size()) {
      state.block[state.blockLength++] = 0;
    }
    processBlock(state, state.block.data());
    state.blockLength = 0;
  }
  while (state.blockLength < 56) {
    state.block[state.blockLength++] = 0;
  }
  for (int i = 7; i >= 0; --i) {
    state.block[state.blockLength++] = static_cast<uint8_t>((bitLength >> (i * 8)) & 0xff);
  }
  processBlock(state, state.block.data());

  std::ostringstream output;
  for (const uint32_t word : state.h) {
    output << std::hex << std::setfill('0') << std::setw(8) << word;
  }
  return output.str();
}

} // namespace

std::string sha256FileHex(const std::string &path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    throw TransportError("Could not open file for checksum: " + path);
  }
  Sha256State state;
  std::array<char, 64 * 1024> buffer = {};
  while (file) {
    file.read(buffer.data(), buffer.size());
    const std::streamsize count = file.gcount();
    if (count > 0) {
      update(state, reinterpret_cast<const uint8_t *>(buffer.data()), static_cast<size_t>(count));
    }
  }
  return finishHex(state);
}

} // namespace reashoot::transport
