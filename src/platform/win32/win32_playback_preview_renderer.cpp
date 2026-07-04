#include "win32_playback_preview_renderer.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#if REASHOOT_WITH_FFMPEG_DECODER
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
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
#include <filesystem>
#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace reashoot::platform::win32 {
namespace {

void playbackDebugLog(const std::string &message) {
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

uint8_t clampByte(int value) {
  return static_cast<uint8_t>((std::max)(0, (std::min)(255, value)));
}

void convertYUV420PToBGRA(const AVFrame *sourceFrame, core::VideoFrame &output) {
  const int sourceWidth = sourceFrame->width;
  const int sourceHeight = sourceFrame->height;
  for (int y = 0; y < output.height; ++y) {
    const int sourceY = output.height == sourceHeight ? y : (y * sourceHeight) / output.height;
    const uint8_t *yRow = sourceFrame->data[0] + static_cast<size_t>(sourceY) * static_cast<size_t>(sourceFrame->linesize[0]);
    const uint8_t *uRow = sourceFrame->data[1] + static_cast<size_t>(sourceY / 2) * static_cast<size_t>(sourceFrame->linesize[1]);
    const uint8_t *vRow = sourceFrame->data[2] + static_cast<size_t>(sourceY / 2) * static_cast<size_t>(sourceFrame->linesize[2]);
    uint8_t *dst = output.pixels.data() + static_cast<size_t>(y) * static_cast<size_t>(output.strideBytes);
    for (int x = 0; x < output.width; ++x) {
      const int sourceX = output.width == sourceWidth ? x : (x * sourceWidth) / output.width;
      const int yy = static_cast<int>(yRow[sourceX]) - 16;
      const int u = static_cast<int>(uRow[sourceX / 2]) - 128;
      const int v = static_cast<int>(vRow[sourceX / 2]) - 128;
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

std::wstring widenAscii(const char *value) {
  return wideFromUtf8(value ? value : "");
}

class FFmpegPlaybackApi {
public:
  using AvFormatOpenInputFn = int (*)(AVFormatContext **, const char *, const AVInputFormat *, AVDictionary **);
  using AvFormatFindStreamInfoFn = int (*)(AVFormatContext *, AVDictionary **);
  using AvFindBestStreamFn = int (*)(AVFormatContext *, AVMediaType, int, int, const AVCodec **, int);
  using AvFormatCloseInputFn = void (*)(AVFormatContext **);
  using AvSeekFrameFn = int (*)(AVFormatContext *, int, int64_t, int);
  using AvReadFrameFn = int (*)(AVFormatContext *, AVPacket *);
  using AvCodecAllocContext3Fn = AVCodecContext *(*)(const AVCodec *);
  using AvCodecParametersToContextFn = int (*)(AVCodecContext *, const AVCodecParameters *);
  using AvCodecOpen2Fn = int (*)(AVCodecContext *, const AVCodec *, AVDictionary **);
  using AvCodecSendPacketFn = int (*)(AVCodecContext *, const AVPacket *);
  using AvCodecReceiveFrameFn = int (*)(AVCodecContext *, AVFrame *);
  using AvCodecFlushBuffersFn = void (*)(AVCodecContext *);
  using AvCodecFreeContextFn = void (*)(AVCodecContext **);
  using AvFrameAllocFn = AVFrame *(*)();
  using AvFrameFreeFn = void (*)(AVFrame **);
  using AvFrameUnrefFn = void (*)(AVFrame *);
  using AvPacketAllocFn = AVPacket *(*)();
  using AvPacketFreeFn = void (*)(AVPacket **);
  using AvPacketUnrefFn = void (*)(AVPacket *);

  AvFormatOpenInputFn avformat_open_input = nullptr;
  AvFormatFindStreamInfoFn avformat_find_stream_info = nullptr;
  AvFindBestStreamFn av_find_best_stream = nullptr;
  AvFormatCloseInputFn avformat_close_input = nullptr;
  AvSeekFrameFn av_seek_frame = nullptr;
  AvReadFrameFn av_read_frame = nullptr;
  AvCodecAllocContext3Fn avcodec_alloc_context3 = nullptr;
  AvCodecParametersToContextFn avcodec_parameters_to_context = nullptr;
  AvCodecOpen2Fn avcodec_open2 = nullptr;
  AvCodecSendPacketFn avcodec_send_packet = nullptr;
  AvCodecReceiveFrameFn avcodec_receive_frame = nullptr;
  AvCodecFlushBuffersFn avcodec_flush_buffers = nullptr;
  AvCodecFreeContextFn avcodec_free_context = nullptr;
  AvFrameAllocFn av_frame_alloc = nullptr;
  AvFrameFreeFn av_frame_free = nullptr;
  AvFrameUnrefFn av_frame_unref = nullptr;
  AvPacketAllocFn av_packet_alloc = nullptr;
  AvPacketFreeFn av_packet_free = nullptr;
  AvPacketUnrefFn av_packet_unref = nullptr;

  template <typename T>
  static bool loadFunction(HMODULE module, const char *name, T &target) {
    target = reinterpret_cast<T>(GetProcAddress(module, name));
    return target != nullptr;
  }

  bool load() {
    const std::wstring binDir = widenAscii(REASHOOT_FFMPEG_BIN_DIR);
    if (binDir.empty()) {
      return false;
    }
    for (const wchar_t *name : {L"avutil-60.dll", L"swresample-6.dll", L"avcodec-62.dll", L"avformat-62.dll"}) {
      if (!LoadLibraryW((binDir + L"\\" + name).c_str())) {
        return false;
      }
    }
    HMODULE avformat = GetModuleHandleW((binDir + L"\\avformat-62.dll").c_str());
    HMODULE avcodec = GetModuleHandleW((binDir + L"\\avcodec-62.dll").c_str());
    HMODULE avutil = GetModuleHandleW((binDir + L"\\avutil-60.dll").c_str());
    if (!avformat || !avcodec || !avutil) {
      return false;
    }
    return loadFunction(avformat, "avformat_open_input", avformat_open_input) &&
           loadFunction(avformat, "avformat_find_stream_info", avformat_find_stream_info) &&
           loadFunction(avformat, "av_find_best_stream", av_find_best_stream) &&
           loadFunction(avformat, "avformat_close_input", avformat_close_input) &&
           loadFunction(avformat, "av_seek_frame", av_seek_frame) &&
           loadFunction(avformat, "av_read_frame", av_read_frame) &&
           loadFunction(avcodec, "avcodec_alloc_context3", avcodec_alloc_context3) &&
           loadFunction(avcodec, "avcodec_parameters_to_context", avcodec_parameters_to_context) &&
           loadFunction(avcodec, "avcodec_open2", avcodec_open2) &&
           loadFunction(avcodec, "avcodec_send_packet", avcodec_send_packet) &&
           loadFunction(avcodec, "avcodec_receive_frame", avcodec_receive_frame) &&
           loadFunction(avcodec, "avcodec_flush_buffers", avcodec_flush_buffers) &&
           loadFunction(avcodec, "avcodec_free_context", avcodec_free_context) &&
           loadFunction(avcodec, "av_packet_alloc", av_packet_alloc) &&
           loadFunction(avcodec, "av_packet_free", av_packet_free) &&
           loadFunction(avcodec, "av_packet_unref", av_packet_unref) &&
           loadFunction(avutil, "av_frame_alloc", av_frame_alloc) &&
           loadFunction(avutil, "av_frame_free", av_frame_free) &&
           loadFunction(avutil, "av_frame_unref", av_frame_unref);
  }
};

FFmpegPlaybackApi *ffmpegPlaybackApi() {
  static FFmpegPlaybackApi api;
  static const bool loaded = api.load();
  return loaded ? &api : nullptr;
}

class FFmpegPlaybackPreview final : public core::PlaybackPreview {
public:
  explicit FFmpegPlaybackPreview(core::VideoFrameCallback frameHandler)
      : frameHandler_(std::move(frameHandler)), api_(ffmpegPlaybackApi()) {
    if (api_) {
      worker_ = std::thread([this]() { workerLoop(); });
      ready_ = true;
    }
  }

  ~FFmpegPlaybackPreview() override {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      stopped_ = true;
      hasPendingRequest_ = false;
    }
    cv_.notify_all();
    if (worker_.joinable()) {
      worker_.join();
    }
    close();
  }

  bool ready() const { return ready_; }

  void showMedia(const std::string &path, double itemStart, double sourceOffset, double projectPosition) override {
    if (!ready_ || path.empty() || !frameHandler_) {
      return;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    pendingRequest_ = {path, itemStart, sourceOffset, projectPosition, ++latestRequestSerial_};
    hasPendingRequest_ = true;
    hidden_ = false;
    cv_.notify_one();
  }

  void hide() override {
    std::lock_guard<std::mutex> lock(mutex_);
    hidden_ = true;
    hasPendingRequest_ = false;
  }

private:
  struct PlaybackRequest {
    std::string path;
    double itemStart = 0.0;
    double sourceOffset = 0.0;
    double projectPosition = 0.0;
    uint64_t serial = 0;
  };

  void workerLoop() {
    while (true) {
      PlaybackRequest request;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this]() { return stopped_ || hasPendingRequest_; });
        if (stopped_) {
          return;
        }
        request = std::move(pendingRequest_);
        hasPendingRequest_ = false;
      }
      renderRequest(request);
    }
  }

  void close() {
    if (!api_) {
      return;
    }
    if (packet_) {
      api_->av_packet_free(&packet_);
    }
    if (frame_) {
      api_->av_frame_free(&frame_);
    }
    if (codecContext_) {
      api_->avcodec_free_context(&codecContext_);
    }
    if (formatContext_) {
      api_->avformat_close_input(&formatContext_);
    }
    videoStreamIndex_ = -1;
    lastRenderedSourceTime_ = -1.0;
    lastDecoderSourceTime_ = -1.0;
    activePath_.clear();
  }

  bool open(const std::string &path) {
    close();
    if (!api_ || api_->avformat_open_input(&formatContext_, path.c_str(), nullptr, nullptr) < 0 || !formatContext_) {
      return false;
    }
    if (api_->avformat_find_stream_info(formatContext_, nullptr) < 0) {
      close();
      return false;
    }
    const AVCodec *codec = nullptr;
    videoStreamIndex_ = api_->av_find_best_stream(formatContext_, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (videoStreamIndex_ < 0 || !codec) {
      close();
      return false;
    }
    AVStream *stream = formatContext_->streams[videoStreamIndex_];
    codecContext_ = api_->avcodec_alloc_context3(codec);
    frame_ = api_->av_frame_alloc();
    packet_ = api_->av_packet_alloc();
    if (!codecContext_ || !frame_ || !packet_ ||
        api_->avcodec_parameters_to_context(codecContext_, stream->codecpar) < 0) {
      close();
      return false;
    }
    codecContext_->thread_count = 0;
    codecContext_->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
    codecContext_->skip_loop_filter = AVDISCARD_NONREF;
    if (api_->avcodec_open2(codecContext_, codec, nullptr) < 0) {
      close();
      return false;
    }
    activePath_ = path;
    lastRenderedSourceTime_ = -1.0;
    lastDecoderSourceTime_ = -1.0;
    streamStartTime_ = stream->start_time == AV_NOPTS_VALUE ? 0 : stream->start_time;
    return true;
  }

  void renderRequest(const PlaybackRequest &request) {
    if (request.path.empty()) {
      return;
    }
    const bool switchedSource = request.path != activePath_ || !formatContext_;
    if (switchedSource && !open(request.path)) {
      return;
    }
    const double sourceTime = (std::max)(0.0, request.projectPosition - request.itemStart + request.sourceOffset);
    if (!switchedSource && lastRenderedSourceTime_ >= 0.0 &&
        std::fabs(sourceTime - lastRenderedSourceTime_) < (1.0 / 30.0)) {
      return;
    }
    activeRequestSerial_ = request.serial;
    if (renderAt(sourceTime)) {
      lastRenderedSourceTime_ = sourceTime;
    }
  }

  bool seekTo(double sourceTime) {
    if (!formatContext_ || videoStreamIndex_ < 0) {
      return false;
    }
    AVStream *stream = formatContext_->streams[videoStreamIndex_];
    const int64_t timestamp = streamStartTime_ + static_cast<int64_t>(sourceTime * static_cast<double>(stream->time_base.den) /
                                                                      static_cast<double>(stream->time_base.num));
    if (api_->av_seek_frame(formatContext_, videoStreamIndex_, timestamp, AVSEEK_FLAG_BACKWARD) < 0) {
      ++failedSeeks_;
      return false;
    }
    ++seeks_;
    api_->avcodec_flush_buffers(codecContext_);
    lastDecoderSourceTime_ = -1.0;
    return true;
  }

  bool renderAt(double sourceTime) {
    const auto started = std::chrono::steady_clock::now();
    const bool needsSeek = lastDecoderSourceTime_ < 0.0 ||
                           sourceTime < lastDecoderSourceTime_ - 0.10 ||
                           sourceTime > lastDecoderSourceTime_ + 0.75;
    if (needsSeek && !seekTo(sourceTime)) {
      return false;
    }
    for (int packets = 0; packets < 80; ++packets) {
      const int readResult = api_->av_read_frame(formatContext_, packet_);
      if (readResult < 0) {
        ++readFailures_;
        return false;
      }
      if (packet_->stream_index != videoStreamIndex_) {
        api_->av_packet_unref(packet_);
        continue;
      }
      const int sendResult = api_->avcodec_send_packet(codecContext_, packet_);
      api_->av_packet_unref(packet_);
      if (sendResult < 0 && sendResult != AVERROR(EAGAIN)) {
        ++sendFailures_;
        return false;
      }
      while (true) {
        const int receiveResult = api_->avcodec_receive_frame(codecContext_, frame_);
        if (receiveResult == AVERROR(EAGAIN) || receiveResult == AVERROR_EOF) {
          break;
        }
        if (receiveResult < 0) {
          ++receiveFailures_;
          return false;
        }
        ++decodedFrames_;
        const double frameTime = frameSourceTime();
        lastDecoderSourceTime_ = frameTime;
        if (frameTime + (1.0 / 30.0) >= sourceTime) {
          const bool emitted = emitFrame(sourceTime, frameTime, started);
          api_->av_frame_unref(frame_);
          return emitted;
        }
        api_->av_frame_unref(frame_);
      }
    }
    return false;
  }

  double frameSourceTime() const {
    if (!formatContext_ || videoStreamIndex_ < 0 || frame_->best_effort_timestamp == AV_NOPTS_VALUE) {
      return lastDecoderSourceTime_ < 0.0 ? 0.0 : lastDecoderSourceTime_;
    }
    const AVStream *stream = formatContext_->streams[videoStreamIndex_];
    return static_cast<double>(frame_->best_effort_timestamp - streamStartTime_) *
           static_cast<double>(stream->time_base.num) /
           static_cast<double>(stream->time_base.den);
  }

  bool emitFrame(double requestedSourceTime, double frameTime, std::chrono::steady_clock::time_point renderStarted) {
    if (!frameHandler_ || frame_->format != AV_PIX_FMT_YUV420P || !frame_->data[0] || !frame_->data[1] || !frame_->data[2]) {
      ++emitFailures_;
      return false;
    }
    const int sourceWidth = frame_->width;
    const int sourceHeight = frame_->height;
    const double scale = (std::min)(1.0, 640.0 / static_cast<double>((std::max)(sourceWidth, sourceHeight)));
    core::VideoFrame output;
    output.width = (std::max)(1, static_cast<int>(std::round(sourceWidth * scale)));
    output.height = (std::max)(1, static_cast<int>(std::round(sourceHeight * scale)));
    output.strideBytes = output.width * 4;
    output.pixels.resize(static_cast<size_t>(output.strideBytes) * static_cast<size_t>(output.height));
    convertYUV420PToBGRA(frame_, output);
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (hidden_ || activeRequestSerial_ != latestRequestSerial_) {
        ++droppedStaleFrames_;
        return false;
      }
    }
    ++emittedFrames_;
    const auto now = std::chrono::steady_clock::now();
    if (lastLog_.time_since_epoch().count() == 0 || now - lastLog_ >= std::chrono::seconds(1)) {
      lastLog_ = now;
      std::ostringstream stream;
      stream << "ffmpeg playback stats req=" << requestedSourceTime
             << " frame=" << frameTime
             << " render_ms=" << std::chrono::duration<double, std::milli>(now - renderStarted).count()
             << " decoded=" << decodedFrames_
             << " emitted=" << emittedFrames_
             << " stale_drop=" << droppedStaleFrames_
             << " seeks=" << seeks_
             << " failures=" << (failedSeeks_ + readFailures_ + sendFailures_ + receiveFailures_ + emitFailures_);
      playbackDebugLog(stream.str());
    }
    frameHandler_(output);
    return true;
  }

  std::mutex mutex_;
  std::condition_variable cv_;
  std::thread worker_;
  PlaybackRequest pendingRequest_;
  uint64_t latestRequestSerial_ = 0;
  uint64_t activeRequestSerial_ = 0;
  bool hasPendingRequest_ = false;
  bool stopped_ = false;
  bool hidden_ = false;
  bool ready_ = false;
  core::VideoFrameCallback frameHandler_;
  FFmpegPlaybackApi *api_ = nullptr;
  AVFormatContext *formatContext_ = nullptr;
  AVCodecContext *codecContext_ = nullptr;
  AVFrame *frame_ = nullptr;
  AVPacket *packet_ = nullptr;
  int videoStreamIndex_ = -1;
  int64_t streamStartTime_ = 0;
  std::string activePath_;
  double lastRenderedSourceTime_ = -1.0;
  double lastDecoderSourceTime_ = -1.0;
  std::chrono::steady_clock::time_point lastLog_;
  uint64_t decodedFrames_ = 0;
  uint64_t emittedFrames_ = 0;
  uint64_t droppedStaleFrames_ = 0;
  uint64_t seeks_ = 0;
  uint64_t failedSeeks_ = 0;
  uint64_t readFailures_ = 0;
  uint64_t sendFailures_ = 0;
  uint64_t receiveFailures_ = 0;
  uint64_t emitFailures_ = 0;
};

} // namespace

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler) {
  auto ffmpegPreview = std::make_unique<FFmpegPlaybackPreview>(frameHandler);
  return ffmpegPreview;
}

} // namespace reashoot::platform::win32
