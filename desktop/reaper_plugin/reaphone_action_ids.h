#pragma once

namespace reaphone::actions {

inline constexpr const char *kVideoEnabledId = "KLONG_VIDEO_RECORDER_ENABLE";
inline constexpr const char *kVideoEnabledName = "Video Recorder: Enable/Disable video features";

inline constexpr const char *kShowPreviewId = "KLONG_VIDEO_RECORDER_SHOW_PREVIEW";
inline constexpr const char *kShowPreviewName = "Video Recorder: Show/Hide Preview";

inline constexpr const char *kFloatPreviewId = "KLONG_VIDEO_RECORDER_FLOAT_PREVIEW";
inline constexpr const char *kFloatPreviewName = "Video Recorder: Float/Dock Preview";

inline constexpr const char *kAlignSelectedId = "KLONG_VIDEO_RECORDER_ALIGN_SELECTED";
inline constexpr const char *kAlignSelectedName = "Video Recorder: Align Selected Video Item";

inline constexpr const char *kRestoreIPhoneId = "KLONG_VIDEO_RECORDER_RESTORE_IPHONE";
inline constexpr const char *kRestoreIPhoneName = "Video Recorder: Restore Pending iPhone Recording";

inline constexpr const char *kDeleteAllIPhoneId = "KLONG_VIDEO_RECORDER_DELETE_ALL_IPHONE";
inline constexpr const char *kDeleteAllIPhoneName = "Video Recorder: Delete All Pending iPhone Recordings";

inline constexpr const char *kToggleFollowId = "KLONG_VIDEO_RECORDER_TOGGLE_FOLLOW";
inline constexpr const char *kToggleFollowName = "Video Recorder: Enable/Disable Transport Follow";

inline constexpr const char *kWindowsDiagnosticId = "KLONG_REAPHONEVIDEO_WINDOWS_DIAGNOSTIC";
inline constexpr const char *kWindowsDiagnosticName = "ReaPhoneVideo: Windows Port Diagnostic";

inline constexpr const char *kPairId = "KLONG_REAPHONEVIDEO_PAIR";
inline constexpr const char *kPairName = "ReaPhoneVideo: Pair iPhone (uses saved pairing code)";

inline constexpr const char *kTestConnectionId = "KLONG_REAPHONEVIDEO_TEST_CONNECTION";
inline constexpr const char *kTestConnectionName = "ReaPhoneVideo: Test iPhone Connection";

inline constexpr const char *kStartRecordingId = "KLONG_REAPHONEVIDEO_START_RECORDING";
inline constexpr const char *kStartRecordingName = "ReaPhoneVideo: Start iPhone Recording";

inline constexpr const char *kStopRecordingId = "KLONG_REAPHONEVIDEO_STOP_RECORDING";
inline constexpr const char *kStopRecordingName = "ReaPhoneVideo: Stop iPhone Recording and Download";

} // namespace reaphone::actions
