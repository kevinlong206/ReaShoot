#pragma once

#include <map>
#include <string>
#include <vector>

namespace reashoot::core {

using FieldMap = std::map<std::string, std::string>;

FieldMap parseFields(const std::string &line, char separator);
std::vector<FieldMap> parseRecordings(const std::string &output);
FieldMap parseFirstDevice(const std::string &output);
std::string parseDownloadedPath(const std::string &output);
std::string progressStatusText(const std::string &line);

} // namespace reashoot::core
