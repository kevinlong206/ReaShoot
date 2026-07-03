#pragma once

#include <functional>
#include <string>

namespace reashoot::core {

struct ReaShootPanelState {
  std::string statusText;
  std::string formatText;
  bool recording = false;
  bool playbackVisible = false;
  bool previewVisible = true;
};

struct ReaShootPanelSettings {
  std::string host;
  std::string token;
  std::string pairingCode;
  std::string resolution;
  std::string fps;
  std::string orientation;
  std::string aspect;
  std::string lens;
  std::string zoom;
  std::string look;
};

struct ReaShootPanelActions {
  std::function<void()> setup;
  std::function<void()> discover;
  std::function<void()> pair;
  std::function<void()> testConnection;
  std::function<void()> restorePending;
  std::function<void()> deleteAllPending;
  std::function<void(int)> selectRelativeLook;
  std::function<void()> settingsChanged;
};

enum class PendingRecordingAction {
  Cancel,
  Download,
  Delete,
};

struct PendingRecordingChoice {
  PendingRecordingAction action = PendingRecordingAction::Cancel;
  std::string recordingID;
};

using NativeDockHandle = void *;

class ReaShootPanel {
public:
  virtual ~ReaShootPanel() = default;
  virtual NativeDockHandle nativeDockHandle() const = 0;
  virtual ReaShootPanelSettings settings() const = 0;
  virtual void setSettings(const ReaShootPanelSettings &settings) = 0;
  virtual void setState(const ReaShootPanelState &state) = 0;
};

class PlaybackPreview {
public:
  virtual ~PlaybackPreview() = default;
  virtual void showMedia(const std::string &path, double itemStart, double sourceOffset, double projectPosition) = 0;
  virtual void hide() = 0;
};

} // namespace reashoot::core
