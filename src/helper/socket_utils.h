#pragma once

#include <cstddef>
#include <string>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/types.h>
#endif

namespace reashoot::helper {

#ifdef _WIN32
using SocketHandle = SOCKET;
constexpr SocketHandle kInvalidSocket = INVALID_SOCKET;
#else
using SocketHandle = int;
constexpr SocketHandle kInvalidSocket = -1;
#endif

void initializeSockets();
void closeSocket(SocketHandle socket);
SocketHandle connectTcpSocket(const std::string &host, int port, int timeoutSeconds, const std::string &description);
int sendSocketBytes(SocketHandle socket, const char *data, size_t length);
int receiveSocketBytes(SocketHandle socket, char *data, size_t length);
std::string socketErrorMessage();
std::string gaiErrorMessage(int status);
void sleepSeconds(int seconds);

} // namespace reashoot::helper
