#include "reashoot/http_download.h"
#include "reashoot/http_headers.h"
#include "reashoot/sha256.h"

#include <cstdlib>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>

namespace {

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void hashesNistKnownAnswers() {
  require(reashoot::sha256Hex("") ==
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "empty string digest");
  require(reashoot::sha256Hex("abc") ==
              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "abc digest");
  // 56-byte message forces the padding into a second block (length lands at 56).
  require(reashoot::sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
              "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
          "56-byte message digest");
}

void hashesIncrementallyAcrossBlocks() {
  reashoot::Sha256 hasher;
  const std::string chunk(1000, 'a');
  for (int i = 0; i < 1000; ++i) {
    hasher.update(chunk);
  }
  require(hasher.finalizeHex() ==
              "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
          "one million 'a' digest");
}

void reusesHasherAfterFinalize() {
  reashoot::Sha256 hasher;
  hasher.update("abc");
  require(hasher.finalizeHex() ==
              "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "first digest");
  hasher.update("");
  require(hasher.finalizeHex() ==
              "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "hasher should reset after finalize");
}

void computesResumeRangeHeader() {
  require(!reashoot::downloadRangeHeaderValue(0, std::nullopt).has_value(),
          "offset 0 with unknown size sends no Range header");
  require(reashoot::downloadRangeHeaderValue(50, std::nullopt) == "bytes=50-",
          "open-ended range when size unknown");
  require(reashoot::downloadRangeHeaderValue(0, std::optional<std::int64_t>(100)) == "bytes=0-99",
          "closed range from start");
  require(reashoot::downloadRangeHeaderValue(50, std::optional<std::int64_t>(200)) == "bytes=50-199",
          "closed range from offset");
  // Chunk cap: end is offset+chunk-1 when smaller than the last byte.
  require(reashoot::downloadRangeHeaderValue(0, std::optional<std::int64_t>(100), 10) == "bytes=0-9",
          "range should cap at the chunk size");
}

void buildsDownloadRequestWithoutRange() {
  const std::string request = reashoot::buildDownloadRequest(
      "/recordings/clip.mov", "phone.local", 8788, "deadbeef", 0, std::nullopt);
  const std::string expected =
      "GET /recordings/clip.mov?token=deadbeef HTTP/1.1\r\n"
      "Host: phone.local:8788\r\n"
      "Accept: */*\r\n"
      "Connection: close\r\n"
      "\r\n";
  require(request == expected, "download request without Range should mirror the helper");
}

void buildsDownloadRequestWithRange() {
  const std::string request = reashoot::buildDownloadRequest(
      "/recordings/clip.mov", "phone.local", 8788, "deadbeef", 50,
      std::optional<std::int64_t>(200), 10);
  const std::string expected =
      "GET /recordings/clip.mov?token=deadbeef HTTP/1.1\r\n"
      "Host: phone.local:8788\r\n"
      "Accept: */*\r\n"
      "Connection: close\r\n"
      "Range: bytes=50-59\r\n"
      "\r\n";
  require(request == expected, "download request with Range should mirror the helper");
}

void parsesPartialContentResponse() {
  const reashoot::HttpHeaders headers = reashoot::parseHttpHeaders(
      "HTTP/1.1 206 Partial Content\r\n"
      "Content-Length: 150\r\n"
      "Content-Range: bytes 50-199/200\r\n"
      "\r\n");
  const reashoot::DownloadResponseInfo info = reashoot::parseDownloadResponse(headers);
  require(info.status == 206, "status should parse");
  require(info.contentLength == 150, "content length should parse");
  require(info.totalBytes == 200, "total bytes should parse from content-range");
}

void parsesOkResponseWithoutContentRange() {
  const reashoot::HttpHeaders headers = reashoot::parseHttpHeaders(
      "HTTP/1.1 200 OK\r\n"
      "Content-Length: 4096\r\n"
      "\r\n");
  const reashoot::DownloadResponseInfo info = reashoot::parseDownloadResponse(headers);
  require(info.status == 200, "status should parse");
  require(info.contentLength == 4096, "content length should parse");
  require(!info.totalBytes.has_value(), "total bytes should be absent without content-range");
}

} // namespace

int main() {
  try {
    hashesNistKnownAnswers();
    hashesIncrementallyAcrossBlocks();
    reusesHasherAfterFinalize();
    computesResumeRangeHeader();
    buildsDownloadRequestWithoutRange();
    buildsDownloadRequestWithRange();
    parsesPartialContentResponse();
    parsesOkResponseWithoutContentRange();
  } catch (const std::exception &error) {
    std::cerr << "download_tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
