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

void jsonWriterSortsKeysAndEscapes() {
  reaphone::json::Value object = reaphone::json::Value::object();
  object.set("b", reaphone::json::Value::integer(2));
  object.set("a", reaphone::json::Value::string("x\"y\\z\n"));
  require(object.dump() == "{\"a\":\"x\\\"y\\\\z\\n\",\"b\":2}",
          "object keys should sort and strings should escape");

  reaphone::json::Value array = reaphone::json::Value::array();
  array.add(reaphone::json::Value::boolean(true));
  array.add(reaphone::json::Value());
  array.add(reaphone::json::Value::real(1.5));
  require(array.dump() == "[true,null,1.5]", "array should serialize in order");

  require(reaphone::json::Value::real(1.0).dump() == "1",
          "whole doubles should format without a decimal point");
}

void encodesPingCommandWithSortedKeys() {
  reaphone::ControlCommand command;
  command.requestID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
  command.type = reaphone::CommandType::Ping;
  command.token = "abc";

  const std::string expected =
      "{\"metadata\":{},"
      "\"protocolVersion\":1,"
      "\"requestID\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\","
      "\"token\":\"abc\","
      "\"type\":\"ping\"}";
  require(reaphone::encodeControlCommand(command) == expected,
          "ping command should encode with sorted keys and omitted optionals");
}

void encodesConfigureCaptureWithProfile() {
  reaphone::ControlCommand command;
  command.requestID = "11111111-2222-3333-4444-555555555555";
  command.type = reaphone::CommandType::ConfigureCapture;
  command.token = "tok";
  command.captureProfile = reaphone::CaptureProfile{}; // defaults

  const std::string expected =
      "{\"captureProfile\":{"
      "\"aspectRatio\":\"9:16\",\"fps\":30,\"lens\":\"wide\",\"look\":\"natural\","
      "\"orientation\":\"portrait\",\"resolution\":\"4K\",\"zoomFactor\":1},"
      "\"metadata\":{},"
      "\"protocolVersion\":1,"
      "\"requestID\":\"11111111-2222-3333-4444-555555555555\","
      "\"token\":\"tok\","
      "\"type\":\"configureCapture\"}";
  require(reaphone::encodeControlCommand(command) == expected,
          "configureCapture should encode a sorted-key capture profile");
}

void encodesIceCandidateAndMetadata() {
  reaphone::ControlCommand command;
  command.requestID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
  command.type = reaphone::CommandType::AddWebRTCIceCandidate;
  command.token = "tok";
  command.webRTCIceCandidateSDP = "candidate:1 1 udp";
  command.webRTCIceCandidateMid = "0";
  command.webRTCIceCandidateMLineIndex = 0;
  command.metadata = {{"path", "a/b"}, {"note", "line1\nline2"}};

  const std::string expected =
      "{\"metadata\":{\"note\":\"line1\\nline2\",\"path\":\"a/b\"},"
      "\"protocolVersion\":1,"
      "\"requestID\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\","
      "\"token\":\"tok\","
      "\"type\":\"addWebRTCIceCandidate\","
      "\"webRTCIceCandidateMLineIndex\":0,"
      "\"webRTCIceCandidateMid\":\"0\","
      "\"webRTCIceCandidateSDP\":\"candidate:1 1 udp\"}";
  require(reaphone::encodeControlCommand(command) == expected,
          "ICE candidate command should encode sorted keys and escaped metadata");
}

void mapsAllCommandTypeRawValues() {
  require(reaphone::commandTypeRawValue(reaphone::CommandType::Pair) == "pair", "pair");
  require(reaphone::commandTypeRawValue(reaphone::CommandType::StartRecording) == "startRecording",
          "startRecording");
  require(reaphone::commandTypeRawValue(reaphone::CommandType::StopWebRTCPreview) ==
              "stopWebRTCPreview",
          "stopWebRTCPreview");
  require(reaphone::commandTypeRawValue(reaphone::CommandType::TransferComplete) ==
              "transferComplete",
          "transferComplete");
}

} // namespace

int main() {
  try {
    jsonWriterSortsKeysAndEscapes();
    encodesPingCommandWithSortedKeys();
    encodesConfigureCaptureWithProfile();
    encodesIceCandidateAndMetadata();
    mapsAllCommandTypeRawValues();
  } catch (const std::exception &error) {
    std::cerr << "protocol_tests failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
