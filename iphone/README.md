# ReaShoot iPhone App

ReaShoot is the companion iPhone app for the standalone ReaShoot desktop app. It records high-quality iPhone video from Mac commands over the local Wi-Fi/Bonjour network, then transfers each stopped clip back to the Mac. The legacy REAPER extension uses the same iPhone app and protocol, but the desktop app is the primary product direction on this branch.

## Layout

- `Sources/ReaShootCore`: shared protocol models, file-state types, and checksum helpers.
- `Sources/ReaShootKit`: iOS capture, local WebSocket control, and HTTP transfer services.
- `Sources/reashoot-mac`: Legacy SwiftPM Mac CLI for discovery/control/download workflows.
- `Apps/ReaShoot`: SwiftUI app sources that consume `ReaShootKit`.
- `Tests/ReaShootCoreTests`: shared protocol tests.

## Build and test

```sh
swift test
swift run reashoot-mac --help
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

The bundle identifier is `com.kevinlong.reashoot`. iOS treats this as a separate app from older personal-device installs, so old pairing state and pending recordings will not migrate automatically.

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

Keep the iPhone unlocked with the app in the foreground. Set the current pairing token in your shell without committing it:

```sh
export REASHOOT_TOKEN='...'
```

Then run:

```sh
swift run reashoot-mac ping --host kevin-long-iphone.local --port 8787
swift run reashoot-mac configure --host kevin-long-iphone.local --port 8787 --token "$REASHOOT_TOKEN" --lens ultrawide --zoom 0.5 --look warmVintage
swift run reashoot-mac start --host kevin-long-iphone.local --port 8787 --token "$REASHOOT_TOKEN" --session smoke-test
sleep 3
swift run reashoot-mac stop --host kevin-long-iphone.local --port 8787 --http-port 8788 --token "$REASHOOT_TOKEN" --download-dir test-downloads
```

Expected result: the CLI prints a downloaded `.mov` path in `test-downloads`, then acknowledges transfer so the iPhone deletes its local copy. Add `--progress` to the `stop` command to print transfer progress lines during on-phone look encoding and movie download. The standalone desktop app and legacy REAPER extension use the safer prompted stop flow: `stop-only` returns raw pending recording metadata immediately, while `download-recording` prepares/encodes only after Download is chosen. If a download fails before acknowledgement, the recording remains pending on the phone and can be restored with `list-recordings` plus `download-recording`, deleted through the helper, or deleted directly in the iPhone app's Recordings section.

## Preview

The current preview implementation uses an authenticated local H.264 stream. The desktop app sends `startPreview` over the control WebSocket, then connects to the preview WebSocket returned in the descriptor. The iPhone app sends low-resolution H.264 frames rendered from the same preview capture output. The iPhone applies the selected look before encoding preview frames, so natural and styled previews use the same transport.

The app starts its WebSocket control listener and HTTP download listener before camera preparation so the desktop app can retry control commands immediately after launch. The WebSocket server must return a complete `\r\n\r\n`-terminated handshake because the bundled helper validates the full `Sec-WebSocket-Accept` response.

Capture configuration supports hardware-dependent lens selection (`wide`, `ultrawide`, `telephoto`, `auto`), zoom, and baked-in artistic looks (`natural`, `warmVintage`, `coolBlue`, `highContrastBW`, `fadedFilm`, `dreamGlow`, `noir`, `saturatedPop`, `bleachBypass`, `sepia`, `instantPhoto`, `chrome`, `tonal`, `silvertone`, `dramaticWarm`, `dramaticCool`, `softMatte`, `comicBook`, `vhs`, `musicVideoPop`) plus a curated `ci:<CoreImageFilterName>` subset for thermal/X-ray, gradients/edges, crystallize/pixel/halftone, and a few kaleidoscope/distortion looks. Zoom is applied through AVFoundation and clamped to the selected camera's supported range. Non-natural looks are applied as a post-record Core Image export only when the clip is prepared for download, so unwanted takes can be discarded before encoding while the reliable movie recording path and embedded camera audio are preserved.

## iOS background note

The app is designed for reliable foreground recording and disables the idle timer while ready/listening so the screen stays awake during tripod preview. The status UI does not expose that implementation detail. iOS normally suspends ordinary apps while backgrounded or locked, so true locked-screen video recording must be validated on device and may require a guided-access or managed-device workflow.

See `AGENTS.md` for detailed handoff notes, device/signing details, known issues, and future work.
