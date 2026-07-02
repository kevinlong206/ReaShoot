#include "reaphone/control_protocol.h"
#include "reaphone/json.h"

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

bool parseThrows(const std::string &text) {
  try {
    (void)reaphone::json::parse(text);
  } catch (const std::invalid_argument &) {
    return true;
  }
  return false;
}

void parsesScalarsAndContainers() {
  require(reaphone::json::parse("  true ").asBool(), "parses whitespace-padded true");
  require(reaphone::json::parse("null").isNull(), "parses null");
  require(reaphone::json::parse("42").asInt() == 42, "parses integer");
  require(reaphone::json::parse("-3.5").asDouble() == -3.5, "parses negative real");

  const reaphone::json::Value array = reaphone::json::parse("[1, \"two\", false]");
  require(array.isArray() && array.items().size() == 3, "parses array size");
  require(array.items()[0].asInt() == 1, "array element 0");
  require(array.items()[1].asString() == "two", "array element 1");
  require(array.items()[2].asBool() == false, "array element 2");

  const reaphone::json::Value object = reaphone::json::parse("{\"a\":1,\"b\":{\"c\":2}}");
  require(object.find("a") != nullptr && object.find("a")->asInt() == 1, "nested lookup a");
  require(object.find("b")->find("c")->asInt() == 2, "nested lookup b.c");
  require(object.find("missing") == nullptr, "missing key returns nullptr");
}

void parsesStringEscapesAndUnicode() {
  require(reaphone::json::parse("\"line1\\nline2\"").asString() == "line1\nline2",
          "decodes newline escape");
  require(reaphone::json::parse("\"a\\/b\"").asString() == "a/b", "decodes escaped slash");
  // U+00E9 (é) as a \u escape becomes two UTF-8 bytes.
  require(reaphone::json::parse("\"\\u00e9\"").asString() == "\xc3\xa9", "decodes BMP \\u escape");
  // U+1F600 via surrogate pair becomes four UTF-8 bytes.
  require(reaphone::json::parse("\"\\ud83d\\ude00\"").asString() == "\xf0\x9f\x98\x80",
          "decodes surrogate pair");
}

void rejectsMalformedJson() {
  require(parseThrows("{\"a\":}"), "missing value");
  require(parseThrows("[1,2"), "unterminated array");
  require(parseThrows("{\"a\":1,}"), "trailing comma is rejected");
  require(parseThrows("nul"), "bad literal");
  require(parseThrows("\"unterminated"), "unterminated string");
  require(parseThrows("1 2"), "trailing content");
}

void roundTripsEncodeThenParse() {
  const std::string encoded = reaphone::json::Value::object()
                                  .set("z", reaphone::json::Value::integer(1))
                                  .set("a", reaphone::json::Value::string("hi\n"))
                                  .dump();
  const reaphone::json::Value parsed = reaphone::json::parse(encoded);
  require(parsed.find("a")->asString() == "hi\n", "round-trips escaped string");
  require(parsed.find("z")->asInt() == 1, "round-trips integer");
}

void decodesRecordingStoppedEvent() {
  const std::string json =
      "{\"type\":\"recordingStopped\",\"protocolVersion\":1,"
      "\"requestID\":\"11111111-2222-3333-4444-555555555555\","
      "\"recording\":{\"id\":\"rec1\",\"filename\":\"clip.mov\",\"byteCount\":123456,"
      "\"durationSeconds\":12.5,\"checksumSHA256\":\"abcd\","
      "\"downloadPath\":\"/recordings/rec1\"}}";
  const reaphone::ControlEvent event = reaphone::decodeControlEvent(json);
  require(event.type == reaphone::EventType::RecordingStopped, "type");
  require(event.requestID == "11111111-2222-3333-4444-555555555555", "requestID");
  require(event.recording.has_value(), "recording present");
  require(event.recording->id == "rec1", "recording id");
  require(event.recording->filename == "clip.mov", "recording filename");
  require(event.recording->byteCount == 123456, "recording byteCount");
  require(event.recording->durationSeconds == 12.5, "recording duration");
  require(event.recording->checksumSHA256 == "abcd", "recording checksum");
  require(event.recording->downloadPath == "/recordings/rec1", "recording downloadPath");
}

void decodesRecordingsListedEvent() {
  const std::string json =
      "{\"type\":\"recordingsListed\",\"recordings\":["
      "{\"id\":\"a\",\"filename\":\"a.mov\",\"byteCount\":1,\"downloadPath\":\"/a\"},"
      "{\"id\":\"b\",\"filename\":\"b.mov\",\"byteCount\":2,\"downloadPath\":\"/b\"}]}";
  const reaphone::ControlEvent event = reaphone::decodeControlEvent(json);
  require(event.type == reaphone::EventType::RecordingsListed, "type");
  require(event.recordings.size() == 2, "two recordings");
  require(event.recordings[0].id == "a" && event.recordings[1].id == "b", "recording order");
  require(!event.recording.has_value(), "single recording absent");
}

void decodesWebRTCAndErrorEvents() {
  const reaphone::ControlEvent answer = reaphone::decodeControlEvent(
      "{\"type\":\"webRTCPreviewAnswer\",\"webRTCAnswerSDP\":\"v=0\\r\\ns=-\"}");
  require(answer.type == reaphone::EventType::WebRTCPreviewAnswer, "answer type");
  require(answer.webRTCAnswerSDP == "v=0\r\ns=-", "answer SDP with escaped CRLF");

  const reaphone::ControlEvent error =
      reaphone::decodeControlEvent("{\"type\":\"error\",\"message\":\"boom\"}");
  require(error.type == reaphone::EventType::Error, "error type");
  require(error.message == "boom", "error message");

  const reaphone::ControlEvent pong = reaphone::decodeControlEvent("{\"type\":\"pong\"}");
  require(pong.type == reaphone::EventType::Pong, "pong type");
  require(!pong.message.has_value(), "pong has no message");
}

void handlesUnknownAndInvalidEvents() {
  const reaphone::ControlEvent unknown =
      reaphone::decodeControlEvent("{\"type\":\"somethingNew\"}");
  require(unknown.type == reaphone::EventType::Unknown, "unknown type maps to Unknown");

  bool threw = false;
  try {
    (void)reaphone::decodeControlEvent("{\"protocolVersion\":1}");
  } catch (const std::invalid_argument &) {
    threw = true;
  }
  require(threw, "missing type throws");

  threw = false;
  try {
    (void)reaphone::decodeControlEvent("not json");
  } catch (const std::invalid_argument &) {
    threw = true;
  }
  require(threw, "malformed JSON throws");
}

} // namespace

int main() {
  try {
    parsesScalarsAndContainers();
    parsesStringEscapesAndUnicode();
    rejectsMalformedJson();
    roundTripsEncodeThenParse();
    decodesRecordingStoppedEvent();
    decodesRecordingsListedEvent();
    decodesWebRTCAndErrorEvents();
    handlesUnknownAndInvalidEvents();
  } catch (const std::exception &error) {
    std::cerr << "event_tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
