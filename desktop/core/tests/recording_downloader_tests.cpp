#include "reashoot/windows/recording_downloader.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include "reashoot/sha256.h"

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {

namespace fs = std::filesystem;

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

// A single-connection loopback HTTP server that serves a fixed payload and
// honours a single Range request (start[-end]), mirroring what the iPhone's
// recording HTTP endpoint provides. Winsock must already be initialised.
class LoopbackHttpServer {
public:
  explicit LoopbackHttpServer(std::string payload) : payload_(std::move(payload)) {
    listener_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    require(listener_ != INVALID_SOCKET, "http server socket");

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    require(bind(listener_, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0, "http bind");
    require(listen(listener_, 1) == 0, "http listen");

    sockaddr_in bound{};
    int length = sizeof(bound);
    require(getsockname(listener_, reinterpret_cast<sockaddr *>(&bound), &length) == 0, "http getsockname");
    port_ = ntohs(bound.sin_port);

    thread_ = std::thread([this] { run(); });
  }

  ~LoopbackHttpServer() {
    if (thread_.joinable()) {
      thread_.join();
    }
    if (listener_ != INVALID_SOCKET) {
      closesocket(listener_);
    }
  }

  LoopbackHttpServer(const LoopbackHttpServer &) = delete;
  LoopbackHttpServer &operator=(const LoopbackHttpServer &) = delete;

  int port() const { return port_; }

private:
  static void sendAll(SOCKET socket, const std::string &data) {
    std::size_t sent = 0;
    while (sent < data.size()) {
      const int chunk = send(socket, data.data() + sent, static_cast<int>(data.size() - sent), 0);
      if (chunk <= 0) {
        return;
      }
      sent += static_cast<std::size_t>(chunk);
    }
  }

  void run() {
    SOCKET client = accept(listener_, nullptr, nullptr);
    if (client == INVALID_SOCKET) {
      return;
    }

    std::string request;
    char chunk[2048];
    while (request.find("\r\n\r\n") == std::string::npos) {
      const int received = recv(client, chunk, sizeof(chunk), 0);
      if (received <= 0) {
        closesocket(client);
        return;
      }
      request.append(chunk, static_cast<std::size_t>(received));
    }

    const std::int64_t total = static_cast<std::int64_t>(payload_.size());
    std::int64_t start = 0;
    std::int64_t end = total - 1;
    bool ranged = false;
    const std::size_t rangePos = request.find("Range: bytes=");
    if (rangePos != std::string::npos) {
      ranged = true;
      std::size_t cursor = rangePos + std::string("Range: bytes=").size();
      start = std::strtoll(request.c_str() + cursor, nullptr, 10);
      const std::size_t dash = request.find('-', cursor);
      const std::size_t lineEnd = request.find("\r\n", cursor);
      if (dash != std::string::npos && dash + 1 < lineEnd && request[dash + 1] != '\r') {
        end = std::strtoll(request.c_str() + dash + 1, nullptr, 10);
      }
    }

    start = (std::max<std::int64_t>)(0, start);
    end = (std::min<std::int64_t>)(end, total - 1);
    const std::int64_t length = end - start + 1;
    const std::string body = payload_.substr(static_cast<std::size_t>(start), static_cast<std::size_t>(length));

    std::string response;
    if (ranged) {
      response += "HTTP/1.1 206 Partial Content\r\n";
      response += "Content-Range: bytes " + std::to_string(start) + "-" + std::to_string(end) + "/" +
                  std::to_string(total) + "\r\n";
    } else {
      response += "HTTP/1.1 200 OK\r\n";
    }
    response += "Content-Length: " + std::to_string(length) + "\r\n";
    response += "Connection: close\r\n\r\n";
    response += body;

    sendAll(client, response);
    closesocket(client);
  }

  std::string payload_;
  SOCKET listener_ = INVALID_SOCKET;
  int port_ = 0;
  std::thread thread_;
};

std::string makePayload(std::size_t size) {
  std::string payload(size, '\0');
  for (std::size_t i = 0; i < size; ++i) {
    payload[i] = static_cast<char>('A' + (i % 41));
  }
  return payload;
}

fs::path uniqueTempDir() {
  const fs::path directory =
      fs::temp_directory_path() / ("reashoot_dl_" + std::to_string(GetCurrentProcessId()) + "_" +
                                   std::to_string(GetTickCount64()));
  fs::create_directories(directory);
  return directory;
}

reashoot::RecordingDescriptor makeRecording(const std::string &payload, bool withChecksum) {
  reashoot::RecordingDescriptor recording;
  recording.id = "rec-1";
  recording.filename = "clip.mov";
  recording.byteCount = static_cast<std::int64_t>(payload.size());
  recording.downloadPath = "/recordings/clip.mov";
  if (withChecksum) {
    recording.checksumSHA256 = reashoot::sha256Hex(payload);
  }
  return recording;
}

std::string readFile(const fs::path &path) {
  std::ifstream stream(path, std::ios::binary);
  std::ostringstream contents;
  contents << stream.rdbuf();
  return contents.str();
}

void downloadsAndVerifiesChecksum() {
  const std::string payload = makePayload(5000);
  const fs::path directory = uniqueTempDir();
  LoopbackHttpServer server(payload);

  const std::wstring path = reashoot::downloadRecording(makeRecording(payload, true), "127.0.0.1",
                                                        server.port(), "hexToken", directory.wstring());
  require(readFile(fs::path(path)) == payload, "downloaded content should match the payload");
  require(!fs::exists(directory / ".clip.mov.download"), "temp file should be removed after success");
  fs::remove_all(directory);
}

void resumesFromPartialTempFile() {
  const std::string payload = makePayload(5000);
  const fs::path directory = uniqueTempDir();
  {
    std::ofstream partial(directory / ".clip.mov.download", std::ios::binary);
    partial.write(payload.data(), 2000); // pretend 2000 bytes were already fetched
  }
  LoopbackHttpServer server(payload);

  const std::wstring path = reashoot::downloadRecording(makeRecording(payload, true), "127.0.0.1",
                                                        server.port(), "hexToken", directory.wstring());
  require(readFile(fs::path(path)) == payload, "resumed download should reconstruct the full payload");
  fs::remove_all(directory);
}

void skipsWhenDestinationAlreadyComplete() {
  const std::string payload = makePayload(4096);
  const fs::path directory = uniqueTempDir();
  {
    std::ofstream complete(directory / "clip.mov", std::ios::binary);
    complete.write(payload.data(), static_cast<std::streamsize>(payload.size()));
  }
  // No server: a network attempt would block, proving the early-return path runs.
  const std::wstring path = reashoot::downloadRecording(makeRecording(payload, true), "127.0.0.1",
                                                        1, "hexToken", directory.wstring());
  require(readFile(fs::path(path)) == payload, "already-complete file should be returned untouched");
  fs::remove_all(directory);
}

void throwsOnChecksumMismatch() {
  const std::string payload = makePayload(3000);
  const fs::path directory = uniqueTempDir();
  LoopbackHttpServer server(payload);

  reashoot::RecordingDescriptor recording = makeRecording(payload, true);
  recording.checksumSHA256 = std::string(64, '0'); // wrong checksum

  bool threw = false;
  try {
    reashoot::downloadRecording(recording, "127.0.0.1", server.port(), "hexToken", directory.wstring());
  } catch (const std::runtime_error &) {
    threw = true;
  }
  require(threw, "a checksum mismatch should throw");
  fs::remove_all(directory);
}

} // namespace

int main() {
  WSADATA data{};
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
    std::cerr << "recording_downloader_tests failed: WSAStartup\n";
    return EXIT_FAILURE;
  }

  int result = EXIT_SUCCESS;
  try {
    downloadsAndVerifiesChecksum();
    resumesFromPartialTempFile();
    skipsWhenDestinationAlreadyComplete();
    throwsOnChecksumMismatch();
  } catch (const std::exception &error) {
    std::cerr << "recording_downloader_tests failed: " << error.what() << '\n';
    result = EXIT_FAILURE;
  }

  WSACleanup();
  return result;
}
