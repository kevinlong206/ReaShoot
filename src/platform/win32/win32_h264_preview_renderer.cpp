#include "win32_h264_preview_renderer.h"

#include "../../core/h264_annex_b.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mfapi.h>
#include <codecapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfobjects.h>
#include <mftransform.h>
#include <wmcodecdsp.h>
#include <wrl/client.h>

#if REASHOOT_WITH_FFMPEG_DECODER
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/display.h>
#include <libavutil/error.h>
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}
#endif

#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <sstream>
#include <thread>
#include <utility>
#include <vector>

namespace reashoot::platform::win32 {
namespace {

using Microsoft::WRL::ComPtr;
constexpr auto kMinimumPreviewFrameInterval = std::chrono::milliseconds(125);

void previewDebugLog(const std::string &message) {
  const std::string line = "ReaShoot: " + message + "\n";
  OutputDebugStringA(line.c_str());
  char appData[MAX_PATH] = {};
  if (GetEnvironmentVariableA("APPDATA", appData, sizeof(appData)) > 0) {
    std::ofstream log(std::filesystem::path(appData) / "REAPER" / "reashoot-win.log", std::ios::app);
    if (log) {
      log << line;
    }
  }
}

class MediaFoundationRuntime {
public:
  MediaFoundationRuntime() {
    mfStarted_ = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
  }

  ~MediaFoundationRuntime() {
    if (mfStarted_) {
      MFShutdown();
    }
  }

  bool ready() const { return mfStarted_; }

private:
  bool mfStarted_ = false;
};

class ComThreadRuntime {
public:
  ComThreadRuntime() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    initialized_ = SUCCEEDED(hr);
    alreadyInitialized_ = hr == RPC_E_CHANGED_MODE;
  }

  ~ComThreadRuntime() {
    if (initialized_) {
      CoUninitialize();
    }
  }

  bool ready() const { return initialized_ || alreadyInitialized_; }

private:
  bool initialized_ = false;
  bool alreadyInitialized_ = false;
};

MediaFoundationRuntime &mfRuntime() {
  static MediaFoundationRuntime runtime;
  return runtime;
}

struct H264Dimensions {
  int width = 0;
  int height = 0;
  int visibleWidth = 0;
  int visibleHeight = 0;
  int cropLeft = 0;
  int cropTop = 0;
};

struct PreviewDiagnosticMetadata {
  bool valid = false;
  uint64_t sequence = 0;
  uint64_t sourceUnixMicros = 0;
  uint32_t nalTypes = 0;
  uint8_t orientationCode = 0;
};

class BitReader {
public:
  explicit BitReader(const std::vector<uint8_t> &bytes) : bytes_(bytes) {}

  bool readBit(uint32_t &value) {
    if (bitOffset_ >= bytes_.size() * 8) {
      return false;
    }
    value = (bytes_[bitOffset_ / 8] >> (7 - (bitOffset_ % 8))) & 1;
    ++bitOffset_;
    return true;
  }

  bool readBits(int count, uint32_t &value) {
    value = 0;
    for (int i = 0; i < count; ++i) {
      uint32_t bit = 0;
      if (!readBit(bit)) {
        return false;
      }
      value = (value << 1) | bit;
    }
    return true;
  }

  bool readUE(uint32_t &value) {
    int leadingZeroBits = 0;
    uint32_t bit = 0;
    while (readBit(bit)) {
      if (bit != 0) {
        break;
      }
      ++leadingZeroBits;
      if (leadingZeroBits > 31) {
        return false;
      }
    }
    uint32_t suffix = 0;
    if (leadingZeroBits > 0 && !readBits(leadingZeroBits, suffix)) {
      return false;
    }
    value = ((1u << leadingZeroBits) - 1u) + suffix;
    return true;
  }

  bool readSE(int32_t &value) {
    uint32_t codeNum = 0;
    if (!readUE(codeNum)) {
      return false;
    }
    value = (codeNum & 1u) != 0 ? static_cast<int32_t>((codeNum + 1u) / 2u) : -static_cast<int32_t>(codeNum / 2u);
    return true;
  }

private:
  const std::vector<uint8_t> &bytes_;
  size_t bitOffset_ = 0;
};

bool copyContiguousBuffer(IMFSample *sample, std::vector<uint8_t> &bytes) {
  if (!sample) {
    return false;
  }
  ComPtr<IMFMediaBuffer> buffer;
  if (FAILED(sample->ConvertToContiguousBuffer(&buffer)) || !buffer) {
    return false;
  }
  BYTE *data = nullptr;
  DWORD maxLength = 0;
  DWORD currentLength = 0;
  if (FAILED(buffer->Lock(&data, &maxLength, &currentLength)) || !data || currentLength == 0) {
    return false;
  }
  bytes.assign(data, data + currentLength);
  buffer->Unlock();
  return true;
}

bool lockSample2D(IMFSample *sample, BYTE **data, LONG *pitch, ComPtr<IMFMediaBuffer> &buffer, ComPtr<IMF2DBuffer> &buffer2D) {
  if (!sample || !data || !pitch) {
    return false;
  }
  if (FAILED(sample->ConvertToContiguousBuffer(&buffer)) || !buffer) {
    return false;
  }
  if (SUCCEEDED(buffer.As(&buffer2D)) && buffer2D && SUCCEEDED(buffer2D->Lock2D(data, pitch)) && *data) {
    return true;
  }
  DWORD maxLength = 0;
  DWORD currentLength = 0;
  if (SUCCEEDED(buffer->Lock(data, &maxLength, &currentLength)) && *data && currentLength > 0) {
    *pitch = 0;
    return true;
  }
  return false;
}

void unlockSample2D(ComPtr<IMFMediaBuffer> &buffer, ComPtr<IMF2DBuffer> &buffer2D) {
  if (buffer2D) {
    buffer2D->Unlock2D();
  } else if (buffer) {
    buffer->Unlock();
  }
}

bool accessUnitHasNalType(const uint8_t *bytes, size_t length, uint8_t type) {
  for (const auto &unit : core::splitAnnexB(bytes, length)) {
    if (unit.type == type) {
      return true;
    }
  }
  return false;
}

uint64_t readBigEndianU64(const uint8_t *bytes) {
  uint64_t value = 0;
  for (int i = 0; i < 8; ++i) {
    value = (value << 8) | bytes[i];
  }
  return value;
}

PreviewDiagnosticMetadata parseDiagnosticSEI(const uint8_t *bytes, size_t length) {
  PreviewDiagnosticMetadata metadata;
  for (const auto &unit : core::splitAnnexB(bytes, length)) {
    if (unit.type < 32) {
      metadata.nalTypes |= (1u << unit.type);
    }
    if (unit.type != 6 || unit.size < 2) {
      continue;
    }
    const uint8_t *nalu = bytes + unit.offset;
    size_t offset = 1;
    int payloadType = 0;
    while (offset < unit.size && nalu[offset] == 0xff) {
      payloadType += 255;
      ++offset;
    }
    if (offset >= unit.size) {
      continue;
    }
    payloadType += nalu[offset++];
    int payloadSize = 0;
    while (offset < unit.size && nalu[offset] == 0xff) {
      payloadSize += 255;
      ++offset;
    }
    if (offset >= unit.size) {
      continue;
    }
    payloadSize += nalu[offset++];
    if (payloadType != 5 || payloadSize < 23 || offset + static_cast<size_t>(payloadSize) > unit.size) {
      continue;
    }
    std::vector<uint8_t> unescapedPayload;
    unescapedPayload.reserve(static_cast<size_t>(payloadSize));
    int zeroCount = 0;
    for (int i = 0; i < payloadSize; ++i) {
      const uint8_t value = nalu[offset + static_cast<size_t>(i)];
      if (zeroCount == 2 && value == 0x03) {
        zeroCount = 0;
        continue;
      }
      unescapedPayload.push_back(value);
      if (value == 0) {
        ++zeroCount;
      } else {
        zeroCount = 0;
      }
    }
    if (unescapedPayload.size() < 23) {
      continue;
    }
    const uint8_t *payload = unescapedPayload.data();
    if (std::memcmp(payload, "RSDIAG1", 7) != 0) {
      continue;
    }
    metadata.valid = true;
    metadata.sequence = readBigEndianU64(payload + 7);
    metadata.sourceUnixMicros = readBigEndianU64(payload + 15);
    if (unescapedPayload.size() >= 24) {
      metadata.orientationCode = payload[23];
    }
    return metadata;
  }
  return metadata;
}

bool isDecoderStartingAccessUnit(const uint8_t *bytes, size_t length) {
  return accessUnitHasNalType(bytes, length, 5) &&
         accessUnitHasNalType(bytes, length, 7) &&
         accessUnitHasNalType(bytes, length, 8);
}

std::vector<uint8_t> rbspFromNalUnit(const uint8_t *bytes, size_t length) {
  std::vector<uint8_t> rbsp;
  if (!bytes || length <= 1) {
    return rbsp;
  }
  rbsp.reserve(length - 1);
  int zeroCount = 0;
  for (size_t i = 1; i < length; ++i) {
    const uint8_t value = bytes[i];
    if (zeroCount == 2 && value == 0x03) {
      zeroCount = 0;
      continue;
    }
    rbsp.push_back(value);
    if (value == 0) {
      ++zeroCount;
    } else {
      zeroCount = 0;
    }
  }
  return rbsp;
}

bool isHighProfileSPS(uint32_t profile) {
  switch (profile) {
  case 100:
  case 110:
  case 122:
  case 244:
  case 44:
  case 83:
  case 86:
  case 118:
  case 128:
  case 138:
  case 139:
  case 134:
  case 135:
    return true;
  default:
    return false;
  }
}

bool skipScalingList(BitReader &reader, int size) {
  int lastScale = 8;
  int nextScale = 8;
  for (int i = 0; i < size; ++i) {
    if (nextScale != 0) {
      int32_t deltaScale = 0;
      if (!reader.readSE(deltaScale)) {
        return false;
      }
      nextScale = (lastScale + deltaScale + 256) % 256;
    }
    lastScale = nextScale == 0 ? lastScale : nextScale;
  }
  return true;
}

bool parseSPSDimensions(const uint8_t *sps, size_t length, H264Dimensions &dimensions) {
  std::vector<uint8_t> rbsp = rbspFromNalUnit(sps, length);
  if (rbsp.size() < 4) {
    return false;
  }
  BitReader reader(rbsp);
  uint32_t profile = 0;
  uint32_t ignored = 0;
  uint32_t level = 0;
  uint32_t chromaFormatIDC = 1;
  if (!reader.readBits(8, profile) ||
      !reader.readBits(8, ignored) ||
      !reader.readBits(8, level) ||
      !reader.readUE(ignored)) {
    return false;
  }
  (void)level;

  if (isHighProfileSPS(profile)) {
    if (!reader.readUE(chromaFormatIDC)) {
      return false;
    }
    if (chromaFormatIDC == 3 && !reader.readBits(1, ignored)) {
      return false;
    }
    if (!reader.readUE(ignored) || !reader.readUE(ignored) || !reader.readBits(1, ignored)) {
      return false;
    }
    uint32_t scalingMatrixPresent = 0;
    if (!reader.readBits(1, scalingMatrixPresent)) {
      return false;
    }
    if (scalingMatrixPresent) {
      const int scalingListCount = chromaFormatIDC == 3 ? 12 : 8;
      for (int i = 0; i < scalingListCount; ++i) {
        uint32_t scalingListPresent = 0;
        if (!reader.readBits(1, scalingListPresent)) {
          return false;
        }
        if (scalingListPresent && !skipScalingList(reader, i < 6 ? 16 : 64)) {
          return false;
        }
      }
    }
  }

  if (!reader.readUE(ignored)) {
    return false;
  }
  uint32_t picOrderCntType = 0;
  if (!reader.readUE(picOrderCntType)) {
    return false;
  }
  if (picOrderCntType == 0) {
    if (!reader.readUE(ignored)) {
      return false;
    }
  } else if (picOrderCntType == 1) {
    int32_t signedIgnored = 0;
    if (!reader.readBits(1, ignored) || !reader.readSE(signedIgnored) || !reader.readSE(signedIgnored)) {
      return false;
    }
    uint32_t cycleCount = 0;
    if (!reader.readUE(cycleCount)) {
      return false;
    }
    for (uint32_t i = 0; i < cycleCount; ++i) {
      if (!reader.readSE(signedIgnored)) {
        return false;
      }
    }
  }

  if (!reader.readUE(ignored) || !reader.readBits(1, ignored)) {
    return false;
  }
  uint32_t picWidthInMbsMinus1 = 0;
  uint32_t picHeightInMapUnitsMinus1 = 0;
  uint32_t frameMbsOnlyFlag = 0;
  if (!reader.readUE(picWidthInMbsMinus1) ||
      !reader.readUE(picHeightInMapUnitsMinus1) ||
      !reader.readBits(1, frameMbsOnlyFlag)) {
    return false;
  }
  if (!frameMbsOnlyFlag && !reader.readBits(1, ignored)) {
    return false;
  }
  if (!reader.readBits(1, ignored)) {
    return false;
  }

  uint32_t cropLeft = 0;
  uint32_t cropRight = 0;
  uint32_t cropTop = 0;
  uint32_t cropBottom = 0;
  uint32_t frameCroppingFlag = 0;
  if (!reader.readBits(1, frameCroppingFlag)) {
    return false;
  }
  if (frameCroppingFlag &&
      (!reader.readUE(cropLeft) || !reader.readUE(cropRight) || !reader.readUE(cropTop) || !reader.readUE(cropBottom))) {
    return false;
  }

  int cropUnitX = 1;
  int cropUnitY = 2 - static_cast<int>(frameMbsOnlyFlag);
  if (chromaFormatIDC == 1) {
    cropUnitX = 2;
    cropUnitY *= 2;
  } else if (chromaFormatIDC == 2) {
    cropUnitX = 2;
  }

  const int codedWidth = static_cast<int>((picWidthInMbsMinus1 + 1) * 16);
  const int codedHeight = static_cast<int>((2 - frameMbsOnlyFlag) * (picHeightInMapUnitsMinus1 + 1) * 16);
  const int width = codedWidth - static_cast<int>(cropLeft + cropRight) * cropUnitX;
  const int height = codedHeight - static_cast<int>(cropTop + cropBottom) * cropUnitY;
  if (width <= 0 || height <= 0) {
    return false;
  }
  dimensions.width = codedWidth;
  dimensions.height = codedHeight;
  dimensions.visibleWidth = width;
  dimensions.visibleHeight = height;
  dimensions.cropLeft = static_cast<int>(cropLeft) * cropUnitX;
  dimensions.cropTop = static_cast<int>(cropTop) * cropUnitY;
  return true;
}

bool parseAccessUnitDimensions(const uint8_t *bytes, size_t length, H264Dimensions &dimensions) {
  for (const auto &unit : core::splitAnnexB(bytes, length)) {
    if (unit.type == 7 && parseSPSDimensions(bytes + unit.offset, unit.size, dimensions)) {
      return true;
    }
  }
  return false;
}

int normalizeRotationDegrees(double degrees) {
  if (!std::isfinite(degrees)) {
    return 0;
  }
  int rounded = static_cast<int>(std::llround(degrees / 90.0)) * 90;
  rounded %= 360;
  if (rounded < 0) {
    rounded += 360;
  }
  return rounded == 360 ? 0 : rounded;
}

core::VideoFrame rotateBGRAFrame(const core::VideoFrame &source, int rotationDegrees) {
  if (rotationDegrees == 0 || source.width <= 0 || source.height <= 0 || source.pixels.empty()) {
    return source;
  }
  core::VideoFrame rotated;
  const bool swapsAxes = rotationDegrees == 90 || rotationDegrees == 270;
  rotated.width = swapsAxes ? source.height : source.width;
  rotated.height = swapsAxes ? source.width : source.height;
  rotated.strideBytes = rotated.width * 4;
  rotated.pixels.resize(static_cast<size_t>(rotated.strideBytes) * static_cast<size_t>(rotated.height));
  for (int y = 0; y < source.height; ++y) {
    const uint8_t *sourcePixel = source.pixels.data() + static_cast<size_t>(y) * static_cast<size_t>(source.strideBytes);
    for (int x = 0; x < source.width; ++x, sourcePixel += 4) {
      int destX = x;
      int destY = y;
      switch (rotationDegrees) {
      case 90:
        destX = source.height - 1 - y;
        destY = x;
        break;
      case 180:
        destX = source.width - 1 - x;
        destY = source.height - 1 - y;
        break;
      case 270:
        destX = y;
        destY = source.width - 1 - x;
        break;
      default:
        break;
      }
      uint8_t *destPixel = rotated.pixels.data() +
                           static_cast<size_t>(destY) * static_cast<size_t>(rotated.strideBytes) +
                           static_cast<size_t>(destX) * 4u;
      std::memcpy(destPixel, sourcePixel, 4);
    }
  }
  rotated.previewReceiveToEmitMs = source.previewReceiveToEmitMs;
  rotated.previewSourceToReceiveMs = source.previewSourceToReceiveMs;
  rotated.previewSourceToEmitMs = source.previewSourceToEmitMs;
  rotated.previewAccessUnitNalTypes = source.previewAccessUnitNalTypes;
  rotated.previewSequence = source.previewSequence;
  return rotated;
}

core::VideoFrame orientPreviewFrameFromMetadata(const core::VideoFrame &source, uint8_t orientationCode) {
  if (orientationCode == 0 || source.width <= 0 || source.height <= 0) {
    return source;
  }
  const bool wantsLandscape = orientationCode == 2 || orientationCode == 3;
  const bool isLandscape = source.width > source.height;
  if (wantsLandscape == isLandscape) {
    return source;
  }
  if (wantsLandscape) {
    return rotateBGRAFrame(source, orientationCode == 3 ? 270 : 90);
  }
  return rotateBGRAFrame(source, orientationCode == 4 ? 90 : 270);
}

void appendBigEndianU16(std::vector<uint8_t> &bytes, size_t value) {
  bytes.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
  bytes.push_back(static_cast<uint8_t>(value & 0xff));
}

void appendBigEndianU32(std::vector<uint8_t> &bytes, size_t value) {
  bytes.push_back(static_cast<uint8_t>((value >> 24) & 0xff));
  bytes.push_back(static_cast<uint8_t>((value >> 16) & 0xff));
  bytes.push_back(static_cast<uint8_t>((value >> 8) & 0xff));
  bytes.push_back(static_cast<uint8_t>(value & 0xff));
}

std::vector<uint8_t> avcDecoderConfigurationRecord(const std::vector<uint8_t> &sps, const std::vector<uint8_t> &pps) {
  std::vector<uint8_t> config;
  if (sps.size() < 4 || pps.empty()) {
    return config;
  }
  config.reserve(11 + sps.size() + pps.size());
  config.push_back(1);
  config.push_back(sps[1]);
  config.push_back(sps[2]);
  config.push_back(sps[3]);
  config.push_back(0xff);
  config.push_back(0xe1);
  appendBigEndianU16(config, sps.size());
  config.insert(config.end(), sps.begin(), sps.end());
  config.push_back(1);
  appendBigEndianU16(config, pps.size());
  config.insert(config.end(), pps.begin(), pps.end());
  return config;
}

#if REASHOOT_WITH_FFMPEG_DECODER
std::wstring widenAscii(const char *value) {
  if (!value) {
    return {};
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value, -1, nullptr, 0);
  if (length <= 0) {
    return {};
  }
  std::wstring output(static_cast<size_t>(length - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value, -1, output.data(), length);
  return output;
}

bool preloadFFmpegDlls() {
  static const bool loaded = []() {
    const std::wstring binDir = widenAscii(REASHOOT_FFMPEG_BIN_DIR);
    if (binDir.empty()) {
      previewDebugLog("ffmpeg preload failed: empty bin dir");
      return false;
    }
    for (const wchar_t *name : {L"avutil-60.dll", L"swresample-6.dll", L"avcodec-62.dll"}) {
      const std::wstring path = binDir + L"\\" + name;
      if (!LoadLibraryW(path.c_str())) {
        std::ostringstream stream;
        stream << "ffmpeg preload failed error=" << GetLastError();
        previewDebugLog(stream.str());
        return false;
      }
    }
    previewDebugLog("ffmpeg preload ok");
    return true;
  }();
  return loaded;
}

struct FFmpegApi {
  using AvCodecFindDecoderFn = const AVCodec *(*)(enum AVCodecID);
  using AvCodecFindDecoderByNameFn = const AVCodec *(*)(const char *);
  using AvCodecAllocContext3Fn = AVCodecContext *(*)(const AVCodec *);
  using AvCodecOpen2Fn = int (*)(AVCodecContext *, const AVCodec *, AVDictionary **);
  using AvCodecSendPacketFn = int (*)(AVCodecContext *, const AVPacket *);
  using AvCodecReceiveFrameFn = int (*)(AVCodecContext *, AVFrame *);
  using AvCodecFreeContextFn = void (*)(AVCodecContext **);
  using AvFrameAllocFn = AVFrame *(*)();
  using AvFrameFreeFn = void (*)(AVFrame **);
  using AvFrameUnrefFn = void (*)(AVFrame *);
  using AvFrameGetSideDataFn = AVFrameSideData *(*)(const AVFrame *, enum AVFrameSideDataType);
  using AvDisplayRotationGetFn = double (*)(const int32_t *);
  using AvPacketAllocFn = AVPacket *(*)();
  using AvPacketFreeFn = void (*)(AVPacket **);
  using AvNewPacketFn = int (*)(AVPacket *, int);
  using AvPacketUnrefFn = void (*)(AVPacket *);

  AvCodecFindDecoderFn avcodec_find_decoder = nullptr;
  AvCodecFindDecoderByNameFn avcodec_find_decoder_by_name = nullptr;
  AvCodecAllocContext3Fn avcodec_alloc_context3 = nullptr;
  AvCodecOpen2Fn avcodec_open2 = nullptr;
  AvCodecSendPacketFn avcodec_send_packet = nullptr;
  AvCodecReceiveFrameFn avcodec_receive_frame = nullptr;
  AvCodecFreeContextFn avcodec_free_context = nullptr;
  AvFrameAllocFn av_frame_alloc = nullptr;
  AvFrameFreeFn av_frame_free = nullptr;
  AvFrameUnrefFn av_frame_unref = nullptr;
  AvFrameGetSideDataFn av_frame_get_side_data = nullptr;
  AvDisplayRotationGetFn av_display_rotation_get = nullptr;
  AvPacketAllocFn av_packet_alloc = nullptr;
  AvPacketFreeFn av_packet_free = nullptr;
  AvNewPacketFn av_new_packet = nullptr;
  AvPacketUnrefFn av_packet_unref = nullptr;

  HMODULE avcodec = nullptr;
  HMODULE avutil = nullptr;

  template <typename T>
  static bool loadFunction(HMODULE module, const char *name, T &target) {
    target = reinterpret_cast<T>(GetProcAddress(module, name));
    return target != nullptr;
  }

  bool load() {
    previewDebugLog("ffmpeg api load begin");
    if (!preloadFFmpegDlls()) {
      return false;
    }
    const std::wstring binDir = widenAscii(REASHOOT_FFMPEG_BIN_DIR);
    avutil = GetModuleHandleW((binDir + L"\\avutil-60.dll").c_str());
    avcodec = GetModuleHandleW((binDir + L"\\avcodec-62.dll").c_str());
    if (!avutil || !avcodec) {
      previewDebugLog("ffmpeg api load failed: module handle missing");
      return false;
    }
    const bool ok = loadFunction(avcodec, "avcodec_find_decoder", avcodec_find_decoder) &&
           loadFunction(avcodec, "avcodec_find_decoder_by_name", avcodec_find_decoder_by_name) &&
           loadFunction(avcodec, "avcodec_alloc_context3", avcodec_alloc_context3) &&
           loadFunction(avcodec, "avcodec_open2", avcodec_open2) &&
           loadFunction(avcodec, "avcodec_send_packet", avcodec_send_packet) &&
           loadFunction(avcodec, "avcodec_receive_frame", avcodec_receive_frame) &&
           loadFunction(avcodec, "avcodec_free_context", avcodec_free_context) &&
           loadFunction(avcodec, "av_packet_alloc", av_packet_alloc) &&
           loadFunction(avcodec, "av_packet_free", av_packet_free) &&
           loadFunction(avcodec, "av_new_packet", av_new_packet) &&
           loadFunction(avcodec, "av_packet_unref", av_packet_unref) &&
           loadFunction(avutil, "av_frame_alloc", av_frame_alloc) &&
           loadFunction(avutil, "av_frame_free", av_frame_free) &&
           loadFunction(avutil, "av_frame_unref", av_frame_unref) &&
           loadFunction(avutil, "av_frame_get_side_data", av_frame_get_side_data) &&
           loadFunction(avutil, "av_display_rotation_get", av_display_rotation_get);
    previewDebugLog(ok ? "ffmpeg api load ok" : "ffmpeg api load failed: symbol missing");
    return ok;
  }
};

FFmpegApi *ffmpegApi() {
  static FFmpegApi api;
  static const bool loaded = api.load();
  return loaded ? &api : nullptr;
}

class FFmpegH264PreviewRenderer final : public core::PreviewRenderer {
public:
  explicit FFmpegH264PreviewRenderer(core::VideoFrameCallback frameHandler)
      : frameHandler_(std::move(frameHandler)) {
    previewDebugLog("ffmpeg renderer ctor begin");
    api_ = ffmpegApi();
    if (!api_) {
      previewDebugLog("ffmpeg renderer unavailable: api not loaded");
      return;
    }
    codec_ = api_->avcodec_find_decoder(AV_CODEC_ID_H264);
    if (!codec_) {
      codec_ = api_->avcodec_find_decoder_by_name("h264");
    }
    if (!codec_) {
      previewDebugLog("ffmpeg renderer unavailable: h264 decoder missing");
      return;
    }
    previewDebugLog("ffmpeg renderer h264 decoder found");
    frame_ = api_->av_frame_alloc();
    packet_ = api_->av_packet_alloc();
    if (!frame_ || !packet_) {
      previewDebugLog("ffmpeg renderer allocation failed");
      reset();
      return;
    }
    if (!recreateCodecContextLocked()) {
      reset();
      return;
    }
    previewDebugLog("ffmpeg renderer ready");
    decodeWorker_ = std::thread([this]() { decodeLoop(); });
    ready_ = true;
  }

  ~FFmpegH264PreviewRenderer() override {
    {
      std::lock_guard<std::mutex> lock(queueMutex_);
      queueStopped_ = true;
      pendingAccessUnits_.clear();
    }
    queueCV_.notify_all();
    if (decodeWorker_.joinable()) {
      decodeWorker_.join();
    }
    reset();
  }

  bool ready() const { return ready_; }

  void reset() override {
    {
      std::lock_guard<std::mutex> queueLock(queueMutex_);
      pendingAccessUnits_.clear();
      requireQueuedKeyframe_ = true;
    }
    std::lock_guard<std::mutex> lock(decoderMutex_);
    previewDebugLog("ffmpeg renderer reset");
    if (packet_) {
      api_->av_packet_free(&packet_);
    }
    if (frame_) {
      api_->av_frame_free(&frame_);
    }
    if (codecContext_) {
      api_->avcodec_free_context(&codecContext_);
    }
    activeCodedWidth_ = 0;
    activeCodedHeight_ = 0;
    ready_ = false;
    waitingForKeyframe_ = true;
    lastFrameEmit_ = {};
  }

  void renderAnnexBAccessUnit(const uint8_t *bytes, size_t length) override {
    if (!ready_ || !bytes || length == 0) {
      return;
    }
    const bool keyframe = isDecoderStartingAccessUnit(bytes, length);
    std::lock_guard<std::mutex> lock(queueMutex_);
    if (queueStopped_) {
      return;
    }
    if (requireQueuedKeyframe_ && !keyframe) {
      return;
    }
    if (pendingAccessUnits_.size() > 90) {
      pendingAccessUnits_.clear();
      requireQueuedKeyframe_ = true;
      if (!keyframe) {
        return;
      }
    }
    pendingAccessUnits_.emplace_back(bytes, bytes + length);
    if (keyframe) {
      requireQueuedKeyframe_ = false;
    }
    queueCV_.notify_one();
  }

private:
  void decodeLoop() {
    while (true) {
      std::vector<uint8_t> accessUnit;
      {
        std::unique_lock<std::mutex> lock(queueMutex_);
        queueCV_.wait(lock, [this]() { return queueStopped_ || !pendingAccessUnits_.empty(); });
        if (queueStopped_) {
          return;
        }
        accessUnit = std::move(pendingAccessUnits_.front());
        pendingAccessUnits_.pop_front();
      }
      decodeAccessUnit(accessUnit.data(), accessUnit.size());
    }
  }

  void decodeAccessUnit(const uint8_t *bytes, size_t length) {
    std::lock_guard<std::mutex> lock(decoderMutex_);
    if (!ready_ || !bytes || length == 0) {
      return;
    }
    const PreviewDiagnosticMetadata diagnostic = parseDiagnosticSEI(bytes, length);
    if (!ensureCodecContextForAccessUnit(bytes, length)) {
      return;
    }
    if (api_->av_new_packet(packet_, static_cast<int>(length)) < 0) {
      previewDebugLog("ffmpeg av_new_packet failed");
      return;
    }
    std::memcpy(packet_->data, bytes, length);
    if (diagnostic.valid && diagnostic.sourceUnixMicros > 0) {
      packet_->pts = static_cast<int64_t>(diagnostic.sourceUnixMicros);
      packet_->dts = packet_->pts;
    }
    const int sendResult = api_->avcodec_send_packet(codecContext_, packet_);
    api_->av_packet_unref(packet_);
    if (sendResult < 0 && sendResult != AVERROR(EAGAIN)) {
      std::ostringstream stream;
      stream << "ffmpeg send_packet failed result=" << sendResult;
      previewDebugLog(stream.str());
      return;
    }
    ++sentPackets_;
    while (true) {
      const int receiveResult = api_->avcodec_receive_frame(codecContext_, frame_);
      if (receiveResult == AVERROR(EAGAIN) || receiveResult == AVERROR_EOF) {
        return;
      }
      if (receiveResult < 0) {
        std::ostringstream stream;
        stream << "ffmpeg receive_frame failed result=" << receiveResult;
        previewDebugLog(stream.str());
        return;
      }
      ++receivedFrames_;
      if (shouldEmitFrame()) {
        emitFrame(diagnostic);
      }
      api_->av_frame_unref(frame_);
    }
  }

  bool recreateCodecContextLocked() {
    if (!api_ || !codec_) {
      return false;
    }
    if (codecContext_) {
      api_->avcodec_free_context(&codecContext_);
    }
    codecContext_ = api_->avcodec_alloc_context3(codec_);
    if (!codecContext_) {
      previewDebugLog("ffmpeg renderer codec context allocation failed");
      return false;
    }
    codecContext_->flags |= AV_CODEC_FLAG_LOW_DELAY;
    codecContext_->thread_count = 1;
    codecContext_->thread_type = 0;
    const int openResult = api_->avcodec_open2(codecContext_, codec_, nullptr);
    if (openResult < 0) {
      std::ostringstream stream;
      stream << "ffmpeg renderer open failed result=" << openResult;
      previewDebugLog(stream.str());
      api_->avcodec_free_context(&codecContext_);
      return false;
    }
    lastFrameEmit_ = {};
    return true;
  }

  bool ensureCodecContextForAccessUnit(const uint8_t *bytes, size_t length) {
    H264Dimensions dimensions;
    if (!isDecoderStartingAccessUnit(bytes, length) || !parseAccessUnitDimensions(bytes, length, dimensions)) {
      return codecContext_ != nullptr;
    }
    const bool dimensionsChanged =
        activeCodedWidth_ > 0 &&
        activeCodedHeight_ > 0 &&
        (dimensions.width != activeCodedWidth_ || dimensions.height != activeCodedHeight_);
    if (dimensionsChanged) {
      std::ostringstream stream;
      stream << "ffmpeg preview dimensions changed "
             << activeCodedWidth_ << "x" << activeCodedHeight_
             << " -> " << dimensions.width << "x" << dimensions.height;
      previewDebugLog(stream.str());
      if (!recreateCodecContextLocked()) {
        return false;
      }
    }
    activeCodedWidth_ = dimensions.width;
    activeCodedHeight_ = dimensions.height;
    return codecContext_ != nullptr;
  }

  bool shouldEmitFrame() {
    const auto now = std::chrono::steady_clock::now();
    if (lastFrameEmit_.time_since_epoch().count() != 0 &&
        now - lastFrameEmit_ < kMinimumPreviewFrameInterval) {
      return false;
    }
    lastFrameEmit_ = now;
    return true;
  }

  void emitFrame(const PreviewDiagnosticMetadata &diagnostic) {
    if (!frameHandler_ || !frame_ || frame_->width <= 0 || frame_->height <= 0) {
      return;
    }
    const int width = frame_->width;
    const int height = frame_->height;
    core::VideoFrame output;
    output.width = width;
    output.height = height;
    output.strideBytes = width * 4;
    output.pixels.resize(static_cast<size_t>(output.strideBytes) * static_cast<size_t>(height));

    if (frame_->format != AV_PIX_FMT_YUV420P ||
        !frame_->data[0] || !frame_->data[1] || !frame_->data[2]) {
      std::ostringstream stream;
      stream << "ffmpeg unsupported pixfmt=" << frame_->format;
      return;
    }
    convertYUV420PToBGRA(frame_, output);
    const int rotationDegrees = frameRotationDegrees();
    if (rotationDegrees != 0) {
      output = rotateBGRAFrame(output, rotationDegrees);
    }
    output = orientPreviewFrameFromMetadata(output, diagnostic.orientationCode);
    ++emittedFrames_;
    const auto now = std::chrono::steady_clock::now();
    if (lastLog_.time_since_epoch().count() == 0 || now - lastLog_ >= std::chrono::seconds(1)) {
      lastLog_ = now;
      std::ostringstream stream;
      stream << "ffmpeg preview stats sent=" << sentPackets_
             << " decoded=" << receivedFrames_
             << " emitted=" << emittedFrames_
             << " pixfmt=" << frame_->format
             << " rotation=" << rotationDegrees
             << " orient=" << static_cast<int>(diagnostic.orientationCode)
             << " size=" << width << "x" << height;
      previewDebugLog(stream.str());
    }

    output.previewSequence = diagnostic.valid ? diagnostic.sequence : ++emittedFrameSequence_;
    output.previewAccessUnitNalTypes = diagnostic.nalTypes;
    if (diagnostic.valid && diagnostic.sourceUnixMicros > 0) {
      const auto now = std::chrono::system_clock::now();
      const auto nowMicros = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count();
      output.previewSourceToEmitMs = static_cast<double>(nowMicros - static_cast<int64_t>(diagnostic.sourceUnixMicros)) / 1000.0;
    }
    if (frame_->pts != AV_NOPTS_VALUE) {
      const auto now = std::chrono::system_clock::now();
      const auto nowMicros = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count();
      output.previewSourceToReceiveMs = static_cast<double>(nowMicros - frame_->pts) / 1000.0;
    }
    frameHandler_(output);
  }

  int frameRotationDegrees() const {
    if (!api_ || !api_->av_frame_get_side_data || !api_->av_display_rotation_get || !frame_) {
      return 0;
    }
    AVFrameSideData *sideData = api_->av_frame_get_side_data(frame_, AV_FRAME_DATA_DISPLAYMATRIX);
    if (!sideData || !sideData->data || sideData->size < sizeof(int32_t) * 9) {
      return 0;
    }
    return normalizeRotationDegrees(api_->av_display_rotation_get(reinterpret_cast<const int32_t *>(sideData->data)));
  }

  static uint8_t clampByte(int value) {
    return static_cast<uint8_t>((std::max)(0, (std::min)(255, value)));
  }

  static void convertYUV420PToBGRA(const AVFrame *frame, core::VideoFrame &output) {
    for (int y = 0; y < output.height; ++y) {
      const uint8_t *yRow = frame->data[0] + static_cast<size_t>(y) * static_cast<size_t>(frame->linesize[0]);
      const uint8_t *uRow = frame->data[1] + static_cast<size_t>(y / 2) * static_cast<size_t>(frame->linesize[1]);
      const uint8_t *vRow = frame->data[2] + static_cast<size_t>(y / 2) * static_cast<size_t>(frame->linesize[2]);
      uint8_t *dst = output.pixels.data() + static_cast<size_t>(y) * static_cast<size_t>(output.strideBytes);
      for (int x = 0; x < output.width; ++x) {
        const int yy = static_cast<int>(yRow[x]) - 16;
        const int u = static_cast<int>(uRow[x / 2]) - 128;
        const int v = static_cast<int>(vRow[x / 2]) - 128;
        const int c = (std::max)(0, yy);
        const int r = (298 * c + 409 * v + 128) >> 8;
        const int g = (298 * c - 100 * u - 208 * v + 128) >> 8;
        const int b = (298 * c + 516 * u + 128) >> 8;
        dst[static_cast<size_t>(x) * 4 + 0] = clampByte(b);
        dst[static_cast<size_t>(x) * 4 + 1] = clampByte(g);
        dst[static_cast<size_t>(x) * 4 + 2] = clampByte(r);
        dst[static_cast<size_t>(x) * 4 + 3] = 255;
      }
    }
  }

  std::mutex decoderMutex_;
  std::mutex queueMutex_;
  std::condition_variable queueCV_;
  std::thread decodeWorker_;
  std::deque<std::vector<uint8_t>> pendingAccessUnits_;
  bool requireQueuedKeyframe_ = true;
  bool queueStopped_ = false;
  FFmpegApi *api_ = nullptr;
  const AVCodec *codec_ = nullptr;
  core::VideoFrameCallback frameHandler_;
  AVCodecContext *codecContext_ = nullptr;
  AVFrame *frame_ = nullptr;
  AVPacket *packet_ = nullptr;
  int activeCodedWidth_ = 0;
  int activeCodedHeight_ = 0;
  std::chrono::steady_clock::time_point lastFrameEmit_;
  std::chrono::steady_clock::time_point lastLog_;
  uint64_t emittedFrameSequence_ = 0;
  uint64_t sentPackets_ = 0;
  uint64_t receivedFrames_ = 0;
  uint64_t emittedFrames_ = 0;
  bool waitingForKeyframe_ = true;
  bool ready_ = false;
};
#endif

class Win32H264PreviewRenderer final : public core::PreviewRenderer {
public:
  Win32H264PreviewRenderer(core::VideoFrameCallback frameHandler, int expectedWidth, int expectedHeight)
      : frameHandler_(std::move(frameHandler)), expectedWidth_(expectedWidth), expectedHeight_(expectedHeight) {
    decodeWorker_ = std::thread([this]() { decodeLoop(); });
  }

  ~Win32H264PreviewRenderer() override {
    {
      std::lock_guard<std::mutex> lock(queueMutex_);
      queueStopped_ = true;
      hasPendingAccessUnit_ = false;
    }
    queueCV_.notify_all();
    if (decodeWorker_.joinable()) {
      decodeWorker_.join();
    }
    reset();
  }

  void reset() override {
    {
      std::lock_guard<std::mutex> queueLock(queueMutex_);
      hasPendingAccessUnit_ = false;
      pendingAccessUnit_.clear();
      pendingRequiresDecoderReset_ = false;
      requireQueuedKeyframe_ = true;
    }
    std::lock_guard<std::mutex> lock(decoderMutex_);
    resetDecoderStateLocked();
  }

  void renderAnnexBAccessUnit(const uint8_t *bytes, size_t length) override {
    if (!bytes || length == 0) {
      return;
    }
    const bool keyframe = isDecoderStartingAccessUnit(bytes, length);
    std::lock_guard<std::mutex> lock(queueMutex_);
    if (queueStopped_) {
      return;
    }
    if (requireQueuedKeyframe_ && !keyframe) {
      return;
    }
    bool resetDecoderBeforeDecode = false;
    if (hasPendingAccessUnit_) {
      if (!keyframe) {
        pendingAccessUnit_.assign(bytes, bytes + length);
        pendingReceiveTime_ = std::chrono::steady_clock::now();
        pendingDiagnostic_ = parseDiagnosticSEI(bytes, length);
        return;
      }
      resetDecoderBeforeDecode = requireQueuedKeyframe_;
    } else if (requireQueuedKeyframe_ && keyframe) {
      resetDecoderBeforeDecode = true;
    }
    pendingAccessUnit_.assign(bytes, bytes + length);
    pendingReceiveTime_ = std::chrono::steady_clock::now();
    pendingDiagnostic_ = parseDiagnosticSEI(bytes, length);
    pendingRequiresDecoderReset_ = resetDecoderBeforeDecode;
    hasPendingAccessUnit_ = true;
    if (keyframe) {
      requireQueuedKeyframe_ = false;
    }
    queueCV_.notify_one();
  }

private:
  void resetDecoderStateLocked() {
    decoder_.Reset();
    inputType_.Reset();
    outputType_.Reset();
    streamID_ = 0;
    frameWidth_ = 0;
    frameHeight_ = 0;
    visibleWidth_ = 0;
    visibleHeight_ = 0;
    cropLeft_ = 0;
    cropTop_ = 0;
    outputStride_ = 0;
    initialized_ = false;
    waitingForKeyframe_ = true;
    lastFrameEmit_ = {};
    activeReceiveTime_ = {};
    sps_.clear();
    pps_.clear();
  }

  void decodeLoop() {
    while (true) {
      std::vector<uint8_t> accessUnit;
      std::chrono::steady_clock::time_point receiveTime;
      PreviewDiagnosticMetadata diagnostic;
      bool resetDecoderBeforeDecode = false;
      {
        std::unique_lock<std::mutex> lock(queueMutex_);
        queueCV_.wait(lock, [this]() { return queueStopped_ || hasPendingAccessUnit_; });
        if (queueStopped_) {
          return;
        }
        accessUnit = std::move(pendingAccessUnit_);
        receiveTime = pendingReceiveTime_;
        diagnostic = pendingDiagnostic_;
        resetDecoderBeforeDecode = pendingRequiresDecoderReset_;
        pendingAccessUnit_.clear();
        pendingRequiresDecoderReset_ = false;
        hasPendingAccessUnit_ = false;
      }
      decodeAnnexBAccessUnit(accessUnit.data(), accessUnit.size(), receiveTime, diagnostic, resetDecoderBeforeDecode);
    }
  }

  void decodeAnnexBAccessUnit(const uint8_t *bytes,
                              size_t length,
                              std::chrono::steady_clock::time_point receiveTime,
                              PreviewDiagnosticMetadata diagnostic,
                              bool resetDecoderBeforeDecode) {
    thread_local ComThreadRuntime comRuntime;
    if (!bytes || length == 0 || !comRuntime.ready() || !mfRuntime().ready()) {
      return;
    }

    std::lock_guard<std::mutex> lock(decoderMutex_);
    if (resetDecoderBeforeDecode) {
      resetDecoderStateLocked();
    }
    if (waitingForKeyframe_) {
      if (!isDecoderStartingAccessUnit(bytes, length)) {
        return;
      }
      H264Dimensions dimensions;
      if (parseAccessUnitDimensions(bytes, length, dimensions)) {
        expectedWidth_ = dimensions.width;
        expectedHeight_ = dimensions.height;
        visibleWidth_ = dimensions.visibleWidth;
        visibleHeight_ = dimensions.visibleHeight;
        cropLeft_ = dimensions.cropLeft;
        cropTop_ = dimensions.cropTop;
      }
      waitingForKeyframe_ = false;
    }
    if (!ensureDecoder()) {
      return;
    }
    activeReceiveTime_ = receiveTime;
    activeDiagnostic_ = diagnostic;
    if (!processInput(bytes, length)) {
      return;
    }
    drainOutput();
  }
  std::vector<uint8_t> sampleFromAnnexBAccessUnit(const uint8_t *bytes, size_t length) {
    std::vector<uint8_t> sample;
    for (const auto &unit : core::splitAnnexB(bytes, length)) {
      if (unit.size == 0) {
        continue;
      }
      const uint8_t *nalu = bytes + unit.offset;
      if (unit.type == 7) {
        sps_.assign(nalu, nalu + unit.size);
        continue;
      }
      if (unit.type == 8) {
        pps_.assign(nalu, nalu + unit.size);
        continue;
      }
      appendBigEndianU32(sample, unit.size);
      sample.insert(sample.end(), nalu, nalu + unit.size);
    }
    return sample;
  }

  bool ensureDecoder() {
    if (decoder_) {
      return true;
    }

    if (FAILED(CoCreateInstance(CLSID_CMSH264DecoderMFT, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&decoder_))) || !decoder_) {
      return false;
    }
    ComPtr<ICodecAPI> codecAPI;
    if (SUCCEEDED(decoder_.As(&codecAPI)) && codecAPI) {
      VARIANT lowLatency;
      VariantInit(&lowLatency);
      lowLatency.vt = VT_UI4;
      lowLatency.ulVal = 1;
      codecAPI->SetValue(&CODECAPI_AVLowLatencyMode, &lowLatency);
    }

    ComPtr<IMFMediaType> inputType;
    if (FAILED(MFCreateMediaType(&inputType)) ||
        FAILED(inputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)) ||
        FAILED(inputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264_ES))) {
      decoder_.Reset();
      return false;
    }
    if (expectedWidth_ > 0 && expectedHeight_ > 0) {
      MFSetAttributeSize(inputType.Get(), MF_MT_FRAME_SIZE, static_cast<UINT32>(expectedWidth_), static_cast<UINT32>(expectedHeight_));
    }
    inputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    if (FAILED(decoder_->SetInputType(0, inputType.Get(), 0))) {
      decoder_.Reset();
      return false;
    }
    inputType_ = inputType;

    if (!setOutputType()) {
      decoder_.Reset();
      inputType_.Reset();
      return false;
    }
    decoder_->ProcessMessage(MFT_MESSAGE_NOTIFY_BEGIN_STREAMING, 0);
    decoder_->ProcessMessage(MFT_MESSAGE_NOTIFY_START_OF_STREAM, 0);
    initialized_ = true;
    return true;
  }

  bool setOutputType() {
    if (!decoder_) {
      return false;
    }
    return setOutputType(MFVideoFormat_RGB32) || setOutputType(MFVideoFormat_NV12) || setManualOutputType();
  }

  bool setOutputType(const GUID &preferredSubtype) {
    if (!decoder_) {
      return false;
    }
    for (DWORD index = 0;; ++index) {
      ComPtr<IMFMediaType> candidate;
      HRESULT hr = decoder_->GetOutputAvailableType(0, index, &candidate);
      if (hr == MF_E_NO_MORE_TYPES) {
        return false;
      }
      if (FAILED(hr) || !candidate) {
        continue;
      }
      GUID subtype = {};
      if (FAILED(candidate->GetGUID(MF_MT_SUBTYPE, &subtype)) ||
          subtype != preferredSubtype) {
        continue;
      }
      if (FAILED(decoder_->SetOutputType(0, candidate.Get(), 0))) {
        continue;
      }
      outputType_ = candidate;
      outputSubtype_ = subtype;
      UINT32 width = 0;
      UINT32 height = 0;
      if (SUCCEEDED(MFGetAttributeSize(candidate.Get(), MF_MT_FRAME_SIZE, &width, &height))) {
        frameWidth_ = static_cast<int>(width);
        frameHeight_ = static_cast<int>(height);
      }
      if ((frameWidth_ <= 0 || frameHeight_ <= 0) && expectedWidth_ > 0 && expectedHeight_ > 0) {
        frameWidth_ = expectedWidth_;
        frameHeight_ = expectedHeight_;
      }
      UINT32 stride = 0;
      if (SUCCEEDED(candidate->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride))) {
        outputStride_ = static_cast<LONG>(stride);
      }
      if (outputStride_ == 0 && frameWidth_ > 0) {
        outputStride_ = outputSubtype_ == MFVideoFormat_NV12 ? frameWidth_ : frameWidth_ * 4;
      }
      return true;
    }
    return false;
  }

  bool setManualOutputType() {
    if (!decoder_ || expectedWidth_ <= 0 || expectedHeight_ <= 0) {
      return false;
    }
    ComPtr<IMFMediaType> outputType;
    if (FAILED(MFCreateMediaType(&outputType)) ||
        FAILED(outputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)) ||
        FAILED(outputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32))) {
      return false;
    }
    MFSetAttributeSize(outputType.Get(), MF_MT_FRAME_SIZE, static_cast<UINT32>(expectedWidth_), static_cast<UINT32>(expectedHeight_));
    outputType->SetUINT32(MF_MT_DEFAULT_STRIDE, static_cast<UINT32>(expectedWidth_ * 4));
    outputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    if (FAILED(decoder_->SetOutputType(0, outputType.Get(), 0))) {
      return false;
    }
    outputType_ = outputType;
    outputSubtype_ = MFVideoFormat_RGB32;
    frameWidth_ = expectedWidth_;
    frameHeight_ = expectedHeight_;
    outputStride_ = expectedWidth_ * 4;
    return true;
  }

  bool processInput(const uint8_t *bytes, size_t length) {
    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(MFCreateMemoryBuffer(static_cast<DWORD>(length), &buffer)) || !buffer) {
      return false;
    }
    BYTE *destination = nullptr;
    DWORD maxLength = 0;
    if (FAILED(buffer->Lock(&destination, &maxLength, nullptr)) || !destination || maxLength < length) {
      return false;
    }
    std::memcpy(destination, bytes, length);
    buffer->Unlock();
    buffer->SetCurrentLength(static_cast<DWORD>(length));

    ComPtr<IMFSample> sample;
    if (FAILED(MFCreateSample(&sample)) || !sample ||
        FAILED(sample->AddBuffer(buffer.Get()))) {
      return false;
    }
    if (activeDiagnostic_.valid && activeDiagnostic_.sourceUnixMicros > 0) {
      sample->SetSampleTime(static_cast<LONGLONG>(activeDiagnostic_.sourceUnixMicros * 10u));
      sample->SetSampleDuration(static_cast<LONGLONG>(10000000 / 12));
    }

    HRESULT hr = decoder_->ProcessInput(0, sample.Get(), 0);
    if (hr == MF_E_TRANSFORM_TYPE_NOT_SET && setOutputType()) {
      hr = decoder_->ProcessInput(0, sample.Get(), 0);
    }
    if (hr == MF_E_NOTACCEPTING) {
      drainOutput();
      hr = decoder_->ProcessInput(0, sample.Get(), 0);
    }
    return SUCCEEDED(hr);
  }

  void drainOutput() {
    if (!decoder_) {
      return;
    }
    while (true) {
      ComPtr<IMFSample> outputSample;
      if (FAILED(MFCreateSample(&outputSample)) || !outputSample) {
        return;
      }

      DWORD bufferSize = 0;
      MFT_OUTPUT_STREAM_INFO streamInfo = {};
      if (SUCCEEDED(decoder_->GetOutputStreamInfo(0, &streamInfo))) {
        bufferSize = streamInfo.cbSize;
      }
      bufferSize = (std::max<DWORD>)(bufferSize, 4 * 1920 * 1080);

      ComPtr<IMFMediaBuffer> outputBuffer;
      if (FAILED(MFCreateMemoryBuffer(bufferSize, &outputBuffer)) || !outputBuffer ||
          FAILED(outputSample->AddBuffer(outputBuffer.Get()))) {
        return;
      }

      MFT_OUTPUT_DATA_BUFFER output = {};
      output.dwStreamID = streamID_;
      output.pSample = outputSample.Get();
      DWORD status = 0;
      HRESULT hr = decoder_->ProcessOutput(0, 1, &output, &status);
      if (output.pEvents) {
        output.pEvents->Release();
      }
      if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
        return;
      }
      if (hr == MF_E_TRANSFORM_STREAM_CHANGE) {
        setOutputType();
        continue;
      }
      if (FAILED(hr)) {
        return;
      }
      if (shouldEmitFrame()) {
        emitFrame(outputSample.Get());
      }
    }
  }

  bool shouldEmitFrame() {
    const auto now = std::chrono::steady_clock::now();
    if (lastFrameEmit_.time_since_epoch().count() != 0 &&
        now - lastFrameEmit_ < kMinimumPreviewFrameInterval) {
      return false;
    }
    lastFrameEmit_ = now;
    return true;
  }

  void emitFrame(IMFSample *sample) {
    if (!frameHandler_ || frameWidth_ <= 0 || frameHeight_ <= 0) {
      return;
    }
    ComPtr<IMFMediaBuffer> buffer;
    ComPtr<IMF2DBuffer> buffer2D;
    BYTE *data = nullptr;
    LONG pitch = 0;
    if (!lockSample2D(sample, &data, &pitch, buffer, buffer2D)) {
      return;
    }

    if (outputSubtype_ == MFVideoFormat_NV12) {
      emitNV12Frame(sample, data, pitch);
      unlockSample2D(buffer, buffer2D);
      return;
    }

    const int outputWidth = normalizedVisibleWidth();
    const int outputHeight = normalizedVisibleHeight();
    const int offsetX = normalizedCropLeft(outputWidth);
    const int offsetY = normalizedCropTop(outputHeight);
    int stride = pitch != 0 ? std::abs(pitch) : (outputStride_ != 0 ? std::abs(outputStride_) : frameWidth_ * 4);
    if (stride < frameWidth_ * 4) {
      unlockSample2D(buffer, buffer2D);
      return;
    }

    core::VideoFrame frame;
    frame.width = outputWidth;
    frame.height = outputHeight;
    frame.strideBytes = outputWidth * 4;
    frame.pixels.resize(static_cast<size_t>(frame.strideBytes) * static_cast<size_t>(frame.height));
    frame.previewReceiveToEmitMs = receiveToEmitMillis();
    frame.previewSourceToReceiveMs = sourceToReceiveMillis();
    frame.previewSourceToEmitMs = outputSourceToEmitMillis(sample);
    frame.previewAccessUnitNalTypes = activeDiagnostic_.nalTypes;
    frame.previewSequence = activeDiagnostic_.valid ? activeDiagnostic_.sequence : ++emittedFrameSequence_;
    for (int y = 0; y < outputHeight; ++y) {
      const uint8_t *sourceRow = pitch < 0
                                     ? data + static_cast<size_t>(frameHeight_ - 1 - (y + offsetY)) * static_cast<size_t>(stride)
                                     : data + static_cast<size_t>(y + offsetY) * static_cast<size_t>(stride);
      sourceRow += static_cast<size_t>(offsetX) * 4u;
      std::memcpy(frame.pixels.data() + static_cast<size_t>(y) * static_cast<size_t>(frame.strideBytes),
                  sourceRow,
                  static_cast<size_t>(frame.strideBytes));
    }
    unlockSample2D(buffer, buffer2D);
    frameHandler_(frame);
  }

  static uint8_t clampByte(int value) {
    return static_cast<uint8_t>((std::max)(0, (std::min)(255, value)));
  }

  void emitNV12Frame(IMFSample *sample, const uint8_t *data, LONG pitch) {
    if (!data) {
      return;
    }
    int yStride = pitch != 0 ? std::abs(pitch) : (outputStride_ != 0 ? std::abs(outputStride_) : frameWidth_);
    if (yStride < frameWidth_) {
      yStride = frameWidth_;
    }
    const int outputWidth = normalizedVisibleWidth();
    const int outputHeight = normalizedVisibleHeight();
    const int offsetX = normalizedCropLeft(outputWidth);
    const int offsetY = normalizedCropTop(outputHeight);
    const int uvStride = yStride;
    const size_t yPlaneBytes = static_cast<size_t>(yStride) * static_cast<size_t>(frameHeight_);

    core::VideoFrame frame;
    frame.width = outputWidth;
    frame.height = outputHeight;
    frame.strideBytes = outputWidth * 4;
    frame.pixels.resize(static_cast<size_t>(frame.strideBytes) * static_cast<size_t>(frame.height));
    frame.previewReceiveToEmitMs = receiveToEmitMillis();
    frame.previewSourceToReceiveMs = sourceToReceiveMillis();
    frame.previewSourceToEmitMs = outputSourceToEmitMillis(sample);
    frame.previewAccessUnitNalTypes = activeDiagnostic_.nalTypes;
    frame.previewSequence = activeDiagnostic_.valid ? activeDiagnostic_.sequence : ++emittedFrameSequence_;
    const uint8_t *uvPlane = data + yPlaneBytes;
    for (int y = 0; y < outputHeight; ++y) {
      uint8_t *dst = frame.pixels.data() + static_cast<size_t>(y) * static_cast<size_t>(frame.strideBytes);
      const int sourceY = y + offsetY;
      const uint8_t *yRow = pitch < 0
                                ? data + static_cast<size_t>(frameHeight_ - 1 - sourceY) * static_cast<size_t>(yStride)
                                : data + static_cast<size_t>(sourceY) * static_cast<size_t>(yStride);
      yRow += offsetX;
      const uint8_t *uvRow = uvPlane + static_cast<size_t>(sourceY / 2) * static_cast<size_t>(uvStride) + static_cast<size_t>((offsetX / 2) * 2);
      for (int x = 0; x < outputWidth; ++x) {
        const int yy = static_cast<int>(yRow[x]) - 16;
        const int u = static_cast<int>(uvRow[(x / 2) * 2]) - 128;
        const int v = static_cast<int>(uvRow[(x / 2) * 2 + 1]) - 128;
        const int c = (std::max)(0, yy);
        const int r = (298 * c + 409 * v + 128) >> 8;
        const int g = (298 * c - 100 * u - 208 * v + 128) >> 8;
        const int b = (298 * c + 516 * u + 128) >> 8;
        dst[static_cast<size_t>(x) * 4 + 0] = clampByte(b);
        dst[static_cast<size_t>(x) * 4 + 1] = clampByte(g);
        dst[static_cast<size_t>(x) * 4 + 2] = clampByte(r);
        dst[static_cast<size_t>(x) * 4 + 3] = 255;
      }
    }
    frameHandler_(frame);
  }

  double receiveToEmitMillis() const {
    if (activeReceiveTime_.time_since_epoch().count() == 0) {
      return 0.0;
    }
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - activeReceiveTime_).count();
  }

  double sourceToReceiveMillis() const {
    if (!activeDiagnostic_.valid || activeDiagnostic_.sourceUnixMicros == 0) {
      return 0.0;
    }
    const auto now = std::chrono::system_clock::now();
    const auto receivedUnixMicros = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count();
    return static_cast<double>(receivedUnixMicros - static_cast<int64_t>(activeDiagnostic_.sourceUnixMicros)) / 1000.0;
  }

  double outputSourceToEmitMillis(IMFSample *sample) const {
    LONGLONG sampleTime = 0;
    if (!sample || FAILED(sample->GetSampleTime(&sampleTime)) || sampleTime <= 0) {
      return 0.0;
    }
    const auto now = std::chrono::system_clock::now();
    const auto nowHns = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()).count() * 10;
    return static_cast<double>(nowHns - sampleTime) / 10000.0;
  }

  int normalizedVisibleWidth() const {
    return visibleWidth_ > 0 && cropLeft_ + visibleWidth_ <= frameWidth_ ? visibleWidth_ : frameWidth_;
  }

  int normalizedVisibleHeight() const {
    return visibleHeight_ > 0 && cropTop_ + visibleHeight_ <= frameHeight_ ? visibleHeight_ : frameHeight_;
  }

  int normalizedCropLeft(int outputWidth) const {
    return cropLeft_ >= 0 && cropLeft_ + outputWidth <= frameWidth_ ? cropLeft_ : 0;
  }

  int normalizedCropTop(int outputHeight) const {
    return cropTop_ >= 0 && cropTop_ + outputHeight <= frameHeight_ ? cropTop_ : 0;
  }

  std::mutex decoderMutex_;
  std::mutex queueMutex_;
  std::condition_variable queueCV_;
  std::thread decodeWorker_;
  std::vector<uint8_t> pendingAccessUnit_;
  std::chrono::steady_clock::time_point pendingReceiveTime_;
  PreviewDiagnosticMetadata pendingDiagnostic_;
  bool hasPendingAccessUnit_ = false;
  bool pendingRequiresDecoderReset_ = false;
  bool requireQueuedKeyframe_ = true;
  bool queueStopped_ = false;
  core::VideoFrameCallback frameHandler_;
  int expectedWidth_ = 0;
  int expectedHeight_ = 0;
  ComPtr<IMFTransform> decoder_;
  ComPtr<IMFMediaType> inputType_;
  ComPtr<IMFMediaType> outputType_;
  GUID outputSubtype_ = GUID_NULL;
  DWORD streamID_ = 0;
  int frameWidth_ = 0;
  int frameHeight_ = 0;
  int visibleWidth_ = 0;
  int visibleHeight_ = 0;
  int cropLeft_ = 0;
  int cropTop_ = 0;
  LONG outputStride_ = 0;
  bool initialized_ = false;
  bool waitingForKeyframe_ = true;
  std::chrono::steady_clock::time_point lastFrameEmit_;
  std::chrono::steady_clock::time_point activeReceiveTime_;
  PreviewDiagnosticMetadata activeDiagnostic_;
  uint64_t emittedFrameSequence_ = 0;
  std::vector<uint8_t> sps_;
  std::vector<uint8_t> pps_;
};

} // namespace

std::unique_ptr<core::PreviewRenderer> createH264PreviewRenderer(core::VideoFrameCallback frameHandler,
                                                                 int expectedWidth,
                                                                 int expectedHeight) {
#if REASHOOT_WITH_FFMPEG_DECODER
  auto ffmpegRenderer = std::make_unique<FFmpegH264PreviewRenderer>(frameHandler);
  if (ffmpegRenderer->ready()) {
    return ffmpegRenderer;
  }
#endif
  return std::make_unique<Win32H264PreviewRenderer>(std::move(frameHandler), expectedWidth, expectedHeight);
}

} // namespace reashoot::platform::win32
