# ReaShoot Windows port plan

This plan is the handoff point for moving REAPER-side ReaShoot work from macOS to Windows. The iOS app is out of scope except for keeping protocol compatibility with `src/core/control_protocol.*` and `iphone/Sources/ReaShootCore/ControlProtocol.swift`.

## Current starting point

- Shared C++ now lives under `src/core/` and is covered by `tests/core_tests.cpp`.
- The C++ helper under `src/helper/` owns the CLI, control WebSocket client, HTTP downloader, checksum, and discovery behavior, but its implementation is still POSIX/mac-oriented.
- CMake builds the shared core, core tests, helper, and macOS extension on macOS.
- macOS services are exposed through C++ factories/adapters for helper process, preview stream, H.264 decode, playback preview, media audio reading, and modal prompts.
- `src/reashoot.mm` is still the macOS REAPER entrypoint, but it no longer constructs concrete mac preview/prompt classes directly.

## Constraints

- Preserve the iPhone H.264 preview transport; do not replace it with MJPEG or a different transport unless requirements change.
- Preserve the single-item recording model: one downloaded `.mov` item with embedded camera audio.
- Keep routine status in the ReaShoot preview/setup UI, not REAPER popups.
- Do not run helper subprocess/network work on REAPER's UI thread.
- Windows Bonjour/mDNS discovery should be lightweight and in-process; do not require the user to install a background service.
- REAPER extension DLL filenames must start with `reaper_`.

## Remaining Windows work

1. **SWELL runtime on Windows**
   - Split `src/platform/swell/swell_runtime.mm` so mac runtime lookup stays mac-specific.
   - Add a Windows implementation that uses REAPER/SWELL exports directly.
   - Keep `swell_panel_probe.cpp` shared if practical.

2. **Helper portability**
   - Abstract POSIX sockets/process/sleep/path functions in `src/helper/`.
   - Add WinSock equivalents, including `WSAStartup`, `closesocket`, timeout setup, and error conversion.
   - Replace `/usr/bin/dns-sd` discovery with lightweight in-process mDNS/DNS-SD for `_reashoot._tcp.local`.
   - Keep manual host entry as a fallback, not the primary first milestone.

3. **Windows REAPER DLL skeleton**
   - Add `reaper_reashoot.dll` target in CMake.
   - Register actions/timers and wire the shared controller plus Windows adapters.
   - Open the shared setup/preview panel from Windows REAPER.

4. **Windows preview**
   - Implement authenticated preview WebSocket client.
   - Feed binary H.264 Annex B access units into a Windows decoder.
   - Decode to BGRA frames, likely through Media Foundation first.
   - Deliver decoded frames to the shared SWELL panel.

5. **Windows recording flow**
   - Wire helper launch and pair/reconnect/configure/start/stop/download flow.
   - Insert downloaded media into REAPER.
   - Implement pending recording restore/delete and progress/status updates.

6. **Windows playback preview and alignment media reading**
   - Replace AVFoundation playback frame extraction with Windows-native playback/frame extraction, likely Media Foundation.
   - Replace AVFoundation audio reading with Windows-native PCM decode.
   - Keep `alignment_math.*` shared.

7. **Windows validation and docs**
   - Document build/install/smoke tests.
   - Validate shared core tests, helper ping/pair/configure, DLL load/action registration, setup panel, preview, recording download/insert, and alignment.

## Suggested implementation order

1. Build shared core tests on Windows with CMake.
2. Port helper networking enough for `ping`, then `pair`, then `configure`.
3. Add the Windows DLL skeleton and verify REAPER loads it.
4. Bring up the shared SWELL setup panel.
5. Implement preview stream client and H.264 decode.
6. Implement recording download/insert/restore/delete.
7. Implement playback preview and alignment audio reading.
8. Add Windows docs and smoke-test commands.

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

