#pragma once

#include "reaphone/control_protocol.h"

#include <cstdint>
#include <functional>
#include <string>

namespace reaphone {

// Reports cumulative bytes written and the expected total (0 when unknown),
// mirroring the macOS Downloader progress callback.
using DownloadProgressCallback = std::function<void(std::int64_t written, std::int64_t total)>;

// Downloads a recording over HTTP into destinationDirectory and returns the
// final file path. Mirrors the macOS RecordingDownloader (Downloader.swift):
// resumes into a hidden ".<name>.download" temp file using Range requests, skips
// work when the destination is already complete, retries transient failures with
// backoff, moves the temp file into place, and verifies the SHA-256 checksum when
// the descriptor provides one. Throws std::runtime_error on any hard failure
// (bad HTTP status, connection loss, or checksum mismatch).
//
// This is the Windows (Winsock) implementation; the declaration is visible on
// all platforms but the definition is compiled only on Windows.
std::wstring downloadRecording(const RecordingDescriptor &recording, const std::string &host,
                               int httpPort, const std::string &token,
                               const std::wstring &destinationDirectory,
                               const DownloadProgressCallback &progress = {},
                               int maxAttempts = 8);

} // namespace reaphone
