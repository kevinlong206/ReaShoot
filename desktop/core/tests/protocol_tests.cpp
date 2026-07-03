#include "reashoot/control_protocol.h"
#include "reashoot/json.h"

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
  reashoot::json::Value object = reashoot::json::Value::object();
  object.set("b", reashoot::json::Value::integer(2));
  object.set("a", reashoot::json::Value::string("x\"y\\z\n"));
  require(object.dump() == "{\"a\":\"x\\\"y\\\\z\\n\",\"b\":2}",
          "object keys should sort and strings should escape");

  reashoot::json::Value array = reashoot::json::Value::array();
  array.add(reashoot::json::Value::boolean(true));
  array.add(reashoot::json::Value());
  array.add(reashoot::json::Value::real(1.5));
  require(array.dump() == "[true,null,1.5]", "array should serialize in order");

  require(reashoot::json::Value::real(1.0).dump() == "1",
          "whole doubles should format without a decimal point");
}

void encodesPingCommandWithSortedKeys() {
  reashoot::ControlCommand command;
  command.requestID = "E621E1F8-C36C-495A-93FC-0C247A3E6E5F";
  command.type = reashoot::CommandType::Ping;
  command.token = "abc";

  const std::string expected =
      "{\"metadata\":{},"
      "\"protocolVersion\":1,"
      "\"requestID\":\"E621E1F8-C36C-495A-93FC-0C247A3E6E5F\","
      "\"token\":\"abc\","
      "\"type\":\"ping\"}";
  require(reashoot::encodeControlCommand(command) == expected,
          "ping command should encode with sorted keys and omitted optionals");
}

void encodesConfigureCaptureWithProfile() {
  reashoot::ControlCommand command;
  command.requestID = "11111111-2222-3333-4444-555555555555";
  command.type = reashoot::CommandType::ConfigureCapture;
  command.token = "tok";
  command.captureProfile = reashoot::CaptureProfile{}; // defaults

  const std::string expected =
      "{\"captureProfile\":{"
      "\"aspectRatio\":\"9:16\",\"fps\":30,\"lens\":\"wide\",\"look\":\"natural\","
      "\"orientation\":\"portrait\",\"resolution\":\"4K\",\"zoomFactor\":1},"
      "\"metadata\":{},"
      "\"protocolVersion\":1,"
      "\"requestID\":\"11111111-2222-3333-4444-555555555555\","
      "\"token\":\"tok\","
      "\"type\":\"configureCapture\"}";
  require(reashoot::encodeControlCommand(command) == expected,
          "configureCapture should encode a sorted-key capture profile");
}

void encodesIceCandidateAndMetadata() {
  reashoot::ControlCommand command;
  command.requestID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE";
  command.type = reashoot::CommandType::AddWebRTCIceCandidate;
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
  require(reashoot::encodeControlCommand(command) == expected,
          "ICE candidate command should encode sorted keys and escaped metadata");
}

void mapsAllCommandTypeRawValues() {
  require(reashoot::commandTypeRawValue(reashoot::CommandType::Pair) == "pair", "pair");
  require(reashoot::commandTypeRawValue(reashoot::CommandType::StartRecording) == "startRecording",
          "startRecording");
  require(reashoot::commandTypeRawValue(reashoot::CommandType::StopWebRTCPreview) ==
              "stopWebRTCPreview",
          "stopWebRTCPreview");
  require(reashoot::commandTypeRawValue(reashoot::CommandType::TransferComplete) ==
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
