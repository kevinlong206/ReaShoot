#pragma once

#include "reaphone/http_headers.h"

#include <string>
#include <string_view>

namespace reaphone {

std::string webSocketAcceptKey(std::string_view clientKey);
bool isWebSocketSwitchingProtocolsResponse(const HttpHeaders &headers, std::string_view clientKey);

} // namespace reaphone
