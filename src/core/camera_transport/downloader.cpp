#include "downloader.h"

#include "checksum.h"
#include "control_client.h"
#include "socket_utils.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <utility>

namespace reashoot::transport {
namespace {

constexpr int64_t kChunkBytes = 32LL * 1024LL * 1024LL;

int64_t fileSize(const std::string &path) {
  struct stat info = {};
  return stat(path.c_str(), &info) == 0 ? static_cast<int64_t>(info.st_size) : 0;
}

void writeAll(SocketHandle socket, const std::string &data) {
  size_t offset = 0;
  while (offset < data.size()) {
    const int sent = sendSocketBytes(socket, data.data() + offset, data.size() - offset);
    if (sent <= 0) {
      throw TransportError("Download connection closed before the file was complete.");
    }
    offset += static_cast<size_t>(sent);
  }
}

std::pair<std::vector<std::string>, std::string> readHeaders(SocketHandle socket) {
  std::string data;
  char buffer[16 * 1024] = {};
  while (data.find("\r\n\r\n") == std::string::npos) {
    const int count = receiveSocketBytes(socket, buffer, sizeof(buffer));
    if (count <= 0) {
      throw TransportError("Download did not return an HTTP response.");
    }
    data.append(buffer, static_cast<size_t>(count));
  }
  const size_t split = data.find("\r\n\r\n");
  std::vector<std::string> headers;
  std::istringstream stream(data.substr(0, split));
  std::string line;
  while (std::getline(stream, line)) {
    if (!line.empty() && line.back() == '\r') {
      line.pop_back();
    }
    headers.push_back(line);
  }
  return {headers, data.substr(split + 4)};
}

int httpStatus(const std::vector<std::string> &headers) {
  if (headers.empty()) {
    throw TransportError("Download returned an invalid HTTP response.");
  }
  std::istringstream stream(headers.front());
  std::string version;
  int status = 0;
  stream >> version >> status;
  if (status == 0) {
    throw TransportError("Download returned an invalid HTTP response.");
  }
  return status;
}

std::string requestPath(const core::ProtocolRecording &recording, const std::string &token) {
  return recording.downloadPath + "?token=" + token;
}

int64_t downloadAttempt(const core::ProtocolRecording &recording,
                        const std::string &host,
                        int httpPort,
                        const std::string &token,
                        const std::string &temporaryPath,
                        int64_t offset,
                        DownloadProgress progress) {
  const SocketHandle socket = connectTcpSocket(host, httpPort, 20, "download server");
  try {
    const int64_t expectedBytes = recording.byteCount;
    const int64_t end = expectedBytes > 0 ? std::min(expectedBytes - 1, offset + kChunkBytes - 1) : -1;
    std::ostringstream request;
    request << "GET " << requestPath(recording, token) << " HTTP/1.1\r\n"
            << "Host: " << host << ":" << httpPort << "\r\n"
            << "Accept: */*\r\n"
            << "Connection: close\r\n";
    if (offset > 0 || expectedBytes > 0) {
      request << "Range: bytes=" << offset << "-";
      if (end >= 0) {
        request << end;
      }
      request << "\r\n";
    }
    request << "\r\n";
    writeAll(socket, request.str());

    auto [headers, initialBody] = readHeaders(socket);
    const int status = httpStatus(headers);
    if (status != 200 && status != 206) {
      throw TransportError("Download failed with HTTP status " + std::to_string(status) + ".");
    }
    if (offset > 0 && status != 206) {
      throw TransportError("Download failed with HTTP status " + std::to_string(status) + ".");
    }

    std::ofstream output(temporaryPath, std::ios::binary | std::ios::app);
    if (!output) {
      throw TransportError("Could not open temporary download file.");
    }
    int64_t written = offset;
    if (!initialBody.empty()) {
      output.write(initialBody.data(), static_cast<std::streamsize>(initialBody.size()));
      written += static_cast<int64_t>(initialBody.size());
      progress(written, expectedBytes);
    }

    char buffer[256 * 1024] = {};
    while (true) {
      const int count = receiveSocketBytes(socket, buffer, sizeof(buffer));
      if (count > 0) {
        output.write(buffer, count);
        written += count;
        progress(written, expectedBytes);
      } else if (count == 0) {
        break;
      } else {
        throw TransportError("Download connection closed before the file was complete.");
      }
    }
    closeSocket(socket);
    return written;
  } catch (...) {
    closeSocket(socket);
    throw;
  }
}

} // namespace

std::string downloadRecording(const core::ProtocolRecording &recording,
                              const std::string &host,
                              int httpPort,
                              const std::string &token,
                              const std::string &destinationDirectory,
                              DownloadProgress progress) {
  std::filesystem::create_directories(destinationDirectory);
  const std::string destination = (std::filesystem::path(destinationDirectory) / recording.filename).string();
  const std::string temporary = (std::filesystem::path(destinationDirectory) / ("." + recording.filename + ".download")).string();
  if (recording.byteCount > 0 && fileSize(destination) == recording.byteCount) {
    if (recording.checksumSHA256.empty() || sha256FileHex(destination) == recording.checksumSHA256) {
      std::filesystem::remove(temporary);
      progress(recording.byteCount, recording.byteCount);
      return destination;
    }
  }
  if (recording.byteCount > 0 && fileSize(temporary) > recording.byteCount) {
    std::filesystem::remove(temporary);
  }
  int attempts = 0;
  int64_t offset = fileSize(temporary);
  while (recording.byteCount <= 0 || offset < recording.byteCount) {
    try {
      offset = downloadAttempt(recording, host, httpPort, token, temporary, offset, progress);
      attempts = 0;
      if (recording.byteCount <= 0) {
        break;
      }
    } catch (...) {
      if (++attempts >= 8) {
        throw;
      }
      sleepSeconds(std::min(attempts, 5));
      offset = fileSize(temporary);
    }
  }
  std::filesystem::remove(destination);
  std::filesystem::rename(temporary, destination);
  if (!recording.checksumSHA256.empty()) {
    const std::string actual = sha256FileHex(destination);
    if (actual != recording.checksumSHA256) {
      throw TransportError("Checksum mismatch. Expected " + recording.checksumSHA256 + ", got " + actual);
    }
  }
  return destination;
}

} // namespace reashoot::transport
