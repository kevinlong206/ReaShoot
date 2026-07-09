# AGENTS.md

Guidance for future agents working in this project.

## Project status

This is the consolidated companion iPhone app for ReaShoot. It records iPhone video controlled by the standalone ReaShoot desktop app over the local Wi-Fi/Bonjour network. REAPER extensions should control recording through the desktop app's local API, not by adding new direct iPhone-control paths.

This directory is the source of truth for the iPhone app. Do not use or recreate old external development copies.

The current implementation has been installed and tested on a physical iPhone in foreground mode. The tested flow is:

1. iPhone app advertises `_reashoot._tcp` with Bonjour.
2. Mac reaches the device over the local Wi-Fi network using the Bonjour-advertised host.
3. Mac sends WebSocket control commands on port `8787`.
4. The desktop app uses an authenticated local H.264 WebSocket stream for preview; the iPhone renders the selected look before sending preview frames.
5. iPhone records video with AVFoundation.
6. Mac sends stop, receives a recording descriptor, downloads the `.mov` over HTTP on port `8788`, verifies checksum, and acknowledges transfer.

The app disables the idle timer while ready/listening so foreground preview does not sleep on a tripod. Do not assume locked-screen or background recording works; iOS may still suspend ordinary apps when backgrounded or locked.

## Repository layout

- `Package.swift`: Swift package with shared core, iPhone kit, and Mac CLI products.
- `ReaShoot.xcodeproj`: installable iOS app project used for device deployment.
- `Apps/ReaShoot`: SwiftUI app entry point, UI, and iOS `Info.plist`.
- `Apps/ReaShoot/Assets.xcassets`: iOS app icon assets, including the ReaShoot camera-and-music-note AppIcon.
- `Sources/ReaShootCore`: shared protocol models, transfer state, and checksums.
- `Sources/ReaShootKit`: iOS recording engine, pairing, WebSocket server, HTTP server, and orchestration service.
- `Sources/ReaShootKit/PreviewH264Encoder.swift`: VideoToolbox H.264 encoder for low-resolution dock preview.
- `Sources/ReaShootKit/PreviewStreamServer.swift`: authenticated binary WebSocket server for preview frames.
- `Tests/ReaShootCoreTests`: shared protocol and state-machine tests.
- `test-downloads`: local output directory for downloaded recordings; do not commit it.

The ReaShoot bundle ID is `com.kevinlong.reashoot`. iOS treats it as a separate app from old personal-device installs that used `older bundle identifiers`; do not assume pairing state or pending recordings migrate automatically.

The iPhone app shows the currently paired computer and keeps only one paired computer at a time. Pairing is request-based: desktop clients send a `pair` command with `metadata.clientName`, and the iPhone UI asks `Accept pairing request from <clientName>` before issuing/replacing the token.

## Build and test commands

Run package tests:

```sh
swift test
```

When SwiftPM commands need to bypass bare-repository safety checks, prefix commands with:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
```

Build the iPhone app for the paired physical device:

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

Install and launch after building:

```sh
APP_PATH="$(xcodebuild \
  -project ReaShoot.xcodeproj \
  -scheme ReaShoot \
  -destination 'platform=iOS,id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  -configuration Debug \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/TARGET_BUILD_DIR/ {dir=$2} /FULL_PRODUCT_NAME/ {name=$2} END {print dir "/" name}')"
xcrun devicectl device install app --device 797DC5E5-610E-5972-9FD3-B0045CA5745F "$APP_PATH"
xcrun devicectl device process launch --device 797DC5E5-610E-5972-9FD3-B0045CA5745F com.kevinlong.reashoot
```

## Device and signing notes

Tested physical device:

- Device name: `kevin long iphone`
- devicectl identifier: `797DC5E5-610E-5972-9FD3-B0045CA5745F`
- Product type: `iPhone15,4`
- iOS: `26.5`
- Bundle ID: `com.kevinlong.reashoot`
- Development team used for local signing: `6QTJXLJJ62`

Prerequisites for device testing:

- iPhone connected and trusted.
- Developer Mode enabled on the iPhone.
- Developer profile trusted on the iPhone under Settings > General > VPN & Device Management.
- Xcode has a valid Apple Development certificate.
- Enough free disk space for Xcode DerivedData.

Do not write pairing tokens into docs or source. Tokens are credentials for controlling the phone.

Remove local build artifacts before wrapping up unless a dependency change intentionally requires them:

```sh
rm -rf .build Package.resolved
```

## Manual end-to-end test

Keep the iPhone unlocked with the ReaShoot app open in the foreground, then use the standalone desktop app to discover/pair, configure, start recording, stop recording, and download from `Videos on iPhone`.

Expected result: pairing shows an iPhone dialog saying `Accept pairing request from <computer name>`; after accepting, the desktop app can control recording and only acknowledges transfer after verifying the downloaded `.mov`. If a download fails before acknowledgement, the recording remains pending on the phone; use `Videos on iPhone` to restore/delete it or delete it from the iPhone app's Recordings section.

`encodeLookAtRecordTime` is opt-in/default-off. When enabled with a non-natural look, the iPhone records through the AVAssetWriter record-time look path with embedded camera audio and marks the recording's `renderedLook` as the selected look, so download preparation must not export the look a second time. Keep this path using recorded-file orientation mapping; do not reuse the live-preview-only landscape mapping from `PreviewFrameStore.normalizedImage`.

## H.264 preview notes

- The desktop app sends `startPreview` over the control WebSocket.
- The iPhone returns a `PreviewDescriptor` for an authenticated preview WebSocket on port `8789`.
- The preview server sends an initial JSON descriptor text frame, then binary H.264 Annex B access units.
- SPS/PPS must be sent before keyframes so desktop clients can rebuild decoder format descriptions after reconnects.
- `PreviewH264Encoder` includes `RSDIAG1` diagnostic SEI metadata (sequence and source timestamp). Desktop preview clients use it to log source-to-display latency and dropped sequence gaps; preserve it when touching encoder output.
- Auto preview orientation uses CoreMotion gravity plus short sample-count/time hysteresis in `CaptureRecordingEngine.swift`. Do not rely only on `UIDevice.current.orientation`; it can bounce between portrait and landscape and make the desktop preview repeatedly reset orientation.
- Keep live-preview orientation separate from recorded-file rotation. `PreviewFrameStore.normalizedImage` intentionally maps `landscapeLeft` to `.down` and `landscapeRight`/`landscape` to `.up`.
- Desktop preview views should draw each decoded frame using that frame's dimensions/aspect. Descriptor text updates should not stretch an old-orientation frame while waiting for the first frame in the new orientation.
- The iPhone app status UI exposes a `Preview` row. It should report `Streaming` only when a preview WebSocket client is actually connected; after `startPreview` but before the desktop app connects, it reports waiting.
- HTTP is used for recording downloads, not live preview.
- The app starts control/HTTP listeners before camera preparation so the desktop app can reconnect quickly after app launch.
- Desktop control clients validate complete WebSocket handshake headers, including `Sec-WebSocket-Accept`; keep `LocalWebSocketServer.handshakeResponse` terminated with `\r\n\r\n`.
- Lens selection uses AVFoundation rear camera discovery. Not every iPhone exposes `ultrawide` or `telephoto`; unavailable lens requests should fail clearly instead of silently pretending they worked.
- Looks include custom names plus a curated raw Core Image subset accepted as `ci:<filterName>`. Keep `VideoLook.rawFilterIDs` aligned with desktop/legacy dropdown lists.

## Known issues and next work

- If Bonjour discovery fails, verify the iPhone advertisement with:

```sh
dns-sd -B _reashoot._tcp local
dns-sd -L iPhone _reashoot._tcp local
```

- Background/locked recording is not validated and may not be permitted by iOS.
- The WebSocket and HTTP servers are custom lightweight implementations; add parser tests before expanding protocol behavior.
- Downloads support HTTP byte ranges and desktop-side resume/retry through `.download` temp files.
- Pending recordings can be restored after app relaunch via recording metadata; continue improving diagnostics around failed transfers.
- Avoid broad rewrites of the manually generated Xcode project unless replacing it with a more maintainable project-generation workflow.
