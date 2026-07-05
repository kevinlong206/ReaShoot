# Contributing to ReaShoot

Pull requests are welcome and will be reviewed as time permits. Bug reports, crashes, confusing workflows, and feature requests should be filed as [GitHub issues](https://github.com/kevinlong206/ReaPhoneVideo/issues).

## Project layout

- `src/reashoot.mm` - Main macOS REAPER extension implementation.
- `src/helper/` - Helper executable used by REAPER for iPhone control, discovery, transfer, and download.
- `src/core/` - Shared protocol, parsing, alignment, status, and controller code.
- `src/platform/swell/swell_panel_probe.cpp` - Shared preview/setup/status panel UI.
- `src/platform/ffmpeg/` - Shared FFmpeg recorded-file playback preview.
- `src/platform/mac/` - macOS platform adapters.
- `src/platform/win32/` - Windows platform adapters.
- `iphone/` - Companion iPhone app and Swift package. This is the source of truth for the iPhone app.

Keep protocol definitions aligned between `src/core/control_protocol.*` and `iphone/Sources/ReaShootCore/ControlProtocol.swift`.

## Development principles

- Keep the implementation native. Do not move iPhone control, preview, media insertion, or playback into JSFX, VST3, or Lua.
- Keep preview/setup/status controls in the shared SWELL panel instead of adding parallel Cocoa or Win32 control trees.
- Preserve the single-item model: one downloaded `.mov` item with embedded camera audio.
- Do not enable REAPER audio recording on the `ReaShoot` track.
- Keep routine status in the preview UI; use REAPER message boxes only for real errors or confirmations.
- Keep macOS and Windows preview/playback logic shared where practical, while avoiding platform-specific workarounds unless they are justified on that platform.
- Do not commit pairing tokens, downloaded `.mov` files, `test-downloads`, DerivedData, `.DS_Store`, Xcode `xcuserdata`, or generated local SwiftPM build output.

## macOS build

macOS playback preview requires FFmpeg headers and dylibs. Install FFmpeg with Homebrew or set `FFMPEG_ROOT` / `REASHOOT_FFMPEG_ROOT` to a prefix containing `include/` and `lib/`:

```sh
brew install ffmpeg
```

Build with:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make
```

Install into REAPER with:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make install
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reashoot-mac"
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_reashoot.dylib"
```

Restart REAPER after every install. Native extensions are loaded at process startup.

By default, the Makefile builds for the current Mac architecture. Universal builds require a universal FFmpeg prefix; the default Apple Silicon Homebrew FFmpeg dylibs are arm64-only.

```sh
make ARCH_FLAGS="-arch arm64 -arch x86_64"
```

## CMake build

macOS:

```sh
cmake -S . -B build-cmake -DCMAKE_BUILD_TYPE=Debug
cmake --build build-cmake --parallel
ctest --test-dir build-cmake --output-on-failure
cmake --install build-cmake
```

Windows:

```powershell
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
cmake --install build --config Release
```

The Windows DLL filename must start with `reaper_`; REAPER silently ignores extension DLLs that do not follow that convention.

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

After Xcode or SwiftPM builds, remove generated local artifacts unless they are intentional:

```sh
rm -rf iphone/Package.resolved iphone/.build helper/.build
```

## Validation

Run the lightweight validation suite before committing C++, Swift, protocol, helper, or shared UI changes:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all make check
```

This builds the C++ helper, checks shared panel drift, and runs the iPhone Swift tests.

For WebSocket/control startup changes, also smoke-test the installed helper against a paired phone:

```sh
TOKEN="$(awk -F= '/^iphone_token=/{print $2}' "$HOME/Library/Application Support/REAPER/reaper-extstate.ini" | tail -1)"
"$HOME/Library/Application Support/REAPER/UserPlugins/reashoot-mac" \
  ping --host kevin-long-iphone.local --port 8787 --token "$TOKEN"
```

Expected output is `OK`.

## Documentation

Keep `README.md` user-facing. Put build commands, architecture notes, and contributor workflow details here in `CONTRIBUTING.md`.
