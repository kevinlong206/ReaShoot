#include "win32_preview_stream_client.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <winhttp.h>

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace reashoot::platform::win32 {
namespace {

std::wstring wideFromUtf8(const std::string &value) {
  if (value.empty()) {
    return {};
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (length <= 0) {
    return {};
  }
  std::wstring output(static_cast<size_t>(length - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), length);
  return output;
}

std::string errorMessage(const char *prefix) {
  const DWORD error = GetLastError();
  char *message = nullptr;
  FormatMessageA(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
                 nullptr,
                 error,
                 MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                 reinterpret_cast<LPSTR>(&message),
                 0,
                 nullptr);
  std::string result = prefix;
  result += ": ";
  result += message && message[0] ? message : ("Windows error " + std::to_string(error));
  if (message) {
    LocalFree(message);
  }
  while (!result.empty() && (result.back() == '\r' || result.back() == '\n')) {
    result.pop_back();
  }
  return result;
}

class Win32PreviewStreamClient final : public core::PreviewStreamClient {
public:
  ~Win32PreviewStreamClient() override { stop(); }

  bool isRunning() const override { return running_.load(); }

  bool start(const core::PreviewStreamRequest &request,
             core::BinaryDataCallback onData,
             core::VoidCallback onActive,
             core::ErrorCallback onError) override {
    stop();
    if (request.host.empty()) {
      return false;
    }
    running_ = true;
    worker_ = std::thread([this, request, onData = std::move(onData), onActive = std::move(onActive), onError = std::move(onError)]() mutable {
      receiveLoop(request, std::move(onData), std::move(onActive), std::move(onError));
    });
    return true;
  }

  void stop() override {
    running_ = false;
    {
      std::lock_guard<std::mutex> lock(handleMutex_);
      if (webSocket_) {
        WinHttpWebSocketClose(webSocket_, WINHTTP_WEB_SOCKET_SUCCESS_CLOSE_STATUS, nullptr, 0);
      }
      if (request_) {
        WinHttpCloseHandle(request_);
        request_ = nullptr;
      }
      if (connection_) {
        WinHttpCloseHandle(connection_);
        connection_ = nullptr;
      }
      if (session_) {
        WinHttpCloseHandle(session_);
        session_ = nullptr;
      }
      webSocket_ = nullptr;
    }
    if (worker_.joinable()) {
      worker_.join();
    }
  }

private:
  void receiveLoop(const core::PreviewStreamRequest &request,
                   core::BinaryDataCallback onData,
                   core::VoidCallback onActive,
                   core::ErrorCallback onError) {
    bool active = false;
    auto fail = [&](const std::string &message) {
      running_ = false;
      if (onError) {
        onError(message);
      }
    };

    const std::wstring host = wideFromUtf8(request.host);
    std::string path = request.path.empty() ? "/preview" : request.path;
    path += path.find('?') == std::string::npos ? "?token=" : "&token=";
    path += request.token;
    const std::wstring widePath = wideFromUtf8(path);
    if (host.empty() || widePath.empty()) {
      fail("Preview stream failed: invalid host or path");
      return;
    }

    HINTERNET session = WinHttpOpen(L"ReaShoot/1.0",
                                    WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
                                    WINHTTP_NO_PROXY_NAME,
                                    WINHTTP_NO_PROXY_BYPASS,
                                    0);
    if (!session) {
      fail(errorMessage("Preview stream failed to open WinHTTP"));
      return;
    }

    HINTERNET connection = WinHttpConnect(session, host.c_str(), static_cast<INTERNET_PORT>(request.port > 0 ? request.port : 8789), 0);
    if (!connection) {
      WinHttpCloseHandle(session);
      fail(errorMessage("Preview stream failed to connect"));
      return;
    }

    HINTERNET httpRequest = WinHttpOpenRequest(connection,
                                               L"GET",
                                               widePath.c_str(),
                                               nullptr,
                                               WINHTTP_NO_REFERER,
                                               WINHTTP_DEFAULT_ACCEPT_TYPES,
                                               0);
    if (!httpRequest) {
      WinHttpCloseHandle(connection);
      WinHttpCloseHandle(session);
      fail(errorMessage("Preview stream failed to create request"));
      return;
    }

    DWORD timeoutMs = 10000;
    WinHttpSetOption(httpRequest, WINHTTP_OPTION_RECEIVE_TIMEOUT, &timeoutMs, sizeof(timeoutMs));
    WinHttpSetOption(httpRequest, WINHTTP_OPTION_SEND_TIMEOUT, &timeoutMs, sizeof(timeoutMs));
    if (!WinHttpSetOption(httpRequest, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, nullptr, 0) ||
        !WinHttpSendRequest(httpRequest, WINHTTP_NO_ADDITIONAL_HEADERS, 0, nullptr, 0, 0, 0) ||
        !WinHttpReceiveResponse(httpRequest, nullptr)) {
      WinHttpCloseHandle(httpRequest);
      WinHttpCloseHandle(connection);
      WinHttpCloseHandle(session);
      fail(errorMessage("Preview WebSocket handshake failed"));
      return;
    }

    HINTERNET webSocket = WinHttpWebSocketCompleteUpgrade(httpRequest, 0);
    if (!webSocket) {
      WinHttpCloseHandle(httpRequest);
      WinHttpCloseHandle(connection);
      WinHttpCloseHandle(session);
      fail(errorMessage("Preview WebSocket upgrade failed"));
      return;
    }

    {
      std::lock_guard<std::mutex> lock(handleMutex_);
      session_ = session;
      connection_ = connection;
      request_ = httpRequest;
      webSocket_ = webSocket;
    }

    std::vector<uint8_t> frame;
    std::vector<uint8_t> buffer(256 * 1024);
    while (running_.load()) {
      DWORD bytesRead = 0;
      WINHTTP_WEB_SOCKET_BUFFER_TYPE bufferType = WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE;
      const DWORD status = WinHttpWebSocketReceive(webSocket,
                                                   buffer.data(),
                                                   static_cast<DWORD>(buffer.size()),
                                                   &bytesRead,
                                                   &bufferType);
      if (status != NO_ERROR) {
        fail("Preview stream disconnected: " + std::to_string(status));
        break;
      }
      if (bufferType == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE) {
        running_ = false;
        break;
      }
      if (bufferType != WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE &&
          bufferType != WINHTTP_WEB_SOCKET_BINARY_FRAGMENT_BUFFER_TYPE) {
        continue;
      }
      frame.insert(frame.end(), buffer.begin(), buffer.begin() + bytesRead);
      if (bufferType == WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE) {
        if (!active) {
          active = true;
          if (onActive) {
            onActive();
          }
        }
        if (onData && !frame.empty()) {
          onData(std::move(frame));
        }
        frame.clear();
      }
    }

    std::lock_guard<std::mutex> lock(handleMutex_);
    if (webSocket_) {
      WinHttpCloseHandle(webSocket_);
      webSocket_ = nullptr;
    }
    if (request_) {
      WinHttpCloseHandle(request_);
      request_ = nullptr;
    }
    if (connection_) {
      WinHttpCloseHandle(connection_);
      connection_ = nullptr;
    }
    if (session_) {
      WinHttpCloseHandle(session_);
      session_ = nullptr;
    }
  }

  std::atomic<bool> running_{false};
  std::thread worker_;
  std::mutex handleMutex_;
  HINTERNET session_ = nullptr;
  HINTERNET connection_ = nullptr;
  HINTERNET request_ = nullptr;
  HINTERNET webSocket_ = nullptr;
};

} // namespace

std::unique_ptr<core::PreviewStreamClient> createPreviewStreamClient() {
  return std::make_unique<Win32PreviewStreamClient>();
}

} // namespace reashoot::platform::win32
