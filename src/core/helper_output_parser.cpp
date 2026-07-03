#include "helper_output_parser.h"

#include <sstream>

namespace reashoot::core {

FieldMap parseFields(const std::string &line, char separator) {
  FieldMap fields;
  std::stringstream stream(line);
  std::string part;
  while (std::getline(stream, part, separator)) {
    const std::string::size_type equals = part.find('=');
    if (equals == std::string::npos || equals == 0) {
      continue;
    }
    fields[part.substr(0, equals)] = part.substr(equals + 1);
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
      return line.substr(std::char_traits<char>::length(prefix));
    }
  }
  return {};
}

} // namespace reashoot::core
