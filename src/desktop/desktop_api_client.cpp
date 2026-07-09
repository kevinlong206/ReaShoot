#include "desktop_api_client.h"

#include "../core/json_value.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <thread>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <cerrno>
#include <cstring>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>
#endif

namespace reashoot::desktop {
namespace {

#ifdef _WIN32
using SocketHandle = SOCKET;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;

class WinSockRuntime {
public:
  WinSockRuntime() {
    WSADATA data = {};
    const int status = WSAStartup(MAKEWORD(2, 2), &data);
    if (status != 0) {
      throw DesktopApiError("Could not initialize WinSock: " + std::to_string(status));
    }
  }

  ~WinSockRuntime() { WSACleanup(); }
};

void initializeSockets() {
  static WinSockRuntime runtime;
  (void)runtime;
}
#else
using SocketHandle = int;
constexpr SocketHandle kInvalidSocket = -1;
void initializeSockets() {}
#endif

void closeSocket(SocketHandle socket) {
  if (socket == kInvalidSocket) {
    return;
  }
#ifdef _WIN32
  closesocket(socket);
#else
  close(socket);
#endif
}

std::string socketErrorMessage() {
#ifdef _WIN32
  const int error = WSAGetLastError();
  char *message = nullptr;
  FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                 nullptr,
                 static_cast<DWORD>(error),
                 MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                 reinterpret_cast<LPSTR>(&message),
                 0,
                 nullptr);
  std::string result = message && message[0] ? message : ("WinSock error " + std::to_string(error));
  if (message) {
    LocalFree(message);
  }
  while (!result.empty() && (result.back() == '\r' || result.back() == '\n')) {
    result.pop_back();
  }
  return result;
#else
  return std::strerror(errno);
#endif
}

std::string gaiErrorMessage(int status) {
#ifdef _WIN32
  return status == 0 ? std::string{} : ("getaddrinfo error " + std::to_string(status));
#else
  return gai_strerror(status);
#endif
}

void setSocketTimeout(SocketHandle socket, int timeoutSeconds) {
  const int seconds = std::max(1, timeoutSeconds);
#ifdef _WIN32
  DWORD timeoutMs = static_cast<DWORD>(seconds * 1000);
  setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char *>(&timeoutMs), sizeof(timeoutMs));
  setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char *>(&timeoutMs), sizeof(timeoutMs));
#else
  timeval timeout = {seconds, 0};
  setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
  setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
#endif
}

SocketHandle connectTcpSocket(const std::string &host, int port, int timeoutSeconds) {
  initializeSockets();
  addrinfo hints = {};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  addrinfo *result = nullptr;
  const std::string portText = std::to_string(port);
  const int status = getaddrinfo(host.c_str(), portText.c_str(), &hints, &result);
  if (status != 0 || !result) {
    throw DesktopApiError("Could not connect to ReaShoot desktop API: " + gaiErrorMessage(status));
  }

  SocketHandle connected = kInvalidSocket;
  std::string lastError = "connection failed";
  const int familyPasses[] = {AF_INET, AF_UNSPEC};
  for (int family : familyPasses) {
    for (addrinfo *address = result; address; address = address->ai_next) {
      if (family != AF_UNSPEC && address->ai_family != family) {
        continue;
      }
      if (family == AF_UNSPEC && address->ai_family == AF_INET) {
        continue;
      }
      const SocketHandle candidate = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
      if (candidate == kInvalidSocket) {
        lastError = socketErrorMessage();
        continue;
      }
      setSocketTimeout(candidate, timeoutSeconds);
      if (connect(candidate, address->ai_addr, static_cast<int>(address->ai_addrlen)) == 0) {
        connected = candidate;
        break;
      }
      lastError = socketErrorMessage();
      closeSocket(candidate);
    }
    if (connected != kInvalidSocket) {
      break;
    }
  }
  freeaddrinfo(result);
  if (connected == kInvalidSocket) {
    throw DesktopApiError("Could not connect to ReaShoot desktop API: " + lastError);
  }
  return connected;
}

int sendSocketBytes(SocketHandle socket, const char *data, size_t length) {
#ifdef _WIN32
  return send(socket, data, static_cast<int>(length), 0);
#else
  return static_cast<int>(send(socket, data, length, 0));
#endif
}

int receiveSocketBytes(SocketHandle socket, char *data, size_t length) {
#ifdef _WIN32
  return recv(socket, data, static_cast<int>(length), 0);
#else
  return static_cast<int>(recv(socket, data, length, 0));
#endif
}

std::string readFile(const std::string &path) {
  std::ifstream file(path);
  if (!file) {
    return {};
  }
  std::ostringstream stream;
  stream << file.rdbuf();
  return stream.str();
}

std::string httpBody(const std::string &response) {
  const size_t headerEnd = response.find("\r\n\r\n");
  return headerEnd == std::string::npos ? response : response.substr(headerEnd + 4);
}

int httpStatus(const std::string &response) {
  std::istringstream stream(response);
  std::string version;
  int status = 0;
  stream >> version >> status;
  return status;
}

void sendAllSocketBytes(SocketHandle socket, const std::string &data) {
  size_t offset = 0;
  while (offset < data.size()) {
    const int sent = sendSocketBytes(socket, data.data() + offset, data.size() - offset);
    if (sent <= 0) {
      throw DesktopApiError("Could not send request to ReaShoot desktop API.");
    }
    offset += static_cast<size_t>(sent);
  }
}

const core::JsonValue &requiredOperation(const std::string &body) {
  static core::JsonValue root;
  root = core::parseJson(body);
  const core::JsonValue *operation = root.find("operation");
  if (!operation) {
    throw DesktopApiError("ReaShoot desktop API response did not include an operation.");
  }
  return *operation;
}

} // namespace

DesktopApiClient::DesktopApiClient(DesktopApiClientOptions options) : options_(options) {}

std::string DesktopApiClient::registrationPath() {
#ifdef _WIN32
  const char *localAppData = std::getenv("LOCALAPPDATA");
  if (!localAppData || !localAppData[0]) {
    throw DesktopApiError("LOCALAPPDATA is not set; ReaShoot desktop API registration was not found.");
  }
  return std::string(localAppData) + "\\ReaShoot\\desktop-api.json";
#else
  const char *home = std::getenv("HOME");
  if (!home || !home[0]) {
    throw DesktopApiError("HOME is not set; ReaShoot desktop API registration was not found.");
  }
  return std::string(home) + "/Library/Application Support/ReaShoot/desktop-api.json";
#endif
}

bool DesktopApiClient::loadRegistration(DesktopApiRegistration &registration) {
  const std::string text = readFile(registrationPath());
  if (text.empty()) {
    return false;
  }
  const core::JsonValue json = core::parseJson(text);
  registration.host = json.stringValue("host", registration.host);
  registration.port = json.intValue("port", 0);
  registration.token = json.stringValue("token");
  registration.baseUrl = json.stringValue("baseUrl");
  registration.appPath = json.stringValue("appPath");
  return registration.port > 0 && !registration.token.empty();
}

void DesktopApiClient::launchDesktopApp(const std::string &appPath) {
#ifdef _WIN32
  ShellExecuteA(nullptr, "open", appPath.empty() ? "ReaShoot.exe" : appPath.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
#else
  (void)appPath;
  std::system("/usr/bin/open -a ReaShoot >/dev/null 2>&1");
#endif
}

DesktopApiRegistration DesktopApiClient::loadOrStartRegistration() const {
  DesktopApiRegistration registration;
  if (loadRegistration(registration)) {
    return registration;
  }
  launchDesktopApp();
  for (int attempt = 0; attempt < options_.launchWaitAttempts; ++attempt) {
    std::this_thread::sleep_for(std::chrono::milliseconds(options_.launchWaitMilliseconds));
    if (loadRegistration(registration)) {
      return registration;
    }
  }
  throw DesktopApiError("ReaShoot desktop API is not registered. Start ReaShoot.app/ReaShoot.exe first.");
}

std::string DesktopApiClient::performRequest(const DesktopApiRegistration &registration,
                                             const std::string &method,
                                             const std::string &path,
                                             const std::string &body) const {
  SocketHandle socket = connectTcpSocket(registration.host, registration.port, options_.connectTimeoutSeconds);
  std::ostringstream request;
  request << method << ' ' << path << " HTTP/1.1\r\n"
          << "Host: " << registration.host << ':' << registration.port << "\r\n"
          << "Authorization: Bearer " << registration.token << "\r\n"
          << "Accept: application/json\r\n"
          << "Connection: close\r\n";
  if (!body.empty()) {
    request << "Content-Type: application/json\r\n"
            << "Content-Length: " << body.size() << "\r\n";
  }
  request << "\r\n" << body;
  sendAllSocketBytes(socket, request.str());

  std::string response;
  char buffer[4096];
  while (true) {
    const int count = receiveSocketBytes(socket, buffer, sizeof(buffer));
    if (count <= 0) {
      break;
    }
    response.append(buffer, static_cast<size_t>(count));
  }
  closeSocket(socket);

  const int status = httpStatus(response);
  const std::string bodyText = httpBody(response);
  if (status >= 400 || status == 0) {
    throw DesktopApiError(bodyText.empty() ? "ReaShoot desktop API request failed." : bodyText);
  }
  return bodyText;
}

std::string DesktopApiClient::request(const std::string &method, const std::string &path, const std::string &body) {
  DesktopApiRegistration registration = loadOrStartRegistration();
  try {
    return performRequest(registration, method, path, body);
  } catch (const DesktopApiError &) {
    launchDesktopApp(registration.appPath);
  }
  for (int attempt = 0; attempt < options_.launchWaitAttempts; ++attempt) {
    std::this_thread::sleep_for(std::chrono::milliseconds(options_.launchWaitMilliseconds));
    if (!loadRegistration(registration)) {
      continue;
    }
    try {
      return performRequest(registration, method, path, body);
    } catch (const DesktopApiError &) {
      if (attempt == options_.launchWaitAttempts - 1) {
        throw;
      }
    }
  }
  throw DesktopApiError("ReaShoot desktop API is not reachable. Start ReaShoot.app/ReaShoot.exe first.");
}

void DesktopApiClient::waitUntilRecordingStarted() {
  for (int attempt = 0; attempt < options_.recordingStartAttempts; ++attempt) {
    const std::string body = request("GET", "/v1/status");
    const core::JsonValue root = core::parseJson(body);
    const core::JsonValue *status = root.find("status");
    if (status && status->boolValue("recording")) {
      return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(options_.recordingStartWaitMilliseconds));
  }
  throw DesktopApiError("Timed out waiting for ReaShoot desktop recording to start.");
}

void DesktopApiClient::startRecording() {
  request("POST", "/v1/recording/start");
  waitUntilRecordingStarted();
}

std::string DesktopApiClient::waitForDownloadedOperation(const std::string &operationID, DesktopApiProgressCallback progress) {
  std::string lastMessage;
  for (int attempt = 0; attempt < options_.operationAttempts; ++attempt) {
    const std::string body = request("GET", "/v1/operations/" + operationID);
    const core::JsonValue &operation = requiredOperation(body);
    const std::string state = operation.stringValue("state");
    const std::string message = operation.stringValue("message");
    if (progress && !message.empty() && message != lastMessage) {
      progress(message);
      lastMessage = message;
    }
    if (state == "succeeded") {
      const std::string downloadedPath = operation.stringValue("downloadedPath");
      if (downloadedPath.empty()) {
        throw DesktopApiError("ReaShoot desktop operation succeeded without a downloaded path.");
      }
      return downloadedPath;
    }
    if (state == "failed") {
      throw DesktopApiError(message.empty() ? "ReaShoot desktop operation failed." : message);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(options_.operationWaitMilliseconds));
  }
  throw DesktopApiError("Timed out waiting for ReaShoot desktop operation.");
}

std::string DesktopApiClient::stopRecordingAndDownload(const std::string &downloadDirectory,
                                                       DesktopApiProgressCallback progress) {
  const std::string output = request("POST", "/v1/recording/stop-download", desktopDownloadBody(downloadDirectory));
  return waitForDownloadedOperation(desktopOperationIDFromResponse(output), std::move(progress));
}

std::string desktopDownloadBody(const std::string &downloadDirectory) {
  core::JsonValue::Object object;
  if (!downloadDirectory.empty()) {
    object.emplace("downloadDirectory", core::JsonValue(downloadDirectory));
  }
  return core::JsonValue(std::move(object)).serialize();
}

std::string desktopOperationIDFromResponse(const std::string &body) {
  const core::JsonValue &operation = requiredOperation(body);
  const std::string id = operation.stringValue("id");
  if (id.empty()) {
    throw DesktopApiError("ReaShoot desktop API operation did not include an id.");
  }
  return id;
}

} // namespace reashoot::desktop
