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
#include <libavutil/dict.h>
#include <libavutil/frame.h>
#include <libavutil/pixfmt.h>
}
#endif

#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdlib>
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

// The docked/floating preview is small, and playback frames are converted from
// YUV to BGRA and rotated on the CPU on every timer tick. Rendering a full
// 1080p (or larger) frame took 30-40 ms each, which dropped effective playback
// to ~7 fps and made it look choppy compared with REAPER's own video window.
// Capping the longest edge keeps per-frame render time well under the ~33 ms
// frame budget so playback stays smooth.
constexpr double kPlaybackPreviewMaxDimension = 960.0;

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
  using AvDictGetFn = AVDictionaryEntry *(*)(const AVDictionary *, const char *, const AVDictionaryEntry *, int);
  using AvDisplayRotationGetFn = double (*)(const int32_t *);

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
  AvDictGetFn av_dict_get = nullptr;
  AvDisplayRotationGetFn av_display_rotation_get = nullptr;

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
           loadFunction(avutil, "av_frame_unref", av_frame_unref) &&
           loadFunction(avutil, "av_dict_get", av_dict_get) &&
           loadFunction(avutil, "av_display_rotation_get", av_display_rotation_get);
  }
};

FFmpegPlaybackApi *ffmpegPlaybackApi() {
  static FFmpegPlaybackApi api;
  static const bool loaded = api.load();
  return loaded ? &api : nullptr;
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
  return rotated;
}

class FFmpegPlaybackPreview final : public core::PlaybackPreview {
public:
  explicit FFmpegPlaybackPreview(core::VideoFrameCallback frameHandler)
      : frameHandler_(std::move(frameHandler)), api_(ffmpegPlaybackApi()) {
    if (api_) {
      worker_ = std::thread([this]() { workerLoop(); });
      ready_ = true;
      playbackDebugLog("ffmpeg playback renderer ready");
    } else {
      playbackDebugLog("ffmpeg playback renderer unavailable: api not loaded");
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
    rotationDegrees_ = 0;
    soughtSinceOpen_ = false;
    activePath_.clear();
  }

  int rotationForStream(const AVStream *stream) const {
    if (!stream || !api_) {
      return 0;
    }
    const AVCodecParameters *parameters = stream->codecpar;
    if (parameters && parameters->coded_side_data && parameters->nb_coded_side_data > 0 && api_->av_display_rotation_get) {
      for (int i = 0; i < parameters->nb_coded_side_data; ++i) {
        const AVPacketSideData &sideData = parameters->coded_side_data[i];
        if (sideData.type == AV_PKT_DATA_DISPLAYMATRIX && sideData.data && sideData.size >= sizeof(int32_t) * 9) {
          return normalizeRotationDegrees(api_->av_display_rotation_get(reinterpret_cast<const int32_t *>(sideData.data)));
        }
      }
    }
    if (api_->av_dict_get) {
      if (const AVDictionaryEntry *entry = api_->av_dict_get(stream->metadata, "rotate", nullptr, 0)) {
        if (entry->value) {
          return normalizeRotationDegrees(std::strtod(entry->value, nullptr));
        }
      }
    }
    return 0;
  }

  bool open(const std::string &path) {
    close();
    playbackDebugLog("ffmpeg playback open path=" + path);
    if (!api_ || api_->avformat_open_input(&formatContext_, path.c_str(), nullptr, nullptr) < 0 || !formatContext_) {
      playbackDebugLog("ffmpeg playback open failed path=" + path);
      return false;
    }
    if (api_->avformat_find_stream_info(formatContext_, nullptr) < 0) {
      playbackDebugLog("ffmpeg playback stream info failed path=" + path);
      close();
      return false;
    }
    const AVCodec *codec = nullptr;
    videoStreamIndex_ = api_->av_find_best_stream(formatContext_, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (videoStreamIndex_ < 0 || !codec) {
      playbackDebugLog("ffmpeg playback video stream not found path=" + path);
      close();
      return false;
    }
    AVStream *stream = formatContext_->streams[videoStreamIndex_];
    codecContext_ = api_->avcodec_alloc_context3(codec);
    frame_ = api_->av_frame_alloc();
    packet_ = api_->av_packet_alloc();
    if (!codecContext_ || !frame_ || !packet_ ||
        api_->avcodec_parameters_to_context(codecContext_, stream->codecpar) < 0) {
      playbackDebugLog("ffmpeg playback codec setup failed path=" + path);
      close();
      return false;
    }
    // Use frame + slice threading for throughput. Frame threading delays first
    // output by ~thread_count frames; that previously starved the decoder when
    // combined with an 80-packet budget on this audio-heavy file (only ~19 video
    // packets/call). The 200-packet budget in renderAt now delivers ~47 video
    // packets per call, well above libavcodec's H.264 frame-thread cap (16), so
    // the decoder primes on the first call and then streams at full throughput
    // (~10 ms/frame vs ~28 ms/frame slice-only). The higher throughput lets 4K
    // decode keep up with real time instead of falling permanently behind.
    codecContext_->thread_count = 0;
    codecContext_->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
    if (api_->avcodec_open2(codecContext_, codec, nullptr) < 0) {
      playbackDebugLog("ffmpeg playback codec open failed path=" + path);
      close();
      return false;
    }
    activePath_ = path;
    lastRenderedSourceTime_ = -1.0;
    lastDecoderSourceTime_ = -1.0;
    streamStartTime_ = stream->start_time == AV_NOPTS_VALUE ? 0 : stream->start_time;
    rotationDegrees_ = rotationForStream(stream);
    if (rotationDegrees_ != 0) {
      std::ostringstream log;
      log << "ffmpeg playback rotation=" << rotationDegrees_;
      playbackDebugLog(log.str());
    }
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
    soughtSinceOpen_ = true;
    return true;
  }

  bool renderAt(double sourceTime) {
    const auto started = std::chrono::steady_clock::now();
    // With frame threading the decoder needs several packets after a flush
    // before it emits its first frame. Only seek when we truly must (never
    // positioned since open, sought backward, or fell far behind). Critically,
    // once we have sought we must NOT re-seek merely because we have not decoded
    // a frame yet, or we would flush the priming pipeline every tick and never
    // produce output (the original "nothing plays" bug).
    const bool haveDecoded = lastDecoderSourceTime_ >= 0.0;
    const bool needsSeek = (!haveDecoded && !soughtSinceOpen_) ||
                           (haveDecoded && (sourceTime < lastDecoderSourceTime_ - 0.10 ||
                                            sourceTime > lastDecoderSourceTime_ + 0.75));
    if (needsSeek && !seekTo(sourceTime)) {
      return false;
    }
    // Budget is generous because the recorded .mov is heavily audio-interleaved
    // (roughly 3 audio packets per video packet); a smaller budget can starve
    // the decoder of the video packets it needs to prime after a flush.
    for (int packets = 0; packets < 200; ++packets) {
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
    const double scale = (std::min)(1.0, kPlaybackPreviewMaxDimension / static_cast<double>((std::max)(sourceWidth, sourceHeight)));
    core::VideoFrame unrotated;
    unrotated.width = (std::max)(1, static_cast<int>(std::round(sourceWidth * scale)));
    unrotated.height = (std::max)(1, static_cast<int>(std::round(sourceHeight * scale)));
    unrotated.strideBytes = unrotated.width * 4;
    unrotated.pixels.resize(static_cast<size_t>(unrotated.strideBytes) * static_cast<size_t>(unrotated.height));
    convertYUV420PToBGRA(frame_, unrotated);
    core::VideoFrame output = rotateBGRAFrame(unrotated, rotationDegrees_);
    {
      std::lock_guard<std::mutex> lock(mutex_);
      // Only drop the frame if playback has been hidden. During continuous
      // playback the worker always renders the newest pending request, so a
      // request that arrived mid-render is only ~1 tick ahead; dropping it here
      // (as the old serial check did) threw away ~75% of decoded frames and
      // made playback choppy. Showing this frame and correcting on the next
      // tick keeps the effective frame rate high.
      if (hidden_) {
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
             << " rotation=" << rotationDegrees_
             << " output=" << output.width << "x" << output.height
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
  bool soughtSinceOpen_ = false;
  int rotationDegrees_ = 0;
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
