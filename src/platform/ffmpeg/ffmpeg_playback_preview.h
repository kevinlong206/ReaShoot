#pragma once

#include "../../core/ui_interfaces.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/buffer.h>
#include <libavutil/dict.h>
#include <libavutil/display.h>
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixfmt.h>
}

#include <functional>
#include <memory>
#include <string>

namespace reashoot::platform::ffmpeg {

struct FFmpegPlaybackApi {
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
  using AvCodecGetHwConfigFn = const AVCodecHWConfig *(*)(const AVCodec *, int);
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
  using AvHwDeviceCtxCreateFn = int (*)(AVBufferRef **, AVHWDeviceType, const char *, AVDictionary *, int);
  using AvHwFrameTransferDataFn = int (*)(AVFrame *, const AVFrame *, int);
  using AvBufferRefFn = AVBufferRef *(*)(const AVBufferRef *);
  using AvBufferUnrefFn = void (*)(AVBufferRef **);

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
  AvCodecGetHwConfigFn avcodec_get_hw_config = nullptr;
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
  AvHwDeviceCtxCreateFn av_hwdevice_ctx_create = nullptr;
  AvHwFrameTransferDataFn av_hwframe_transfer_data = nullptr;
  AvBufferRefFn av_buffer_ref = nullptr;
  AvBufferUnrefFn av_buffer_unref = nullptr;

  bool valid() const;
};

using PlaybackLogCallback = std::function<void(const std::string &)>;

struct PlaybackOptions {
  AVHWDeviceType hardwareDeviceType = AV_HWDEVICE_TYPE_NONE;
  std::string hardwareDeviceName;
};

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler,
                                                             FFmpegPlaybackApi *api,
                                                             PlaybackOptions options,
                                                             PlaybackLogCallback log);

} // namespace reashoot::platform::ffmpeg
