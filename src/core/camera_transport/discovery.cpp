#include "discovery.h"

#include <algorithm>
#include <chrono>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <sstream>

#ifdef _WIN32
#include "socket_utils.h"

#include <iphlpapi.h>

#include <cstdint>
#include <vector>
#elif defined(__APPLE__)
#include <dns_sd.h>
#include <netinet/in.h>
#include <sys/select.h>
#endif

namespace reashoot::transport {
namespace {

std::string lowercase(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  return value;
}

#ifdef _WIN32

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

// Enumerates the IPv4 address of every up, non-loopback adapter so the mDNS
// query can be sent out each interface explicitly. On multi-homed Windows
// machines (Hyper-V/WSL/VPN/virtual adapters) the default multicast interface
// is often not the Wi-Fi/LAN the iPhone is on, so relying on the routing
// table alone can silently send the query out the wrong NIC.
std::vector<in_addr> localIPv4Interfaces() {
  std::vector<in_addr> addresses;
  ULONG size = 15 * 1024;
  std::vector<uint8_t> buffer(size);
  const ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
  ULONG result = GetAdaptersAddresses(AF_INET, flags, nullptr,
                                      reinterpret_cast<IP_ADAPTER_ADDRESSES *>(buffer.data()), &size);
  if (result == ERROR_BUFFER_OVERFLOW) {
    buffer.resize(size);
    result = GetAdaptersAddresses(AF_INET, flags, nullptr,
                                  reinterpret_cast<IP_ADAPTER_ADDRESSES *>(buffer.data()), &size);
  }
  if (result != NO_ERROR) {
    return addresses;
  }
  for (auto *adapter = reinterpret_cast<IP_ADAPTER_ADDRESSES *>(buffer.data()); adapter; adapter = adapter->Next) {
    if (adapter->OperStatus != IfOperStatusUp || adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK) {
      continue;
    }
    for (auto *unicast = adapter->FirstUnicastAddress; unicast; unicast = unicast->Next) {
      const sockaddr *address = unicast->Address.lpSockaddr;
      if (address && address->sa_family == AF_INET) {
        addresses.push_back(reinterpret_cast<const sockaddr_in *>(address)->sin_addr);
      }
    }
  }
  return addresses;
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
  const std::vector<in_addr> interfaces = localIPv4Interfaces();

  // Send the query out every interface (falling back to the OS default when
  // enumeration yields nothing) so a wrong default multicast NIC can't hide
  // the phone.
  auto sendQuery = [&]() {
    if (interfaces.empty()) {
      sendto(socketFd, reinterpret_cast<const char *>(query.data()), static_cast<int>(query.size()), 0,
             reinterpret_cast<const sockaddr *>(&destination), sizeof(destination));
      return;
    }
    for (const in_addr &interfaceAddress : interfaces) {
      setsockopt(socketFd, IPPROTO_IP, IP_MULTICAST_IF, reinterpret_cast<const char *>(&interfaceAddress),
                 sizeof(interfaceAddress));
      sendto(socketFd, reinterpret_cast<const char *>(query.data()), static_cast<int>(query.size()), 0,
             reinterpret_cast<const sockaddr *>(&destination), sizeof(destination));
    }
  };
  sendQuery();
  auto lastSend = std::chrono::steady_clock::now();

  std::map<std::string, ServiceDetails> services;
  std::map<std::string, std::string> targetAddresses;
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(std::max(1, timeoutSeconds));
  while (std::chrono::steady_clock::now() < deadline) {
    // Re-send roughly once per second to tolerate dropped multicast packets.
    if (std::chrono::steady_clock::now() - lastSend >= std::chrono::seconds(1)) {
      sendQuery();
      lastSend = std::chrono::steady_clock::now();
    }
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

#elif defined(__APPLE__)

struct BonjourService {
  std::string name;
  std::string type;
  std::string domain;
  uint32_t interfaceIndex = 0;
};

struct ResolveContext {
  DiscoveredPhone phone;
  bool complete = false;
};

void stripTrailingDot(std::string &value) {
  if (!value.empty() && value.back() == '.') {
    value.pop_back();
  }
}

void applyTxtRecord(DiscoveredPhone &phone, const unsigned char *data, uint16_t length) {
  size_t offset = 0;
  while (offset < length) {
    const uint8_t fieldLength = data[offset++];
    if (offset + fieldLength > length) {
      break;
    }
    const std::string field(reinterpret_cast<const char *>(data + offset), fieldLength);
    offset += fieldLength;
    const size_t equals = field.find('=');
    const std::string key = lowercase(equals == std::string::npos ? field : field.substr(0, equals));
    const std::string value = equals == std::string::npos ? "" : field.substr(equals + 1);
    if (key == "httpport" && !value.empty()) {
      phone.httpPort = std::atoi(value.c_str());
    } else if (key == "paired") {
      phone.isPaired = value == "true" || value == "1";
    }
  }
}

bool processDnsServiceUntil(DNSServiceRef serviceRef, std::chrono::steady_clock::time_point deadline) {
  const int fd = DNSServiceRefSockFD(serviceRef);
  if (fd < 0) {
    return false;
  }
  while (std::chrono::steady_clock::now() < deadline) {
    const auto remaining =
        std::chrono::duration_cast<std::chrono::milliseconds>(deadline - std::chrono::steady_clock::now());
    timeval timeout = {};
    timeout.tv_sec = static_cast<long>(remaining.count() / 1000);
    timeout.tv_usec = static_cast<int>((remaining.count() % 1000) * 1000);
    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(fd, &readSet);
    const int result = select(fd + 1, &readSet, nullptr, nullptr, &timeout);
    if (result > 0 && FD_ISSET(fd, &readSet)) {
      return DNSServiceProcessResult(serviceRef) == kDNSServiceErr_NoError;
    }
    if (result < 0) {
      return false;
    }
  }
  return false;
}

void DNSSD_API browseCallback(DNSServiceRef, DNSServiceFlags flags, uint32_t interfaceIndex,
                              DNSServiceErrorType errorCode, const char *serviceName, const char *regtype,
                              const char *replyDomain, void *context) {
  if (errorCode != kDNSServiceErr_NoError || !(flags & kDNSServiceFlagsAdd) || !serviceName || !regtype ||
      !replyDomain) {
    return;
  }
  auto *services = static_cast<std::vector<BonjourService> *>(context);
  services->push_back({serviceName, regtype, replyDomain, interfaceIndex});
}

void DNSSD_API resolveCallback(DNSServiceRef, DNSServiceFlags, uint32_t, DNSServiceErrorType errorCode,
                               const char *, const char *hosttarget, uint16_t port, uint16_t txtLen,
                               const unsigned char *txtRecord, void *context) {
  auto *resolveContext = static_cast<ResolveContext *>(context);
  resolveContext->complete = true;
  if (errorCode != kDNSServiceErr_NoError || !hosttarget) {
    return;
  }
  resolveContext->phone.host = hosttarget;
  stripTrailingDot(resolveContext->phone.host);
  resolveContext->phone.controlPort = ntohs(port);
  if (txtRecord && txtLen > 0) {
    applyTxtRecord(resolveContext->phone, txtRecord, txtLen);
  }
}

DiscoveredPhone resolvePhone(const BonjourService &service, int timeoutSeconds) {
  ResolveContext context;
  context.phone.name = service.name;
  DNSServiceRef resolveRef = nullptr;
  const DNSServiceErrorType error =
      DNSServiceResolve(&resolveRef, 0, service.interfaceIndex, service.name.c_str(), service.type.c_str(),
                        service.domain.c_str(), resolveCallback, &context);
  if (error != kDNSServiceErr_NoError || !resolveRef) {
    return context.phone;
  }
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(std::max(1, timeoutSeconds));
  while (!context.complete && std::chrono::steady_clock::now() < deadline) {
    if (!processDnsServiceUntil(resolveRef, deadline)) {
      break;
    }
  }
  DNSServiceRefDeallocate(resolveRef);
  return context.phone;
}

std::vector<DiscoveredPhone> discoverPhonesWithBonjour(int timeoutSeconds) {
  std::vector<BonjourService> services;
  DNSServiceRef browseRef = nullptr;
  const DNSServiceErrorType error =
      DNSServiceBrowse(&browseRef, 0, 0, "_reashoot._tcp", "local", browseCallback, &services);
  if (error != kDNSServiceErr_NoError || !browseRef) {
    return {};
  }
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(std::max(1, timeoutSeconds));
  while (std::chrono::steady_clock::now() < deadline) {
    if (!processDnsServiceUntil(browseRef, deadline)) {
      break;
    }
  }
  DNSServiceRefDeallocate(browseRef);

  std::vector<DiscoveredPhone> phones;
  std::set<std::string> seen;
  for (const BonjourService &service : services) {
    const std::string key = lowercase(service.name + "\t" + service.type + "\t" + service.domain);
    if (!seen.insert(key).second) {
      continue;
    }
    DiscoveredPhone phone = resolvePhone(service, timeoutSeconds);
    if (!phone.host.empty() && phone.controlPort > 0) {
      phones.push_back(phone);
    }
  }
  return phones;
}

#endif

} // namespace

std::vector<DiscoveredPhone> discoverPhones(int timeoutSeconds) {
#ifdef _WIN32
  return discoverPhonesWithMdns(timeoutSeconds);
#elif defined(__APPLE__)
  return discoverPhonesWithBonjour(timeoutSeconds);
#else
  (void)timeoutSeconds;
  return {};
#endif
}

} // namespace reashoot::transport
