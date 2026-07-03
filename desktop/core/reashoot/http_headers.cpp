#include "reashoot/http_headers.h"

#include <algorithm>
#include <cctype>
#include <stdexcept>

namespace reashoot {
namespace {

bool equalsIgnoreAsciiCase(std::string_view left, std::string_view right) {
  if (left.size() != right.size()) {
    return false;
  }

  for (std::size_t i = 0; i < left.size(); ++i) {
    const auto l = static_cast<unsigned char>(left[i]);
    const auto r = static_cast<unsigned char>(right[i]);
    if (std::tolower(l) != std::tolower(r)) {
      return false;
    }
  }
  return true;
}

std::vector<std::string_view> splitHeaderLines(std::string_view bytes) {
  std::vector<std::string_view> lines;
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const std::size_t lineEnd = bytes.find("\r\n", offset);
    if (lineEnd == std::string_view::npos) {
      lines.push_back(bytes.substr(offset));
      break;
    }
    lines.push_back(bytes.substr(offset, lineEnd - offset));
    offset = lineEnd + 2;
  }
  return lines;
}

} // namespace

std::string trimAsciiWhitespace(std::string_view value) {
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) {
    value.remove_prefix(1);
  }
  while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) {
    value.remove_suffix(1);
  }
  return std::string(value);
}

std::optional<std::size_t> completeHeaderLength(std::string_view bytes) {
  const std::size_t end = bytes.find("\r\n\r\n");
  if (end == std::string_view::npos) {
    return std::nullopt;
  }
  return end + 4;
}

HttpHeaders parseHttpHeaders(std::string_view bytes) {
  const auto length = completeHeaderLength(bytes);
  if (!length) {
    throw std::invalid_argument("HTTP headers are incomplete");
  }

  const std::string_view headerBlock = bytes.substr(0, *length - 4);
  const std::vector<std::string_view> lines = splitHeaderLines(headerBlock);
  if (lines.empty() || lines.front().empty()) {
    throw std::invalid_argument("HTTP headers are missing a start line");
  }

  HttpHeaders headers;
  headers.startLine = std::string(lines.front());

  for (std::size_t i = 1; i < lines.size(); ++i) {
    const std::string_view line = lines[i];
    if (line.empty()) {
      continue;
    }

    const std::size_t separator = line.find(':');
    if (separator == std::string_view::npos) {
      throw std::invalid_argument("HTTP header line is missing ':'");
    }

    headers.fields.push_back({
        trimAsciiWhitespace(line.substr(0, separator)),
        trimAsciiWhitespace(line.substr(separator + 1)),
    });
  }

  return headers;
}

std::optional<std::string> HttpHeaders::value(std::string_view name) const {
  const auto found = std::find_if(fields.begin(), fields.end(), [&](const HttpHeader &header) {
    return equalsIgnoreAsciiCase(header.name, name);
  });
  if (found == fields.end()) {
    return std::nullopt;
  }
  return found->value;
}

} // namespace reashoot
