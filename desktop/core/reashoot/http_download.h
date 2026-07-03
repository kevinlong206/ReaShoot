#pragma once

#include "reashoot/http_headers.h"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace reashoot {

// Mirrors Downloader.chunkBytes: the maximum span requested per Range attempt.
inline constexpr std::int64_t kDownloadChunkBytes = 32ll * 1024 * 1024;

// Computes the Range header value (e.g. "bytes=0-33554431") for a download
// attempt, mirroring Downloader.httpRequest. Returns std::nullopt when no Range
// header should be sent (offset == 0 and the total size is unknown).
std::optional<std::string> downloadRangeHeaderValue(
    std::int64_t offset, std::optional<std::int64_t> expectedBytes,
    std::int64_t chunkBytes = kDownloadChunkBytes);

// Builds the GET request for a recording download, mirroring Downloader.httpRequest.
// The pairing token is a hex string (UUID without dashes) so it needs no
// percent-encoding when appended as the "token" query parameter.
std::string buildDownloadRequest(std::string_view downloadPath, std::string_view host,
                                 int httpPort, std::string_view token, std::int64_t offset,
                                 std::optional<std::int64_t> expectedBytes,
                                 std::int64_t chunkBytes = kDownloadChunkBytes);

// Metadata extracted from a download response's headers, mirroring the values
// Downloader reads: HTTP status, Content-Length, and the total size from the
// "/<total>" suffix of a Content-Range header.
struct DownloadResponseInfo {
  int status = 0;
  std::optional<std::int64_t> contentLength;
  std::optional<std::int64_t> totalBytes;
};

DownloadResponseInfo parseDownloadResponse(const HttpHeaders &headers);

} // namespace reashoot
