#include "ReaShootWin32IntegrationServer.h"

#include "ReaShootWin32Support.h"
#include "../../core/json_value.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shlobj.h>
#include <winsock2.h>
#include <ws2tcpip.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <random>
#include <sstream>
#include <thread>

namespace reashoot::app::win32 {
namespace {

std::filesystem::path applicationSupportDirectory() {
  wchar_t *localAppData = nullptr;
  std::filesystem::path base;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &localAppData)) && localAppData) {
    base = localAppData;
    CoTaskMemFree(localAppData);
  } else {
    base = std::filesystem::temp_directory_path();
  }
  base /= L"ReaShoot";
  std::error_code ec;
  std::filesystem::create_directories(base, ec);
  return base;
}

std::filesystem::path registrationPath() { return applicationSupportDirectory() / L"desktop-api.json"; }

std::string randomToken() {
  static constexpr char alphabet[] = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  std::random_device random;
  std::string token;
  token.reserve(48);
  for (int index = 0; index < 48; ++index) {
    token.push_back(alphabet[random() % (sizeof(alphabet) - 1)]);
  }
  return token;
}

std::string reasonPhrase(int status) {
  switch (status) {
  case 200:
    return "OK";
  case 202:
    return "Accepted";
  case 400:
    return "Bad Request";
  case 401:
    return "Unauthorized";
  case 404:
    return "Not Found";
  case 409:
    return "Conflict";
  case 500:
    return "Internal Server Error";
  default:
    return "OK";
  }
}

std::string headerValue(const std::map<std::string, std::string> &headers, const std::string &key) {
  for (const auto &entry : headers) {
    std::string normalized = entry.first;
    std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char ch) {
      return static_cast<char>(std::tolower(ch));
    });
    if (normalized == key) {
      return entry.second;
    }
  }
  return {};
}

std::string trim(std::string value) {
  while (!value.empty() && (value.back() == '\r' || value.back() == '\n' || value.back() == ' ' || value.back() == '\t')) {
    value.pop_back();
  }
  size_t start = 0;
  while (start < value.size() && (value[start] == ' ' || value[start] == '\t')) {
    ++start;
  }
  return value.substr(start);
}

bool sendAll(SOCKET socket, const std::string &data) {
  const char *bytes = data.data();
  size_t remaining = data.size();
  while (remaining > 0) {
    const int sent = send(socket, bytes, static_cast<int>(remaining), 0);
    if (sent <= 0) {
      return false;
    }
    bytes += sent;
    remaining -= static_cast<size_t>(sent);
  }
  return true;
}

std::string httpResponse(const desktop::IntegrationHttpResponse &response) {
  std::ostringstream stream;
  stream << "HTTP/1.1 " << response.status << ' ' << reasonPhrase(response.status) << "\r\n";
  stream << "Content-Type: " << response.contentType << "\r\n";
  stream << "Content-Length: " << response.body.size() << "\r\n";
  stream << "Cache-Control: no-store\r\n";
  stream << "Connection: close\r\n";
  for (const auto &header : response.headers) {
    stream << header.first << ": " << header.second << "\r\n";
  }
  stream << "\r\n" << response.body;
  return stream.str();
}

} // namespace

class ReaShootWin32IntegrationServer::Impl {
public:
  bool start(const std::string &token,
             IntegrationRequestHandler handler,
             IntegrationEventSnapshotProvider eventSnapshotProvider,
             std::string *errorMessage) {
    token_ = token;
    handler_ = std::move(handler);
    eventSnapshotProvider_ = std::move(eventSnapshotProvider);
    WSADATA data = {};
    if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
      if (errorMessage) {
        *errorMessage = "WSAStartup failed.";
      }
      return false;
    }
    wsaStarted_ = true;
    listenSocket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listenSocket_ == INVALID_SOCKET) {
      if (errorMessage) {
        *errorMessage = "Could not create API socket.";
      }
      stop();
      return false;
    }
    BOOL yes = TRUE;
    setsockopt(listenSocket_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char *>(&yes), sizeof(yes));
    sockaddr_in address = {};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(listenSocket_, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
      if (errorMessage) {
        *errorMessage = "Could not bind API socket.";
      }
      stop();
      return false;
    }
    int length = sizeof(address);
    if (getsockname(listenSocket_, reinterpret_cast<sockaddr *>(&address), &length) != 0) {
      if (errorMessage) {
        *errorMessage = "Could not read API socket port.";
      }
      stop();
      return false;
    }
    port_ = ntohs(address.sin_port);
    if (listen(listenSocket_, 16) != 0) {
      if (errorMessage) {
        *errorMessage = "Could not listen on API socket.";
      }
      stop();
      return false;
    }
    running_ = true;
    acceptThread_ = std::thread([this] { acceptLoop(); });
    return true;
  }

  void stop() {
    running_ = false;
    if (listenSocket_ != INVALID_SOCKET) {
      shutdown(listenSocket_, SD_BOTH);
      closesocket(listenSocket_);
      listenSocket_ = INVALID_SOCKET;
    }
    if (acceptThread_.joinable()) {
      acceptThread_.join();
    }
    if (wsaStarted_) {
      WSACleanup();
      wsaStarted_ = false;
    }
  }

  int port() const { return port_; }

private:
  void acceptLoop() {
    while (running_) {
      SOCKET client = accept(listenSocket_, nullptr, nullptr);
      if (client == INVALID_SOCKET) {
        if (running_) {
          continue;
        }
        break;
      }
      std::thread([this, client] { handleClient(client); }).detach();
    }
  }

  void handleClient(SOCKET socket) {
    desktop::IntegrationHttpRequest request;
    if (!readRequest(socket, request)) {
      sendAll(socket, httpResponse(desktop::errorResponse(400, "bad_request", "Could not parse request.")));
      closesocket(socket);
      return;
    }
    if (request.path == "/v1/events") {
      handleEvents(socket, request);
      closesocket(socket);
      return;
    }
    desktop::IntegrationHttpResponse response = handler_ ? handler_(request) : desktop::errorResponse(500, "unavailable", "No handler.");
    sendAll(socket, httpResponse(response));
    closesocket(socket);
  }

  bool readRequest(SOCKET socket, desktop::IntegrationHttpRequest &request) {
    std::string data;
    char buffer[4096];
    size_t headerEnd = std::string::npos;
    while ((headerEnd = data.find("\r\n\r\n")) == std::string::npos && data.size() < 1024 * 1024) {
      const int count = recv(socket, buffer, sizeof(buffer), 0);
      if (count <= 0) {
        return false;
      }
      data.append(buffer, static_cast<size_t>(count));
    }
    if (headerEnd == std::string::npos) {
      return false;
    }
    std::istringstream stream(data.substr(0, headerEnd));
    std::string requestLine;
    if (!std::getline(stream, requestLine)) {
      return false;
    }
    requestLine = trim(requestLine);
    std::istringstream requestLineStream(requestLine);
    std::string target;
    std::string version;
    requestLineStream >> request.method >> target >> version;
    if (request.method.empty() || target.empty()) {
      return false;
    }
    const size_t queryStart = target.find('?');
    request.path = queryStart == std::string::npos ? target : target.substr(0, queryStart);
    request.query = queryStart == std::string::npos ? "" : target.substr(queryStart + 1);
    std::string line;
    while (std::getline(stream, line)) {
      line = trim(line);
      const size_t colon = line.find(':');
      if (colon != std::string::npos) {
        request.headers[trim(line.substr(0, colon))] = trim(line.substr(colon + 1));
      }
    }
    const int contentLength = std::atoi(headerValue(request.headers, "content-length").c_str());
    const size_t bodyStart = headerEnd + 4;
    request.body = data.substr(bodyStart);
    while (contentLength > 0 && request.body.size() < static_cast<size_t>(contentLength)) {
      const int count = recv(socket, buffer, sizeof(buffer), 0);
      if (count <= 0) {
        return false;
      }
      request.body.append(buffer, static_cast<size_t>(count));
    }
    if (contentLength > 0 && request.body.size() > static_cast<size_t>(contentLength)) {
      request.body.resize(static_cast<size_t>(contentLength));
    }
    return true;
  }

  void handleEvents(SOCKET socket, const desktop::IntegrationHttpRequest &request) {
    if (!desktop::requestHasValidToken(request, token_)) {
      sendAll(socket, httpResponse(desktop::errorResponse(401, "unauthorized", "Invalid API token.")));
      return;
    }
    const std::string headers = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n";
    if (!sendAll(socket, headers)) {
      return;
    }
    for (int index = 0; index < 30 && running_; ++index) {
      const std::string snapshot = eventSnapshotProvider_ ? eventSnapshotProvider_() : "{}";
      std::ostringstream event;
      event << "event: status\n"
            << "data: " << snapshot << "\n\n";
      if (!sendAll(socket, event.str())) {
        return;
      }
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }
  }

  std::atomic<bool> running_{false};
  bool wsaStarted_ = false;
  SOCKET listenSocket_ = INVALID_SOCKET;
  int port_ = 0;
  std::string token_;
  IntegrationRequestHandler handler_;
  IntegrationEventSnapshotProvider eventSnapshotProvider_;
  std::thread acceptThread_;
};

ReaShootWin32IntegrationServer::ReaShootWin32IntegrationServer() : impl_(std::make_unique<Impl>()) {}
ReaShootWin32IntegrationServer::~ReaShootWin32IntegrationServer() { stop(); }

bool ReaShootWin32IntegrationServer::start(const std::string &token,
                                           IntegrationRequestHandler handler,
                                           IntegrationEventSnapshotProvider eventSnapshotProvider,
                                           std::string *errorMessage) {
  token_ = token;
  if (!impl_->start(token, std::move(handler), std::move(eventSnapshotProvider), errorMessage)) {
    return false;
  }
  port_ = impl_->port();
  return true;
}

void ReaShootWin32IntegrationServer::stop() {
  if (impl_) {
    impl_->stop();
  }
}

std::string loadOrCreateIntegrationToken() {
  std::string token = reashoot::win32app::settingsGet("integrationApiToken");
  if (!token.empty()) {
    return token;
  }
  token = randomToken();
  reashoot::win32app::settingsSet("integrationApiToken", token);
  return token;
}

void writeIntegrationRegistration(int port, const std::string &token) {
  core::JsonValue::Object object;
  object.emplace("apiVersion", core::JsonValue(std::string(desktop::kIntegrationApiVersion)));
  object.emplace("host", core::JsonValue(std::string("127.0.0.1")));
  object.emplace("port", core::JsonValue(static_cast<double>(port)));
  object.emplace("token", core::JsonValue(token));
  object.emplace("baseUrl", core::JsonValue("http://127.0.0.1:" + std::to_string(port) + "/v1"));
  wchar_t executablePath[MAX_PATH] = {};
  if (GetModuleFileNameW(nullptr, executablePath, static_cast<DWORD>(std::size(executablePath))) > 0) {
    object.emplace("appPath", core::JsonValue(reashoot::win32app::narrow(executablePath)));
  }
  const std::string json = core::JsonValue(std::move(object)).serialize();
  std::ofstream file(registrationPath(), std::ios::binary | std::ios::trunc);
  file << json;
}

void removeIntegrationRegistration() {
  std::error_code ec;
  std::filesystem::remove(registrationPath(), ec);
}

} // namespace reashoot::app::win32
