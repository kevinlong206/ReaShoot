#include "helper_output_parser.h"

#include <cctype>
#include <sstream>

namespace reashoot::core {
namespace {

std::string trimAsciiWhitespace(std::string value) {
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) {
    value.erase(value.begin());
  }
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) {
    value.pop_back();
  }
  return value;
}

} // namespace

FieldMap parseFields(const std::string &line, char separator) {
  FieldMap fields;
  std::stringstream stream(line);
  std::string part;
  while (std::getline(stream, part, separator)) {
    const std::string::size_type equals = part.find('=');
    if (equals == std::string::npos || equals == 0) {
      continue;
    }
    std::string key = trimAsciiWhitespace(part.substr(0, equals));
    if (key.empty()) {
      continue;
    }
    fields[key] = trimAsciiWhitespace(part.substr(equals + 1));
  }
  return fields;
}

std::vector<FieldMap> parseRecordings(const std::string &output) {
  std::vector<FieldMap> recordings;
  std::stringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    if (line.rfind("recording\t", 0) == 0) {
      recordings.push_back(parseFields(line, '\t'));
    }
  }
  return recordings;
}

FieldMap parseFirstDevice(const std::string &output) {
  std::stringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    if (line.rfind("device\t", 0) == 0) {
      FieldMap fields = parseFields(line, '\t');
      if (!fields["host"].empty()) {
        return fields;
      }
    }
  }
  return {};
}

std::string parseDownloadedPath(const std::string &output) {
  std::stringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    constexpr const char *prefix = "downloaded ";
    if (line.rfind(prefix, 0) == 0) {
      return trimAsciiWhitespace(line.substr(std::char_traits<char>::length(prefix)));
    }
  }
  return {};
}

std::string progressStatusText(const std::string &line) {
  if (line.rfind("encode ", 0) == 0) {
    FieldMap fields = parseFields(line, ' ');
    const auto percent = fields.find("percent");
    if (percent != fields.end() && !percent->second.empty()) {
      return "Encoding iPhone look: " + percent->second + "%";
    }
    return "Encoding iPhone look";
  }
  if (line.rfind("progress ", 0) != 0) {
    return {};
  }
  FieldMap fields = parseFields(line, ' ');
  const auto percent = fields.find("percent");
  if (percent != fields.end() && !percent->second.empty()) {
    return "Downloading iPhone video: " + percent->second + "%";
  }
  const auto bytes = fields.find("bytes");
  const auto total = fields.find("total");
  if (bytes != fields.end() && !bytes->second.empty() &&
      total != fields.end() && !total->second.empty()) {
    return "Downloading iPhone video: " + bytes->second + "/" + total->second + " bytes";
  }
  return {};
}

} // namespace reashoot::core
