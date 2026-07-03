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

check_pair "helper/Sources/ReaShootCore/Checksum.swift" "iphone/Sources/ReaShootCore/Checksum.swift"
check_pair "helper/Sources/ReaShootCore/ControlProtocol.swift" "iphone/Sources/ReaShootCore/ControlProtocol.swift"
check_pair "helper/Sources/reashoot-mac/ControlClient.swift" "iphone/Sources/reashoot-mac/ControlClient.swift"
check_pair "helper/Sources/reashoot-mac/DebugLog.swift" "iphone/Sources/reashoot-mac/DebugLog.swift"
check_pair "helper/Sources/reashoot-mac/Discovery.swift" "iphone/Sources/reashoot-mac/Discovery.swift"
check_pair "helper/Sources/reashoot-mac/Downloader.swift" "iphone/Sources/reashoot-mac/Downloader.swift"
check_pair "helper/Sources/reashoot-mac/ReaShootMacCLI.swift" "iphone/Sources/reashoot-mac/ReaShootMacCLI.swift"

echo "Mirrored Swift files match."
