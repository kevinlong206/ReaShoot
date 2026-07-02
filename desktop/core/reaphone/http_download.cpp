#include "reaphone/http_download.h"

#include <algorithm>
#include <cctype>
#include <string>

namespace reaphone {
namespace {

std::optional<std::int64_t> parseInt64(std::string_view text) {
  const std::string trimmed = trimAsciiWhitespace(text);
  if (trimmed.empty()) {
    return std::nullopt;
  }
  std::size_t index = 0;
  bool negative = false;
  if (trimmed[index] == '+' || trimmed[index] == '-') {
    negative = trimmed[index] == '-';
    ++index;
  }
  if (index == trimmed.size()) {
    return std::nullopt;
  }
  std::int64_t value = 0;
  for (; index < trimmed.size(); ++index) {
    const char c = trimmed[index];
    if (c < '0' || c > '9') {
      return std::nullopt;
    }
    value = value * 10 + (c - '0');
  }
  return negative ? -value : value;
}

} // namespace

std::optional<std::string> downloadRangeHeaderValue(std::int64_t offset,
                                                    std::optional<std::int64_t> expectedBytes,
                                                    std::int64_t chunkBytes) {
  if (offset <= 0 && !expectedBytes.has_value()) {
    return std::nullopt;
  }

  std::string range = "bytes=" + std::to_string(offset) + "-";
  if (expectedBytes.has_value()) {
    const std::int64_t end = std::min(*expectedBytes - 1, offset + chunkBytes - 1);
    range += std::to_string(end);
  }
  return range;
}

std::string buildDownloadRequest(std::string_view downloadPath, std::string_view host,
                                 int httpPort, std::string_view token, std::int64_t offset,
                                 std::optional<std::int64_t> expectedBytes,
                                 std::int64_t chunkBytes) {
  std::string path(downloadPath);
  path.append("?token=").append(token);

  std::string request;
  request.append("GET ").append(path).append(" HTTP/1.1\r\n");
  request.append("Host: ").append(host).append(":").append(std::to_string(httpPort)).append("\r\n");
  request.append("Accept: */*\r\n");
  request.append("Connection: close\r\n");

  const auto range = downloadRangeHeaderValue(offset, expectedBytes, chunkBytes);
  if (range.has_value()) {
    request.append("Range: ").append(*range).append("\r\n");
  }

  request.append("\r\n");
  return request;
}

DownloadResponseInfo parseDownloadResponse(const HttpHeaders &headers) {
  DownloadResponseInfo info;

  // Status is the second whitespace-delimited token of the start line.
  const std::string &startLine = headers.startLine;
  std::size_t start = startLine.find(' ');
  if (start != std::string::npos) {
    while (start < startLine.size() && startLine[start] == ' ') {
      ++start;
    }
    std::size_t end = start;
    while (end < startLine.size() && startLine[end] != ' ') {
      ++end;
    }
    if (const auto status = parseInt64(startLine.substr(start, end - start))) {
      info.status = static_cast<int>(*status);
    }
  }

  if (const auto contentLength = headers.value("content-length")) {
    info.contentLength = parseInt64(*contentLength);
  }

  if (const auto contentRange = headers.value("content-range")) {
    const std::size_t slash = contentRange->find_last_of('/');
    if (slash != std::string::npos) {
      info.totalBytes = parseInt64(std::string_view(*contentRange).substr(slash + 1));
    }
  }

  return info;
}

} // namespace reaphone
