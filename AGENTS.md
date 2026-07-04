# Repository Guide for Copilot Agents

## Project

This repository contains ReaShoot: a native REAPER extension plus its companion iPhone camera app.

- The macOS REAPER extension is implemented in Objective-C++ with the REAPER Extension SDK, AVFoundation, Cocoa, and a local H.264 preview stream.
- The Windows REAPER extension builds with CMake as `reaper_reashoot.dll`; it currently includes the helper, shared setup/status panel, pairing/configure/start/stop/download flow, pending recording restore/delete, FFmpeg-based H.264 live/playback preview, and media insertion.
- The companion iPhone app lives in `iphone/` and records full-quality iPhone video while REAPER controls it over the local Wi-Fi/Bonjour network.
- `iphone/` is the source of truth for the iPhone app; do not recreate old external development copies.

## Important files

- `src/reashoot.mm` - Main extension implementation, including REAPER action registration, docked preview UI, iPhone app control, media insertion, playback preview, and post-record audio alignment.
- `src/helper/` - Bundled C++ helper executable. Builds `reashoot-mac` on macOS and `reashoot-win.exe` on Windows for REAPER-side iPhone control, discovery, and media download.
- `iphone/` - Consolidated iPhone app project and Swift package.
- `iphone/Sources/ReaShootKit/` - iOS capture, H.264 preview streaming, WebSocket control, HTTP transfer, and pairing.
- `src/core/control_protocol.*` and `iphone/Sources/ReaShootCore/ControlProtocol.swift` - Protocol definitions; keep these compatible when adding commands/events.
- `Info.plist` - Bundle metadata for the REAPER extension.
- `Makefile` - Builds and installs `reaper_reashoot.dylib` and `reashoot-mac`.
- `README.md` - User-facing install and behavior notes.

## REAPER build and install

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make install
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reashoot-mac"
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_reashoot.dylib"
```

REAPER must be restarted after installing a new dylib.

The `GIT_CONFIG_*` variables avoid SwiftPM failures caused by Git's `safe.bareRepository` default.

## iPhone app build, install, and launch

Run iPhone commands from `iphone/`:

```sh
cd iphone
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project ReaShoot.xcodeproj \
  -scheme ReaShoot \
  -destination 'platform=iOS,id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  -quiet build

APP_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*Build/Products/*-iphoneos/ReaShoot.app' -type d -print -quit)"
xcrun devicectl device install app --device 797DC5E5-610E-5972-9FD3-B0045CA5745F "$APP_PATH"

xcrun devicectl device process launch \
  --device 797DC5E5-610E-5972-9FD3-B0045CA5745F \
  com.kevinlong.reashoot
```

If DerivedData changes, compute the app path with `xcodebuild -showBuildSettings` instead of hard-coding it.

After Xcode or SwiftPM builds, remove generated local artifacts unless they are intentional:

```sh
rm -rf iphone/Package.resolved iphone/.build helper/.build
```

## Current behavior

- Registers actions:
  - `ReaShoot: Enable ReaShoot`
  - `ReaShoot: Float/Dock Preview`
  - `ReaShoot: Align Selected Video Item`
  - `ReaShoot: Restore Pending iPhone Recording`
  - `ReaShoot: Delete All Pending iPhone Recordings`
  - `ReaShoot: Enable/Disable Transport Follow`
- The user has a main-toolbar button wired to `_KLONG_REASHOOT_ENABLE` in `~/Library/Application Support/REAPER/reaper-menu.ini`.
- Video features are off by default. Enabling video shows the floating preview by default and creates/reuses a `ReaShoot` track.
- The `ReaShoot` track is forced to REAPER record-disabled state: unarmed, no input, record mode `none`, monitoring off, item monitoring off, and auto-recarm off.
- The extension is iPhone-only. The preview has iPhone setup/profile controls and a format/status area below the video. The format label shows the transport (Wi-Fi), resolution, FPS, orientation, aspect, lens, zoom, selected look, and preview state. The look row has `Prev`/`Next` buttons for quick auditioning. Format/status text turns red while recording.
- For `ReaShoot`, REAPER controls the companion iPhone app over WebSocket port `8787`, downloads recordings over HTTP port `8788`, and receives preview video over an authenticated H.264 WebSocket stream on port `8789`, all over the local Wi-Fi network using the host saved from setup/discovery (Bonjour).
- The helper `stop --progress` command emits `encode percent=...` while preparing non-natural looks and `progress bytes=... total=... percent=...` while downloading; REAPER parses these live and shows progress in the dock status label.
- REAPER's iPhone stop flow uses helper `stop-only` to receive raw pending recording metadata immediately, prompts for Download vs Delete before look encoding, then calls either `download-recording --progress` or confirmed `delete-recording`. Canceling delete confirmation downloads instead.
- Failed/canceled downloads remain pending on the phone because the Mac only sends transfer acknowledgement after verifying the downloaded file. The preview window has `Pending...` and `Delete All` buttons. `Pending...` / `ReaShoot: Restore Pending iPhone Recording` calls helper `list-recordings`, prompts for a clip, then can either download/insert with `download-recording --progress` at the current edit cursor or delete the pending recording with `delete-recording`. `Delete All` / `ReaShoot: Delete All Pending iPhone Recordings` lists pending clips, confirms, then deletes them all.
- After the helper verifies checksum and sends `transferComplete`, the iPhone app deletes the transferred local `.mov` immediately.
- The current iPhone preview implementation uses a dedicated authenticated binary WebSocket carrying H.264 Annex B access units.
- The helper validates complete WebSocket handshake headers, including `Sec-WebSocket-Accept`; keep the iPhone server response terminated with `\r\n\r\n`.
- The iPhone app UI has a `Preview` row showing idle/streaming/failure state.
- The iPhone capture profile includes resolution, FPS, orientation, aspect, lens, zoom, and look. The look picker keeps custom looks plus a curated raw Core Image subset, not the full Core Image catalog. Lens availability is hardware-dependent; zoom is clamped by AVFoundation on iPhone and is not guaranteed optical for every value.
- The iPhone app records a single `.mov` with video and camera audio embedded. The extension inserts only one media item on the `ReaShoot` track.
- The docked preview uses an `AVPlayerLayer` for video playback preview but mutes that internal player so audio is heard only through REAPER. Avoid aggressive per-timer exact seeking; the player should seek on source changes/playback start and only correct larger drift.
- After inserting the movie item, the extension tries to auto-align it to the first non-video track item that overlaps the video item using peak-envelope correlation.

## Design constraints and preferences

- Keep the implementation native; do not move iPhone control, preview, or media insertion into JSFX, VST3, or Lua.
- Keep the preview transport dependency-light and same-LAN oriented; prefer simple H.264 streaming over heavyweight realtime SDKs unless requirements change.
- Windows live preview should prefer the FFmpeg H.264 decoder path; do not suggest switching live preview back to Media Foundation to fix orientation or restart issues, because Media Foundation had other regressions.
- Windows preview ownership is a single explicit `PreviewMode { Idle, Live, Playback }` state machine in `reaper_reashoot_win32.cpp` (`setPreviewMode`, `showingPlayback`). Every panel paint is gated on it: live H.264 frames paint only in `Live`, downloaded-file playback frames only in `Playback`. When entering playback, DO NOT tear down the live stream and DO NOT re-issue `configure`/`start-preview` on transport stop — leave the live stream connected and just switch which source paints. Restarting live preview per play/stop is what caused the panel to blink and churn (`start-preview` fired hundreds of times).
- Windows playback preview (`win32_playback_preview_renderer.cpp`) decodes recorded `.mov` files with FFmpeg. Recorded clips are heavily audio-interleaved (~3 audio packets per video packet), so `renderAt` must read a generous packet budget (200) to feed the decoder enough VIDEO packets. Keep the decoder on slice+frame threading (`FF_THREAD_FRAME | FF_THREAD_SLICE`, `thread_count=0`); frame threading is required for throughput so 4K decode keeps up with real time. Never re-seek/flush just because no frame has decoded yet (`soughtSinceOpen_` guard) — that flushed the frame-threading pipeline before it could prime and produced ZERO frames ("nothing plays").
- Windows preview panel repaints (`setSwellPanelPreviewFrame`) invalidate ONLY the video region below the controls (via `kPreviewControlsHeight`), not the whole client. Invalidating the full panel every frame made the docked panel's child controls flicker at playback frame rate. Keep this region-limited invalidate.
- Avoid per-timer-tick panel churn on Windows: `setPanelStatus` skips redundant updates, because `updateSwellPanelProbe` re-sets label text, syncs setup fields, and invalidates the panel — calling it every tick (e.g. during playback) flickers the docked panel.
- Preserve the single-item model: one recorded `.mov` item with embedded camera audio. Do not add a separate reference-audio item unless the user explicitly asks.
- Keep routine status in the preview UI, not REAPER popups. Use REAPER message boxes only for real errors.
- Keep the REAPER extension GUI defined in the shared SWELL panel (`src/platform/swell/swell_panel_probe.cpp`). Do not add parallel Cocoa or Win32 control trees for preview/setup/status UI; platform files should only adapt SWELL, preview decoding, helper execution, prompts, and REAPER host glue.
- Avoid enabling REAPER audio recording on the `ReaShoot` track.
- Be careful editing `~/Library/Application Support/REAPER/reaper-menu.ini`; preserve user toolbar config and avoid duplicate toolbar entries.
- Keep the iPhone app and REAPER helper protocol definitions aligned. Prefer copying shared protocol/CLI changes both ways or extracting a single shared package before adding divergent behavior.
- Keep the curated raw look lists aligned between `src/reashoot.mm` and `iphone/Sources/ReaShootKit/CaptureRecordingEngine.swift`; saved removed `ci:` looks should fall back to `natural`.
- Do not commit iPhone pairing tokens, downloaded `.mov` files, `test-downloads`, DerivedData, `.DS_Store`, or Xcode `xcuserdata`.
- The manually generated iPhone Xcode project is fragile; make surgical project-file edits and validate with `xcodebuild`.

## Useful smoke tests

Control ping using the installed helper:

```sh
TOKEN="$(awk -F= '/^iphone_token=/{print $2}' "$HOME/Library/Application Support/REAPER/reaper-extstate.ini" | tail -1)"
"$HOME/Library/Application Support/REAPER/UserPlugins/reashoot-mac" \
  ping --host kevin-long-iphone.local --port 8787 --token "$TOKEN"
```

Preview control check:

```sh
"$HOME/Library/Application Support/REAPER/UserPlugins/reashoot-mac" \
  ping --host kevin-long-iphone.local --port 8787 --token "$TOKEN"
```

Expected output is `OK`; preview is started by REAPER through the control channel and streamed on the preview socket.

## Known follow-up areas

- Automatic audio alignment is a first pass. It searches +/-5 seconds around expected placement and requires enough shared sound between the camera audio and a reference REAPER audio item. If alignment is unreliable, improve reference-track selection and correlation diagnostics before changing placement heuristics.
- If the current H.264 preview regresses, inspect preview-stream connection, SPS/PPS/keyframe handling, and iPhone-side Core Image rendering before changing capture settings.
- A recorded file at `~/Desktop/ReaperMedia/Video Recordings/unsaved_project_20260627_162649.mov` inspected with `ffprobe` was healthy: `1920x1080` H.264 Main, ~29.99/30 fps, steady decoded 33.34 ms frame cadence, ~23.7 Mbps video, and AAC mono 48 kHz audio. If playback looks jumpy in the extension but fine in VLC, suspect docked preview playback/resync behavior before changing capture settings.
- The preview `AVPlayer` should remain muted and should not exact-seek every timer tick. Current behavior seeks on source changes/playback start, disables stalling waits, and corrects only large drift.
- Real-time waveform drawing during capture is not implemented. REAPER sees the media only after the iPhone app finalizes and downloads the movie.
- Windows downloads go under REAPER's default recording path (`defrecpath` from REAPER.ini via `reashoot::reaper::defaultRecordingPath()`), not the OneDrive project folder. macOS `captureOutputPath` prefers the same. The helper verifies downloads with a streaming SHA-256 (`src/helper/checksum.cpp`) — do not reintroduce whole-file/stack-buffer hashing (it caused a stack-overflow crash on large 4K files).
- Windows playback preview is driven by the REAPER extension timer (~20-30 Hz), so effective playback frame rate is timer-bound (~20 fps) even though decode is fast. If silky 30 fps playback is needed later, decouple the playback renderer from the timer with its own decode/present clock rather than tuning seek/threading again.

## Validation

- Run `make check` before committing Swift/protocol/helper changes; it checks mirrored Swift files, runs iPhone Swift tests, and builds the helper.
- Use the installed helper `ping` and `configure` smoke tests after changing WebSocket/control startup behavior.

## Commit style

Use concise commit messages. Include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
