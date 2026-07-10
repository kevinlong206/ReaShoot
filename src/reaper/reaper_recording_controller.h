#pragma once

#include "reaper_host.h"

#include "../core/remote_camera.h"

#include <atomic>
#include <functional>
#include <string>

namespace reashoot::reaper {

// Platform glue the shared recording workflow needs. Everything else (desktop
// API calls, the Download/Delete/Cancel prompt, track creation, and media
// insertion) is shared. Only the hooks below differ between macOS and Windows.
struct RecordingControllerHooks {
  // Runs work on REAPER's main thread. Required.
  std::function<void(std::function<void()>)> postToMain;
  // Shows routine status text (e.g. in the docked panel or status label).
  std::function<void(const std::string &)> setStatus;
  // Shows a modal error message.
  std::function<void(const std::string &)> showError;
  // Reflects the recording visual state (optional).
  std::function<void(bool)> setRecordingActive;
  // Resolves the directory the desktop app should download the take into.
  std::function<std::string(ReaProject *)> resolveDownloadDirectory;
  // Called on the main thread after a video item is inserted. macOS uses this
  // to run audio alignment; Windows leaves it empty.
  std::function<void(ReaProject *, MediaTrack *, MediaItem *)> onInserted;
};

// Cross-platform recording workflow shared by the macOS and Windows REAPER
// extensions. Drives start/stop through the ReaShoot desktop integration API,
// prompts to download or delete the stopped take, and inserts the downloaded
// video on the ReaShoot track. All public methods must be called on REAPER's
// main thread; background work is dispatched back via the postToMain hook.
class RecordingController {
 public:
  explicit RecordingController(RecordingControllerHooks hooks);

  // Launches the ReaShoot desktop app if it is not already running. Call when
  // ReaShoot is enabled in REAPER. Runs asynchronously.
  void ensureDesktopAppRunning();

  // True while a recording start/stop/download cycle is in flight.
  bool isActive() const { return active_.load(); }

  // True while a downloaded take is waiting to be inserted on the next timer tick.
  bool hasPendingInsert() const { return pendingInsert_; }

  // Called when REAPER transport recording starts / stops.
  void begin(ReaProject *project);
  void finish();

  // Call from the main-thread timer to complete any queued media insertion.
  void processPendingInsert();

 private:
  void handleStoppedRecording(ReaProject *project,
                              double insertPosition,
                              const std::string &downloadDirectory,
                              const core::RemoteRecordingDescriptor &recording);
  void downloadAndQueueInsert(ReaProject *project,
                              double insertPosition,
                              const std::string &downloadDirectory,
                              const core::RemoteRecordingDescriptor &recording);
  void deleteStoppedRecording(const core::RemoteRecordingDescriptor &recording);

  RecordingControllerHooks hooks_;

  std::atomic<bool> active_{false};
  bool startInFlight_ = false;
  bool stopRequested_ = false;
  ReaProject *recordProject_ = nullptr;
  double recordStartPosition_ = 0.0;

  bool pendingInsert_ = false;
  std::string pendingInsertPath_;
  double pendingInsertPosition_ = 0.0;
  ReaProject *pendingInsertProject_ = nullptr;
};

} // namespace reashoot::reaper
