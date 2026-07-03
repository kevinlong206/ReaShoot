#include "reashoot/http_headers.h"
#include "reashoot/websocket.h"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void detectsCompleteHeadersOnlyAtDoubleCrlf() {
  require(!reashoot::completeHeaderLength("HTTP/1.1 101 Switching Protocols\r\n").has_value(),
          "partial headers should not be complete");

  const std::string response =
      "HTTP/1.1 101 Switching Protocols\r\n"
      "Sec-WebSocket-Accept: abc\r\n"
      "\r\n"
      "body";
  const auto length = reashoot::completeHeaderLength(response);
  require(length.has_value(), "complete headers should be detected");
  require(*length == response.find("body"), "header length should exclude body bytes");
}

void parsesHeadersCaseInsensitively() {
  const std::string response =
      "HTTP/1.1 101 Switching Protocols\r\n"
      "Upgrade: websocket\r\n"
      "Sec-WebSocket-Accept:  expected-value \r\n"
      "\r\n";

  const reashoot::HttpHeaders headers = reashoot::parseHttpHeaders(response);
  require(headers.startLine == "HTTP/1.1 101 Switching Protocols", "start line should parse");
  require(headers.value("sec-websocket-accept") == "expected-value", "lookup should ignore case and trim");
  require(headers.value("missing") == std::nullopt, "missing header should return nullopt");
}

void rejectsMalformedOrIncompleteHeaders() {
  bool threw = false;
  try {
    (void)reashoot::parseHttpHeaders("HTTP/1.1 200 OK\r\nBadHeader\r\n\r\n");
  } catch (const std::invalid_argument &) {
    threw = true;
  }
  require(threw, "malformed header should throw");

  threw = false;
  try {
    (void)reashoot::parseHttpHeaders("HTTP/1.1 200 OK\r\nHeader: value\r\n");
  } catch (const std::invalid_argument &) {
    threw = true;
  }
  require(threw, "incomplete header should throw");
}

void validatesWebSocketAcceptKey() {
  require(reashoot::webSocketAcceptKey("dGhlIHNhbXBsZSBub25jZQ==") ==
              "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
          "accept key should match RFC 6455 example");
}

void validatesWebSocketSwitchingProtocolResponse() {
  const std::string clientKey = "dGhlIHNhbXBsZSBub25jZQ==";
  const std::string response =
      "HTTP/1.1 101 Switching Protocols\r\n"
      "Upgrade: websocket\r\n"
      "Connection: keep-alive, Upgrade\r\n"
      "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"
      "\r\n";

  require(reashoot::isWebSocketSwitchingProtocolsResponse(reashoot::parseHttpHeaders(response), clientKey),
          "valid WebSocket switching response should pass");

  const std::string badResponse =
      "HTTP/1.1 101 Switching Protocols\r\n"
      "Upgrade: websocket\r\n"
      "Connection: Upgrade\r\n"
      "Sec-WebSocket-Accept: wrong\r\n"
      "\r\n";
  require(!reashoot::isWebSocketSwitchingProtocolsResponse(reashoot::parseHttpHeaders(badResponse), clientKey),
          "wrong Sec-WebSocket-Accept should fail");
}

} // namespace

int main() {
  try {
    detectsCompleteHeadersOnlyAtDoubleCrlf();
    parsesHeadersCaseInsensitively();
    rejectsMalformedOrIncompleteHeaders();
    validatesWebSocketAcceptKey();
    validatesWebSocketSwitchingProtocolResponse();
  } catch (const std::exception &error) {
    std::cerr << "http_headers_tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
