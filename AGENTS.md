# Repository Guide for Copilot Agents

## Project

This repository contains ReaPhoneVideo: a macOS-only native REAPER extension plus its companion iPhone camera app.

- The REAPER extension is implemented in Objective-C++ with the REAPER Extension SDK, AVFoundation, Cocoa, and LiveKit WebRTC.
- The companion iPhone app lives in `iphone/` and records full-quality iPhone video while REAPER controls it over the local Wi-Fi/Bonjour network.
- The GitHub repository is named `ReaPhoneVideo`; deeper code/action/bundle renames are intentionally deferred.
- `~/iphone_reapervideosync` was the old development copy and has been moved to Trash. Do not use or recreate it; `reaper_video_recorder/iphone` is the source of truth.

## Important files

- `src/reaper_video_recorder.mm` - Main extension implementation, including REAPER action registration, docked preview UI, iPhone app control, media insertion, playback preview, and post-record audio alignment.
- `helper/` - Bundled Swift helper package. Builds `video-sync-mac`, shares protocol types with the iPhone app, and fetches/copies `LiveKitWebRTC.framework` for the REAPER plugin.
- `iphone/` - Consolidated iPhone app project and Swift package.
- `iphone/Sources/iPhoneVideoSyncKit/` - iOS capture, preview, WebSocket control, HTTP transfer, pairing, and WebRTC sender.
- `iphone/Sources/VideoSyncCore/ControlProtocol.swift` and `helper/Sources/VideoSyncCore/ControlProtocol.swift` - Protocol definitions; keep these in sync when adding commands/events.
- `Info.plist` - Bundle metadata for the REAPER extension.
- `Makefile` - Builds and installs `reaper_video_recorder.dylib`, `video-sync-mac`, and `LiveKitWebRTC.framework`.
- `README.md` - User-facing install and behavior notes.

## REAPER build and install

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make install
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/video-sync-mac"
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

APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Build/Products/*-iphoneos/iPhoneVideoSync.app' -type d -print -quit)"
xcrun devicectl device install app --device 797DC5E5-610E-5972-9FD3-B0045CA5745F "$APP_PATH"

xcrun devicectl device process launch \
  --device 797DC5E5-610E-5972-9FD3-B0045CA5745F \
  com.kevinlong.iphonevideosync
```

If DerivedData changes, compute the app path with `xcodebuild -showBuildSettings` instead of hard-coding it.

After Xcode or SwiftPM builds, remove generated local artifacts unless they are intentional:

```sh
rm -rf iphone/Package.resolved iphone/.build helper/.build
```

## Current behavior

- Registers actions:
  - `Video Recorder: Enable/Disable video features`
  - `Video Recorder: Show/Hide Preview`
  - `Video Recorder: Float/Dock Preview`
  - `Video Recorder: Align Selected Video Item`
  - `Video Recorder: Restore Pending iPhone Recording`
  - `Video Recorder: Delete All Pending iPhone Recordings`
  - `Video Recorder: Enable/Disable Transport Follow`
- The user has a main-toolbar button wired to `_KLONG_VIDEO_RECORDER_ENABLE` in `~/Library/Application Support/REAPER/reaper-menu.ini`.
- Video features are off by default. Enabling video shows the floating preview by default and creates/reuses a `Video Recorder` track.
- The `Video Recorder` track is forced to REAPER record-disabled state: unarmed, no input, record mode `none`, monitoring off, item monitoring off, and auto-recarm off.
- The extension is iPhone-only. The preview has iPhone setup/profile controls and a format/status area below the video. The format label shows the transport (Wi-Fi), resolution, FPS, orientation, aspect, lens, zoom, selected look, and WebRTC preview state. The look row has `Prev`/`Next` buttons for quick auditioning. Format/status text turns red while recording.
- For `iPhone Video Sync`, REAPER controls the companion iPhone app over WebSocket port `8787`, downloads recordings over HTTP port `8788`, and uses authenticated WebRTC control messages for preview, all over the local Wi-Fi network using the host saved from setup/discovery (Bonjour).
- The helper `stop --progress` command emits `encode percent=...` while preparing non-natural looks and `progress bytes=... total=... percent=...` while downloading; REAPER parses these live and shows progress in the dock status label.
- REAPER's iPhone stop flow uses helper `stop-only` to receive raw pending recording metadata immediately, prompts for Download vs Delete before look encoding, then calls either `download-recording --progress` or confirmed `delete-recording`. Canceling delete confirmation downloads instead.
- Failed/canceled downloads remain pending on the phone because the Mac only sends transfer acknowledgement after verifying the downloaded file. The preview window has `Pending...` and `Delete All` buttons. `Pending...` / `Video Recorder: Restore Pending iPhone Recording` calls helper `list-recordings`, prompts for a clip, then can either download/insert with `download-recording --progress` at the current edit cursor or delete the pending recording with `delete-recording`. `Delete All` / `Video Recorder: Delete All Pending iPhone Recordings` lists pending clips, confirms, then deletes them all.
- After the helper verifies checksum and sends `transferComplete`, the iPhone app deletes the transferred local `.mov` immediately.
- iPhone preview uses WebRTC only with `LiveKitWebRTC.framework` and a docked `LKRTCMTLVideoView`; there is no HTTP preview fallback.
- WebRTC signaling uses the existing authenticated control WebSocket. REAPER sends a receive-only offer, the iPhone returns an answer, REAPER strips inline iPhone ICE candidates before `setRemoteDescription`, adds them separately, and trickles Mac ICE candidates back with `addWebRTCIceCandidate`.
- The helper validates complete WebSocket handshake headers, including `Sec-WebSocket-Accept`; keep the iPhone server response terminated with `\r\n\r\n`.
- The iPhone app UI has a `Preview` row showing `Idle`, `WebRTC`, or `WebRTC failed`.
- The iPhone capture profile includes resolution, FPS, orientation, aspect, lens, zoom, and look. The look picker keeps custom looks plus a curated raw Core Image subset, not the full Core Image catalog. Lens availability is hardware-dependent; zoom is clamped by AVFoundation on iPhone and is not guaranteed optical for every value.
- The iPhone app records a single `.mov` with video and camera audio embedded. The extension inserts only one media item on the `Video Recorder` track.
- The docked preview uses an `AVPlayerLayer` for video playback preview but mutes that internal player so audio is heard only through REAPER. Avoid aggressive per-timer exact seeking; the player should seek on source changes/playback start and only correct larger drift.
- After inserting the movie item, the extension tries to auto-align it to the first non-video track item that overlaps the video item using peak-envelope correlation.

## Design constraints and preferences

- Keep the implementation native; do not move iPhone control, preview, or media insertion into JSFX, VST3, or Lua.
- Preserve the single-item model: one recorded `.mov` item with embedded camera audio. Do not add a separate reference-audio item unless the user explicitly asks.
- Keep routine status in the preview UI, not REAPER popups. Use REAPER message boxes only for real errors.
- Avoid enabling REAPER audio recording on the `Video Recorder` track.
- Be careful editing `~/Library/Application Support/REAPER/reaper-menu.ini`; preserve user toolbar config and avoid duplicate toolbar entries.
- Keep the iPhone app and REAPER helper protocol definitions aligned. Prefer copying shared protocol/CLI changes both ways or extracting a single shared package before adding divergent behavior.
- Keep the curated raw look lists aligned between `src/reaper_video_recorder.mm` and `iphone/Sources/iPhoneVideoSyncKit/CaptureRecordingEngine.swift`; saved removed `ci:` looks should fall back to `natural`.
- Do not commit iPhone pairing tokens, downloaded `.mov` files, `test-downloads`, DerivedData, `.DS_Store`, or Xcode `xcuserdata`.
- The manually generated iPhone Xcode project is fragile; make surgical project-file edits and validate with `xcodebuild`.

## Useful smoke tests

Control ping using the installed helper:

```sh
TOKEN="$(awk -F= '/^iphone_token=/{print $2}' "$HOME/Library/Application Support/REAPER/reaper-extstate.ini" | tail -1)"
"$HOME/Library/Application Support/REAPER/UserPlugins/video-sync-mac" \
  ping --host kevin-long-iphone.local --port 8787 --token "$TOKEN"
```

Preview control check:

```sh
"$HOME/Library/Application Support/REAPER/UserPlugins/video-sync-mac" \
  ping --host kevin-long-iphone.local --port 8787 --token "$TOKEN"
```

Expected output is `OK`; WebRTC preview itself is negotiated by REAPER through the control channel.

## Known follow-up areas

- Automatic audio alignment is a first pass. It searches +/-5 seconds around expected placement and requires enough shared sound between the camera audio and a reference REAPER audio item. If alignment is unreliable, improve reference-track selection and correlation diagnostics before changing placement heuristics.
- WebRTC is the only preview path. If preview regresses, inspect offer/answer, ICE handling, and iPhone-side Core Image rendering before changing capture settings.
- A recorded file at `~/Desktop/ReaperMedia/Video Recordings/unsaved_project_20260627_162649.mov` inspected with `ffprobe` was healthy: `1920x1080` H.264 Main, ~29.99/30 fps, steady decoded 33.34 ms frame cadence, ~23.7 Mbps video, and AAC mono 48 kHz audio. If playback looks jumpy in the extension but fine in VLC, suspect docked preview playback/resync behavior before changing capture settings.
- The preview `AVPlayer` should remain muted and should not exact-seek every timer tick. Current behavior seeks on source changes/playback start, disables stalling waits, and corrects only large drift.
- Real-time waveform drawing during capture is not implemented. REAPER sees the media only after the iPhone app finalizes and downloads the movie.

## Validation

- Run `make check` before committing Swift/protocol/helper changes; it checks mirrored Swift files, runs iPhone Swift tests, and builds the helper.
- Use the installed helper `ping` and `configure` smoke tests after changing WebSocket/control startup behavior.

## Commit style

Use concise commit messages. Include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
