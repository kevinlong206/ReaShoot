#include "win32_playback_preview_renderer.h"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include "../ffmpeg/ffmpeg_playback_preview.h"

#include <filesystem>
#include <fstream>
#include <memory>
#include <string>
#include <utility>

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

std::wstring widenAscii(const char *value) {
  return wideFromUtf8(value ? value : "");
}

template <typename T>
bool loadFunction(HMODULE module, const char *name, T &target) {
  target = reinterpret_cast<T>(GetProcAddress(module, name));
  return target != nullptr;
}

bool loadWindowsFFmpegApi(reashoot::platform::ffmpeg::FFmpegPlaybackApi &api) {
  const std::wstring binDir = widenAscii(REASHOOT_FFMPEG_BIN_DIR);
  if (binDir.empty()) {
    playbackDebugLog("ffmpeg playback unavailable: missing REASHOOT_FFMPEG_BIN_DIR");
    return false;
  }
  for (const wchar_t *name : {L"avutil-60.dll", L"swresample-6.dll", L"avcodec-62.dll", L"avformat-62.dll"}) {
    if (!LoadLibraryW((binDir + L"\\" + name).c_str())) {
      playbackDebugLog("ffmpeg playback unavailable: failed to load dependency dll");
      return false;
    }
  }
  HMODULE avformat = GetModuleHandleW((binDir + L"\\avformat-62.dll").c_str());
  HMODULE avcodec = GetModuleHandleW((binDir + L"\\avcodec-62.dll").c_str());
  HMODULE avutil = GetModuleHandleW((binDir + L"\\avutil-60.dll").c_str());
  if (!avformat || !avcodec || !avutil) {
    playbackDebugLog("ffmpeg playback unavailable: required modules not loaded");
    return false;
  }
  const bool loaded =
      loadFunction(avformat, "avformat_open_input", api.avformat_open_input) &&
      loadFunction(avformat, "avformat_find_stream_info", api.avformat_find_stream_info) &&
      loadFunction(avformat, "av_find_best_stream", api.av_find_best_stream) &&
      loadFunction(avformat, "avformat_close_input", api.avformat_close_input) &&
      loadFunction(avformat, "av_seek_frame", api.av_seek_frame) &&
      loadFunction(avformat, "av_read_frame", api.av_read_frame) &&
      loadFunction(avcodec, "avcodec_alloc_context3", api.avcodec_alloc_context3) &&
      loadFunction(avcodec, "avcodec_parameters_to_context", api.avcodec_parameters_to_context) &&
      loadFunction(avcodec, "avcodec_open2", api.avcodec_open2) &&
      loadFunction(avcodec, "avcodec_send_packet", api.avcodec_send_packet) &&
      loadFunction(avcodec, "avcodec_receive_frame", api.avcodec_receive_frame) &&
      loadFunction(avcodec, "avcodec_get_hw_config", api.avcodec_get_hw_config) &&
      loadFunction(avcodec, "avcodec_flush_buffers", api.avcodec_flush_buffers) &&
      loadFunction(avcodec, "avcodec_free_context", api.avcodec_free_context) &&
      loadFunction(avcodec, "av_packet_alloc", api.av_packet_alloc) &&
      loadFunction(avcodec, "av_packet_free", api.av_packet_free) &&
      loadFunction(avcodec, "av_packet_unref", api.av_packet_unref) &&
      loadFunction(avutil, "av_frame_alloc", api.av_frame_alloc) &&
      loadFunction(avutil, "av_frame_free", api.av_frame_free) &&
      loadFunction(avutil, "av_frame_unref", api.av_frame_unref) &&
      loadFunction(avutil, "av_dict_get", api.av_dict_get) &&
      loadFunction(avutil, "av_display_rotation_get", api.av_display_rotation_get) &&
      loadFunction(avutil, "av_hwdevice_ctx_create", api.av_hwdevice_ctx_create) &&
      loadFunction(avutil, "av_hwframe_transfer_data", api.av_hwframe_transfer_data) &&
      loadFunction(avutil, "av_buffer_ref", api.av_buffer_ref) &&
      loadFunction(avutil, "av_buffer_unref", api.av_buffer_unref);
  if (!loaded || !api.valid()) {
    playbackDebugLog("ffmpeg playback unavailable: required symbols not loaded");
    return false;
  }
  return true;
}

reashoot::platform::ffmpeg::FFmpegPlaybackApi *ffmpegPlaybackApi() {
  static reashoot::platform::ffmpeg::FFmpegPlaybackApi api;
  static const bool loaded = loadWindowsFFmpegApi(api);
  return loaded ? &api : nullptr;
}

} // namespace

std::unique_ptr<core::PlaybackPreview> createPlaybackPreview(core::VideoFrameCallback frameHandler) {
  return reashoot::platform::ffmpeg::createPlaybackPreview(std::move(frameHandler),
                                                           ffmpegPlaybackApi(),
                                                           reashoot::platform::ffmpeg::PlaybackOptions{},
                                                           playbackDebugLog);
}

} // namespace reashoot::platform::win32
