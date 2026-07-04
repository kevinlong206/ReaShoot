#include "discovery.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <thread>

#ifdef _WIN32
#include "socket_utils.h"

#include <cstdint>
#include <vector>
#else
#include <csignal>
#include <sys/wait.h>
#include <unistd.h>
#endif

namespace reashoot::helper {
namespace {

#ifdef _WIN32

std::string lowercase(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

uint16_t readU16(const uint8_t *data) {
  return static_cast<uint16_t>((static_cast<uint16_t>(data[0]) << 8) | data[1]);
}

uint32_t readU32(const uint8_t *data) {
  return (static_cast<uint32_t>(data[0]) << 24) | (static_cast<uint32_t>(data[1]) << 16) |
         (static_cast<uint32_t>(data[2]) << 8) | data[3];
}

void appendU16(std::vector<uint8_t> &data, uint16_t value) {
  data.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
  data.push_back(static_cast<uint8_t>(value & 0xff));
}

void appendName(std::vector<uint8_t> &packet, const std::string &name) {
  size_t start = 0;
  while (start < name.size()) {
    const size_t dot = name.find('.', start);
    const size_t end = dot == std::string::npos ? name.size() : dot;
    const size_t length = end - start;
    if (length > 0 && length <= 63) {
      packet.push_back(static_cast<uint8_t>(length));
      packet.insert(packet.end(), name.begin() + static_cast<std::string::difference_type>(start),
                    name.begin() + static_cast<std::string::difference_type>(end));
    }
    if (dot == std::string::npos) {
      break;
    }
    start = dot + 1;
  }
  packet.push_back(0);
}

bool readName(const std::vector<uint8_t> &packet, size_t &offset, std::string &name, int depth = 0) {
  if (depth > 8) {
    return false;
  }
  size_t cursor = offset;
  bool jumped = false;
  std::string result;
  while (cursor < packet.size()) {
    const uint8_t length = packet[cursor++];
    if (length == 0) {
      if (!jumped) {
        offset = cursor;
      }
      name = result;
      return true;
    }
    if ((length & 0xc0) == 0xc0) {
      if (cursor >= packet.size()) {
        return false;
      }
      const size_t pointer = (static_cast<size_t>(length & 0x3f) << 8) | packet[cursor++];
      if (!jumped) {
        offset = cursor;
      }
      cursor = pointer;
      jumped = true;
      ++depth;
      if (depth > 8) {
        return false;
      }
      continue;
    }
    if ((length & 0xc0) != 0 || cursor + length > packet.size()) {
      return false;
    }
    if (!result.empty()) {
      result.push_back('.');
    }
    result.append(reinterpret_cast<const char *>(packet.data() + cursor), length);
    cursor += length;
  }
  return false;
}

struct MdnsRecord {
  std::string name;
  uint16_t type = 0;
  std::vector<uint8_t> data;
  size_t rdataOffset = 0;
};

struct ServiceDetails {
  std::string name;
  std::string target;
  std::string address;
  int port = 0;
  int httpPort = 8788;
  bool isPaired = false;
};

std::vector<uint8_t> makePtrQuery() {
  std::vector<uint8_t> packet;
  packet.resize(12, 0);
  packet[5] = 1;
  appendName(packet, "_reashoot._tcp.local");
  appendU16(packet, 12);
  appendU16(packet, 0x8001);
  return packet;
}

std::vector<MdnsRecord> parseRecords(const std::vector<uint8_t> &packet) {
  if (packet.size() < 12) {
    return {};
  }
  const uint16_t questionCount = readU16(packet.data() + 4);
  const uint16_t answerCount = readU16(packet.data() + 6);
  const uint16_t authorityCount = readU16(packet.data() + 8);
  const uint16_t additionalCount = readU16(packet.data() + 10);
  size_t offset = 12;
  for (uint16_t i = 0; i < questionCount; ++i) {
    std::string ignored;
    if (!readName(packet, offset, ignored) || offset + 4 > packet.size()) {
      return {};
    }
    offset += 4;
  }

  std::vector<MdnsRecord> records;
  const uint32_t recordCount = static_cast<uint32_t>(answerCount) + authorityCount + additionalCount;
  for (uint32_t i = 0; i < recordCount && offset < packet.size(); ++i) {
    MdnsRecord record;
    if (!readName(packet, offset, record.name) || offset + 10 > packet.size()) {
      break;
    }
    record.type = readU16(packet.data() + offset);
    offset += 2;
    offset += 2;
    (void)readU32(packet.data() + offset);
    offset += 4;
    const uint16_t length = readU16(packet.data() + offset);
    offset += 2;
    if (offset + length > packet.size()) {
      break;
    }
    record.rdataOffset = offset;
    record.data.assign(packet.begin() + static_cast<std::string::difference_type>(offset),
                       packet.begin() + static_cast<std::string::difference_type>(offset + length));
    records.push_back(std::move(record));
    offset += length;
  }
  return records;
}

std::string nameFromRecordData(const std::vector<uint8_t> &packet, const MdnsRecord &record) {
  size_t offset = record.rdataOffset;
  std::string name;
  return readName(packet, offset, name) ? name : "";
}

std::string ipv4FromData(const std::vector<uint8_t> &data) {
  if (data.size() != 4) {
    return {};
  }
  char buffer[INET_ADDRSTRLEN] = {};
  in_addr address = {};
  std::memcpy(&address, data.data(), data.size());
  return InetNtopA(AF_INET, &address, buffer, sizeof(buffer)) ? buffer : "";
}

void applyTxtRecord(ServiceDetails &service, const std::vector<uint8_t> &data) {
  size_t offset = 0;
  while (offset < data.size()) {
    const uint8_t length = data[offset++];
    if (offset + length > data.size()) {
      break;
    }
    const std::string field(reinterpret_cast<const char *>(data.data() + offset), length);
    offset += length;
    const size_t equals = field.find('=');
    const std::string key = lowercase(equals == std::string::npos ? field : field.substr(0, equals));
    const std::string value = equals == std::string::npos ? "" : field.substr(equals + 1);
    if (key == "httpport" && !value.empty()) {
      service.httpPort = std::atoi(value.c_str());
    } else if (key == "paired") {
      service.isPaired = value == "true" || value == "1";
    }
  }
}

std::vector<DiscoveredPhone> discoverPhonesWithMdns(int timeoutSeconds) {
  initializeSockets();
  SocketHandle socketFd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (socketFd == kInvalidSocket) {
    return {};
  }

  DWORD timeoutMs = 250;
  setsockopt(socketFd, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char *>(&timeoutMs), sizeof(timeoutMs));

  sockaddr_in destination = {};
  destination.sin_family = AF_INET;
  destination.sin_port = htons(5353);
  InetPtonA(AF_INET, "224.0.0.251", &destination.sin_addr);
  const std::vector<uint8_t> query = makePtrQuery();
  sendto(socketFd,
         reinterpret_cast<const char *>(query.data()),
         static_cast<int>(query.size()),
         0,
         reinterpret_cast<const sockaddr *>(&destination),
         sizeof(destination));

  std::map<std::string, ServiceDetails> services;
  std::map<std::string, std::string> targetAddresses;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(std::max(1, timeoutSeconds));
  while (std::chrono::steady_clock::now() < deadline) {
    std::vector<uint8_t> packet(9000);
    const int count = recv(socketFd, reinterpret_cast<char *>(packet.data()), static_cast<int>(packet.size()), 0);
    if (count <= 0) {
      continue;
    }
    packet.resize(static_cast<size_t>(count));
    const std::vector<MdnsRecord> records = parseRecords(packet);
    for (const MdnsRecord &record : records) {
      const std::string owner = lowercase(record.name);
      if (record.type == 12 && owner == "_reashoot._tcp.local") {
        const std::string instance = nameFromRecordData(packet, record);
        if (!instance.empty()) {
          services[lowercase(instance)].name = instance;
        }
      } else if (record.type == 33 && record.data.size() >= 7) {
        ServiceDetails &service = services[owner];
        if (service.name.empty()) {
          service.name = record.name;
        }
        service.port = readU16(record.data.data() + 4);
        size_t targetOffset = record.rdataOffset + 6;
        std::string target;
        if (readName(packet, targetOffset, target)) {
          service.target = target;
        }
      } else if (record.type == 16) {
        ServiceDetails &service = services[owner];
        if (service.name.empty()) {
          service.name = record.name;
        }
        applyTxtRecord(service, record.data);
      } else if (record.type == 1) {
        const std::string address = ipv4FromData(record.data);
        if (!address.empty()) {
          targetAddresses[owner] = address;
        }
      }
    }
  }
  closeSocket(socketFd);

  std::vector<DiscoveredPhone> phones;
  std::set<std::string> seen;
  for (auto &[key, service] : services) {
    if (service.port <= 0 || !seen.insert(key).second) {
      continue;
    }
    DiscoveredPhone phone;
    phone.name = service.name.empty() ? key : service.name;
    const auto address = targetAddresses.find(lowercase(service.target));
    phone.host = address != targetAddresses.end() ? address->second : service.target;
    if (phone.host.empty()) {
      continue;
    }
    phone.controlPort = service.port;
    phone.httpPort = service.httpPort > 0 ? service.httpPort : 8788;
    phone.isPaired = service.isPaired;
    phones.push_back(std::move(phone));
  }
  return phones;
}

#else

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

#endif

#ifndef _WIN32

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

#endif

} // namespace

std::vector<DiscoveredPhone> discoverPhones(int timeoutSeconds) {
#ifdef _WIN32
  return discoverPhonesWithMdns(timeoutSeconds);
#else
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
#endif
}

} // namespace reashoot::helper
