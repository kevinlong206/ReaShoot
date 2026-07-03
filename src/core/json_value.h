#pragma once

#include <cstdint>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace reashoot::core {

class JsonError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

class JsonValue {
public:
  enum class Type { Null, Bool, Number, String, Object, Array };
  using Object = std::map<std::string, JsonValue>;
  using Array = std::vector<JsonValue>;

  JsonValue();
  explicit JsonValue(bool value);
  explicit JsonValue(double value);
  explicit JsonValue(std::string value);
  explicit JsonValue(Object value);
  explicit JsonValue(Array value);

  Type type() const { return type_; }
  bool isNull() const { return type_ == Type::Null; }
  bool asBool(bool fallback = false) const;
  double asNumber(double fallback = 0.0) const;
  const std::string &asString() const;
  const Object &asObject() const;
  const Array &asArray() const;

  const JsonValue *find(const std::string &key) const;
  std::string stringValue(const std::string &key, const std::string &fallback = "") const;
  int intValue(const std::string &key, int fallback = 0) const;
  int64_t int64Value(const std::string &key, int64_t fallback = 0) const;
  double numberValue(const std::string &key, double fallback = 0.0) const;
  bool boolValue(const std::string &key, bool fallback = false) const;

  std::string serialize() const;

private:
  Type type_ = Type::Null;
  bool boolValue_ = false;
  double numberValue_ = 0.0;
  std::string stringValue_;
  Object objectValue_;
  Array arrayValue_;
};

JsonValue parseJson(const std::string &text);
std::string escapeJsonString(const std::string &value);

} // namespace reashoot::core
