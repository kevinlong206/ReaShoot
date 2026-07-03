#include "checksum.h"

#include "control_client.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <vector>

namespace reashoot::helper {
namespace {

uint32_t rotr(uint32_t value, int bits) {
  return (value >> bits) | (value << (32 - bits));
}

std::string sha256Hex(const std::vector<uint8_t> &input) {
  static constexpr uint32_t k[] = {
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
      0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
      0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
      0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
      0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
      0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

  std::vector<uint8_t> message = input;
  const uint64_t bitLength = static_cast<uint64_t>(message.size()) * 8;
  message.push_back(0x80);
  while ((message.size() % 64) != 56) {
    message.push_back(0);
  }
  for (int i = 7; i >= 0; --i) {
    message.push_back(static_cast<uint8_t>((bitLength >> (i * 8)) & 0xff));
  }

  uint32_t h[] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  for (size_t chunk = 0; chunk < message.size(); chunk += 64) {
    uint32_t w[64] = {};
    for (int i = 0; i < 16; ++i) {
      const size_t offset = chunk + static_cast<size_t>(i * 4);
      w[i] = (static_cast<uint32_t>(message[offset]) << 24) |
             (static_cast<uint32_t>(message[offset + 1]) << 16) |
             (static_cast<uint32_t>(message[offset + 2]) << 8) |
             static_cast<uint32_t>(message[offset + 3]);
    }
    for (int i = 16; i < 64; ++i) {
      const uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      const uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (int i = 0; i < 64; ++i) {
      const uint32_t s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const uint32_t ch = (e & f) ^ ((~e) & g);
      const uint32_t temp1 = hh + s1 + ch + k[i] + w[i];
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
    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
    h[5] += f;
    h[6] += g;
    h[7] += hh;
  }

  std::ostringstream output;
  for (const uint32_t word : h) {
    output << std::hex << std::setfill('0') << std::setw(8) << word;
  }
  return output.str();
}

} // namespace

std::string sha256FileHex(const std::string &path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    throw HelperError("Could not open file for checksum: " + path);
  }
  std::vector<uint8_t> data;
  std::array<char, 1024 * 1024> buffer = {};
  while (file) {
    file.read(buffer.data(), buffer.size());
    const std::streamsize count = file.gcount();
    if (count > 0) {
      data.insert(data.end(), buffer.begin(), buffer.begin() + count);
    }
  }
  return sha256Hex(data);
}

} // namespace reashoot::helper
