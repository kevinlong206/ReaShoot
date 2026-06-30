# iPhone Reaper Video Sync

Swift implementation for recording 4K video on an iPhone from REAPER/Mac commands over USB when available, falling back to local Wi-Fi/Bonjour, then transferring each stopped clip back to the Mac.

## Layout

- `Sources/VideoSyncCore`: shared protocol models, file-state types, and checksum helpers.
- `Sources/iPhoneVideoSyncKit`: iOS capture, local WebSocket control, and HTTP transfer services.
- `Sources/video-sync-mac`: Mac CLI for discovery/control/download workflows.
- `Apps/iPhoneVideoSync`: SwiftUI app sources that consume `iPhoneVideoSyncKit`.
- `Tests/VideoSyncCoreTests`: shared protocol tests.

## Build and test

```sh
swift test
swift run video-sync-mac --help
```

The iPhone app can be built from `iPhoneVideoSync.xcodeproj`. For local device testing on the currently paired phone:

```sh
xcodebuild \
  -project iPhoneVideoSync.xcodeproj \
  -scheme iPhoneVideoSync \
  -destination 'id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  -configuration Debug \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  -allowProvisioningUpdates \
  build
```

## End-to-end smoke test

Keep the iPhone unlocked with the app in the foreground. Set the current pairing token in your shell without committing it:

```sh
export VIDEO_SYNC_TOKEN='...'
```

Then run:

```sh
swift run video-sync-mac usb-host
swift run video-sync-mac ping --host kevin-long-iphone.local --port 8787
swift run video-sync-mac configure --host kevin-long-iphone.local --port 8787 --token "$VIDEO_SYNC_TOKEN" --lens ultrawide --zoom 0.5 --look warmVintage
swift run video-sync-mac start --host kevin-long-iphone.local --port 8787 --token "$VIDEO_SYNC_TOKEN" --session smoke-test
sleep 3
swift run video-sync-mac stop --host kevin-long-iphone.local --port 8787 --http-port 8788 --token "$VIDEO_SYNC_TOKEN" --download-dir test-downloads
```

Expected result: the CLI prints a downloaded `.mov` path in `test-downloads`, then acknowledges transfer so the iPhone deletes its local copy. Add `--progress` to the `stop` command to print transfer progress lines during the movie download. For REAPER's prompted stop flow, the helper also exposes `stop-only`, `list-recordings`, `download-recording`, and `delete-recording`. If a download fails before acknowledgement, the recording remains pending on the phone and can be restored with `list-recordings` plus `download-recording`.

## Preview endpoints

The iPhone HTTP service also exposes authenticated low-resolution preview endpoints for REAPER integration:

```text
http://HOST:8788/preview.jpg?token=TOKEN
http://HOST:8788/preview.mjpg?token=TOKEN
http://HOST:8788/preview.bin?token=TOKEN
```

`/preview.jpg` returns the latest JPEG frame. `/preview.mjpg` streams a multipart MJPEG preview, and `/preview.bin` streams the same JPEG frames with a 4-byte big-endian length prefix before each frame. Preview frames are capped to 640 px on the longest side and are separate from the 4K movie recording path.

The control WebSocket also supports an experimental authenticated WebRTC preview offer/answer flow. REAPER sends a receive-only SDP offer with `startWebRTCPreview`; the iPhone app answers with a low-resolution video track fed from the same preview capture output. The HTTP preview endpoints remain available as fallback/debugging paths.

Capture configuration supports hardware-dependent lens selection (`wide`, `ultrawide`, `telephoto`, `auto`), zoom, and baked-in artistic looks (`natural`, `warmVintage`, `coolBlue`, `highContrastBW`, `fadedFilm`, `dreamGlow`, `noir`, `saturatedPop`, `bleachBypass`, `sepia`, `instantPhoto`, `chrome`, `tonal`, `silvertone`, `dramaticWarm`, `dramaticCool`, `softMatte`, `comicBook`, `vhs`, `musicVideoPop`) plus a curated `ci:<CoreImageFilterName>` subset for thermal/X-ray, gradients/edges, crystallize/pixel/halftone, and a few kaleidoscope/distortion looks. Zoom is applied through AVFoundation and clamped to the selected camera's supported range. Non-natural looks are previewed through the HTTP preview stream and applied as a post-record Core Image export so the reliable movie recording path and embedded camera audio are preserved. The helper can report encoding progress during `stop`/`stop-only` with `--progress`.

## iOS background note

The app is designed for reliable foreground recording and disables the idle timer while ready/listening so the screen stays awake during tripod preview. The status UI shows `Keep awake: Yes` when this is active. iOS normally suspends ordinary apps while backgrounded or locked, so true locked-screen video recording must be validated on device and may require a guided-access or managed-device workflow.

See `AGENTS.md` for detailed handoff notes, device/signing details, known issues, and future work.
