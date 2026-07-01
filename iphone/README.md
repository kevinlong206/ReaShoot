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

If a paired wired device is visible but the USB tunnel is not connected, `usb-host` asks CoreDevice to activate the tunnel before reporting the host. REAPER uses that USB host automatically when possible and filters WebRTC ICE candidates to the USB tunnel prefix while keeping the SDP offer intact.

Expected result: the CLI prints a downloaded `.mov` path in `test-downloads`, then acknowledges transfer so the iPhone deletes its local copy. Add `--progress` to the `stop` command to print transfer progress lines during on-phone look encoding and movie download. For REAPER's prompted stop flow, the helper also exposes `stop-only`, `prepare-recording`, `list-recordings`, `download-recording`, and `delete-recording`; `stop-only` returns raw pending recording metadata immediately, while `download-recording` prepares/encodes only after Download is chosen. If a download fails before acknowledgement, the recording remains pending on the phone and can be restored with `list-recordings` plus `download-recording`, deleted through the helper, or deleted directly in the iPhone app's Recordings section.

## Preview

REAPER uses the authenticated WebRTC offer/answer flow for all iPhone preview. It sends a receive-only SDP offer with `startWebRTCPreview`; the iPhone app answers with a low-resolution video track rendered from the same preview capture output. The iPhone applies the selected look before sending WebRTC frames, so natural and styled previews use the same transport.

Capture configuration supports hardware-dependent lens selection (`wide`, `ultrawide`, `telephoto`, `auto`), zoom, and baked-in artistic looks (`natural`, `warmVintage`, `coolBlue`, `highContrastBW`, `fadedFilm`, `dreamGlow`, `noir`, `saturatedPop`, `bleachBypass`, `sepia`, `instantPhoto`, `chrome`, `tonal`, `silvertone`, `dramaticWarm`, `dramaticCool`, `softMatte`, `comicBook`, `vhs`, `musicVideoPop`) plus a curated `ci:<CoreImageFilterName>` subset for thermal/X-ray, gradients/edges, crystallize/pixel/halftone, and a few kaleidoscope/distortion looks. Zoom is applied through AVFoundation and clamped to the selected camera's supported range. Non-natural looks are applied as a post-record Core Image export only when the clip is prepared for download, so unwanted takes can be discarded before encoding while the reliable movie recording path and embedded camera audio are preserved.

## iOS background note

The app is designed for reliable foreground recording and disables the idle timer while ready/listening so the screen stays awake during tripod preview. The status UI shows `Keep awake: Yes` when this is active. iOS normally suspends ordinary apps while backgrounded or locked, so true locked-screen video recording must be validated on device and may require a guided-access or managed-device workflow.

See `AGENTS.md` for detailed handoff notes, device/signing details, known issues, and future work.
