#include "control_client.h"

#include <cctype>
#include <random>
#include <sstream>
#include <utility>
#include <vector>

namespace reashoot::helper {
namespace {

uint32_t leftRotate(uint32_t value, int bits) {
  return (value << bits) | (value >> (32 - bits));
}

std::string sha1(const std::string &input) {
  std::vector<uint8_t> message(input.begin(), input.end());
  const uint64_t bitLength = static_cast<uint64_t>(message.size()) * 8;
  message.push_back(0x80);
  while ((message.size() % 64) != 56) {
    message.push_back(0);
  }
  for (int i = 7; i >= 0; --i) {
    message.push_back(static_cast<uint8_t>((bitLength >> (i * 8)) & 0xff));
  }

  uint32_t h0 = 0x67452301;
  uint32_t h1 = 0xefcdab89;
  uint32_t h2 = 0x98badcfe;
  uint32_t h3 = 0x10325476;
  uint32_t h4 = 0xc3d2e1f0;

  for (size_t chunk = 0; chunk < message.size(); chunk += 64) {
    uint32_t w[80] = {};
    for (int i = 0; i < 16; ++i) {
      const size_t offset = chunk + static_cast<size_t>(i * 4);
      w[i] = (static_cast<uint32_t>(message[offset]) << 24) |
             (static_cast<uint32_t>(message[offset + 1]) << 16) |
             (static_cast<uint32_t>(message[offset + 2]) << 8) |
             static_cast<uint32_t>(message[offset + 3]);
    }
    for (int i = 16; i < 80; ++i) {
      w[i] = leftRotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }

    uint32_t a = h0;
    uint32_t b = h1;
    uint32_t c = h2;
    uint32_t d = h3;
    uint32_t e = h4;
    for (int i = 0; i < 80; ++i) {
      uint32_t f = 0;
      uint32_t k = 0;
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
      const uint32_t temp = leftRotate(a, 5) + f + e + k + w[i];
      e = d;
      d = c;
      c = leftRotate(b, 30);
      b = a;
      a = temp;
    }
    h0 += a;
    h1 += b;
    h2 += c;
    h3 += d;
    h4 += e;
  }

  std::string digest;
  digest.reserve(20);
  for (uint32_t word : {h0, h1, h2, h3, h4}) {
    digest.push_back(static_cast<char>((word >> 24) & 0xff));
    digest.push_back(static_cast<char>((word >> 16) & 0xff));
    digest.push_back(static_cast<char>((word >> 8) & 0xff));
    digest.push_back(static_cast<char>(word & 0xff));
  }
  return digest;
}

std::string base64Encode(const std::string &bytes) {
  static constexpr char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  std::string output;
  int value = 0;
  int bits = -6;
  for (uint8_t byte : bytes) {
    value = (value << 8) + byte;
    bits += 8;
    while (bits >= 0) {
      output.push_back(alphabet[(value >> bits) & 0x3f]);
      bits -= 6;
    }
  }
  if (bits > -6) {
    output.push_back(alphabet[((value << 8) >> (bits + 8)) & 0x3f]);
  }
  while (output.size() % 4) {
    output.push_back('=');
  }
  return output;
}

std::string randomBytes(size_t count) {
  std::random_device device;
  std::mt19937 generator(device());
  std::uniform_int_distribution<int> distribution(0, 255);
  std::string bytes;
  bytes.reserve(count);
  for (size_t i = 0; i < count; ++i) {
    bytes.push_back(static_cast<char>(distribution(generator)));
  }
  return bytes;
}

std::string readExact(SocketHandle socket, size_t count) {
  std::string data(count, '\0');
  size_t offset = 0;
  while (offset < count) {
    const int result = receiveSocketBytes(socket, data.data() + offset, count - offset);
    if (result <= 0) {
      throw HelperError("Could not connect to the control socket: connection closed");
    }
    offset += static_cast<size_t>(result);
  }
  return data;
}

void writeAll(SocketHandle socket, const std::string &data) {
  size_t offset = 0;
  while (offset < data.size()) {
    const int result = sendSocketBytes(socket, data.data() + offset, data.size() - offset);
    if (result <= 0) {
      throw HelperError("Could not connect to the control socket: " + socketErrorMessage());
    }
    offset += static_cast<size_t>(result);
  }
}

std::string lowercase(std::string value) {
  for (char &c : value) {
    c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
  }
  return value;
}

std::string headerValue(const std::string &headers, const std::string &name) {
  const std::string prefix = lowercase(name) + ":";
  std::istringstream stream(headers);
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    const std::string lower = lowercase(line);
    if (lower.rfind(prefix, 0) == 0) {
      size_t start = prefix.size();
      while (start < line.size() && std::isspace(static_cast<unsigned char>(line[start]))) {
        ++start;
      }
      return line.substr(start);
    }
  }
  return {};
}

} // namespace

ControlClient::ControlClient(std::string host, int port, int timeoutSeconds)
    : host_(std::move(host)), port_(port), timeoutSeconds_(timeoutSeconds) {}

core::ProtocolEvent ControlClient::send(const core::ProtocolCommand &command) const {
  const SocketHandle socket = openSocket();
  try {
    performHandshake(socket);
    sendFrame(socket, core::encodeCommandJson(command));
    const std::string response = receiveFrame(socket);
    closeSocket(socket);
    return core::decodeEventJson(response);
  } catch (...) {
    closeSocket(socket);
    throw;
  }
}

SocketHandle ControlClient::openSocket() const {
  return connectTcpSocket(host_, port_, timeoutSeconds_, "the control socket");
}

void ControlClient::performHandshake(SocketHandle socket) const {
  const std::string key = randomWebSocketKey();
  std::ostringstream request;
  request << "GET /control HTTP/1.1\r\n"
          << "Host: " << host_ << ":" << port_ << "\r\n"
          << "Upgrade: websocket\r\n"
          << "Connection: Upgrade\r\n"
          << "Sec-WebSocket-Key: " << key << "\r\n"
          << "Sec-WebSocket-Version: 13\r\n\r\n";
  writeAll(socket, request.str());

  std::string response;
  char buffer[4096] = {};
  while (response.find("\r\n\r\n") == std::string::npos) {
    const int count = receiveSocketBytes(socket, buffer, sizeof(buffer));
    if (count <= 0) {
      throw HelperError("Could not connect to the control socket: connection closed");
    }
    response.append(buffer, static_cast<size_t>(count));
  }
  if (response.find("101 Switching Protocols") == std::string::npos ||
      headerValue(response, "sec-websocket-accept") != webSocketAcceptForKey(key)) {
    throw HelperError("WebSocket handshake failed: " + response);
  }
}

void ControlClient::sendFrame(SocketHandle socket, const std::string &payload) const {
  std::string frame;
  frame.push_back(static_cast<char>(0x81));
  if (payload.size() < 126) {
    frame.push_back(static_cast<char>(0x80 | payload.size()));
  } else if (payload.size() <= 0xffff) {
    frame.push_back(static_cast<char>(0x80 | 126));
    frame.push_back(static_cast<char>((payload.size() >> 8) & 0xff));
    frame.push_back(static_cast<char>(payload.size() & 0xff));
  } else {
    throw HelperError("WebSocket frame is too large.");
  }
  const std::string mask = randomBytes(4);
  frame += mask;
  for (size_t i = 0; i < payload.size(); ++i) {
    frame.push_back(static_cast<char>(payload[i] ^ mask[i % 4]));
  }
  writeAll(socket, frame);
}

std::string ControlClient::receiveFrame(SocketHandle socket) const {
  const std::string header = readExact(socket, 2);
  const uint8_t first = static_cast<uint8_t>(header[0]);
  const uint8_t second = static_cast<uint8_t>(header[1]);
  if ((first & 0x0f) != 0x1) {
    throw HelperError("Received an unexpected WebSocket frame.");
  }
  uint64_t length = second & 0x7f;
  if (length == 126) {
    const std::string extended = readExact(socket, 2);
    length = (static_cast<uint8_t>(extended[0]) << 8) | static_cast<uint8_t>(extended[1]);
  } else if (length == 127) {
    throw HelperError("Received an unexpected WebSocket frame.");
  }
  if (second & 0x80) {
    (void)readExact(socket, 4);
    throw HelperError("Received an unexpected WebSocket frame.");
  }
  return readExact(socket, static_cast<size_t>(length));
}

std::string webSocketAcceptForKey(const std::string &key) {
  return base64Encode(sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));
}

std::string randomWebSocketKey() {
  return base64Encode(randomBytes(16));
}

std::string randomUUID() {
  const std::string bytes = randomBytes(16);
  static constexpr char hex[] = "0123456789abcdef";
  std::string output;
  for (size_t i = 0; i < bytes.size(); ++i) {
    if (i == 4 || i == 6 || i == 8 || i == 10) {
      output.push_back('-');
    }
    uint8_t byte = static_cast<uint8_t>(bytes[i]);
    if (i == 6) {
      byte = static_cast<uint8_t>((byte & 0x0f) | 0x40);
    } else if (i == 8) {
      byte = static_cast<uint8_t>((byte & 0x3f) | 0x80);
    }
    output.push_back(hex[(byte >> 4) & 0x0f]);
    output.push_back(hex[byte & 0x0f]);
  }
  return output;
}

} // namespace reashoot::helper
