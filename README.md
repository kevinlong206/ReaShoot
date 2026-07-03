# ReaShoot

ReaShoot is a macOS-only REAPER extension for controlling a companion iPhone camera app from REAPER, recording full-quality iPhone video, and inserting the downloaded movie in sync with the REAPER transport.

## MVP behavior

- Adds REAPER actions:
  - `ReaShoot: Enable/Disable ReaShoot`
  - `ReaShoot: Show/Hide Preview`
  - `ReaShoot: Float/Dock Preview`
  - `ReaShoot: Align Selected Video Item`
  - `ReaShoot: Restore Pending iPhone Recording`
  - `ReaShoot: Delete All Pending iPhone Recordings`
  - `ReaShoot: Enable/Disable Transport Follow`
- Adds a main-toolbar toggle button for enabling/disabling all video behavior.
- Shows the iPhone live preview in a native macOS preview window.
- Shows the active iPhone profile below the preview, including resolution, frame rate, orientation, aspect, lens, zoom, and look; status text turns red while recording.
- Controls the companion iPhone app for full-resolution iPhone capture. The REAPER extension no longer records directly from macOS webcams or Continuity Camera.
- Records iPhone camera audio into the `.mov` alongside video so the inserted item contains an alignment reference.
- Starts video recording when REAPER enters record.
- Stops video recording when REAPER leaves record.
- Keeps video behavior disabled by default until the toolbar/action toggle is enabled.
- Creates the `ReaShoot` track as soon as video features are enabled, before the first recording finishes.
- Keeps REAPER audio recording disabled on the `ReaShoot` track; camera audio stays embedded in the recorded movie item.
- Shows the preview in a floating window by default; the `Float/Dock Preview` action can still toggle docking and remembers that choice.
- Shows recorded video playback in the same preview panel when REAPER plays over an item on the `ReaShoot` track.
- Adds a `Float/Dock Preview` action because REAPER's normal docker undock controls do not work reliably for this custom native preview view.
- Mutes the docked preview's internal player so playback audio comes only from REAPER.
- Lets the docked playback player run smoothly and only re-seeks on source changes, playback start, or larger drift.
- Inserts the finalized `.mov` onto a `ReaShoot` track at the record-start timeline position.
- After insertion, compares the movie's embedded camera audio against the first non-video track item that overlaps the video item and shifts the video item to the strongest correlation match on that reference.
- Can manually re-run alignment for an existing project with `ReaShoot: Align Selected Video Item`; select the item on the `ReaShoot` track first, or it falls back to that track's latest item. If a REAPER time selection is active, only that region is analyzed.
- Shows load/record/finalize/import state in the preview status label instead of console chatter.
- Places downloaded iPhone video at the REAPER record-start timeline position.
- Controls the companion iPhone app for 4K recording, low-latency Wi-Fi preview, download/restore, and timeline insertion over the local Wi-Fi/Bonjour network.
- The iPhone preview uses a low-latency local H.264 stream. The iPhone renders the selected look into low-resolution preview frames before sending them to REAPER.
- The dock includes capture profile controls for resolution, FPS, orientation, social aspect ratio, lens, zoom, and baked-in artistic look. Changing a profile control sends the new profile to the iPhone immediately when paired.
- The look picker keeps the custom looks plus a curated Core Image subset for music-video use, including thermal/X-ray, gradients/edges, crystallize/pixel/halftone, and a few kaleidoscope/distortion looks. `Prev` and `Next` buttons beside the picker make it quick to audition looks.
- During iPhone recording stop, REAPER prompts before any on-phone look encoding so unwanted takes can be deleted without waiting.
- If a non-natural iPhone look is selected and the user chooses Download, the dock status shows on-phone look encoding progress before the full-resolution movie downloads.
- When an iPhone recording stops, REAPER prompts to either download the video or delete it from the iPhone. Delete requires a second confirmation; canceling that confirmation downloads instead.
- If a download fails or is canceled before transfer acknowledgement, the iPhone keeps the pending recording. Use the preview window's `Pending...` button or `ReaShoot: Restore Pending iPhone Recording` to list pending clips on the phone, then either download one into the project or delete it from the phone. Use `Delete All` in the preview window or `ReaShoot: Delete All Pending iPhone Recordings` to remove every pending clip from the phone after confirmation.
- After the Mac verifies the downloaded movie and acknowledges transfer, the iPhone app deletes its local copy immediately.
- The iPhone app disables the idle timer while it is ready/listening so the phone does not sleep and interrupt preview on a tripod.
- The iPhone app status screen shows `Keep awake: Yes` when the idle timer is disabled.

## Build

```sh
make
```

Run the lightweight validation suite with:

```sh
make check
```

By default the Makefile builds for the current Mac architecture. To build a universal binary:

```sh
make ARCH_FLAGS="-arch arm64 -arch x86_64"
```

The companion iPhone app is now consolidated in this repository under `iphone/`. Build it with:

```sh
cd iphone
xcodebuild -project ReaShoot.xcodeproj -scheme ReaShoot -destination 'generic/platform=iOS' build
```

For local device iteration, this tested device command is usually more useful:

```sh
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all \
  xcodebuild -project iphone/ReaShoot.xcodeproj \
  -scheme ReaShoot \
  -destination 'platform=iOS,id=797DC5E5-610E-5972-9FD3-B0045CA5745F' \
  DEVELOPMENT_TEAM=6QTJXLJJ62 \
  build
```

## Install

```sh
make install
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reashoot-mac"
codesign --verify "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_reashoot.dylib"
```

`make install` ad-hoc signs the helper and REAPER extension dylib.

Restart REAPER, then open the Action List and search for `ReaShoot`.

If macOS blocks the dylib during local development:

```sh
xattr -dr com.apple.quarantine "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_reashoot.dylib"
make install
```

## Notes

- REAPER remains responsible for production audio recording and mixing; iPhone camera audio is captured as a sync/alignment reference.
- macOS camera and microphone permission are not required because capture happens in the iPhone app.
- The companion iPhone app sources live in `iphone/`; old external development copies should no longer be treated as the source of truth.
- The extension builds and installs a bundled `reashoot-mac` helper next to the REAPER extension dylib.
- To use the extension, launch the iPhone app, click `iPhone Setup` in the REAPER dock, click `Discover`, enter the pairing code shown on the iPhone, click `Pair`, then click `Test` to verify preview/control before recording.
- The iPhone app shows the currently configured capture profile and pending recordings. Pending videos can be deleted directly in the app. Aspect ratio is currently metadata/framing intent; resolution, FPS, orientation, lens, zoom, and selected look are applied on the iPhone side. Non-natural looks are applied only after the user chooses to download a stopped clip and are baked into the downloaded movie while preserving the camera audio track.
- Lens options depend on the connected iPhone hardware. Zoom is clamped to the selected camera's supported range; values beyond a physical lens's native view may be digital crop rather than guaranteed optical zoom.
- Captures are written under `ReaShoot Recordings` in the saved project directory, or under REAPER's resource path for unsaved projects.
- A tested recording inspected with `ffprobe` was `1920x1080` H.264 at a stable ~30 fps and ~24 Mbps, so laggy motion in the docked preview can be a preview playback issue rather than a bad recording.
- The docked playback preview intentionally avoids frequent exact seeks; it may drift slightly before correcting, but this keeps AVPlayer playback smooth.
- True real-time waveform drawing during capture is not implemented because REAPER receives the media after the iPhone app finalizes and downloads the movie.

## Iterating locally

- Restart REAPER after every `make install`; the extension dylib is loaded at process startup.
- Keep protocol changes mirrored between `helper/Sources/ReaShootCore/ControlProtocol.swift` and `iphone/Sources/ReaShootCore/ControlProtocol.swift`.
- Keep helper CLI behavior mirrored between `helper/Sources/reashoot-mac` and `iphone/Sources/reashoot-mac`.
- Run `make check` before committing shared Swift changes; it verifies mirrored helper/iPhone files and runs the Swift checks.
- Xcode/SwiftPM may regenerate `iphone/Package.resolved` or local `.build` directories during builds. Do not commit those unless dependency pinning intentionally changes.
