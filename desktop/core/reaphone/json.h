#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace reaphone::json {

// Minimal JSON value writer. Objects use std::map so keys are always emitted in
// sorted order, matching the macOS helper's JSONEncoder(.sortedKeys) output.
class Value {
public:
  Value(); // null

  static Value string(std::string value);
  static Value integer(std::int64_t value);
  static Value real(double value);
  static Value boolean(bool value);
  static Value object();
  static Value array();

  // Sets a key on an object value and returns *this for chaining.
  Value &set(const std::string &key, Value value);
  // Appends an element to an array value and returns *this for chaining.
  Value &add(Value value);

  std::string dump() const;

private:
  enum class Type { Null, Bool, Integer, Real, String, Array, Object };

  Type type_ = Type::Null;
  bool bool_ = false;
  std::int64_t integer_ = 0;
  double real_ = 0.0;
  std::string string_;
  std::vector<Value> array_;
  std::map<std::string, Value> object_;

  void dumpTo(std::string &out) const;
};

// Appends a JSON-escaped, double-quoted string to out.
void appendEscapedString(std::string &out, std::string_view value);

} // namespace reaphone::json
