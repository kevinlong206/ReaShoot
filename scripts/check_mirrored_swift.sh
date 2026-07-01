#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

check_pair() {
  left="$1"
  right="$2"
  if ! cmp -s "$root/$left" "$root/$right"; then
    echo "Mirrored Swift files differ:" >&2
    echo "  $left" >&2
    echo "  $right" >&2
    diff -u "$root/$left" "$root/$right" >&2 || true
    exit 1
  fi
}

check_pair "helper/Sources/VideoSyncCore/Checksum.swift" "iphone/Sources/VideoSyncCore/Checksum.swift"
check_pair "helper/Sources/VideoSyncCore/ControlProtocol.swift" "iphone/Sources/VideoSyncCore/ControlProtocol.swift"
check_pair "helper/Sources/video-sync-mac/ControlClient.swift" "iphone/Sources/video-sync-mac/ControlClient.swift"
check_pair "helper/Sources/video-sync-mac/DebugLog.swift" "iphone/Sources/video-sync-mac/DebugLog.swift"
check_pair "helper/Sources/video-sync-mac/Discovery.swift" "iphone/Sources/video-sync-mac/Discovery.swift"
check_pair "helper/Sources/video-sync-mac/Downloader.swift" "iphone/Sources/video-sync-mac/Downloader.swift"
check_pair "helper/Sources/video-sync-mac/VideoSyncMacCLI.swift" "iphone/Sources/video-sync-mac/VideoSyncMacCLI.swift"

echo "Mirrored Swift files match."
