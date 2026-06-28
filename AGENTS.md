# Repository Guide for Copilot Agents

## Project

This repository contains a macOS-only native REAPER extension for recording one camera source directly into REAPER. The extension is implemented in Objective-C++ with the REAPER Extension SDK and AVFoundation.

## Important files

- `src/reaper_video_recorder.mm` - Main extension implementation, including REAPER action registration, docked preview UI, AVFoundation capture, media insertion, playback preview, camera selection, and post-record audio alignment.
- `Info.plist` - Bundle metadata plus macOS camera/microphone and Continuity Camera usage keys.
- `Makefile` - Builds and installs `reaper_video_recorder.dylib`.
- `README.md` - User-facing install and behavior notes.

## Build and install

```sh
make clean
make install
codesign --force --sign - "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
```

REAPER must be restarted after installing a new dylib.

## Current behavior

- Registers actions:
  - `Video Recorder: Enable/Disable video features`
  - `Video Recorder: Show/Hide Preview`
  - `Video Recorder: Enable/Disable Transport Follow`
- The user has a main-toolbar button wired to `_KLONG_VIDEO_RECORDER_ENABLE` in `~/Library/Application Support/REAPER/reaper-menu.ini`.
- Video features are off by default. Enabling video shows the docked preview and creates/reuses a `Video Recorder` track.
- The `Video Recorder` track is forced to REAPER record-disabled state: unarmed, no input, record mode `none`, monitoring off, item monitoring off, and auto-recarm off.
- The preview has a camera selector, a format diagnostics dropdown, and a format/status area below the video. The diagnostics dropdown shows 4K30/1080p30 availability and every format AVFoundation exposes for the selected camera. The format label shows active resolution, FPS, codec/source format, and whether 4K30/1080p30/highest fallback was selected. Format/status text turns red while recording.
- On session creation the extension prefers 4K30, falls back to stable 1080p30, then the highest available 30 fps device format. It reapplies the requested format after the session starts because some capture sessions can reset device timing.
- AVFoundation records a single `.mov` with video and camera audio embedded. The extension inserts only one media item on the `Video Recorder` track.
- The docked preview uses an `AVPlayerLayer` for video playback preview but mutes that internal player so audio is heard only through REAPER. Avoid aggressive per-timer exact seeking; the player should seek on source changes/playback start and only correct larger drift.
- After inserting the movie item, the extension tries to auto-align it to other overlapping non-video REAPER audio items using low-resolution peak-envelope correlation.

## Design constraints and preferences

- Keep the implementation native; do not move camera capture into JSFX, VST3, or Lua.
- Preserve the single-item model: one recorded `.mov` item with embedded camera audio. Do not add a separate reference-audio item unless the user explicitly asks.
- Keep routine status in the preview UI, not REAPER popups. Use REAPER message boxes only for real errors.
- Avoid enabling REAPER audio recording on the `Video Recorder` track.
- Be careful editing `~/Library/Application Support/REAPER/reaper-menu.ini`; preserve user toolbar config and avoid duplicate toolbar entries.

## Known follow-up areas

- Automatic audio alignment is a first pass. It searches +/-5 seconds around expected placement and requires enough shared sound between the camera audio and a reference REAPER audio item. If alignment is unreliable, improve reference-track selection and correlation diagnostics before changing placement heuristics.
- Capture quality is automatically selected, but not yet user-selectable. A likely next step is adding a quality selector such as `Auto`, `4K 30`, `1080p 30`, and `Highest`.
- Continuity Camera may not expose 4K or codec controls on all macOS/iPhone combinations. Always show the actual active format rather than assuming the requested format was applied.
- Real-time waveform drawing during capture is not implemented. With the current `AVCaptureMovieFileOutput` path, REAPER sees the media only after AVFoundation finalizes the movie.

## Commit style

Use concise commit messages. Include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
