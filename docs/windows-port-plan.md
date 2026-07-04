# ReaShoot Windows port plan

This plan is the handoff point for moving REAPER-side ReaShoot work from macOS to Windows. The iOS app is out of scope except for keeping protocol compatibility with `src/core/control_protocol.*` and `iphone/Sources/ReaShootCore/ControlProtocol.swift`.

## Current status

- Shared C++ now lives under `src/core/` and is covered by `tests/core_tests.cpp`.
- The C++ helper under `src/helper/` owns the CLI, control WebSocket client, HTTP downloader, checksum, and discovery behavior. It now builds on Windows as `reashoot-win.exe` with WinSock TCP and lightweight in-process mDNS discovery.
- CMake builds the shared core, core tests, helper, and macOS extension on macOS; on Windows it builds `reashoot-win.exe` and `reaper_reashoot.dll`.
- macOS services are exposed through C++ factories/adapters for helper process, preview stream, H.264 decode, playback preview, media audio reading, and modal prompts.
- `src/reashoot.mm` is still the macOS REAPER entrypoint, but it no longer constructs concrete mac preview/prompt classes directly.
- Windows has a native DLL entrypoint in `src/platform/win32/` that registers ReaShoot actions, opens the shared setup/status panel, runs helper work off the UI thread, performs pair/configure/start/stop/download plus pending restore/delete and single-item insertion, and decodes live/playback preview frames through Media Foundation.

## Constraints

- Preserve the iPhone H.264 preview transport; do not replace it with MJPEG or a different transport unless requirements change.
- Preserve the single-item recording model: one downloaded `.mov` item with embedded camera audio.
- Keep routine status in the ReaShoot preview/setup UI, not REAPER popups.
- Do not run helper subprocess/network work on REAPER's UI thread.
- Windows Bonjour/mDNS discovery should be lightweight and in-process; do not require the user to install a background service.
- REAPER extension DLL filenames must start with `reaper_`.

## Remaining Windows work

1. **Windows alignment media reading**
   - Replace AVFoundation audio reading with Windows-native PCM decode.
   - Keep `alignment_math.*` shared.

2. **Windows validation and docs**
   - Validate helper ping/pair/configure against a device, DLL load/action registration in REAPER, setup panel pairing, recording download/insert, preview, pending recording management, and alignment.

## Suggested implementation order

1. Implement alignment audio reading.
2. Add device/REAPER smoke-test notes as each Windows surface is validated.

## Validation gates

- `cmake --build` succeeds on Windows.
- `ctest` passes for shared C++ tests.
- Helper can discover or manually connect to the iPhone and run `ping`, `pair`, and `configure`.
- `reaper_reashoot.dll` loads in Windows REAPER and registers ReaShoot actions.
- Setup panel can pair/reconnect without blocking REAPER's UI thread.
- Preview displays the authenticated H.264 stream.
- Recording stop downloads and inserts a single `.mov`.
- Pending recording restore/delete works.
- Alignment still uses shared math and can read Windows media audio.
