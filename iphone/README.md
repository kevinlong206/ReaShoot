# iPhone Reaper Video Sync

Greenfield Swift implementation for recording 4K video on an iPhone from Mac commands over local Wi-Fi, then transferring each stopped clip back to the Mac.

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
swift run video-sync-mac ping --host kevin-long-iphone.local --port 8787
swift run video-sync-mac start --host kevin-long-iphone.local --port 8787 --token "$VIDEO_SYNC_TOKEN" --session smoke-test
sleep 3
swift run video-sync-mac stop --host kevin-long-iphone.local --port 8787 --http-port 8788 --token "$VIDEO_SYNC_TOKEN" --download-dir test-downloads
```

Expected result: the CLI prints a downloaded `.mov` path in `test-downloads`.

## Preview endpoints

The iPhone HTTP service also exposes authenticated low-resolution preview endpoints for REAPER integration:

```text
http://HOST:8788/preview.jpg?token=TOKEN
http://HOST:8788/preview.mjpg?token=TOKEN
http://HOST:8788/preview.bin?token=TOKEN
```

`/preview.jpg` returns the latest JPEG frame. `/preview.mjpg` streams a multipart MJPEG preview, and `/preview.bin` streams the same JPEG frames with a 4-byte big-endian length prefix before each frame. Preview frames are capped to 640 px on the longest side and are separate from the 4K movie recording path.

The control WebSocket also supports an experimental authenticated WebRTC preview offer/answer flow. REAPER sends a receive-only SDP offer with `startWebRTCPreview`; the iPhone app answers with a low-resolution video track fed from the same preview capture output. The HTTP preview endpoints remain available as fallback/debugging paths.

## iOS background note

The app is designed for reliable foreground recording with the screen kept awake while armed or recording. iOS normally suspends ordinary apps while backgrounded or locked, so true locked-screen video recording must be validated on device and may require a guided-access or managed-device workflow.

See `AGENTS.md` for detailed handoff notes, device/signing details, known issues, and future work.
