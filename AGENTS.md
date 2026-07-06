# Repository Guide for Copilot Agents

## Project

This branch contains ReaShoot as a standalone desktop app plus its companion iPhone camera app. The product direction is no longer REAPER-first: `ReaShoot.app` is the primary macOS target, and the existing native REAPER extension is legacy/secondary.

- The macOS desktop app is implemented as native Cocoa/Objective-C++ with a thin UI over shared C++ workflow code.
- The iPhone app lives in `iphone/` and records full-quality iPhone video while the desktop app controls it over the local Wi-Fi/Bonjour network.
- The desktop app controls the iPhone over WebSocket port `8787`, downloads recordings over HTTP port `8788`, and receives preview video over an authenticated H.264 WebSocket stream on port `8789`.
- Keep desktop workflow logic cross-platform-friendly so future Windows desktop support can reuse protocol, discovery, control, preview transport, download, pending-recording, and capture-profile behavior.
- The REAPER extension remains in the repo for legacy users. Keep it buildable where practical, but do not put new standalone desktop behavior behind REAPER APIs, SWELL controls, REAPER transport, track insertion, or audio alignment.
- `iphone/` is the source of truth for the iPhone app; do not recreate old external development copies.

## Important files

- `src/app/mac/` - Standalone macOS desktop app bundle sources.
- `src/desktop/` - Desktop workflow helpers shared by standalone app frontends.
- `src/core/control_protocol.*` and `iphone/Sources/ReaShootCore/ControlProtocol.swift` - Protocol definitions; keep these compatible when adding commands/events.
- `src/core/` - Shared C++ protocol, parsing, capture-profile, H.264, status, and controller code.
- `src/helper/` - C++ helper executable. Builds `reashoot-mac` on macOS and `reashoot-win.exe` on Windows for iPhone discovery/control/download. The macOS desktop app bundles this helper.
- `src/platform/mac/` - macOS adapters for helper execution, preview stream transport, H.264 preview decode, prompts, media reading, and legacy extension support.
- `src/platform/win32/` - Windows adapters; keep future desktop support in mind.
- `src/platform/ffmpeg/` - Shared FFmpeg recorded-file playback preview used by legacy playback surfaces.
- `src/reashoot.mm`, `src/reaper/`, `src/platform/swell/` - Legacy REAPER extension and shared SWELL panel.
- `iphone/` - Consolidated iPhone app project and Swift package.
- `README.md` - User-facing standalone desktop app manual.
- `CONTRIBUTING.md` - Build commands, architecture notes, validation, and legacy target details.

## macOS desktop app build

macOS legacy playback targets require FFmpeg headers/dylibs. Install with Homebrew or set `REASHOOT_FFMPEG_ROOT` to a prefix containing `include/` and `lib/`.

```sh
brew install ffmpeg
cmake -S . -B build-desktop -DCMAKE_BUILD_TYPE=Debug
cmake --build build-desktop --target reashoot_desktop --parallel
open build-desktop/ReaShoot.app
```

The app bundle copies `reashoot-mac` into `ReaShoot.app/Contents/Resources/reashoot-mac`.
When developing pairing, discovery, preview, or window layout, launch with debug logging enabled:

```sh
open build-desktop/ReaShoot.app --args -debug
```

Debug logs are written to stderr and `~/Library/Logs/ReaShoot/ReaShoot-debug.log`; pairing tokens and codes should be redacted in logs.

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

## Current desktop behavior

- `ReaShoot.app` provides a native macOS window with live preview, host discovery/manual entry, pairing, capture settings, start/stop recording controls, pending restore, and download destination selection.
- Discovery should be prominent, with manual host/IP fallback.
- Downloads default to `~/Movies/ReaShoot` and should be user-changeable.
- Stop flow should remain safe: send `stop-only`, show Download/Delete/Cancel, prepare/download only after Download, and acknowledge transfer only after verifying the downloaded file.
- Failed/canceled downloads remain pending on the phone because the Mac only sends transfer acknowledgement after verifying the downloaded file.
- The first desktop milestone reveals downloaded files in Finder; a local recordings library/player is deferred.
- Pairing tokens are credentials. Do not write them into docs or source, and do not commit them.

## iPhone protocol and preview behavior

- The iPhone app advertises `_reashoot._tcp` with Bonjour.
- The iPhone app records a single `.mov` with video and camera audio embedded.
- The current preview implementation uses a dedicated authenticated binary WebSocket carrying H.264 Annex B access units.
- The helper validates complete WebSocket handshake headers, including `Sec-WebSocket-Accept`; keep the iPhone server response terminated with `\r\n\r\n`.
- The iPhone capture profile includes resolution, FPS, orientation, aspect, lens, zoom, and look. Lens availability is hardware-dependent; zoom is clamped by AVFoundation and is not guaranteed optical for every value.
- Keep the curated raw look lists aligned between legacy desktop UI surfaces and `iphone/Sources/ReaShootKit/CaptureRecordingEngine.swift`; saved removed `ci:` looks should fall back to `natural`.
- The iPhone app UI has a `Preview` row showing idle/streaming/failure state.

## Design constraints and preferences

- Keep the implementation native; do not move iPhone control, preview, media insertion, or downloads into JSFX, VST3, Lua, or a web wrapper.
- Prefer shared code for behavior that should be consistent across macOS and future Windows desktop support. Add platform-specific code only when host APIs, OS services, UI toolkits, or build constraints make sharing impractical.
- Keep preview transport dependency-light and same-LAN oriented; prefer simple H.264 streaming over heavyweight realtime SDKs unless requirements change.
- Keep routine status in the desktop app UI. Use modal alerts for real decisions and errors.
- Do not commit iPhone pairing tokens, downloaded `.mov` files, `test-downloads`, DerivedData, `.DS_Store`, or Xcode `xcuserdata`.
- The manually generated iPhone Xcode project is fragile; make surgical project-file edits and validate with `xcodebuild`.

## Legacy REAPER extension notes

- The legacy macOS REAPER extension is implemented in Objective-C++ with the REAPER Extension SDK, AVFoundation/Cocoa for Mac services, a local H.264 preview stream, and shared FFmpeg recorded-file playback preview.
- The legacy Windows REAPER extension builds with CMake as `reaper_reashoot.dll`.
- Keep legacy extension fixes cross-platform where behavior exists on both macOS and Windows, but do not apply Windows-specific playback workarounds to macOS without Mac-specific evidence.
- Keep the REAPER extension GUI defined in the shared SWELL panel (`src/platform/swell/swell_panel_probe.cpp`). Do not add parallel Cocoa or Win32 control trees for legacy preview/setup/status UI.
- Avoid enabling REAPER audio recording on the `ReaShoot` track.
- Be careful editing `~/Library/Application Support/REAPER/reaper-menu.ini`; preserve user toolbar config and avoid duplicate toolbar entries.
- Windows live preview should prefer the FFmpeg H.264 decoder path; do not suggest switching live preview back to Media Foundation.
- macOS recorded-file playback preview should use the shared FFmpeg playback path rather than restoring AVFoundation/`AVAssetImageGenerator`.

## Validation

- Run `make check` before committing Swift/protocol/helper changes; it checks mirrored Swift files, runs iPhone Swift tests, and builds the helper.
- Build the desktop app with `cmake --build build-desktop --target reashoot_desktop --parallel` after macOS app changes.
- Use helper `ping`, `configure`, start/stop/download, and preview smoke tests after changing WebSocket/control startup behavior.

## Commit style

Use concise commit messages. Include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
