# Repository Guide for Copilot Agents

## Project

This branch contains ReaShoot as a standalone desktop app plus its companion iPhone camera app. The product direction is no longer REAPER-first: `ReaShoot.app` is the primary macOS target, and the existing native REAPER extension is legacy/secondary.

- The macOS desktop app currently uses native Cocoa/Objective-C++; the Windows desktop app uses native Win32 (Windows SDK). Keep both thin over shared C++ workflow code. Native Win32 (not WinUI 3/Qt/.NET) is the Windows UI direction: it links the shared C++ core directly and needs no external runtime, maximizing compatibility. Both frontends sit over the same shared controller/state layer.
- The iPhone app lives in `iphone/` and records full-quality iPhone video while the desktop app controls it over the local Wi-Fi/Bonjour network.
- The desktop app controls the iPhone over WebSocket port `8787`, downloads recordings over HTTP port `8788`, and receives preview video over an authenticated H.264 WebSocket stream on port `8789`.
- `ReaShoot.app` is also the integration hub. Other apps should use its local desktop API instead of duplicating iPhone discovery, pairing, control, preview, download, or transfer-acknowledgement logic.
- Keep desktop workflow logic cross-platform-friendly so future Windows desktop support can reuse protocol, discovery, control, preview transport, download, stored-recording management, and capture-profile behavior.
- The REAPER extension remains in the repo for legacy users as a thin client of the desktop app's local API. Keep it buildable where practical, but do not put iPhone discovery, pairing, setup, preview, recording ownership, downloads, deletes, or transfer acknowledgement back behind REAPER APIs or SWELL controls.
- `iphone/` is the source of truth for the iPhone app; do not recreate old external development copies.

## Important files

- `src/app/mac/` - Standalone macOS desktop app bundle sources. Keep AppKit/SwiftUI files focused on native controls, layout, windows, menus, and rendering.
- `src/app/mac/ReaShootMacIntegrationServer.*` - macOS loopback HTTP/SSE server for the desktop integration API.
- `src/app/win32/` - Standalone Windows desktop app (`ReaShoot.exe`, native Win32). `ReaShootDesktopWin32.cpp` is the app/UI + main-thread dispatch; `ReaShootWin32Support.*` holds registry settings, folder picker, reveal-in-Explorer, and string helpers. Keep it thin over `src/desktop`/`src/core`.
- `src/desktop/` - Desktop workflow/state/view-model helpers shared by standalone app frontends. Cross-platform desktop behavior belongs here unless it is protocol-level core code.
- `src/desktop/desktop_integration_api.*` - Shared `/v1` integration API request/response/status/profile/recording JSON helpers and auth checks.
- `src/core/control_protocol.*` and `iphone/Sources/ReaShootCore/ControlProtocol.swift` - Protocol definitions; keep these compatible when adding commands/events.
- `src/core/` - Shared C++ protocol, parsing, capture-profile, H.264, status, and controller code.
- `src/helper/` - C++ helper executable. Builds `reashoot-mac` on macOS and `reashoot-win.exe` on Windows for iPhone discovery/control/download. The macOS desktop app bundles this helper.
- `src/platform/mac/` - macOS adapters for helper execution, preview stream transport, H.264 preview decode, prompts, media reading, and legacy extension support.
- `src/platform/win32/` - Windows adapters (helper process, preview stream client, FFmpeg H.264 live-preview decoder) shared by the standalone Windows app and the legacy Windows REAPER extension. Prefer FFmpeg for live preview; do not switch back to Media Foundation.
- `src/platform/ffmpeg/` - Shared FFmpeg recorded-file playback preview used by legacy playback surfaces.
- `src/reashoot.mm`, `src/platform/win32/reaper_reashoot_win32.cpp`, `src/reaper/`, `src/platform/swell/` - REAPER extension integration surfaces. Keep them thin over the desktop local API; do not add new REAPER-hosted camera setup/preview/phone-management UI.
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

## Windows desktop app build

The standalone Windows app is native Win32 (`ReaShoot.exe`, target `reashoot_desktop_win32`, enabled by default). Live preview needs the Gyan shared FFmpeg build (`winget install Gyan.FFmpeg.Shared`, auto-detected) or `REASHOOT_FFMPEG_ROOT`.

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target reashoot_desktop_win32
.\build\Release\ReaShoot.exe
```

`reashoot-win.exe` and the FFmpeg DLLs are staged next to `ReaShoot.exe`. Settings live in `HKCU\Software\ReaShoot`; `-debug` logs to `%LOCALAPPDATA%\ReaShoot\ReaShoot-debug.log` (tokens redacted). Windows discovery fans the mDNS query out every up interface (`GetAdaptersAddresses` + `IP_MULTICAST_IF`); keep that, since a single default-NIC send fails on multi-homed machines.

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

- `ReaShoot.app` provides a native macOS window with live preview, host discovery/manual entry, request-based pairing, capture settings, consolidated start/stop recording control, a `Videos on iPhone` manager, and download destination selection.
- Standalone desktop windows stay always-on-top by default so they remain visible while driving REAPER or other apps; keep the setup option that lets users disable this.
- Discovery should be prominent, with manual host/IP fallback.
- Pairing is request-based: desktop clients send `pair` with `metadata.clientName`, the iPhone asks `Accept pairing request from <clientName>`, and accepting replaces the single stored paired computer/token.
- Downloads default to `~/Movies/ReaShoot` and should be user-changeable.
- Stop flow should remain safe: send `stop-only`, show Download/Delete/Cancel, prepare/download only after Download, and acknowledge transfer only after verifying the downloaded file.
- Failed/canceled downloads remain on the phone because the Mac only sends transfer acknowledgement after verifying the downloaded file. Use `Videos on iPhone` to download or delete stored phone videos.
- The desktop app exposes a loopback-only `/v1` HTTP JSON API plus Server-Sent Events at `/v1/events`. It registers `host`, `port`, `baseUrl`, and bearer `token` in `~/Library/Application Support/ReaShoot/desktop-api.json` with owner-only permissions.
- The helper supports desktop API client commands including `desktop-status`, `desktop-profile`, `desktop-set-profile`, `desktop-preview-start`, `desktop-preview-stop`, `desktop-start-recording`, `desktop-stop-recording`, `desktop-stop-recording-download`, `desktop-refresh-recordings`, `desktop-list-recordings`, `desktop-download-recording`, and `desktop-delete-recording`.
- The first desktop milestone reveals downloaded files in Finder; a local recordings library/player is deferred.
- Pairing tokens are credentials. Do not write them into docs or source, and do not commit them.

## iPhone protocol and preview behavior

- The iPhone app advertises `_reashoot._tcp` with Bonjour.
- The iPhone app records a single `.mov` with video and camera audio embedded.
- The current preview implementation uses a dedicated authenticated binary WebSocket carrying H.264 Annex B access units.
- Live preview rotation is intentionally separate from recorded-file rotation in `iphone/Sources/ReaShootKit/CaptureRecordingEngine.swift`. Keep `PreviewFrameStore.normalizedImage` mapping as `landscapeLeft -> .down` and `landscapeRight/landscape -> .up`; do not "fix" it to match `rotationAngle(for:)`, or landscape live preview becomes upside down.
- Auto live-preview orientation uses CoreMotion gravity with short sample-based hysteresis in `CaptureRecordingEngine.swift`; avoid reverting to raw `UIDevice.current.orientation`, which bounces and causes repeated descriptor/keyframe resets.
- The iPhone preview encoder emits `RSDIAG1` diagnostic SEI metadata (sequence and source timestamp). Mac preview logs use this to report connect time, source-to-display latency, receive-to-display latency, and dropped sequence gaps; keep these diagnostics when changing preview transport or decode paths.
- macOS preview decode must not backlog stale frames on the main thread. Keep WebSocket receive/decode off the main run loop, coalesce decoded frames to the latest frame, and let each decoded frame own its draw aspect; descriptor updates must not stretch old-orientation pixels while waiting for the next frame.
- Desktop live preview should default to non-mirrored so it matches the recorded video/REAPER playback. Keep the `Mirror live preview` setup option as an explicit monitoring-only override.
- The helper validates complete WebSocket handshake headers, including `Sec-WebSocket-Accept`; keep the iPhone server response terminated with `\r\n\r\n`.
- The iPhone capture profile includes resolution, FPS, orientation, aspect, lens, zoom, look, and `encodeLookAtRecordTime`. Lens availability is hardware-dependent; zoom is clamped by AVFoundation and is not guaranteed optical for every value.
- Keep `encodeLookAtRecordTime` opt-in/default-off. When true with a non-natural look, the iPhone uses the AVAssetWriter record-time look path and records the selected look as `renderedLook`; otherwise it keeps the AVCaptureMovieFileOutput path and prepares non-natural looks only after Download is chosen.
- Keep the curated raw look lists aligned between legacy desktop UI surfaces and `iphone/Sources/ReaShootKit/CaptureRecordingEngine.swift`; saved removed `ci:` looks should fall back to `natural`.
- The iPhone app UI has a `Preview` row showing idle/streaming/failure state.

## Design constraints and preferences

- Keep the implementation native; do not move iPhone control, preview, media insertion, or downloads into JSFX, VST3, Lua, or a web wrapper.
- Prefer shared code for behavior that should be consistent across macOS and future Windows desktop support. Add platform-specific code only when host APIs, OS services, UI toolkits, or build constraints make sharing impractical.
- Keep desktop app orchestration out of native UI files. Pairing, discovery retry policy, configure-on-profile-change, preview start/stop state, stale-frame empty states, recording start/stop, and iPhone video list/download/delete workflows should live in `src/desktop/` or `src/core/`.
- Native UI/platform files may own layout, colors, menus, alerts, file dialogs, settings storage adapters, main-thread dispatch/timers, thumbnail/image display, and preview renderer/client factories.
- Keep the desktop API local-only by default (`127.0.0.1`). Do not expose iPhone control to the LAN, and do not log the API bearer token or iPhone pairing token.
- Integration clients are clients of `ReaShoot.app`; they must not independently acknowledge iPhone transfers or race the desktop app for recording/download/delete ownership.
- Keep preview transport dependency-light and same-LAN oriented; prefer simple H.264 streaming over heavyweight realtime SDKs unless requirements change.
- Keep routine status in the desktop app UI. Use modal alerts for real decisions and errors.
- Do not commit iPhone pairing tokens, downloaded `.mov` files, `test-downloads`, DerivedData, `.DS_Store`, or Xcode `xcuserdata`.
- The manually generated iPhone Xcode project is fragile; make surgical project-file edits and validate with `xcodebuild`.

## Legacy REAPER extension notes

- The macOS and Windows REAPER extensions are thin desktop API clients. When ReaShoot is enabled in REAPER, transport record start/stop should call `ReaShoot.app` / `ReaShoot.exe` over the loopback desktop API, then insert/synchronize the verified downloaded movie returned by the desktop app.
- The legacy Windows REAPER extension builds with CMake as `reaper_reashoot.dll`.
- Keep legacy extension fixes cross-platform where behavior exists on both macOS and Windows, but do not apply Windows-specific playback workarounds to macOS without Mac-specific evidence.
- Do not restore REAPER-hosted camera preview, setup, pairing, pending-recording restore/delete, or direct iPhone helper-control flows. Users should use the standalone desktop app for those surfaces.
- Avoid enabling REAPER audio recording on the `ReaShoot` track.
- Be careful editing `~/Library/Application Support/REAPER/reaper-menu.ini`; preserve user toolbar config and avoid duplicate toolbar entries.
- Windows live preview should prefer the FFmpeg H.264 decoder path; do not suggest switching live preview back to Media Foundation.
- macOS recorded-file playback preview should use the shared FFmpeg playback path rather than restoring AVFoundation/`AVAssetImageGenerator`.

## Validation

- Run `make check` before committing Swift/protocol/helper changes; it checks mirrored Swift files, runs iPhone Swift tests, and builds the helper.
- `make check` includes a source-level guard for the iPhone live-preview landscape rotation mapping because that regression is easy to reintroduce.
- Build the desktop app with `cmake --build build-desktop --target reashoot_desktop --parallel` after macOS app changes.
- Use helper `ping`, `configure`, start/stop/download, and preview smoke tests after changing WebSocket/control startup behavior. For preview latency/orientation changes, launch the Mac app with `-debug` and check preview logs for connect time, source-to-display latency, dropped sequence gaps, and descriptor flip behavior.

## Commit style

Use concise commit messages. Include:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```
