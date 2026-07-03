#include "reashoot/json.h"

#include <cstdio>
#include <stdexcept>
#include <string>

namespace reashoot::json {

Value::Value() : type_(Type::Null) {}

Value Value::string(std::string value) {
  Value result;
  result.type_ = Type::String;
  result.string_ = std::move(value);
  return result;
}

Value Value::integer(std::int64_t value) {
  Value result;
  result.type_ = Type::Integer;
  result.integer_ = value;
  return result;
}

Value Value::real(double value) {
  Value result;
  result.type_ = Type::Real;
  result.real_ = value;
  return result;
}

Value Value::boolean(bool value) {
  Value result;
  result.type_ = Type::Bool;
  result.bool_ = value;
  return result;
}

Value Value::object() {
  Value result;
  result.type_ = Type::Object;
  return result;
}

Value Value::array() {
  Value result;
  result.type_ = Type::Array;
  return result;
}

Value &Value::set(const std::string &key, Value value) {
  object_[key] = std::move(value);
  return *this;
}

Value &Value::add(Value value) {
  array_.push_back(std::move(value));
  return *this;
}

void appendEscapedString(std::string &out, std::string_view value) {
  out.push_back('"');
  for (const char rawChar : value) {
    const unsigned char c = static_cast<unsigned char>(rawChar);
    switch (c) {
    case '"':
      out.append("\\\"");
      break;
    case '\\':
      out.append("\\\\");
      break;
    case '\b':
      out.append("\\b");
      break;
    case '\f':
      out.append("\\f");
      break;
    case '\n':
      out.append("\\n");
      break;
    case '\r':
      out.append("\\r");
      break;
    case '\t':
      out.append("\\t");
      break;
    default:
      if (c < 0x20) {
        char buffer[7];
        std::snprintf(buffer, sizeof(buffer), "\\u%04x", c);
        out.append(buffer);
      } else {
        out.push_back(rawChar);
      }
      break;
    }
  }
  out.push_back('"');
}

void Value::dumpTo(std::string &out) const {
  switch (type_) {
  case Type::Null:
    out.append("null");
    break;
  case Type::Bool:
    out.append(bool_ ? "true" : "false");
    break;
  case Type::Integer:
    out.append(std::to_string(integer_));
    break;
  case Type::Real: {
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "%.10g", real_);
    out.append(buffer);
    break;
  }
  case Type::String:
    appendEscapedString(out, string_);
    break;
  case Type::Array: {
    out.push_back('[');
    bool first = true;
    for (const Value &element : array_) {
      if (!first) {
        out.push_back(',');
      }
      first = false;
      element.dumpTo(out);
    }
    out.push_back(']');
    break;
  }
  case Type::Object: {
    out.push_back('{');
    bool first = true;
    for (const auto &[key, value] : object_) {
      if (!first) {
        out.push_back(',');
      }
      first = false;
      appendEscapedString(out, key);
      out.push_back(':');
      value.dumpTo(out);
    }
    out.push_back('}');
    break;
  }
  }
}

std::string Value::dump() const {
  std::string out;
  dumpTo(out);
  return out;
}

bool Value::asBool() const {
  if (type_ != Type::Bool) {
    throw std::invalid_argument("JSON value is not a boolean");
  }
  return bool_;
}

std::int64_t Value::asInt() const {
  if (type_ == Type::Integer) {
    return integer_;
  }
  if (type_ == Type::Real) {
    return static_cast<std::int64_t>(real_);
  }
  throw std::invalid_argument("JSON value is not a number");
}

double Value::asDouble() const {
  if (type_ == Type::Real) {
    return real_;
  }
  if (type_ == Type::Integer) {
    return static_cast<double>(integer_);
  }
  throw std::invalid_argument("JSON value is not a number");
}

const std::string &Value::asString() const {
  if (type_ != Type::String) {
    throw std::invalid_argument("JSON value is not a string");
  }
  return string_;
}

const std::vector<Value> &Value::items() const {
  if (type_ != Type::Array) {
    throw std::invalid_argument("JSON value is not an array");
  }
  return array_;
}

const Value *Value::find(const std::string &key) const {
  if (type_ != Type::Object) {
    return nullptr;
  }
  const auto it = object_.find(key);
  return it == object_.end() ? nullptr : &it->second;
}

namespace {

class Parser {
public:
  explicit Parser(std::string_view text) : text_(text) {}

  Value parseDocument() {
    skipWhitespace();
    Value value = parseValue();
    skipWhitespace();
    if (index_ != text_.size()) {
      fail("trailing characters after JSON document");
    }
    return value;
  }

private:
  std::string_view text_;
  std::size_t index_ = 0;

  [[noreturn]] void fail(const char *message) const { throw std::invalid_argument(message); }

  char peek() const {
    if (index_ >= text_.size()) {
      fail("unexpected end of JSON input");
    }
    return text_[index_];
  }

  char take() {
    const char c = peek();
    ++index_;
    return c;
  }

  void skipWhitespace() {
    while (index_ < text_.size()) {
      const char c = text_[index_];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        ++index_;
      } else {
        break;
      }
    }
  }

  void expect(char expected) {
    if (take() != expected) {
      fail("unexpected character in JSON input");
    }
  }

  Value parseValue() {
    skipWhitespace();
    const char c = peek();
    switch (c) {
    case '{':
      return parseObject();
    case '[':
      return parseArray();
    case '"':
      return Value::string(parseRawString());
    case 't':
    case 'f':
      return parseBool();
    case 'n':
      return parseNull();
    default:
      return parseNumber();
    }
  }

  Value parseObject() {
    expect('{');
    Value object = Value::object();
    skipWhitespace();
    if (peek() == '}') {
      ++index_;
      return object;
    }
    while (true) {
      skipWhitespace();
      if (peek() != '"') {
        fail("expected string key in JSON object");
      }
      const std::string key = parseRawString();
      skipWhitespace();
      expect(':');
      object.set(key, parseValue());
      skipWhitespace();
      const char c = take();
      if (c == ',') {
        continue;
      }
      if (c == '}') {
        break;
      }
      fail("expected ',' or '}' in JSON object");
    }
    return object;
  }

  Value parseArray() {
    expect('[');
    Value array = Value::array();
    skipWhitespace();
    if (peek() == ']') {
      ++index_;
      return array;
    }
    while (true) {
      array.add(parseValue());
      skipWhitespace();
      const char c = take();
      if (c == ',') {
        continue;
      }
      if (c == ']') {
        break;
      }
      fail("expected ',' or ']' in JSON array");
    }
    return array;
  }

  void appendUtf8(std::string &out, unsigned int codePoint) const {
    if (codePoint <= 0x7f) {
      out.push_back(static_cast<char>(codePoint));
    } else if (codePoint <= 0x7ff) {
      out.push_back(static_cast<char>(0xc0 | (codePoint >> 6)));
      out.push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
    } else if (codePoint <= 0xffff) {
      out.push_back(static_cast<char>(0xe0 | (codePoint >> 12)));
      out.push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3f)));
      out.push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
    } else {
      out.push_back(static_cast<char>(0xf0 | (codePoint >> 18)));
      out.push_back(static_cast<char>(0x80 | ((codePoint >> 12) & 0x3f)));
      out.push_back(static_cast<char>(0x80 | ((codePoint >> 6) & 0x3f)));
      out.push_back(static_cast<char>(0x80 | (codePoint & 0x3f)));
    }
  }

  unsigned int parseHex4() {
    unsigned int value = 0;
    for (int i = 0; i < 4; ++i) {
      const char c = take();
      value <<= 4;
      if (c >= '0' && c <= '9') {
        value |= static_cast<unsigned int>(c - '0');
      } else if (c >= 'a' && c <= 'f') {
        value |= static_cast<unsigned int>(c - 'a' + 10);
      } else if (c >= 'A' && c <= 'F') {
        value |= static_cast<unsigned int>(c - 'A' + 10);
      } else {
        fail("invalid \\u escape in JSON string");
      }
    }
    return value;
  }

  std::string parseRawString() {
    expect('"');
    std::string out;
    while (true) {
      const char c = take();
      if (c == '"') {
        break;
      }
      if (c == '\\') {
        const char escape = take();
        switch (escape) {
        case '"':
          out.push_back('"');
          break;
        case '\\':
          out.push_back('\\');
          break;
        case '/':
          out.push_back('/');
          break;
        case 'b':
          out.push_back('\b');
          break;
        case 'f':
          out.push_back('\f');
          break;
        case 'n':
          out.push_back('\n');
          break;
        case 'r':
          out.push_back('\r');
          break;
        case 't':
          out.push_back('\t');
          break;
        case 'u': {
          unsigned int codePoint = parseHex4();
          if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
            // High surrogate; expect a following low surrogate.
            if (take() != '\\' || take() != 'u') {
              fail("expected low surrogate in JSON string");
            }
            const unsigned int low = parseHex4();
            if (low < 0xdc00 || low > 0xdfff) {
              fail("invalid low surrogate in JSON string");
            }
            codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (low - 0xdc00);
          }
          appendUtf8(out, codePoint);
          break;
        }
        default:
          fail("invalid escape in JSON string");
        }
      } else {
        out.push_back(c);
      }
    }
    return out;
  }

  Value parseNumber() {
    const std::size_t start = index_;
    bool isReal = false;
    if (index_ < text_.size() && (text_[index_] == '-' || text_[index_] == '+')) {
      ++index_;
    }
    while (index_ < text_.size()) {
      const char c = text_[index_];
      if (c >= '0' && c <= '9') {
        ++index_;
      } else if (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') {
        isReal = isReal || c == '.' || c == 'e' || c == 'E';
        ++index_;
      } else {
        break;
      }
    }
    if (index_ == start) {
      fail("invalid number in JSON input");
    }
    const std::string token(text_.substr(start, index_ - start));
    try {
      if (isReal) {
        return Value::real(std::stod(token));
      }
      return Value::integer(static_cast<std::int64_t>(std::stoll(token)));
    } catch (const std::exception &) {
      fail("invalid number in JSON input");
    }
  }

  Value parseBool() {
    if (text_.compare(index_, 4, "true") == 0) {
      index_ += 4;
      return Value::boolean(true);
    }
    if (text_.compare(index_, 5, "false") == 0) {
      index_ += 5;
      return Value::boolean(false);
    }
    fail("invalid literal in JSON input");
  }

  Value parseNull() {
    if (text_.compare(index_, 4, "null") == 0) {
      index_ += 4;
      return Value();
    }
    fail("invalid literal in JSON input");
  }
};

} // namespace

Value parse(std::string_view text) {
  Parser parser(text);
  return parser.parseDocument();
}

} // namespace reashoot::json
