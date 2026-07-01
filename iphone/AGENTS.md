# AGENTS.md

Guidance for future agents working in this project.

## Project status

This is the consolidated companion iPhone app for `reaper_video_recorder`. It records iPhone video controlled from REAPER over the local Wi-Fi/Bonjour network.

This directory is the source of truth for the iPhone app. Do not use the old `~/iphone_reapervideosync` directory.

The current implementation has been installed and tested on a physical iPhone in foreground mode. The tested flow is:

1. iPhone app advertises `_iphone-video-sync._tcp` with Bonjour.
2. Mac reaches the device over the local Wi-Fi network using the Bonjour-advertised host.
3. Mac sends WebSocket control commands on port `8787`.
4. REAPER uses WebRTC as the only preview path; the iPhone renders the selected look before sending preview frames.
5. iPhone records video with AVFoundation.
6. Mac sends stop, receives a recording descriptor, downloads the `.mov` over HTTP on port `8788`, verifies checksum, and acknowledges transfer.

The app disables the idle timer while ready/listening so foreground preview does not sleep on a tripod. Do not assume locked-screen or background recording works; iOS may still suspend ordinary apps when backgrounded or locked.

## Repository layout

- `Package.swift`: Swift package with shared core, iPhone kit, and Mac CLI products.
- `iPhoneVideoSync.xcodeproj`: installable iOS app project used for device deployment.
- `Apps/iPhoneVideoSync`: SwiftUI app entry point, UI, and iOS `Info.plist`.
- `Sources/VideoSyncCore`: shared protocol models, transfer state, and checksums.
- `Sources/iPhoneVideoSyncKit`: iOS recording engine, pairing, WebSocket server, HTTP server, and orchestration service.
- `Sources/iPhoneVideoSyncKit/WebRTCPreviewSession.swift`: LiveKit WebRTC sender for the low-resolution dock preview.
- `Sources/video-sync-mac`: Mac command-line tool. Keep this aligned with `../helper/Sources/video-sync-mac`.
- `Tests/VideoSyncCoreTests`: shared protocol and state-machine tests.
- `test-downloads`: local output directory for downloaded recordings; do not commit it.

## Build and test commands

Run package tests:

```sh
swift test
```

Show CLI help:

```sh
swift run video-sync-mac --help
```

When SwiftPM touches the LiveKit WebRTC package, prefix commands with:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all
```

Build the iPhone app for the paired physical device:

```sh
xcodebuild \
  -project iPhoneVideoSync.xcodeproj \
  -scheme iPhoneVideoSync \
  -destination 'platform=iOS,id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  -configuration Debug \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  -allowProvisioningUpdates \
  build
```

Install and launch after building:

```sh
APP_PATH="$(xcodebuild \
  -project iPhoneVideoSync.xcodeproj \
  -scheme iPhoneVideoSync \
  -destination 'platform=iOS,id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  -configuration Debug \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/TARGET_BUILD_DIR/ {dir=$2} /FULL_PRODUCT_NAME/ {name=$2} END {print dir "/" name}')"
xcrun devicectl device install app --device 797DC5E5-610E-5972-9FD3-B0045CA5745F "$APP_PATH"
xcrun devicectl device process launch --device 797DC5E5-610E-5972-9FD3-B0045CA5745F com.kevinlong.iphonevideosync
```

## Device and signing notes

Tested physical device:

- Device name: `kevin long iphone`
- devicectl identifier: `797DC5E5-610E-5972-9FD3-B0045CA5745F`
- Product type: `iPhone15,4`
- iOS: `26.5`
- Bundle ID: `com.kevinlong.iphonevideosync`
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
rm -rf .build Package.resolved ../helper/.build
```

## Manual end-to-end test

Keep the iPhone unlocked with the Video Sync app open in the foreground, then run:

```sh
swift run video-sync-mac ping --host kevin-long-iphone.local --port 8787

swift run video-sync-mac configure \
  --host kevin-long-iphone.local \
  --port 8787 \
  --token "$VIDEO_SYNC_TOKEN" \
  --lens ultrawide \
  --zoom 0.5 \
  --look ci:CIThermal

swift run video-sync-mac start \
  --host kevin-long-iphone.local \
  --port 8787 \
  --token "$VIDEO_SYNC_TOKEN" \
  --session cli-tool-test

sleep 3

swift run video-sync-mac stop \
  --host kevin-long-iphone.local \
  --port 8787 \
  --http-port 8788 \
  --token "$VIDEO_SYNC_TOKEN" \
  --download-dir test-downloads
```

Expected result: a `.mov` appears in `test-downloads`, and the CLI prints `downloaded ...`.

Add `--progress` to `swift run video-sync-mac stop ...` when testing progress. It emits `encode percent=...` during on-phone look preparation and `progress bytes=... total=... percent=...` lines during the HTTP download.

For the REAPER prompted stop flow, use `stop-only` to get raw pending recording metadata immediately, then either `download-recording --progress` or `delete-recording`. `download-recording` prepares/encodes non-natural looks only after Download is chosen. If a download fails before acknowledgement, the recording remains pending on the phone; use `list-recordings` plus `download-recording --progress` to restore it, `delete-recording` to remove it, or delete it from the iPhone app's Recordings section.

## WebRTC preview notes

- REAPER sends `startWebRTCPreview` with an SDP offer.
- The iPhone creates a send-only video answer from `WebRTCPreviewSession`.
- The answer may include inline ICE candidates. REAPER is expected to strip and add them separately because the Mac-side parser rejected the full inline-candidate answer during testing.
- REAPER sends its own candidates back with `addWebRTCIceCandidate`.
- The iPhone app status UI exposes a `Preview` row so agents/users can see whether WebRTC is active.
- Keep preview on WebRTC only; HTTP is used for recording downloads, not live preview.
- Lens selection uses AVFoundation rear camera discovery. Not every iPhone exposes `ultrawide` or `telephoto`; unavailable lens requests should fail clearly instead of silently pretending they worked.
- Looks include custom names plus a curated raw Core Image subset accepted as `ci:<filterName>`. Keep `VideoLook.rawFilterIDs` aligned with the REAPER dropdown list in `../src/reaper_video_recorder.mm`.

## Known issues and next work

- Bonjour discovery in the CLI may be less reliable than `dns-sd`; if discovery fails, verify with:

```sh
dns-sd -B _iphone-video-sync._tcp local
dns-sd -L iPhone _iphone-video-sync._tcp local
```

- Background/locked recording is not validated and may not be permitted by iOS.
- The WebSocket and HTTP servers are intentionally minimal. Harden them before relying on unattended long sessions.
- Add range/resume support for large interrupted downloads.
- Pending recordings can be restored while the app is still running; fully persistent recording metadata across app relaunch remains a future hardening area.
- Avoid broad rewrites of the manually generated Xcode project unless replacing it with a more maintainable project-generation workflow.
