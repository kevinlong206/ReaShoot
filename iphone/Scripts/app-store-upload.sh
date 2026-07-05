#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Scripts/app-store-upload.sh [options]

Archives the ReaShoot iPhone app, exports it for App Store Connect, and uploads it
with xcodebuild. Credentials are read from environment variables unless provided
as options.

Required for upload unless REASHOOT_USE_XCODE_ACCOUNT=1:
  APP_STORE_CONNECT_API_KEY_ID       App Store Connect API key ID
  APP_STORE_CONNECT_API_ISSUER_ID    App Store Connect issuer UUID
  APP_STORE_CONNECT_API_KEY_PATH     Path to AuthKey_<key-id>.p8

Options:
  --export-only, --no-upload         Export an IPA but do not upload it
  --upload                           Upload to App Store Connect (default)
  --build-number VALUE               CFBundleVersion for this archive
  --marketing-version VALUE          CFBundleShortVersionString for this archive
  --team-id VALUE                    Apple Developer team ID
  --build-root PATH                  Archive/export output directory
  --api-key-id VALUE                 App Store Connect API key ID
  --api-issuer-id VALUE              App Store Connect issuer UUID
  --api-key-path PATH                Path to AuthKey_<key-id>.p8
  -h, --help                         Show this help

Examples:
  APP_STORE_CONNECT_API_KEY_ID=ABC123DEFG \
  APP_STORE_CONNECT_API_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
  APP_STORE_CONNECT_API_KEY_PATH="$HOME/private_keys/AuthKey_ABC123DEFG.p8" \
    Scripts/app-store-upload.sh --marketing-version 1.0

  Scripts/app-store-upload.sh --export-only --build-number 202607041743
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
cd "$project_dir"

scheme="${REASHOOT_SCHEME:-ReaShoot}"
project="${REASHOOT_XCODE_PROJECT:-ReaShoot.xcodeproj}"
configuration="${REASHOOT_CONFIGURATION:-Release}"
team_id="${REASHOOT_TEAM_ID:-6QTJXLJJ62}"
bundle_id="${REASHOOT_BUNDLE_ID:-com.kevinlong.reashoot}"
build_number="${REASHOOT_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
marketing_version="${REASHOOT_MARKETING_VERSION:-}"
build_root="${REASHOOT_APP_STORE_BUILD_ROOT:-$project_dir/build/app-store}"
upload=1

api_key_id="${APP_STORE_CONNECT_API_KEY_ID:-}"
api_issuer_id="${APP_STORE_CONNECT_API_ISSUER_ID:-}"
api_key_path="${APP_STORE_CONNECT_API_KEY_PATH:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --export-only|--no-upload)
      upload=0
      ;;
    --upload)
      upload=1
      ;;
    --build-number)
      [[ $# -ge 2 ]] || die "--build-number requires a value"
      build_number="$2"
      shift
      ;;
    --build-number=*)
      build_number="${1#*=}"
      ;;
    --marketing-version)
      [[ $# -ge 2 ]] || die "--marketing-version requires a value"
      marketing_version="$2"
      shift
      ;;
    --marketing-version=*)
      marketing_version="${1#*=}"
      ;;
    --team-id)
      [[ $# -ge 2 ]] || die "--team-id requires a value"
      team_id="$2"
      shift
      ;;
    --team-id=*)
      team_id="${1#*=}"
      ;;
    --build-root)
      [[ $# -ge 2 ]] || die "--build-root requires a value"
      build_root="$2"
      shift
      ;;
    --build-root=*)
      build_root="${1#*=}"
      ;;
    --api-key-id)
      [[ $# -ge 2 ]] || die "--api-key-id requires a value"
      api_key_id="$2"
      shift
      ;;
    --api-key-id=*)
      api_key_id="${1#*=}"
      ;;
    --api-issuer-id)
      [[ $# -ge 2 ]] || die "--api-issuer-id requires a value"
      api_issuer_id="$2"
      shift
      ;;
    --api-issuer-id=*)
      api_issuer_id="${1#*=}"
      ;;
    --api-key-path)
      [[ $# -ge 2 ]] || die "--api-key-path requires a value"
      api_key_path="$2"
      shift
      ;;
    --api-key-path=*)
      api_key_path="${1#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ -d "$project" ]] || die "Xcode project not found: $project"
[[ -n "$build_number" ]] || die "build number is empty"
[[ "$build_number" =~ ^[0-9A-Za-z.-]+$ ]] || die "build number contains characters Apple will reject: $build_number"

auth_args=()
if [[ -n "$api_key_id$api_issuer_id$api_key_path" ]]; then
  [[ -n "$api_key_id" ]] || die "APP_STORE_CONNECT_API_KEY_ID is required with API key auth"
  [[ -n "$api_issuer_id" ]] || die "APP_STORE_CONNECT_API_ISSUER_ID is required with API key auth"
  [[ -n "$api_key_path" ]] || die "APP_STORE_CONNECT_API_KEY_PATH is required with API key auth"
  [[ -f "$api_key_path" ]] || die "API key file not found: $api_key_path"
  auth_args=(
    -authenticationKeyPath "$api_key_path"
    -authenticationKeyID "$api_key_id"
    -authenticationKeyIssuerID "$api_issuer_id"
  )
elif [[ "$upload" -eq 1 && "${REASHOOT_USE_XCODE_ACCOUNT:-0}" != "1" ]]; then
  die "upload requires App Store Connect API key variables, or set REASHOOT_USE_XCODE_ACCOUNT=1 to use Xcode Accounts"
fi

timestamp="$(date -u +%Y%m%d-%H%M%S)"
archive_path="$build_root/archives/ReaShoot-$timestamp.xcarchive"
export_path="$build_root/exports/ReaShoot-$timestamp"
export_options_plist="$build_root/ExportOptions-$timestamp.plist"
export_destination="export"
if [[ "$upload" -eq 1 ]]; then
  export_destination="upload"
fi

mkdir -p "$(dirname "$archive_path")" "$export_path"

cat > "$export_options_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>$export_destination</string>
  <key>distributionBundleIdentifier</key>
  <string>$bundle_id</string>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
  <key>method</key>
  <string>app-store-connect</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$team_id</string>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
PLIST

build_settings=(
  "DEVELOPMENT_TEAM=$team_id"
  "CURRENT_PROJECT_VERSION=$build_number"
)
if [[ -n "$marketing_version" ]]; then
  build_settings+=("MARKETING_VERSION=$marketing_version")
fi

export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=safe.bareRepository
export GIT_CONFIG_VALUE_0=all

echo "Archiving $scheme ($configuration) for App Store Connect..."
echo "Build number: $build_number"
if [[ -n "$marketing_version" ]]; then
  echo "Marketing version: $marketing_version"
fi

xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_root/DerivedData" \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  "${auth_args[@]}" \
  "${build_settings[@]}" \
  clean archive

echo "Exporting archive with destination=$export_destination..."
xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options_plist" \
  -allowProvisioningUpdates \
  "${auth_args[@]}"

echo "Archive: $archive_path"
echo "Export output: $export_path"
if [[ "$upload" -eq 1 ]]; then
  echo "Upload submitted to App Store Connect."
else
  echo "Export-only run complete. Upload by rerunning without --export-only."
fi
