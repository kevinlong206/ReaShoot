#include "win32_playback_preview_renderer.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace reashoot::platform::win32 {
namespace {

using Microsoft::WRL::ComPtr;

class ComThreadRuntime {
public:
  ComThreadRuntime() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    initialized_ = SUCCEEDED(hr);
    alreadyInitialized_ = hr == RPC_E_CHANGED_MODE;
    mfStarted_ = SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE));
  }

  ~ComThreadRuntime() {
    if (mfStarted_) {
      MFShutdown();
    }
    if (initialized_) {
      CoUninitialize();
    }
  }

  bool ready() const { return (initialized_ || alreadyInitialized_) && mfStarted_; }

private:
  bool initialized_ = false;
  bool alreadyInitialized_ = false;
  bool mfStarted_ = false;
};

std::wstring wideFromUtf8(const std::string &value) {
  if (value.empty()) {
    return {};
  }
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, nullptr, 0);
  if (length <= 0) {
    return {};
  }
  std::wstring output(static_cast<size_t>(length - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, output.data(), length);
  return output;
}

class Win32PlaybackPreview final : public core::PlaybackPreview {
public:
  explicit Win32PlaybackPreview(core::VideoFrameCallback frameHandler)
      : frameHandler_(std::move(frameHandler)) {}

  void showMedia(const std::string &path, double itemStart, double sourceOffset, double projectPosition) override {
    thread_local ComThreadRuntime runtime;
    if (!runtime.ready() || path.empty() || !frameHandler_) {
      return;
    }

    std::lock_guard<std::mutex> lock(mutex_);
    const bool switchedSource = path != activePath_ || !reader_;
    if (switchedSource && !open(path)) {
      return;
    }

    const double sourceTime = (std::max)(0.0, projectPosition - itemStart + sourceOffset);
    if (!switchedSource && visible_ && lastRenderedSourceTime_ >= 0.0 &&
        std::fabs(sourceTime - lastRenderedSourceTime_) < (1.0 / 40.0)) {
      return;
    }

    if (renderAt(sourceTime)) {
      lastRenderedSourceTime_ = sourceTime;
      visible_ = true;
    }
  }

  void hide() override {
    std::lock_guard<std::mutex> lock(mutex_);
    visible_ = false;
    lastRenderedSourceTime_ = -1.0;
  }

private:
  bool open(const std::string &path) {
    reader_.Reset();
    activePath_.clear();
    width_ = 0;
    height_ = 0;
    stride_ = 0;

    ComPtr<IMFAttributes> attributes;
    if (FAILED(MFCreateAttributes(&attributes, 1))) {
      return false;
    }
    attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);

    const std::wstring widePath = wideFromUtf8(path);
    if (widePath.empty() ||
        FAILED(MFCreateSourceReaderFromURL(widePath.c_str(), attributes.Get(), &reader_)) ||
        !reader_) {
      return false;
    }

    ComPtr<IMFMediaType> outputType;
    if (FAILED(MFCreateMediaType(&outputType)) ||
        FAILED(outputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)) ||
        FAILED(outputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32)) ||
        FAILED(reader_->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, outputType.Get()))) {
      reader_.Reset();
      return false;
    }

    ComPtr<IMFMediaType> currentType;
    if (SUCCEEDED(reader_->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &currentType)) && currentType) {
      UINT32 width = 0;
      UINT32 height = 0;
      if (SUCCEEDED(MFGetAttributeSize(currentType.Get(), MF_MT_FRAME_SIZE, &width, &height))) {
        width_ = static_cast<int>(width);
        height_ = static_cast<int>(height);
      }
      UINT32 stride = 0;
      if (SUCCEEDED(currentType->GetUINT32(MF_MT_DEFAULT_STRIDE, &stride))) {
        stride_ = static_cast<LONG>(stride);
      }
    }
    activePath_ = path;
    lastRenderedSourceTime_ = -1.0;
    visible_ = false;
    return width_ > 0 && height_ > 0;
  }

  bool renderAt(double sourceTime) {
    if (!reader_ || width_ <= 0 || height_ <= 0) {
      return false;
    }

    PROPVARIANT position;
    PropVariantInit(&position);
    position.vt = VT_I8;
    position.hVal.QuadPart = static_cast<LONGLONG>(sourceTime * 10000000.0);
    reader_->SetCurrentPosition(GUID_NULL, position);
    PropVariantClear(&position);

    for (int attempt = 0; attempt < 8; ++attempt) {
      DWORD streamIndex = 0;
      DWORD flags = 0;
      LONGLONG timestamp = 0;
      ComPtr<IMFSample> sample;
      HRESULT hr = reader_->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &streamIndex, &flags, &timestamp, &sample);
      if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) {
        return false;
      }
      if (!sample) {
        continue;
      }
      return emitFrame(sample.Get());
    }
    return false;
  }

  bool emitFrame(IMFSample *sample) {
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

    int sourceStride = stride_ != 0 ? std::abs(stride_) : width_ * 4;
    if (sourceStride < width_ * 4) {
      sourceStride = width_ * 4;
    }
    const size_t required = static_cast<size_t>(sourceStride) * static_cast<size_t>(height_);
    if (currentLength < required) {
      buffer->Unlock();
      return false;
    }

    core::VideoFrame frame;
    frame.width = width_;
    frame.height = height_;
    frame.strideBytes = width_ * 4;
    frame.pixels.resize(static_cast<size_t>(frame.strideBytes) * static_cast<size_t>(frame.height));
    const uint8_t *source = data;
    if (stride_ < 0) {
      source += static_cast<size_t>(sourceStride) * static_cast<size_t>(height_ - 1);
    }
    for (int y = 0; y < height_; ++y) {
      const uint8_t *sourceRow = stride_ < 0
                                     ? source - static_cast<size_t>(y) * static_cast<size_t>(sourceStride)
                                     : source + static_cast<size_t>(y) * static_cast<size_t>(sourceStride);
      std::memcpy(frame.pixels.data() + static_cast<size_t>(y) * static_cast<size_t>(frame.strideBytes),
                  sourceRow,
                  static_cast<size_t>(frame.strideBytes));
    }
    buffer->Unlock();
    frameHandler_(frame);
    return true;
  }

  std::mutex mutex_;
  core::VideoFrameCallback frameHandler_;
  ComPtr<IMFSourceReader> reader_;
  std::string activePath_;
  double lastRenderedSourceTime_ = -1.0;
  int width_ = 0;
  int height_ = 0;
  LONG stride_ = 0;
  bool visible_ = false;
};

} // namespace

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler) {
  return std::make_unique<Win32PlaybackPreview>(std::move(frameHandler));
}

} // namespace reashoot::platform::win32
