# ReaShoot iPhone App

ReaShoot is the companion iPhone app for the standalone ReaShoot desktop app. It records high-quality iPhone video from Mac commands over the local Wi-Fi/Bonjour network, then transfers each stopped clip back to the Mac. The legacy REAPER extension uses the same iPhone app and protocol, but the desktop app is the primary product direction on this branch.

## Layout

- `Sources/ReaShootCore`: shared protocol models, file-state types, and checksum helpers.
- `Sources/ReaShootKit`: iOS capture, local WebSocket control, and HTTP transfer services.
- `Apps/ReaShoot`: SwiftUI app sources that consume `ReaShootKit`.
- `Tests/ReaShootCoreTests`: shared protocol tests.

## Build and test

```sh
swift test
```

The iPhone app can be built from `ReaShoot.xcodeproj`. For local device testing on the currently paired phone:

```sh
xcodebuild \
  -project ReaShoot.xcodeproj \
  -scheme ReaShoot \
  -destination 'platform=iOS,id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  -configuration Debug \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  -allowProvisioningUpdates \
  build
```

The bundle identifier is `com.kevinlong.reashoot`. iOS treats this as a separate app from older personal-device installs, so old pairing state and pending recordings will not migrate automatically. The app displays the currently paired computer and only keeps one paired computer at a time.

## App Store Connect upload

Use `Scripts/app-store-upload.sh` to archive the Release build, export it for App Store Connect, and upload it with `xcodebuild`. Keep the App Store Connect API key outside the repository:

```sh
export APP_STORE_CONNECT_API_KEY_ID='ABC123DEFG'
export APP_STORE_CONNECT_API_ISSUER_ID='00000000-0000-0000-0000-000000000000'
export APP_STORE_CONNECT_API_KEY_PATH="$HOME/private_keys/AuthKey_ABC123DEFG.p8"

Scripts/app-store-upload.sh --marketing-version 1.0
```

The script assigns a UTC timestamp build number by default so repeated uploads of the same marketing version do not collide. To preview the archive/export flow without uploading, run:

```sh
Scripts/app-store-upload.sh --export-only --marketing-version 1.0
```

## End-to-end smoke test

Keep the iPhone unlocked with the app in the foreground, then use the standalone desktop app to discover/pair, configure, start recording, stop recording, and download from `Videos on iPhone`.

Expected result: pairing shows an iPhone dialog saying `Accept pairing request from <computer name>`; after accepting, the desktop app can control recording and only acknowledges transfer after verifying the downloaded `.mov`. If a download fails before acknowledgement, the recording remains pending on the phone and can be restored or deleted from the desktop app's `Videos on iPhone` window, or deleted directly in the iPhone app's Recordings section.

## Preview

The current preview implementation uses an authenticated local H.264 stream. The desktop app sends `startPreview` over the control WebSocket, then connects to the preview WebSocket returned in the descriptor. The iPhone app sends low-resolution H.264 frames rendered from the same preview capture output. The iPhone applies the selected look before encoding preview frames, so natural and styled previews use the same transport.

The app starts its WebSocket control listener and HTTP download listener before camera preparation so the desktop app can retry control commands immediately after launch. The WebSocket server must return a complete `\r\n\r\n`-terminated handshake because the desktop control client validates the full `Sec-WebSocket-Accept` response.

Capture configuration supports hardware-dependent lens selection (`wide`, `ultrawide`, `telephoto`, `auto`), zoom, and baked-in artistic looks (`natural`, `warmVintage`, `coolBlue`, `highContrastBW`, `fadedFilm`, `dreamGlow`, `noir`, `saturatedPop`, `bleachBypass`, `sepia`, `instantPhoto`, `chrome`, `tonal`, `silvertone`, `dramaticWarm`, `dramaticCool`, `softMatte`, `comicBook`, `vhs`, `musicVideoPop`) plus a curated `ci:<CoreImageFilterName>` subset for thermal/X-ray, gradients/edges, crystallize/pixel/halftone, and a few kaleidoscope/distortion looks. Zoom is applied through AVFoundation and clamped to the selected camera's supported range. Non-natural looks are applied as a post-record Core Image export only when the clip is prepared for download, so unwanted takes can be discarded before encoding while the reliable movie recording path and embedded camera audio are preserved.

## iOS background note

The app is designed for reliable foreground recording and disables the idle timer while ready/listening so the screen stays awake during tripod preview. The status UI does not expose that implementation detail. iOS normally suspends ordinary apps while backgrounded or locked, so true locked-screen video recording must be validated on device and may require a guided-access or managed-device workflow.

See `AGENTS.md` for detailed handoff notes, device/signing details, known issues, and future work.
