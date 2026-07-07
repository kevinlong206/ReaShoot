# Contributing to ReaShoot

Pull requests are welcome and will be reviewed as time permits. Bug reports, crashes, confusing workflows, and feature requests should be filed as [GitHub issues](https://github.com/kevinlong206/ReaShoot/issues).

## Project direction

This branch pivots ReaShoot toward a standalone desktop app for controlling the companion iPhone camera app. The first desktop target is a native macOS app bundle, `ReaShoot.app`; Windows support ships alongside it as a native Win32 app (`ReaShoot.exe`) over the same cross-platform C++ core. The UI is native-modern per platform: AppKit/SwiftUI-style on macOS and native Win32 (Windows SDK, dark Fluent-style theme) on Windows, both over a shared C++ controller/state layer. Native Win32 was chosen over WinUI 3/Qt for maximum compatibility (no external runtime dependencies) and to link the shared C++ core directly.

The existing REAPER extension remains in the repository as a legacy/secondary target. Keep it buildable where practical, but do not let new desktop-app workflow code depend on REAPER APIs, SWELL UI, REAPER transport, track insertion, or audio-alignment behavior.

## Project layout

- `src/app/mac/` - Native macOS desktop app entry point and UI. Keep these files focused on native controls, layout, windows, menus, alerts, and rendering.
- `src/desktop/` - Desktop workflow, state, view-model, and UI-facing constants shared by the standalone app and future platform frontends.
- `src/core/` - Shared protocol, parsing, capture profile, H.264 Annex B, status, and controller code.
- `src/helper/` - C++ helper executable used by the desktop app bundle and legacy REAPER extension for discovery, iPhone control, transfer, and download.
- `src/platform/mac/` - macOS adapters for helper execution, preview WebSocket transport, H.264 preview decode, prompts, media reading, and legacy extension support.
- `src/platform/win32/` - Windows adapters. Keep future desktop logic reusable here.
- `src/platform/ffmpeg/` - Shared FFmpeg recorded-file playback preview used by legacy preview/playback surfaces.
- `src/reashoot.mm`, `src/reaper/`, `src/platform/swell/` - Legacy REAPER extension and shared SWELL panel.
- `iphone/` - Companion iPhone app and Swift package. This remains the source of truth for the iPhone app.

Keep protocol definitions aligned between `src/core/control_protocol.*` and `iphone/Sources/ReaShootCore/ControlProtocol.swift`.

## Development principles

- Keep the implementation native. Do not move iPhone control, preview, download, or media workflows into JSFX, VST3, Lua, or web wrappers.
- Keep standalone app workflow state in `src/desktop/` or `src/core/`; keep Cocoa/Objective-C++ UI thin.
- Prefer shared C++ for behavior that should be consistent between macOS and future Windows desktop support.
- Add platform-specific code only for OS APIs, host integration, UI toolkits, decode backends, or build constraints.
- Do not put desktop orchestration back into AppKit/SwiftUI/WinUI code. Pairing, discovery retry policy, configure-on-profile-change, preview start/stop state, stale-frame empty states, recording start/stop, and iPhone video list/download/delete workflows should be shared C++.
- Native UI/platform adapters may own layout, colors, menus, alerts, file dialogs, settings storage adapters, main-thread dispatch/timers, thumbnail/image display, and preview renderer/client factories.
- Preserve the iPhone single-file recording model: one downloaded `.mov` with embedded camera audio.
- Keep routine status in the desktop app UI. Use modal alerts for user decisions and real errors.
- Do not commit pairing tokens, downloaded `.mov` files, `test-downloads`, DerivedData, `.DS_Store`, Xcode `xcuserdata`, or generated local SwiftPM build output.
- Keep the iPhone app and desktop/helper protocol definitions compatible.

## macOS desktop app build

macOS recorded-file playback support for legacy targets requires FFmpeg headers and dylibs. Install FFmpeg with Homebrew or set `REASHOOT_FFMPEG_ROOT` to a prefix containing `include/` and `lib/`:

```sh
brew install ffmpeg
```

Build the standalone macOS app with CMake:

```sh
cmake -S . -B build-desktop -DCMAKE_BUILD_TYPE=Debug
cmake --build build-desktop --target reashoot_desktop --parallel
open build-desktop/ReaShoot.app
```

The app bundle copies the C++ helper into `ReaShoot.app/Contents/Resources/reashoot-mac`.
For pairing, discovery, preview, and window-layout debugging, launch with:

```sh
open build-desktop/ReaShoot.app --args -debug
```

Debug output goes to stderr and `~/Library/Logs/ReaShoot/ReaShoot-debug.log`; pairing tokens and codes should be redacted.

## Windows desktop app build

The Windows standalone app is a native Win32 executable, `ReaShoot.exe` (CMake target `reashoot_desktop_win32`, sources in `src/app/win32/`). It reuses the shared `reashoot_desktop_core`/`reashoot_core` libraries and the `src/platform/win32/` adapters (helper process, preview stream client, FFmpeg H.264 live-preview decoder).

Live preview decoding requires the shared FFmpeg headers/libs. Install the Gyan FFmpeg shared build (CMake auto-detects the winget install location) or set `REASHOOT_FFMPEG_ROOT` to a prefix containing `include/`, `lib/`, and `bin/`:

```powershell
winget install Gyan.FFmpeg.Shared
```

Build (the target is enabled by default on Windows):

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --target reashoot_desktop_win32
.\build\Release\ReaShoot.exe
```

The build stages `reashoot-win.exe` and the FFmpeg runtime DLLs next to `ReaShoot.exe`. Settings persist under `HKCU\Software\ReaShoot`. Launch with `-debug` to log to stderr and `%LOCALAPPDATA%\ReaShoot\ReaShoot-debug.log` (tokens redacted). Disable the target with `-DREASHOOT_BUILD_DESKTOP_WIN32=OFF`.

## CMake build

macOS full build:

```sh
cmake -S . -B build-cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cmake --parallel
ctest --test-dir build-cmake --output-on-failure
```

Windows legacy extension build:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

The Windows REAPER extension DLL filename must start with `reaper_`; REAPER silently ignores extension DLLs that do not follow that convention.

## Legacy REAPER build and install

The Makefile remains available for the legacy macOS REAPER extension:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make install
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reashoot-mac"
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_reashoot.dylib"
```

Restart REAPER after every install. Native extensions are loaded at process startup.

## iPhone app build

Generic build:

```sh
cd iphone
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project ReaShoot.xcodeproj \
  -scheme ReaShoot \
  -destination 'generic/platform=iOS' \
  build
```

For local device iteration, use your actual device ID and development team:

```sh
cd iphone
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project ReaShoot.xcodeproj \
  -scheme ReaShoot \
  -destination 'platform=iOS,id=YOUR_DEVICE_ID' \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  build
```

The iPhone bundle ID remains `com.kevinlong.reashoot`.

## Validation

Run the lightweight validation suite before committing C++, Swift, protocol, helper, or shared UI changes:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make check
```

For desktop-app changes, also build the app target:

```sh
cmake -S . -B build-desktop -DCMAKE_BUILD_TYPE=Debug
cmake --build build-desktop --target reashoot_desktop --parallel
```

For WebSocket/control startup changes, smoke-test against a paired iPhone with the helper or the desktop app. Keep the iPhone unlocked with ReaShoot open in the foreground.

## Documentation

Keep `README.md` user-facing for the standalone desktop app. Put build commands, architecture notes, legacy REAPER details, and contributor workflow details here in `CONTRIBUTING.md`.
