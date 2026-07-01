#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace reaphone {

struct HttpHeader {
  std::string name;
  std::string value;
};

struct HttpHeaders {
  std::string startLine;
  std::vector<HttpHeader> fields;

  std::optional<std::string> value(std::string_view name) const;
};

std::optional<std::size_t> completeHeaderLength(std::string_view bytes);
HttpHeaders parseHttpHeaders(std::string_view bytes);
std::string trimAsciiWhitespace(std::string_view value);

} // namespace reaphone
