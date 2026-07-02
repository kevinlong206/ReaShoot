#include "reaphone/debug_logger.h"

#include <chrono>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <sstream>

namespace reaphone {

namespace {

std::string timestamp() {
  using namespace std::chrono;
  const auto now = system_clock::now();
  const auto time = system_clock::to_time_t(now);
  const auto ms = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;

  std::tm tm{};
#ifdef _WIN32
  localtime_s(&tm, &time);
#else
  localtime_r(&time, &tm);
#endif

  std::ostringstream out;
  out << std::put_time(&tm, "%Y-%m-%d %H:%M:%S");
  out << '.' << std::setfill('0') << std::setw(3) << ms.count();
  return out.str();
}

} // namespace

DebugLogger::DebugLogger(std::string filePath) : filePath_(std::move(filePath)) {}

void DebugLogger::log(const std::string &message) {
  const std::string line = timestamp() + " REAPER " + message + "\n";

  std::lock_guard<std::mutex> lock(mutex_);
  std::ofstream out(filePath_, std::ios::out | std::ios::app | std::ios::binary);
  if (!out.is_open()) {
    return;
  }
  out << line;
}

std::string DebugLogger::defaultPath() {
  std::error_code ec;
  std::filesystem::path base = std::filesystem::temp_directory_path(ec);
  if (ec) {
    base = std::filesystem::path(".");
  }
  base /= "reaphonevideo_debug.log";
  return base.string();
}

} // namespace reaphone
