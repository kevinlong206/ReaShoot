#include "socket_utils.h"

#include "control_client.h"

#include <algorithm>
#include <chrono>
#include <cstring>
#include <sstream>
#include <thread>
#include <vector>

#ifndef _WIN32
#include <cerrno>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

namespace reashoot::transport {
namespace {

#ifdef _WIN32
class WinSockRuntime {
public:
  WinSockRuntime() {
    WSADATA data = {};
    const int status = WSAStartup(MAKEWORD(2, 2), &data);
    if (status != 0) {
      throw TransportError("Could not initialize WinSock: " + std::to_string(status));
    }
  }

  ~WinSockRuntime() { WSACleanup(); }
};
#endif

void setSocketTimeout(SocketHandle socket, int timeoutSeconds) {
  const int seconds = (std::max)(1, timeoutSeconds);
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

} // namespace

void initializeSockets() {
#ifdef _WIN32
  static WinSockRuntime runtime;
  (void)runtime;
#endif
}

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

SocketHandle connectTcpSocket(const std::string &host, int port, int timeoutSeconds, const std::string &description) {
  initializeSockets();
  addrinfo hints = {};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  addrinfo *result = nullptr;
  const std::string portText = std::to_string(port);
  const int status = getaddrinfo(host.c_str(), portText.c_str(), &hints, &result);
  if (status != 0 || !result) {
    throw TransportError("Could not connect to " + description + ": " + gaiErrorMessage(status));
  }

  SocketHandle connected = kInvalidSocket;
  std::string lastError = "connection failed";
  std::vector<int> familyPasses = {AF_INET, AF_UNSPEC};
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
    throw TransportError("Could not connect to " + description + ": " + lastError);
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

void sleepSeconds(int seconds) {
  std::this_thread::sleep_for(std::chrono::seconds((std::max)(0, seconds)));
}

} // namespace reashoot::transport
