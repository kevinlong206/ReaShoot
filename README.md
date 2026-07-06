# ReaShoot

ReaShoot is a standalone desktop app for recording high-quality iPhone video from your Mac. Open ReaShoot on the iPhone, pair it with the Mac app over your local network, use the live preview to frame the shot, then start and stop recording from the desktop.

The iPhone records the full-quality `.mov` with embedded camera audio. When you stop, ReaShoot lets you download or delete the take; downloaded files default to `~/Movies/ReaShoot` and can be revealed in Finder. Interrupted transfers stay recoverable on the iPhone until the desktop app verifies and acknowledges the download.

The older REAPER extension remains in this repository as a legacy/secondary target, but this branch is focused on the general-purpose desktop app.

**Need help or want to contribute?** Open a [GitHub issue](https://github.com/kevinlong206/ReaShoot/issues) for bugs, crashes, confusing behavior, or feature requests. Technical build and contribution notes live in [CONTRIBUTING.md](CONTRIBUTING.md).

## What ReaShoot does

- Controls the companion iPhone app over local Wi-Fi/Bonjour.
- Shows a live iPhone preview in a macOS desktop window.
- Starts and stops iPhone video capture from the desktop.
- Lets you choose resolution, FPS, orientation, aspect ratio, lens, zoom, and look.
- Prompts to download or delete each stopped take.
- Shows videos still stored on the iPhone in a `Videos on iPhone` window.
- Downloads verified `.mov` files to `~/Movies/ReaShoot` by default.
- Keeps failed or canceled transfers stored on the iPhone for later recovery.

## Requirements

- macOS 14 or newer for the first desktop app target.
- The ReaShoot iPhone app from this repository, bundle ID `com.kevinlong.reashoot`.
- An iPhone or other supported iOS device for the camera.
- iPhone and Mac on the same reachable local network.
- Local-network permission enabled for the iPhone app.

Only iOS devices are supported as cameras today. Keep the iPhone app open in the foreground while using ReaShoot. The app keeps the phone awake during capture, so plugging the phone into a charger is recommended.

## Quick start

1. Build or install `ReaShoot.app` on the Mac and the ReaShoot app on the iPhone.
2. Launch ReaShoot on the iPhone and keep it open.
3. Launch `ReaShoot.app` on the Mac.
4. Click `Discover`, or enter the iPhone host/IP manually if discovery fails.
5. Click `Pair` on the Mac, then accept the pairing request shown on the iPhone.
6. Click `Start Preview` to frame the shot.
7. Choose capture settings, then click `Start Recording`.
8. Click the same recording button again to stop, then choose `Download` or `Delete`.

## Pairing your phone

ReaShoot connects from the Mac to the iPhone over your local network. The phone must be on the same Wi-Fi network as the Mac, or on a network the Mac can reach. The Mac can be wired with Ethernet as long as it can connect to the iPhone.

The Mac app makes Bonjour discovery prominent and keeps manual host/IP entry as a fallback. Pairing no longer requires typing a code: the iPhone shows `Accept pairing request from <computer>` and records the paired computer name after you accept. Only one computer can be paired at a time; accepting a new request replaces the previous pairing. Pairing tokens are credentials for controlling the phone; do not commit or share them.

## Preview and recording

The preview uses an authenticated H.264 WebSocket stream from the iPhone. The desktop app starts preview through the control channel, connects to the returned preview socket, decodes frames on macOS with VideoToolbox, and displays them in the app window.

When recording stops, the desktop app first receives recording metadata from the phone, then prompts before doing any download/delete action. Non-natural looks are prepared on the iPhone only after you choose to download.

## Recovering recordings

If a download fails, is canceled, or cannot be acknowledged, the iPhone keeps the recording instead of deleting it. Use `Videos on iPhone` in the desktop app to review stored phone videos and either download or delete them.

After the desktop app verifies a downloaded movie and acknowledges the transfer, the iPhone app deletes its local copy.

## Legacy REAPER extension

The repository still contains the original native REAPER extension for macOS and Windows. It uses the same iPhone app, protocol, helper, and preview transport, but it is no longer the primary product direction on this branch. See [CONTRIBUTING.md](CONTRIBUTING.md) for build details and legacy target notes.

## Troubleshooting

### The iPhone is not discovered

Make sure the iPhone and Mac are on the same local network, the iPhone app is open in the foreground, and local-network permission is enabled for ReaShoot on iOS. If Bonjour discovery still fails, enter the iPhone host or IP address manually.

### Pairing fails

Click `Pair` in the Mac app and accept the request on the iPhone. If the phone rejects a saved token, pair again from the Mac app.

### A download failed

Use `Videos on iPhone` to recover the recording from the iPhone. Failed or canceled transfers remain on the phone until the desktop app verifies the movie and acknowledges the transfer.

For build instructions, architecture notes, validation commands, and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).
