#include "discovery.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <csignal>
#include <cstring>
#include <regex>
#include <set>
#include <sstream>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

namespace reashoot::helper {
namespace {

std::string runDnsSd(const std::vector<std::string> &arguments, int timeoutSeconds) {
  int pipefd[2] = {};
  if (pipe(pipefd) != 0) {
    return {};
  }
  const pid_t pid = fork();
  if (pid == 0) {
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[0]);
    close(pipefd[1]);
    std::vector<char *> argv;
    argv.push_back(const_cast<char *>("/usr/bin/dns-sd"));
    for (const std::string &argument : arguments) {
      argv.push_back(const_cast<char *>(argument.c_str()));
    }
    argv.push_back(nullptr);
    execv("/usr/bin/dns-sd", argv.data());
    _exit(127);
  }
  close(pipefd[1]);
  if (pid < 0) {
    close(pipefd[0]);
    return {};
  }

  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(timeoutSeconds);
  int status = 0;
  while (std::chrono::steady_clock::now() < deadline) {
    if (waitpid(pid, &status, WNOHANG) == pid) {
      break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }
  kill(pid, SIGTERM);
  waitpid(pid, &status, 0);

  std::string output;
  std::array<char, 4096> buffer = {};
  while (true) {
    const ssize_t count = read(pipefd[0], buffer.data(), buffer.size());
    if (count <= 0) {
      break;
    }
    output.append(buffer.data(), static_cast<size_t>(count));
  }
  close(pipefd[0]);
  return output;
}

std::string serviceNameFromLine(const std::string &line) {
  if (line.find("_reashoot._tcp.") == std::string::npos) {
    return {};
  }
  std::istringstream stream(line);
  std::vector<std::string> columns;
  std::string column;
  while (stream >> column) {
    columns.push_back(column);
  }
  if (columns.size() < 7) {
    return {};
  }
  std::string name = columns[6];
  for (size_t i = 7; i < columns.size(); ++i) {
    name += " " + columns[i];
  }
  return name;
}

std::string firstMatch(const std::string &text, const std::regex &pattern) {
  std::smatch match;
  return std::regex_search(text, match, pattern) && match.size() > 1 ? match[1].str() : "";
}

DiscoveredPhone resolvePhone(const std::string &serviceName, int timeoutSeconds) {
  const std::string output = runDnsSd({"-L", serviceName, "_reashoot._tcp", "local"}, timeoutSeconds);
  DiscoveredPhone phone;
  phone.name = serviceName;
  phone.host = firstMatch(output, std::regex("hostname = ([^,\\s]+)"));
  const std::string port = firstMatch(output, std::regex("port = ([0-9]+)"));
  if (!port.empty()) {
    phone.controlPort = std::stoi(port);
  }
  const std::string httpPort = firstMatch(output, std::regex("httpPort=([0-9]+)"));
  if (!httpPort.empty()) {
    phone.httpPort = std::stoi(httpPort);
  }
  phone.isPaired = output.find("paired=true") != std::string::npos;
  return phone;
}

} // namespace

std::vector<DiscoveredPhone> discoverPhones(int timeoutSeconds) {
  std::vector<DiscoveredPhone> phones;
  const std::string output = runDnsSd({"-B", "_reashoot._tcp", "local"}, timeoutSeconds);
  std::set<std::string> seen;
  std::istringstream stream(output);
  std::string line;
  while (std::getline(stream, line)) {
    const std::string serviceName = serviceNameFromLine(line);
    if (serviceName.empty() || !seen.insert(serviceName).second) {
      continue;
    }
    DiscoveredPhone phone = resolvePhone(serviceName, timeoutSeconds);
    if (!phone.host.empty() && phone.controlPort > 0) {
      phones.push_back(phone);
    }
  }
  return phones;
}

} // namespace reashoot::helper
