# Repository Guide for Copilot Agents

## Project

This repository contains a macOS-only native REAPER extension plus its companion iPhone camera app.

- The REAPER extension is implemented in Objective-C++ with the REAPER Extension SDK, AVFoundation, Cocoa, and LiveKit WebRTC.
- The companion iPhone app lives in `iphone/` and records full-quality iPhone video while REAPER controls it over local Wi-Fi.
- `~/iphone_reapervideosync` was the old development copy and has been moved to Trash. Do not use or recreate it; `reaper_video_recorder/iphone` is the source of truth.

## Important files

- `src/reaper_video_recorder.mm` - Main extension implementation, including REAPER action registration, docked preview UI, AVFoundation capture, media insertion, playback preview, camera selection, and post-record audio alignment.
- `helper/` - Bundled Swift helper package. Builds `video-sync-mac`, shares protocol types with the iPhone app, and fetches/copies `LiveKitWebRTC.framework` for the REAPER plugin.
- `iphone/` - Consolidated iPhone app project and Swift package.
- `iphone/Sources/iPhoneVideoSyncKit/` - iOS capture, preview, WebSocket control, HTTP transfer, pairing, and WebRTC sender.
- `iphone/Sources/VideoSyncCore/ControlProtocol.swift` and `helper/Sources/VideoSyncCore/ControlProtocol.swift` - Protocol definitions; keep these in sync when adding commands/events.
- `Info.plist` - Bundle metadata plus macOS camera/microphone and Continuity Camera usage keys.
- `Makefile` - Builds and installs `reaper_video_recorder.dylib`, `video-sync-mac`, and `LiveKitWebRTC.framework`.
- `README.md` - User-facing install and behavior notes.

## REAPER build and install

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make install
codesign --force --sign - "$HOME/Library/Application Support/REAPER/UserPlugins/LiveKitWebRTC.framework"
codesign --force --sign - "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/LiveKitWebRTC.framework"
```

REAPER must be restarted after installing a new dylib or framework.

The `GIT_CONFIG_*` variables avoid SwiftPM failures caused by Git's `safe.bareRepository` default when resolving cached binary dependencies.

## iPhone app build, install, and launch

Run iPhone commands from `iphone/`:

```sh
cd iphone
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project iPhoneVideoSync.xcodeproj \
  -scheme iPhoneVideoSync \
  -destination 'platform=iOS,id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  -quiet build

xcrun devicectl device install app \
  --device 797DC5E5-610E-5972-9FD3-B0045CA5745F \
  "$HOME/Library/Developer/Xcode/DerivedData/iPhoneVideoSync-gmnikqkhnsosqigkbkagydpehvji/Build/Products/Debug-iphoneos/iPhoneVideoSync.app"

xcrun devicectl device process launch \
  --device 797DC5E5-610E-5972-9FD3-B0045CA5745F \
  com.kevinlong.iphonevideosync
```

If DerivedData changes, compute the app path with `xcodebuild -showBuildSettings` instead of hard-coding it.

## Current behavior

- Registers actions:
  - `Video Recorder: Enable/Disable video features`
  - `Video Recorder: Show/Hide Preview`
  - `Video Recorder: Float/Dock Preview`
  - `Video Recorder: Align Selected Video Item`
  - `Video Recorder: Enable/Disable Transport Follow`
- The user has a main-toolbar button wired to `_KLONG_VIDEO_RECORDER_ENABLE` in `~/Library/Application Support/REAPER/reaper-menu.ini`.
- Video features are off by default. Enabling video shows the floating preview by default and creates/reuses a `Video Recorder` track.
- The `Video Recorder` track is forced to REAPER record-disabled state: unarmed, no input, record mode `none`, monitoring off, item monitoring off, and auto-recarm off.
- The preview has a camera selector, a format diagnostics dropdown, and a format/status area below the video. The diagnostics dropdown shows 4K30/1080p30 availability and every format AVFoundation exposes for the selected camera. The format label shows active resolution, FPS, codec/source format, and whether 4K30/1080p30/highest fallback was selected. Format/status text turns red while recording.
- For `iPhone Video Sync`, REAPER controls the companion iPhone app over WebSocket port `8787`, downloads recordings over HTTP port `8788`, and uses authenticated preview endpoints/control messages.
- The helper `stop --progress` command emits `progress bytes=... total=... percent=...` lines while downloading; REAPER parses these live and shows transfer progress in the dock status label.
- REAPER's iPhone stop flow uses helper `stop-only`, prompts for Download vs Delete, then calls either `download-recording --progress` or confirmed `delete-recording`. Canceling delete confirmation downloads instead.
- After the helper verifies checksum and sends `transferComplete`, the iPhone app deletes the transferred local `.mov` immediately.
- iPhone preview attempts WebRTC first using `LiveKitWebRTC.framework` and a docked `LKRTCMTLVideoView`. If WebRTC fails, REAPER falls back to `/preview.bin` binary JPEG streaming, then snapshot fallback if needed.
- WebRTC signaling uses the existing authenticated control WebSocket. REAPER sends a receive-only offer, the iPhone returns an answer, REAPER strips inline iPhone ICE candidates before `setRemoteDescription`, adds them separately, and trickles Mac ICE candidates back with `addWebRTCIceCandidate`.
- The iPhone app UI has a `Preview` row showing `Idle`, `WebRTC`, or `WebRTC failed`.
- The iPhone capture profile includes resolution, FPS, orientation, aspect, lens, and zoom. Lens availability is hardware-dependent; zoom is clamped by AVFoundation and is not guaranteed optical for every value.
- On session creation the extension prefers 4K30, falls back to stable 1080p30, then the highest available 30 fps device format. It reapplies the requested format after the session starts because some capture sessions can reset device timing.
- AVFoundation records a single `.mov` with video and camera audio embedded. The extension inserts only one media item on the `Video Recorder` track.
- The docked preview uses an `AVPlayerLayer` for video playback preview but mutes that internal player so audio is heard only through REAPER. Avoid aggressive per-timer exact seeking; the player should seek on source changes/playback start and only correct larger drift.
- After inserting the movie item, the extension tries to auto-align it to the first non-video track item that overlaps the video item using peak-envelope correlation.

## Design constraints and preferences

- Keep the implementation native; do not move camera capture into JSFX, VST3, or Lua.
- Preserve the single-item model: one recorded `.mov` item with embedded camera audio. Do not add a separate reference-audio item unless the user explicitly asks.
- Keep routine status in the preview UI, not REAPER popups. Use REAPER message boxes only for real errors.
- Avoid enabling REAPER audio recording on the `Video Recorder` track.
- Be careful editing `~/Library/Application Support/REAPER/reaper-menu.ini`; preserve user toolbar config and avoid duplicate toolbar entries.
- Keep the iPhone app and REAPER helper protocol definitions aligned. Prefer copying shared protocol/CLI changes both ways or extracting a single shared package before adding divergent behavior.
- Do not commit iPhone pairing tokens, downloaded `.mov` files, `test-downloads`, DerivedData, `.DS_Store`, or Xcode `xcuserdata`.
- The manually generated iPhone Xcode project is fragile; make surgical project-file edits and validate with `xcodebuild`.

## Useful smoke tests

Control ping using the installed helper:

```sh
TOKEN="$(awk -F= '/^iphone_token=/{print $2}' "$HOME/Library/Application Support/REAPER/reaper-extstate.ini" | tail -1)"
"$HOME/Library/Application Support/REAPER/UserPlugins/video-sync-mac" \
  ping --host kevin-long-iphone.local --port 8787 --token "$TOKEN"
```

Preview endpoint check:

```sh
curl -sS --max-time 2 "http://kevin-long-iphone.local:8788/preview.bin?token=$TOKEN" -o /tmp/preview.bin || true
python3 - <<'PY'
from pathlib import Path
data = Path('/tmp/preview.bin').read_bytes()
print(len(data), int.from_bytes(data[:4], 'big') if len(data) >= 4 else None, data[4:6].hex() if len(data) >= 6 else '')
PY
rm -f /tmp/preview.bin
```

Expected binary preview output includes a nonzero byte count and JPEG magic `ffd8`.

## Known follow-up areas

- Automatic audio alignment is a first pass. It searches +/-5 seconds around expected placement and requires enough shared sound between the camera audio and a reference REAPER audio item. If alignment is unreliable, improve reference-track selection and correlation diagnostics before changing placement heuristics.
- Capture quality is automatically selected, but not yet user-selectable. A likely next step is adding a quality selector such as `Auto`, `4K 30`, `1080p 30`, and `Highest`.
- WebRTC preview currently works on the tested LAN setup, but keep `/preview.bin` fallback intact. If WebRTC regresses, inspect offer/answer and ICE handling before changing capture settings.
- Continuity Camera may not expose 4K, vertical formats, or codec controls on all macOS/iPhone combinations. Always show the actual active format rather than assuming the requested format was applied.
- A direct AVFoundation probe on this machine found the connected iPhone Continuity Camera exposed only `640x480`, `1280x720`, `1920x1080`, and `1920x1440` in `420v`; no 4K or portrait iPhone formats were exposed. The built-in FaceTime camera did expose portrait-ish formats such as `1080x1920`.
- A recorded file at `~/Desktop/ReaperMedia/Video Recordings/unsaved_project_20260627_162649.mov` inspected with `ffprobe` was healthy: `1920x1080` H.264 Main, ~29.99/30 fps, steady decoded 33.34 ms frame cadence, ~23.7 Mbps video, and AAC mono 48 kHz audio. If playback looks jumpy in the extension but fine in VLC, suspect docked preview playback/resync behavior before changing capture settings.
- The preview `AVPlayer` should remain muted and should not exact-seek every timer tick. Current behavior seeks on source changes/playback start, disables stalling waits, and corrects only large drift.
- Real-time waveform drawing during capture is not implemented. With the current `AVCaptureMovieFileOutput` path, REAPER sees the media only after AVFoundation finalizes the movie.

## Commit style

Use concise commit messages. Include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
