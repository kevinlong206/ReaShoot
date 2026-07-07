#include "ReaShootMacIntegrationServer.h"
#import "ReaShootMacSupport.h"

#include "../../core/json_value.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <sstream>
#include <thread>

namespace reashoot::app::mac {
namespace {

std::string applicationSupportDirectory() {
  NSURL *supportURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
  supportURL = [supportURL URLByAppendingPathComponent:@"ReaShoot" isDirectory:YES];
  [NSFileManager.defaultManager createDirectoryAtURL:supportURL withIntermediateDirectories:YES attributes:nil error:nil];
  return stdString(supportURL.path);
}

std::string registrationPath() {
  return applicationSupportDirectory() + "/desktop-api.json";
}

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
  case 204:
    return "No Content";
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

bool sendAll(int fd, const std::string &data) {
  const char *bytes = data.data();
  size_t remaining = data.size();
  while (remaining > 0) {
    const ssize_t sent = send(fd, bytes, remaining, 0);
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
  stream << "\r\n";
  stream << response.body;
  return stream.str();
}

} // namespace

class ReaShootMacIntegrationServer::Impl {
public:
  bool start(const std::string &token,
             IntegrationRequestHandler handler,
             IntegrationEventSnapshotProvider eventSnapshotProvider,
             std::string *errorMessage) {
    token_ = token;
    handler_ = std::move(handler);
    eventSnapshotProvider_ = std::move(eventSnapshotProvider);
    listenFd_ = socket(AF_INET, SOCK_STREAM, 0);
    if (listenFd_ < 0) {
      if (errorMessage) {
        *errorMessage = std::strerror(errno);
      }
      return false;
    }
    int yes = 1;
    setsockopt(listenFd_, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    sockaddr_in address = {};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(listenFd_, reinterpret_cast<sockaddr *>(&address), sizeof(address)) != 0) {
      if (errorMessage) {
        *errorMessage = std::strerror(errno);
      }
      close(listenFd_);
      listenFd_ = -1;
      return false;
    }
    socklen_t length = sizeof(address);
    if (getsockname(listenFd_, reinterpret_cast<sockaddr *>(&address), &length) != 0) {
      if (errorMessage) {
        *errorMessage = std::strerror(errno);
      }
      close(listenFd_);
      listenFd_ = -1;
      return false;
    }
    port_ = ntohs(address.sin_port);
    if (listen(listenFd_, 16) != 0) {
      if (errorMessage) {
        *errorMessage = std::strerror(errno);
      }
      close(listenFd_);
      listenFd_ = -1;
      return false;
    }
    running_ = true;
    acceptThread_ = std::thread([this] { acceptLoop(); });
    return true;
  }

  void stop() {
    running_ = false;
    if (listenFd_ >= 0) {
      shutdown(listenFd_, SHUT_RDWR);
      close(listenFd_);
      listenFd_ = -1;
    }
    if (acceptThread_.joinable()) {
      acceptThread_.join();
    }
  }

  int port() const { return port_; }

private:
  void acceptLoop() {
    while (running_) {
      sockaddr_in client = {};
      socklen_t clientLength = sizeof(client);
      const int fd = accept(listenFd_, reinterpret_cast<sockaddr *>(&client), &clientLength);
      if (fd < 0) {
        if (running_) {
          continue;
        }
        break;
      }
      std::thread([this, fd] { handleClient(fd); }).detach();
    }
  }

  void handleClient(int fd) {
    desktop::IntegrationHttpRequest request;
    if (!readRequest(fd, request)) {
      sendAll(fd, httpResponse(desktop::errorResponse(400, "bad_request", "Could not parse request.")));
      close(fd);
      return;
    }
    if (request.path == "/v1/events") {
      handleEvents(fd, request);
      close(fd);
      return;
    }
    desktop::IntegrationHttpResponse response = handler_ ? handler_(request) : desktop::errorResponse(500, "unavailable", "No handler.");
    sendAll(fd, httpResponse(response));
    close(fd);
  }

  bool readRequest(int fd, desktop::IntegrationHttpRequest &request) {
    std::string data;
    char buffer[4096];
    size_t headerEnd = std::string::npos;
    while ((headerEnd = data.find("\r\n\r\n")) == std::string::npos && data.size() < 1024 * 1024) {
      const ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
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
      if (colon == std::string::npos) {
        continue;
      }
      request.headers[trim(line.substr(0, colon))] = trim(line.substr(colon + 1));
    }
    const int contentLength = std::atoi(headerValue(request.headers, "content-length").c_str());
    const size_t bodyStart = headerEnd + 4;
    request.body = data.substr(bodyStart);
    while (contentLength > 0 && request.body.size() < static_cast<size_t>(contentLength)) {
      const ssize_t count = recv(fd, buffer, sizeof(buffer), 0);
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

  void handleEvents(int fd, const desktop::IntegrationHttpRequest &request) {
    if (!desktop::requestHasValidToken(request, token_)) {
      sendAll(fd, httpResponse(desktop::errorResponse(401, "unauthorized", "Invalid API token.")));
      return;
    }
    std::ostringstream headers;
    headers << "HTTP/1.1 200 OK\r\n"
            << "Content-Type: text/event-stream\r\n"
            << "Cache-Control: no-store\r\n"
            << "Connection: close\r\n\r\n";
    if (!sendAll(fd, headers.str())) {
      return;
    }
    for (int index = 0; index < 30 && running_; ++index) {
      const std::string snapshot = eventSnapshotProvider_ ? eventSnapshotProvider_() : "{}";
      std::ostringstream event;
      event << "event: status\n"
            << "data: " << snapshot << "\n\n";
      if (!sendAll(fd, event.str())) {
        return;
      }
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }
  }

  std::atomic<bool> running_{false};
  int listenFd_ = -1;
  int port_ = 0;
  std::string token_;
  IntegrationRequestHandler handler_;
  IntegrationEventSnapshotProvider eventSnapshotProvider_;
  std::thread acceptThread_;
};

ReaShootMacIntegrationServer::ReaShootMacIntegrationServer() : impl_(std::make_unique<Impl>()) {}
ReaShootMacIntegrationServer::~ReaShootMacIntegrationServer() { stop(); }

bool ReaShootMacIntegrationServer::start(const std::string &token,
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

void ReaShootMacIntegrationServer::stop() {
  if (impl_) {
    impl_->stop();
  }
}

std::string loadOrCreateIntegrationToken() {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSString *existing = [defaults stringForKey:@"integrationApiToken"];
  if (existing.length > 0) {
    return stdString(existing);
  }
  std::string token = randomToken();
  [defaults setObject:nsString(token) forKey:@"integrationApiToken"];
  return token;
}

void writeIntegrationRegistration(int port, const std::string &token) {
  core::JsonValue::Object object;
  object.emplace("apiVersion", core::JsonValue(std::string(desktop::kIntegrationApiVersion)));
  object.emplace("host", core::JsonValue(std::string("127.0.0.1")));
  object.emplace("port", core::JsonValue(static_cast<double>(port)));
  object.emplace("token", core::JsonValue(token));
  object.emplace("baseUrl", core::JsonValue("http://127.0.0.1:" + std::to_string(port) + "/v1"));
  const std::string path = registrationPath();
  const std::string json = core::JsonValue(std::move(object)).serialize();
  [nsString(json) writeToFile:nsString(path) atomically:YES encoding:NSUTF8StringEncoding error:nil];
  chmod(path.c_str(), S_IRUSR | S_IWUSR);
}

void removeIntegrationRegistration() {
  std::remove(registrationPath().c_str());
}

} // namespace reashoot::app::mac
