#include "reashoot/debug_logger.h"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

namespace {

std::string readFile(const std::string &path) {
  std::ifstream in(path, std::ios::in | std::ios::binary);
  std::ostringstream buffer;
  buffer << in.rdbuf();
  return buffer.str();
}

std::string uniqueTempPath() {
  std::filesystem::path base = std::filesystem::temp_directory_path();
  base /= "reashoot_logger_test_" + std::to_string(std::rand()) + ".log";
  return base.string();
}

void testAppendsTimestampedLines() {
  const std::string path = uniqueTempPath();
  std::filesystem::remove(path);

  {
    reashoot::DebugLogger logger(path);
    logger.log("first message");
    logger.log("second message");
  }

  const std::string contents = readFile(path);
  assert(contents.find("REAPER first message") != std::string::npos);
  assert(contents.find("REAPER second message") != std::string::npos);

  // Two lines, each terminated with a newline.
  std::size_t newlines = 0;
  for (const char c : contents) {
    if (c == '\n') {
      ++newlines;
    }
  }
  assert(newlines == 2);

  // Timestamp prefix format "YYYY-MM-DD HH:MM:SS.mmm ".
  assert(contents.size() > 24);
  assert(contents[4] == '-' && contents[7] == '-' && contents[10] == ' ');
  assert(contents[13] == ':' && contents[16] == ':' && contents[19] == '.');

  std::filesystem::remove(path);
}

void testMissingDirectoryDoesNotThrow() {
  reashoot::DebugLogger logger("Z:/definitely/missing/dir/log.txt");
  logger.log("should be swallowed");
}

void testDefaultPathHasExpectedName() {
  const std::string path = reashoot::DebugLogger::defaultPath();
  assert(path.find("reashoot_debug.log") != std::string::npos);
}

} // namespace

int main() {
  testAppendsTimestampedLines();
  testMissingDirectoryDoesNotThrow();
  testDefaultPathHasExpectedName();
  std::cout << "debug_logger_tests passed\n";
  return 0;
}
