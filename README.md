# ReaShoot

ReaShoot lets you record video on your iPhone while recording audio in REAPER. Press record once in REAPER: your iPhone captures full-quality video, REAPER captures your session audio, and ReaShoot brings the finished movie back into the project in sync.

It replaces the awkward camera-app workflow: no starting two recordings by hand, no AirDrop/file transfer step, and less manual syncing afterward.

**Need help or want to contribute?** Open a [GitHub issue](https://github.com/kevinlong206/ReaShoot/issues) for bugs, crashes, confusing behavior, or feature requests. Technical build and contribution notes live in [CONTRIBUTING.md](CONTRIBUTING.md).

## What ReaShoot does

- Controls the companion iPhone app from REAPER over local Wi-Fi.
- Starts and stops iPhone video capture with REAPER recording.
- Shows a live iPhone preview inside REAPER.
- Downloads the finished `.mov` automatically.
- Inserts the movie on a `ReaShoot` track at the original record position.
- Uses the iPhone's embedded camera audio as a sync reference and tries to align the video to your REAPER audio.
- Keeps interrupted transfers recoverable on the iPhone.

## Requirements

- REAPER on macOS or Windows. Linux support is TBD.
- The ReaShoot iPhone app from this repository.
- An iPhone or other supported iOS device for the camera.
- iOS device and computer on the same reachable local network.
- Local-network permission enabled for the iPhone app.

Only iOS devices are supported as cameras today. Keep the iOS app open in the foreground while using ReaShoot. The app keeps the phone awake during capture, so plugging the phone into a charger is recommended.

## Quick start

1. Install the REAPER extension and the iPhone app.
2. Restart REAPER.
3. In REAPER, open the Action List and run `ReaShoot: Enable ReaShoot`.
4. Open the ReaShoot preview window.
5. Launch ReaShoot on the iPhone.
6. In the preview window, click `Setup`, then `Discover`.
7. Enter the pairing code shown on the iPhone and click `Pair`.
8. Record in REAPER as usual. ReaShoot starts and stops the iPhone video with you.
9. When you stop, choose whether to download or delete the iPhone take.

## Pairing your phone

ReaShoot connects from REAPER to the iOS device over your local network. The phone must be on the same Wi-Fi network as the computer, or on a network the computer can reach. The computer itself can be wired with Ethernet as long as it can connect to the iOS device.

To pair:

1. Open ReaShoot on the iOS device.
2. Open the ReaShoot preview window in REAPER.
3. Click `Setup`, then `Discover`.
4. Select the phone, enter the pairing code shown on the iOS device, and click `Pair`.

On Windows, automatic discovery may not always find the phone. If that happens, enter the phone's IP address manually in the setup fields, then pair with the code shown on the device.

## Preview window

The preview window is the main control surface. Use it to pair the iPhone, watch the live camera feed, choose capture settings, see recording/download progress, and recover pending recordings.

## Recording workflow

Enable ReaShoot before recording. When REAPER enters record, the iPhone starts recording video. When REAPER leaves record, ReaShoot asks what to do with the iPhone take.

If you choose **Download**, the phone prepares the movie, the helper downloads it, and REAPER inserts it on the `ReaShoot` track at the original record-start position. If you choose **Delete**, the phone deletes the take after confirmation.

The `ReaShoot` track is intentionally kept record-disabled. REAPER remains responsible for production audio recording; iPhone audio stays inside the movie so ReaShoot can use it for sync and alignment.

## Capture settings

Use the preview window to choose resolution, FPS, orientation, aspect ratio, lens, zoom, and look. Lens and zoom options depend on the iPhone hardware.

Non-natural looks are applied on the iPhone after you choose to download a take. Encoding and download progress are shown in the preview window.

## Recovering recordings

If a download fails, is canceled, or cannot be acknowledged, the iPhone keeps the recording instead of deleting it. Use `Pending...` in the preview window, or run `ReaShoot: Restore Pending iPhone Recording`, to choose a pending clip and either download it into the project or delete it.

Use `Delete All` in the preview window, or run `ReaShoot: Delete All Pending iPhone Recordings`, to remove all pending clips after confirmation.

After REAPER verifies a downloaded movie and acknowledges the transfer, the iPhone app deletes its local copy.

## Troubleshooting

### REAPER does not see ReaShoot

Restart REAPER after installing the extension. REAPER loads native extensions only at process startup.

### The iPhone is not discovered

Make sure the iPhone and computer are on the same local Wi-Fi network, the iPhone app is open, and local-network permission is enabled for ReaShoot on iOS.

### Pairing fails

Use the current pairing code shown in the iPhone app. If the phone rejects a saved token, pair again from `Setup`.

### Preview works but playback looks different

The docked preview is optimized for responsiveness and smooth editing. Playback audio comes from REAPER, not the internal preview renderer. The downloaded `.mov` is the source of truth for final media quality.

### A download failed

Use `Pending...` to recover the recording from the iPhone. Failed or canceled transfers remain pending until REAPER verifies the movie and acknowledges the transfer.

For build instructions, architecture notes, validation commands, and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).
