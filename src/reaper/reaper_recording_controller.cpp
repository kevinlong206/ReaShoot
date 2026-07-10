#include "reaper_recording_controller.h"

#include "../core/reashoot_status.h"
#include "../desktop/desktop_api_client.h"

#include <exception>
#include <thread>
#include <utility>

namespace reashoot::reaper {
namespace {

std::string friendly(const std::string &message) {
  return core::friendlyStatusText(message);
}

// ShowMessageBox flags/returns follow the Win32 MB_* / ID* conventions.
constexpr int kMessageBoxYesNoCancel = 3;
constexpr int kMessageBoxYes = 6;
constexpr int kMessageBoxNo = 7;

} // namespace

RecordingController::RecordingController(RecordingControllerHooks hooks) : hooks_(std::move(hooks)) {}

void RecordingController::ensureDesktopAppRunning() {
  if (hooks_.setStatus) {
    hooks_.setStatus("Starting the ReaShoot app...");
  }
  std::thread([this]() {
    std::string error;
    try {
      desktop::DesktopApiClient().ensureDesktopAppRunning();
    } catch (const std::exception &e) {
      error = e.what();
    }
    if (!hooks_.postToMain) {
      return;
    }
    hooks_.postToMain([this, error]() {
      if (!hooks_.setStatus) {
        return;
      }
      if (error.empty()) {
        hooks_.setStatus("ReaShoot app is running.");
      } else {
        hooks_.setStatus("ReaShoot app is not running yet. Start it to control the iPhone.");
      }
    });
  }).detach();
}

void RecordingController::begin(ReaProject *project) {
  if (active_.load()) {
    return;
  }
  active_.store(true);
  startInFlight_ = true;
  stopRequested_ = false;
  recordProject_ = project;
  recordStartPosition_ = cursorPosition(project);
  ensureReaShootTrack(project);
  if (hooks_.setRecordingActive) {
    hooks_.setRecordingActive(true);
  }
  if (hooks_.setStatus) {
    hooks_.setStatus("Starting recording through the ReaShoot app...");
  }
  std::thread([this]() {
    std::string error;
    try {
      desktop::DesktopApiClient().startRecording();
    } catch (const std::exception &e) {
      error = e.what();
    }
    if (!hooks_.postToMain) {
      return;
    }
    hooks_.postToMain([this, error]() {
      startInFlight_ = false;
      if (!error.empty()) {
        active_.store(false);
        stopRequested_ = false;
        if (hooks_.setRecordingActive) {
          hooks_.setRecordingActive(false);
        }
        if (hooks_.showError) {
          hooks_.showError(
              "ReaShoot could not start recording. Make sure the ReaShoot desktop app is running and paired with the iPhone.\n\n" +
              friendly(error));
        }
        return;
      }
      if (hooks_.setStatus) {
        hooks_.setStatus("Recording through the ReaShoot app.");
      }
      if (stopRequested_) {
        stopRequested_ = false;
        finish();
      }
    });
  }).detach();
}

void RecordingController::finish() {
  if (!active_.load()) {
    return;
  }
  if (startInFlight_) {
    stopRequested_ = true;
    if (hooks_.setStatus) {
      hooks_.setStatus("Waiting for the ReaShoot app to start recording...");
    }
    return;
  }
  const double insertPosition = recordStartPosition_ < 0.0 ? 0.0 : recordStartPosition_;
  ReaProject *project = recordProject_ ? recordProject_ : currentProject();
  const std::string downloadDirectory =
      hooks_.resolveDownloadDirectory ? hooks_.resolveDownloadDirectory(project) : std::string();
  if (hooks_.setStatus) {
    hooks_.setStatus("Stopping recording through the ReaShoot app...");
  }
  std::thread([this, project, insertPosition, downloadDirectory]() {
    std::string error;
    core::RemoteRecordingDescriptor recording;
    try {
      recording = desktop::DesktopApiClient().stopRecording();
    } catch (const std::exception &e) {
      error = e.what();
    }
    if (!hooks_.postToMain) {
      return;
    }
    hooks_.postToMain([this, project, insertPosition, downloadDirectory, recording, error]() {
      active_.store(false);
      if (hooks_.setRecordingActive) {
        hooks_.setRecordingActive(false);
      }
      if (!error.empty()) {
        if (hooks_.showError) {
          hooks_.showError("ReaShoot could not stop the recording.\n\n" + friendly(error));
        }
        return;
      }
      handleStoppedRecording(project, insertPosition, downloadDirectory, recording);
    });
  }).detach();
}

void RecordingController::handleStoppedRecording(ReaProject *project,
                                                 double insertPosition,
                                                 const std::string &downloadDirectory,
                                                 const core::RemoteRecordingDescriptor &recording) {
  const std::string message = "Download " + recording.filename +
                              " into the REAPER project, or delete it from the iPhone?\n\n"
                              "Yes = Download and insert on the ReaShoot track\n"
                              "No = Delete from the iPhone\n"
                              "Cancel = Leave it on the iPhone";
  const int choice = messageBox(message, "ReaShoot recording stopped", kMessageBoxYesNoCancel);
  if (choice == kMessageBoxYes) {
    downloadAndQueueInsert(project, insertPosition, downloadDirectory, recording);
  } else if (choice == kMessageBoxNo) {
    deleteStoppedRecording(recording);
  } else if (hooks_.setStatus) {
    hooks_.setStatus("Recording left on the iPhone. Use the ReaShoot app to download or delete it.");
  }
}

void RecordingController::downloadAndQueueInsert(ReaProject *project,
                                                 double insertPosition,
                                                 const std::string &downloadDirectory,
                                                 const core::RemoteRecordingDescriptor &recording) {
  if (hooks_.setStatus) {
    hooks_.setStatus("Downloading iPhone video through the ReaShoot app...");
  }
  const std::string recordingID = recording.id;
  std::thread([this, project, insertPosition, downloadDirectory, recordingID]() {
    std::string path;
    std::string error;
    try {
      path = desktop::DesktopApiClient().downloadRecording(recordingID, downloadDirectory, [this](const std::string &line) {
        if (line.empty() || !hooks_.postToMain) {
          return;
        }
        hooks_.postToMain([this, line]() {
          if (hooks_.setStatus) {
            hooks_.setStatus(line);
          }
        });
      });
    } catch (const std::exception &e) {
      error = e.what();
    }
    if (!hooks_.postToMain) {
      return;
    }
    hooks_.postToMain([this, project, insertPosition, path, error]() {
      if (!error.empty()) {
        if (hooks_.showError) {
          hooks_.showError("ReaShoot could not download the recording.\n\n" + friendly(error));
        }
        return;
      }
      if (path.empty()) {
        if (hooks_.showError) {
          hooks_.showError("ReaShoot downloaded the recording, but did not report a local file path.");
        }
        return;
      }
      pendingInsertPath_ = path;
      pendingInsertPosition_ = insertPosition;
      pendingInsertProject_ = project;
      pendingInsert_ = true;
    });
  }).detach();
}

void RecordingController::deleteStoppedRecording(const core::RemoteRecordingDescriptor &recording) {
  if (hooks_.setStatus) {
    hooks_.setStatus("Deleting iPhone recording through the ReaShoot app...");
  }
  const std::string recordingID = recording.id;
  std::thread([this, recordingID]() {
    std::string error;
    try {
      desktop::DesktopApiClient().deleteRecording(recordingID);
    } catch (const std::exception &e) {
      error = e.what();
    }
    if (!hooks_.postToMain) {
      return;
    }
    hooks_.postToMain([this, error]() {
      if (!error.empty()) {
        if (hooks_.showError) {
          hooks_.showError("ReaShoot could not delete the recording.\n\n" + friendly(error));
        }
        return;
      }
      if (hooks_.setStatus) {
        hooks_.setStatus("Recording deleted from the iPhone.");
      }
    });
  }).detach();
}

void RecordingController::processPendingInsert() {
  if (!pendingInsert_) {
    return;
  }
  pendingInsert_ = false;
  ReaProject *project = pendingInsertProject_ ? pendingInsertProject_ : currentProject();
  MediaTrack *track = ensureReaShootTrack(project);
  if (!track) {
    if (hooks_.showError) {
      hooks_.showError("Recording downloaded, but ReaShoot could not create the ReaShoot track.");
    }
    return;
  }
  std::string error;
  MediaItem *item = insertVideoItem(track, pendingInsertPath_, pendingInsertPosition_, error);
  if (!item) {
    if (hooks_.showError) {
      hooks_.showError(error);
    }
    return;
  }
  refreshArrangeTimeline();
  if (hooks_.setStatus) {
    hooks_.setStatus("Inserted iPhone recording on the ReaShoot track.");
  }
  pendingInsertProject_ = nullptr;
  if (hooks_.onInserted) {
    hooks_.onInserted(project, track, item);
  }
}

} // namespace reashoot::reaper
