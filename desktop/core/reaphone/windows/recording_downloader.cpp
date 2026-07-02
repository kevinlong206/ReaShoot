#include "reaphone/windows/recording_downloader.h"

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>

#include "reaphone/http_download.h"
#include "reaphone/http_headers.h"
#include "reaphone/sha256.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace reaphone {

namespace {

namespace fs = std::filesystem;

std::wstring widen(std::string_view value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0);
  std::wstring wide(static_cast<std::size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      wide.data(), length);
  return wide;
}

class SocketHandle {
public:
  SocketHandle() = default;
  explicit SocketHandle(SOCKET socket) : socket_(socket) {}
  ~SocketHandle() {
    if (socket_ != INVALID_SOCKET) {
      closesocket(socket_);
    }
  }
  SocketHandle(const SocketHandle &) = delete;
  SocketHandle &operator=(const SocketHandle &) = delete;

  SOCKET get() const { return socket_; }
  bool valid() const { return socket_ != INVALID_SOCKET; }
  void assign(SOCKET socket) { socket_ = socket; }

private:
  SOCKET socket_ = INVALID_SOCKET;
};

SOCKET connectTcp(const std::string &host, int port) {
  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;

  addrinfo *resolved = nullptr;
  if (getaddrinfo(host.c_str(), std::to_string(port).c_str(), &hints, &resolved) != 0 || !resolved) {
    return INVALID_SOCKET;
  }

  SOCKET result = INVALID_SOCKET;
  for (addrinfo *address = resolved; address != nullptr; address = address->ai_next) {
    SOCKET candidate = ::socket(address->ai_family, address->ai_socktype, address->ai_protocol);
    if (candidate == INVALID_SOCKET) {
      continue;
    }
    if (::connect(candidate, address->ai_addr, static_cast<int>(address->ai_addrlen)) == 0) {
      result = candidate;
      break;
    }
    closesocket(candidate);
  }
  freeaddrinfo(resolved);

  if (result != INVALID_SOCKET) {
    const DWORD timeoutMs = 20000;
    setsockopt(result, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char *>(&timeoutMs), sizeof(timeoutMs));
    setsockopt(result, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char *>(&timeoutMs), sizeof(timeoutMs));
  }
  return result;
}

void sendAll(SOCKET socket, std::string_view data) {
  std::size_t sent = 0;
  while (sent < data.size()) {
    const int chunk = ::send(socket, data.data() + sent, static_cast<int>(data.size() - sent), 0);
    if (chunk <= 0) {
      throw std::runtime_error("download: failed to send request");
    }
    sent += static_cast<std::size_t>(chunk);
  }
}

std::optional<std::int64_t> fileSize(const fs::path &path) {
  std::error_code ec;
  const auto size = fs::file_size(path, ec);
  if (ec) {
    return std::nullopt;
  }
  return static_cast<std::int64_t>(size);
}

std::string fileChecksum(const fs::path &path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) {
    throw std::runtime_error("download: could not open file for checksum");
  }
  Sha256 hasher;
  std::vector<char> buffer(256 * 1024);
  while (stream) {
    stream.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
    const std::streamsize read = stream.gcount();
    if (read > 0) {
      hasher.update(reinterpret_cast<const std::uint8_t *>(buffer.data()), static_cast<std::size_t>(read));
    }
  }
  return hasher.finalizeHex();
}

bool fileMatchesExpectedChecksumOrTrustsSize(const fs::path &path,
                                             const std::optional<std::string> &expected) {
  if (!expected) {
    return true;
  }
  try {
    return fileChecksum(path) == *expected;
  } catch (const std::exception &) {
    return true; // mirror Downloader: if the checksum cannot be read, trust the size
  }
}

// Performs one download attempt starting at offset, appending to temporaryPath.
// Returns the new cumulative byte count. Throws on any failure.
std::int64_t downloadAttempt(const RecordingDescriptor &recording, const std::string &host,
                             int httpPort, const std::string &token, const fs::path &temporaryPath,
                             std::int64_t offset, std::optional<std::int64_t> expectedBytes,
                             const DownloadProgressCallback &progress) {
  SocketHandle socket(connectTcp(host, httpPort));
  if (!socket.valid()) {
    throw std::runtime_error("download: could not connect to " + host + ":" + std::to_string(httpPort));
  }

  sendAll(socket.get(), buildDownloadRequest(recording.downloadPath, host, httpPort, token, offset,
                                             expectedBytes));

  std::string headerBuffer;
  std::string initialBody;
  char chunk[16 * 1024];
  while (true) {
    const auto complete = completeHeaderLength(headerBuffer);
    if (complete) {
      initialBody = headerBuffer.substr(*complete);
      headerBuffer.resize(*complete);
      break;
    }
    const int received = ::recv(socket.get(), chunk, sizeof(chunk), 0);
    if (received <= 0) {
      throw std::runtime_error("download: no HTTP response");
    }
    headerBuffer.append(chunk, static_cast<std::size_t>(received));
  }

  const HttpHeaders headers = parseHttpHeaders(headerBuffer);
  const DownloadResponseInfo info = parseDownloadResponse(headers);
  if (info.status != 200 && info.status != 206) {
    throw std::runtime_error("download: unexpected HTTP status " + std::to_string(info.status));
  }
  if (offset > 0 && info.status != 206) {
    throw std::runtime_error("download: server ignored the resume range");
  }

  const std::int64_t total = info.totalBytes.value_or(expectedBytes.value_or(0));

  std::ofstream file(temporaryPath, std::ios::binary | std::ios::in | std::ios::out);
  if (!file) {
    // The file may not exist yet as read/write; fall back to append.
    file.open(temporaryPath, std::ios::binary | std::ios::app);
  }
  if (!file) {
    throw std::runtime_error("download: could not open temp file for writing");
  }
  file.seekp(0, std::ios::end);

  std::int64_t written = offset;
  if (!initialBody.empty()) {
    file.write(initialBody.data(), static_cast<std::streamsize>(initialBody.size()));
    written += static_cast<std::int64_t>(initialBody.size());
    if (progress) {
      progress(written, total);
    }
  }

  std::int64_t bodyRead = static_cast<std::int64_t>(initialBody.size());
  while (!info.contentLength || bodyRead < *info.contentLength) {
    int limit = static_cast<int>(sizeof(chunk));
    if (info.contentLength) {
      limit = static_cast<int>((std::min<std::int64_t>)(static_cast<std::int64_t>(sizeof(chunk)),
                                                        *info.contentLength - bodyRead));
    }
    const int received = ::recv(socket.get(), chunk, limit, 0);
    if (received > 0) {
      file.write(chunk, received);
      bodyRead += received;
      written += received;
      if (progress) {
        progress(written, total);
      }
    } else if (received == 0) {
      break;
    } else {
      throw std::runtime_error("download: connection closed before the body completed");
    }
  }

  if (info.contentLength && bodyRead < *info.contentLength) {
    throw std::runtime_error("download: connection closed before the body completed");
  }

  file.flush();
  if (!file) {
    throw std::runtime_error("download: failed writing to temp file");
  }
  return written;
}

} // namespace

std::wstring downloadRecording(const RecordingDescriptor &recording, const std::string &host,
                               int httpPort, const std::string &token,
                               const std::wstring &destinationDirectory,
                               const DownloadProgressCallback &progress, int maxAttempts) {
  const fs::path directory(destinationDirectory);
  std::error_code ec;
  fs::create_directories(directory, ec);

  const fs::path destination = directory / fs::path(widen(recording.filename));
  const fs::path temporaryPath = directory / fs::path(L"." + widen(recording.filename) + L".download");

  const std::optional<std::int64_t> expectedBytes =
      recording.byteCount > 0 ? std::optional<std::int64_t>(recording.byteCount) : std::nullopt;

  if (expectedBytes && fileSize(destination) == *expectedBytes &&
      fileMatchesExpectedChecksumOrTrustsSize(destination, recording.checksumSHA256)) {
    fs::remove(temporaryPath, ec);
    if (progress) {
      progress(*expectedBytes, *expectedBytes);
    }
    return destination.wstring();
  }

  if (expectedBytes) {
    if (const auto existing = fileSize(temporaryPath); existing && *existing > *expectedBytes) {
      fs::remove(temporaryPath, ec);
    }
  }
  if (!fs::exists(temporaryPath)) {
    std::ofstream create(temporaryPath, std::ios::binary);
  }

  std::int64_t offset = fileSize(temporaryPath).value_or(0);
  int attempts = 0;
  while (!expectedBytes || offset < *expectedBytes) {
    try {
      offset = fileSize(temporaryPath).value_or(offset);
      offset = downloadAttempt(recording, host, httpPort, token, temporaryPath, offset, expectedBytes,
                               progress);
      attempts = 0;
      if (!expectedBytes) {
        break;
      }
    } catch (const std::exception &) {
      ++attempts;
      offset = fileSize(temporaryPath).value_or(offset);
      if (attempts >= maxAttempts) {
        throw;
      }
      std::this_thread::sleep_for(std::chrono::seconds((std::min)(attempts, 5)));
    }
  }

  fs::remove(destination, ec);
  fs::rename(temporaryPath, destination, ec);
  if (ec) {
    throw std::runtime_error("download: could not move the completed file into place");
  }

  if (recording.checksumSHA256) {
    const std::string actual = fileChecksum(destination);
    if (actual != *recording.checksumSHA256) {
      throw std::runtime_error("download: checksum mismatch (expected " + *recording.checksumSHA256 +
                               ", got " + actual + ")");
    }
  }

  return destination.wstring();
}

} // namespace reaphone

#endif // _WIN32
