#include "reaphone/json.h"

#include <cstdio>
#include <string>

namespace reaphone::json {

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

} // namespace reaphone::json
