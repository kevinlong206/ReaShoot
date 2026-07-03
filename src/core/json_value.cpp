#include "json_value.h"

#include <cctype>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <sstream>

namespace reashoot::core {
namespace {

class Parser {
public:
  explicit Parser(const std::string &text) : text_(text) {}

  JsonValue parse() {
    JsonValue value = parseValue();
    skipWhitespace();
    if (position_ != text_.size()) {
      throw JsonError("Unexpected trailing JSON content.");
    }
    return value;
  }

private:
  JsonValue parseValue() {
    skipWhitespace();
    if (position_ >= text_.size()) {
      throw JsonError("Unexpected end of JSON.");
    }
    const char c = text_[position_];
    if (c == 'n') {
      expect("null");
      return JsonValue();
    }
    if (c == 't') {
      expect("true");
      return JsonValue(true);
    }
    if (c == 'f') {
      expect("false");
      return JsonValue(false);
    }
    if (c == '"') {
      return JsonValue(parseString());
    }
    if (c == '{') {
      return JsonValue(parseObject());
    }
    if (c == '[') {
      return JsonValue(parseArray());
    }
    if (c == '-' || std::isdigit(static_cast<unsigned char>(c))) {
      return JsonValue(parseNumber());
    }
    throw JsonError("Unexpected JSON value.");
  }

  JsonValue::Object parseObject() {
    JsonValue::Object object;
    consume('{');
    skipWhitespace();
    if (peek('}')) {
      consume('}');
      return object;
    }
    while (true) {
      skipWhitespace();
      std::string key = parseString();
      skipWhitespace();
      consume(':');
      object.emplace(std::move(key), parseValue());
      skipWhitespace();
      if (peek('}')) {
        consume('}');
        return object;
      }
      consume(',');
    }
  }

  JsonValue::Array parseArray() {
    JsonValue::Array array;
    consume('[');
    skipWhitespace();
    if (peek(']')) {
      consume(']');
      return array;
    }
    while (true) {
      array.push_back(parseValue());
      skipWhitespace();
      if (peek(']')) {
        consume(']');
        return array;
      }
      consume(',');
    }
  }

  std::string parseString() {
    consume('"');
    std::string value;
    while (position_ < text_.size()) {
      const char c = text_[position_++];
      if (c == '"') {
        return value;
      }
      if (c != '\\') {
        value.push_back(c);
        continue;
      }
      if (position_ >= text_.size()) {
        throw JsonError("Invalid JSON string escape.");
      }
      const char escaped = text_[position_++];
      switch (escaped) {
      case '"':
      case '\\':
      case '/':
        value.push_back(escaped);
        break;
      case 'b':
        value.push_back('\b');
        break;
      case 'f':
        value.push_back('\f');
        break;
      case 'n':
        value.push_back('\n');
        break;
      case 'r':
        value.push_back('\r');
        break;
      case 't':
        value.push_back('\t');
        break;
      case 'u':
        value.push_back(parseUnicodeEscape());
        break;
      default:
        throw JsonError("Invalid JSON string escape.");
      }
    }
    throw JsonError("Unterminated JSON string.");
  }

  char parseUnicodeEscape() {
    if (position_ + 4 > text_.size()) {
      throw JsonError("Invalid JSON unicode escape.");
    }
    int value = 0;
    for (int i = 0; i < 4; ++i) {
      const char c = text_[position_++];
      value <<= 4;
      if (c >= '0' && c <= '9') {
        value += c - '0';
      } else if (c >= 'a' && c <= 'f') {
        value += c - 'a' + 10;
      } else if (c >= 'A' && c <= 'F') {
        value += c - 'A' + 10;
      } else {
        throw JsonError("Invalid JSON unicode escape.");
      }
    }
    return value >= 0 && value <= 0x7f ? static_cast<char>(value) : '?';
  }

  double parseNumber() {
    const size_t start = position_;
    if (peek('-')) {
      ++position_;
    }
    while (position_ < text_.size() && std::isdigit(static_cast<unsigned char>(text_[position_]))) {
      ++position_;
    }
    if (peek('.')) {
      ++position_;
      while (position_ < text_.size() && std::isdigit(static_cast<unsigned char>(text_[position_]))) {
        ++position_;
      }
    }
    if (peek('e') || peek('E')) {
      ++position_;
      if (peek('+') || peek('-')) {
        ++position_;
      }
      while (position_ < text_.size() && std::isdigit(static_cast<unsigned char>(text_[position_]))) {
        ++position_;
      }
    }
    char *end = nullptr;
    const double value = std::strtod(text_.c_str() + start, &end);
    if (end != text_.c_str() + position_) {
      throw JsonError("Invalid JSON number.");
    }
    return value;
  }

  void expect(const char *literal) {
    const std::string value(literal);
    if (text_.compare(position_, value.size(), value) != 0) {
      throw JsonError("Invalid JSON literal.");
    }
    position_ += value.size();
  }

  bool peek(char c) const { return position_ < text_.size() && text_[position_] == c; }

  void consume(char c) {
    if (!peek(c)) {
      throw JsonError("Unexpected JSON token.");
    }
    ++position_;
  }

  void skipWhitespace() {
    while (position_ < text_.size() && std::isspace(static_cast<unsigned char>(text_[position_]))) {
      ++position_;
    }
  }

  const std::string &text_;
  size_t position_ = 0;
};

std::string serializeNumber(double value) {
  if (std::isfinite(value) && std::floor(value) == value) {
    return std::to_string(static_cast<int64_t>(value));
  }
  std::ostringstream stream;
  stream << std::setprecision(15) << value;
  return stream.str();
}

} // namespace

JsonValue::JsonValue() = default;
JsonValue::JsonValue(bool value) : type_(Type::Bool), boolValue_(value) {}
JsonValue::JsonValue(double value) : type_(Type::Number), numberValue_(value) {}
JsonValue::JsonValue(std::string value) : type_(Type::String), stringValue_(std::move(value)) {}
JsonValue::JsonValue(Object value) : type_(Type::Object), objectValue_(std::move(value)) {}
JsonValue::JsonValue(Array value) : type_(Type::Array), arrayValue_(std::move(value)) {}

bool JsonValue::asBool(bool fallback) const { return type_ == Type::Bool ? boolValue_ : fallback; }
double JsonValue::asNumber(double fallback) const { return type_ == Type::Number ? numberValue_ : fallback; }

const std::string &JsonValue::asString() const {
  if (type_ != Type::String) {
    throw JsonError("JSON value is not a string.");
  }
  return stringValue_;
}

const JsonValue::Object &JsonValue::asObject() const {
  if (type_ != Type::Object) {
    throw JsonError("JSON value is not an object.");
  }
  return objectValue_;
}

const JsonValue::Array &JsonValue::asArray() const {
  if (type_ != Type::Array) {
    throw JsonError("JSON value is not an array.");
  }
  return arrayValue_;
}

const JsonValue *JsonValue::find(const std::string &key) const {
  if (type_ != Type::Object) {
    return nullptr;
  }
  const auto it = objectValue_.find(key);
  return it == objectValue_.end() ? nullptr : &it->second;
}

std::string JsonValue::stringValue(const std::string &key, const std::string &fallback) const {
  const JsonValue *value = find(key);
  return value && value->type_ == Type::String ? value->stringValue_ : fallback;
}

int JsonValue::intValue(const std::string &key, int fallback) const {
  const JsonValue *value = find(key);
  return value && value->type_ == Type::Number ? static_cast<int>(value->numberValue_) : fallback;
}

int64_t JsonValue::int64Value(const std::string &key, int64_t fallback) const {
  const JsonValue *value = find(key);
  return value && value->type_ == Type::Number ? static_cast<int64_t>(value->numberValue_) : fallback;
}

double JsonValue::numberValue(const std::string &key, double fallback) const {
  const JsonValue *value = find(key);
  return value && value->type_ == Type::Number ? value->numberValue_ : fallback;
}

bool JsonValue::boolValue(const std::string &key, bool fallback) const {
  const JsonValue *value = find(key);
  return value && value->type_ == Type::Bool ? value->boolValue_ : fallback;
}

std::string JsonValue::serialize() const {
  switch (type_) {
  case Type::Null:
    return "null";
  case Type::Bool:
    return boolValue_ ? "true" : "false";
  case Type::Number:
    return serializeNumber(numberValue_);
  case Type::String:
    return escapeJsonString(stringValue_);
  case Type::Object: {
    std::string output = "{";
    bool first = true;
    for (const auto &entry : objectValue_) {
      if (!first) {
        output += ",";
      }
      first = false;
      output += escapeJsonString(entry.first);
      output += ":";
      output += entry.second.serialize();
    }
    output += "}";
    return output;
  }
  case Type::Array: {
    std::string output = "[";
    for (size_t i = 0; i < arrayValue_.size(); ++i) {
      if (i > 0) {
        output += ",";
      }
      output += arrayValue_[i].serialize();
    }
    output += "]";
    return output;
  }
  }
  return "null";
}

JsonValue parseJson(const std::string &text) {
  return Parser(text).parse();
}

std::string escapeJsonString(const std::string &value) {
  std::string output = "\"";
  for (const char c : value) {
    switch (c) {
    case '"':
      output += "\\\"";
      break;
    case '\\':
      output += "\\\\";
      break;
    case '\b':
      output += "\\b";
      break;
    case '\f':
      output += "\\f";
      break;
    case '\n':
      output += "\\n";
      break;
    case '\r':
      output += "\\r";
      break;
    case '\t':
      output += "\\t";
      break;
    default:
      output.push_back(c);
      break;
    }
  }
  output += "\"";
  return output;
}

} // namespace reashoot::core
