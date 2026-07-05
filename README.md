# ReaShoot

ReaShoot lets REAPER control an iPhone as a video camera. Start recording in REAPER, capture full-quality iPhone video, download the finished movie, and place it on a `ReaShoot` track in time with your session.

**Need help or want to contribute?** Open a [GitHub issue](https://github.com/kevinlong206/ReaPhoneVideo/issues) for bugs, crashes, confusing behavior, or feature requests. Technical build and contribution notes live in [CONTRIBUTING.md](CONTRIBUTING.md).

## What ReaShoot does

ReaShoot is built for musicians, producers, and video creators who want a simple way to capture phone video while recording in REAPER.

- Controls the companion iPhone app from REAPER over local Wi-Fi.
- Shows a live iPhone preview in a floating or docked REAPER window.
- Starts and stops iPhone video capture with the REAPER transport.
- Downloads the finished `.mov` and inserts it as one media item on a `ReaShoot` track.
- Keeps iPhone camera audio embedded in the movie as an alignment reference.
- Tries to auto-align the video item to overlapping REAPER audio after import.
- Lets you recover pending recordings if a transfer is canceled or interrupted.

## Requirements

- REAPER on macOS for the full current experience.
- The ReaShoot iPhone app from this repository.
- iPhone and computer on the same local Wi-Fi network.
- Local-network permission enabled for the iPhone app.

Windows support is in progress. The Windows build includes the helper, REAPER extension DLL, shared setup panel, pairing/configure/start/stop/download flow, pending recording restore/delete, preview, playback preview, and media insertion.

## Quick start

1. Install the REAPER extension and the iPhone app.
2. Restart REAPER.
3. In REAPER, open the Action List and run `ReaShoot: Enable ReaShoot`.
4. Open the ReaShoot preview window.
5. Launch ReaShoot on the iPhone.
6. In the REAPER preview window, click `Setup`, then `Discover`.
7. Enter the pairing code shown on the iPhone and click `Pair`.
8. Press record in REAPER. ReaShoot starts recording on the iPhone.
9. Stop recording in REAPER. Choose whether to download or delete the stopped take.

## Preview window

The preview window is the main control surface:

- **Large status text** shows important user-facing state, including recording, transfer, encoding, and error messages.
- **Small detail text** shows transport/profile information such as Wi-Fi, resolution, FPS, orientation, aspect, lens, zoom, look, and decode status.
- **Setup** opens pairing and connection controls.
- **Pending...** lists recordings still stored on the iPhone.
- **Delete All** removes all pending iPhone recordings after confirmation.
- **Prev / Next** quickly auditions video looks.

During playback or live preview, the small detail text reports whether preview decoding is using hardware or software and names the decode system, for example `Preview HW decode: VideoToolbox` or `Playback Software decode: FFmpeg software`.

## Recording workflow

Enable ReaShoot before recording. When REAPER enters record, the iPhone starts recording video. When REAPER leaves record, ReaShoot asks what to do with the iPhone take.

If you choose **Download**, the phone prepares the movie, the helper downloads it, and REAPER inserts it on the `ReaShoot` track at the original record-start position. If you choose **Delete**, the phone deletes the take after confirmation.

The `ReaShoot` track is intentionally kept record-disabled. REAPER remains responsible for production audio recording; iPhone audio stays inside the movie so ReaShoot can use it for sync and alignment.

## Looks and capture settings

The preview window includes iPhone capture controls:

- Resolution
- FPS
- Orientation
- Social aspect ratio
- Lens
- Zoom
- Look

Changing a profile control sends the new profile to the paired iPhone. Lens options depend on iPhone hardware, and zoom is clamped to the selected camera's supported range.

Non-natural looks are applied on the iPhone after you choose to download a stopped take. While the phone encodes a look, the large status text shows progress such as `Encoding iPhone look: 42%`. Download progress is also shown there so it is clear the app is still working.

## Pending recordings

If a download fails, is canceled, or cannot be acknowledged, the iPhone keeps the recording instead of deleting it. Use `Pending...` in the preview window, or run `ReaShoot: Restore Pending iPhone Recording`, to choose a pending clip and either download it into the project or delete it.

Use `Delete All` in the preview window, or run `ReaShoot: Delete All Pending iPhone Recordings`, to remove all pending clips after confirmation.

After REAPER verifies a downloaded movie and acknowledges the transfer, the iPhone app deletes its local copy.

## REAPER actions

ReaShoot registers these actions:

- `ReaShoot: Enable ReaShoot`
- `ReaShoot: Float/Dock Preview`
- `ReaShoot: Align Selected Video Item`
- `ReaShoot: Restore Pending iPhone Recording`
- `ReaShoot: Delete All Pending iPhone Recordings`
- `ReaShoot: Enable/Disable Transport Follow`

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

## Project status

ReaShoot is under active development. The macOS version is the primary full implementation today. Windows support is actively being brought up with shared UI, helper, preview, playback, and media insertion code.

For build instructions, architecture notes, validation commands, and contribution guidelines, see [CONTRIBUTING.md](CONTRIBUTING.md).
