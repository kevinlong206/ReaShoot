# REAPER Video Recorder

macOS-only REAPER extension MVP for recording one webcam/video source in sync with REAPER transport.

## MVP behavior

- Adds REAPER actions:
  - `Video Recorder: Enable/Disable video features`
  - `Video Recorder: Show/Hide Preview`
  - `Video Recorder: Enable/Disable Transport Follow`
- Adds a main-toolbar toggle button for enabling/disabling all video behavior.
- Shows a native macOS live preview window using AVFoundation.
- Shows the active capture format below the preview, including resolution, frame rate, and codec/source format, and turns the status text red while recording.
- Provides a camera selector for available macOS video inputs, including Continuity Camera when macOS exposes it.
- Provides a format diagnostics dropdown showing whether 4K30 and 1080p30 are available plus every format AVFoundation exposes for the selected camera.
- Automatically requests a stable capture format, preferring 4K30, then 1080p30, then the highest exposed 30 fps camera format.
- Records camera audio into the `.mov` alongside video so the inserted item contains an alignment reference.
- Starts video recording when REAPER enters record.
- Stops video recording when REAPER leaves record.
- Keeps video behavior disabled by default until the toolbar/action toggle is enabled.
- Creates the `Video Recorder` track as soon as video features are enabled, before the first recording finishes.
- Keeps REAPER audio recording disabled on the `Video Recorder` track; camera audio stays embedded in the recorded movie item.
- Shows the preview in REAPER's docker.
- Shows recorded video playback in the same preview panel when REAPER plays over an item on the `Video Recorder` track.
- Mutes the docked preview's internal player so playback audio comes only from REAPER.
- Lets the docked playback player run smoothly and only re-seeks on source changes, playback start, or larger drift.
- Inserts the finalized `.mov` onto a `Video Recorder` track at the record-start timeline position.
- After insertion, compares the movie's embedded camera audio against overlapping non-video REAPER items and shifts the video item to the strongest correlation match.
- Shows load/record/finalize/import state in the preview status label instead of console chatter.
- Places recorded video using AVFoundation's actual recording-start callback to compensate for capture startup latency.

## Build

```sh
make
```

By default the Makefile builds for the current Mac architecture. To build a universal binary:

```sh
make ARCH_FLAGS="-arch arm64 -arch x86_64"
```

## Install

```sh
make install
```

Restart REAPER, then open the Action List and search for `Video Recorder`.

If macOS blocks the dylib during local development:

```sh
xattr -dr com.apple.quarantine "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
codesign --force --sign - "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
```

## Notes

- REAPER remains responsible for production audio recording and mixing; camera audio is captured as a sync/alignment reference.
- Camera and microphone permission are requested the first time the preview/session is opened.
- Selected camera input is persisted in REAPER ext state.
- Captures are written under `Video Recordings` in the saved project directory, or under REAPER's resource path for unsaved projects.
- The extension has been observed with an iPhone Continuity Camera exposing only up to `1920x1440` / `1920x1080`; no 4K or true vertical iPhone formats were exposed by AVFoundation in that session.
- A tested recording inspected with `ffprobe` was `1920x1080` H.264 at a stable ~30 fps and ~24 Mbps, so laggy motion in the docked preview can be a preview playback issue rather than a bad recording.
- The docked playback preview intentionally avoids frequent exact seeks; it may drift slightly before correcting, but this keeps AVPlayer playback smooth.
- True real-time waveform drawing during capture is not implemented because `AVCaptureMovieFileOutput` finalizes the movie only after recording stops.
