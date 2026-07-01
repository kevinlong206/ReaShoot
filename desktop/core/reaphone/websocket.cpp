#include "reaphone/websocket.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

namespace reaphone {
namespace {

constexpr std::string_view kWebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
constexpr char kBase64Alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::uint32_t rotateLeft(std::uint32_t value, int bits) {
  return (value << bits) | (value >> (32 - bits));
}

std::array<std::uint8_t, 20> sha1(std::string_view input) {
  std::vector<std::uint8_t> message(input.begin(), input.end());
  const std::uint64_t bitLength = static_cast<std::uint64_t>(message.size()) * 8;
  message.push_back(0x80);
  while ((message.size() % 64) != 56) {
    message.push_back(0);
  }
  for (int shift = 56; shift >= 0; shift -= 8) {
    message.push_back(static_cast<std::uint8_t>((bitLength >> shift) & 0xff));
  }

  std::uint32_t h0 = 0x67452301;
  std::uint32_t h1 = 0xefcdab89;
  std::uint32_t h2 = 0x98badcfe;
  std::uint32_t h3 = 0x10325476;
  std::uint32_t h4 = 0xc3d2e1f0;

  for (std::size_t chunk = 0; chunk < message.size(); chunk += 64) {
    std::array<std::uint32_t, 80> words{};
    for (std::size_t i = 0; i < 16; ++i) {
      const std::size_t offset = chunk + i * 4;
      words[i] = (static_cast<std::uint32_t>(message[offset]) << 24) |
                 (static_cast<std::uint32_t>(message[offset + 1]) << 16) |
                 (static_cast<std::uint32_t>(message[offset + 2]) << 8) |
                 static_cast<std::uint32_t>(message[offset + 3]);
    }
    for (std::size_t i = 16; i < words.size(); ++i) {
      words[i] = rotateLeft(words[i - 3] ^ words[i - 8] ^ words[i - 14] ^ words[i - 16], 1);
    }

    std::uint32_t a = h0;
    std::uint32_t b = h1;
    std::uint32_t c = h2;
    std::uint32_t d = h3;
    std::uint32_t e = h4;

    for (std::size_t i = 0; i < words.size(); ++i) {
      std::uint32_t f = 0;
      std::uint32_t k = 0;
      if (i < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5a827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ed9eba1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8f1bbcdc;
      } else {
        f = b ^ c ^ d;
        k = 0xca62c1d6;
      }

      const std::uint32_t temp = rotateLeft(a, 5) + f + e + k + words[i];
      e = d;
      d = c;
      c = rotateLeft(b, 30);
      b = a;
      a = temp;
    }

    h0 += a;
    h1 += b;
    h2 += c;
    h3 += d;
    h4 += e;
  }

  std::array<std::uint8_t, 20> digest{};
  const std::array<std::uint32_t, 5> words = {h0, h1, h2, h3, h4};
  for (std::size_t i = 0; i < words.size(); ++i) {
    digest[i * 4] = static_cast<std::uint8_t>((words[i] >> 24) & 0xff);
    digest[i * 4 + 1] = static_cast<std::uint8_t>((words[i] >> 16) & 0xff);
    digest[i * 4 + 2] = static_cast<std::uint8_t>((words[i] >> 8) & 0xff);
    digest[i * 4 + 3] = static_cast<std::uint8_t>(words[i] & 0xff);
  }
  return digest;
}

std::string base64Encode(const std::uint8_t *bytes, std::size_t size) {
  std::string encoded;
  encoded.reserve(((size + 2) / 3) * 4);
  for (std::size_t i = 0; i < size; i += 3) {
    const std::uint32_t octetA = bytes[i];
    const std::uint32_t octetB = i + 1 < size ? bytes[i + 1] : 0;
    const std::uint32_t octetC = i + 2 < size ? bytes[i + 2] : 0;
    const std::uint32_t triple = (octetA << 16) | (octetB << 8) | octetC;

    encoded.push_back(kBase64Alphabet[(triple >> 18) & 0x3f]);
    encoded.push_back(kBase64Alphabet[(triple >> 12) & 0x3f]);
    encoded.push_back(i + 1 < size ? kBase64Alphabet[(triple >> 6) & 0x3f] : '=');
    encoded.push_back(i + 2 < size ? kBase64Alphabet[triple & 0x3f] : '=');
  }
  return encoded;
}

bool tokenListContains(std::string value, std::string_view expected) {
  std::size_t start = 0;
  while (start <= value.size()) {
    const std::size_t comma = value.find(',', start);
    const std::size_t end = comma == std::string::npos ? value.size() : comma;
    if (trimAsciiWhitespace(std::string_view(value).substr(start, end - start)) == expected) {
      return true;
    }
    if (comma == std::string::npos) {
      break;
    }
    start = comma + 1;
  }
  return false;
}

} // namespace

std::string webSocketAcceptKey(std::string_view clientKey) {
  std::string material(clientKey);
  material.append(kWebSocketGuid);
  const auto digest = sha1(material);
  return base64Encode(digest.data(), digest.size());
}

bool isWebSocketSwitchingProtocolsResponse(const HttpHeaders &headers, std::string_view clientKey) {
  if (headers.startLine.find("101") == std::string::npos) {
    return false;
  }

  const auto upgrade = headers.value("upgrade");
  const auto connection = headers.value("connection");
  const auto accept = headers.value("sec-websocket-accept");

  return upgrade && *upgrade == "websocket" &&
         connection && tokenListContains(*connection, "Upgrade") &&
         accept && *accept == webSocketAcceptKey(clientKey);
}

} // namespace reaphone
