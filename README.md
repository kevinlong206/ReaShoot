# REAPER Video Recorder

macOS-only REAPER extension MVP for recording one webcam/video source in sync with REAPER transport.

## MVP behavior

- Adds REAPER actions:
  - `Video Recorder: Show/Hide Preview`
  - `Video Recorder: Enable/Disable Transport Follow`
- Shows a native macOS live preview window using AVFoundation.
- Starts video recording when REAPER enters record.
- Stops video recording when REAPER leaves record.
- Shows the preview in REAPER's docker.
- Inserts the finalized `.mov` onto a `Video Recorder` track at the record-start timeline position.
- Shows load/record/finalize/import state in the preview status label instead of console chatter.

## Build

```sh
make
```

By default the Makefile builds for the current Mac architecture. To build a universal binary:

```sh
make ARCH_FLAGS="-arch arm64 -arch x86_64"
```

## Install

```sh
make install
```

Restart REAPER, then open the Action List and search for `Video Recorder`.

If macOS blocks the dylib during local development:

```sh
xattr -dr com.apple.quarantine "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
codesign --force --sign - "$HOME/Library/Application Support/REAPER/UserPlugins/reaper_video_recorder.dylib"
```

## Notes

- The extension records video only; REAPER remains responsible for audio recording and mixing.
- Camera permission is requested the first time the preview/session is opened.
- Captures are written under `Video Recordings` in the saved project directory, or under REAPER's resource path for unsaved projects.
