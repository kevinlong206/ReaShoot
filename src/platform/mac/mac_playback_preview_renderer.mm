#import "mac_playback_preview_renderer.h"

#include "../ffmpeg/ffmpeg_playback_preview.h"

#import <Foundation/Foundation.h>

#include <memory>
#include <string>
#include <utility>

namespace reashoot::platform::mac {
namespace {

ffmpeg::FFmpegPlaybackApi *macFFmpegPlaybackApi() {
  static ffmpeg::FFmpegPlaybackApi api = {
      avformat_open_input,
      avformat_find_stream_info,
      av_find_best_stream,
      avformat_close_input,
      av_seek_frame,
      av_read_frame,
      avcodec_alloc_context3,
      avcodec_parameters_to_context,
      avcodec_open2,
      avcodec_send_packet,
      avcodec_receive_frame,
      avcodec_flush_buffers,
      avcodec_free_context,
      av_frame_alloc,
      av_frame_free,
      av_frame_unref,
      av_packet_alloc,
      av_packet_free,
      av_packet_unref,
      av_dict_get,
      av_display_rotation_get,
  };
  return api.valid() ? &api : nullptr;
}

void playbackDebugLog(const std::string &message) {
  NSLog(@"ReaShoot: %s", message.c_str());
}

} // namespace

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler) {
  return ffmpeg::createPlaybackPreview(std::move(frameHandler), macFFmpegPlaybackApi(), playbackDebugLog);
}

} // namespace reashoot::platform::mac

