#!/bin/bash
# Build, sign, install, and validate a tvOS app for Apple TV development use.
#
# This script is intentionally generic: configure it with environment variables
# instead of hardcoding a personal Apple ID, Team ID, Bundle ID, or device.
#
# Required by default:
#   - Run from a tvOS Xcode project repo, or set PROJECT_DIR.
#   - Set BUNDLE_ID; targets must derive their identifiers from APP_BUNDLE_IDENTIFIER.
#
# Common example, run from this repository root:
#   BUNDLE_ID="com.example.MoviePilotTV" ./scripts/apple-tv-renew.sh
#
# If you run it from another directory, set PROJECT_DIR to your own checkout:
#   PROJECT_DIR="/path/to/your/checkout" \
#   BUNDLE_ID="com.example.MoviePilotTV" \
#   /path/to/your/checkout/scripts/apple-tv-renew.sh

set -euo pipefail

FORCE_RENEW=0
PROFILE_TOOL="$(cd "$(dirname "$0")" && pwd)/apple_tv_profiles.py"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE_RENEW=1
      shift
      ;;
    --help|-h)
      cat <<'EOF'
Usage: scripts/apple-tv-renew.sh [--force]

Build, sign, install, and validate a tvOS app on a paired Apple TV.
By default, the script skips work only when the app and all embedded
extensions have readable, unexpired provisioning profiles. Use --force to build/install
anyway.
Run it from the repository root, or set PROJECT_DIR to your checkout path.
Configure with environment variables:
  PROJECT_DIR, PROJECT_FILE, WORKSPACE, SCHEME, CONFIGURATION
  BUNDLE_ID, APP_GROUP_IDENTIFIER, DEVELOPMENT_TEAM, DEVICE_ID, DEVICE_NAME_CONTAINS
  CLEAR_PROFILE_CACHE=1, MIN_VALID_SECONDS=432000
  CODESIGN_ENV_REPORT=1, KEYCHAIN_PATH

Example:
  BUNDLE_ID="com.example.MoviePilotTV" ./scripts/apple-tv-renew.sh
  BUNDLE_ID="com.example.MoviePilotTV" ./scripts/apple-tv-renew.sh --force
EOF
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      echo "Run scripts/apple-tv-renew.sh --help for usage." >&2
      exit 2
      ;;
  esac
done

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_FILE="${PROJECT_FILE:-}"
WORKSPACE="${WORKSPACE:-}"
SCHEME="${SCHEME:-}"
CONFIGURATION="${CONFIGURATION:-Release}"
BUNDLE_ID="${BUNDLE_ID:-}"
[ -n "$BUNDLE_ID" ] || {
  cat >&2 <<'EOF'
ERROR: BUNDLE_ID is required.
Set it to your own unique identifier, for example:
  BUNDLE_ID="com.example.MoviePilotTV" ./scripts/apple-tv-renew.sh
EOF
  exit 1
}
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
DEVICE_ID="${DEVICE_ID:-}"
DEVICE_NAME_CONTAINS="${DEVICE_NAME_CONTAINS:-Apple TV}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
ALLOW_PROVISIONING_DEVICE_REGISTRATION="${ALLOW_PROVISIONING_DEVICE_REGISTRATION:-1}"
CLEAR_PROFILE_CACHE="${CLEAR_PROFILE_CACHE:-0}"
MIN_VALID_SECONDS="${MIN_VALID_SECONDS:-432000}" # 5 days
CODESIGN_ENV_REPORT="${CODESIGN_ENV_REPORT:-1}"
KEYCHAIN_PATH="${KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"
LOG_FILE="${LOG_FILE:-$PROJECT_DIR/renew.log}"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "$msg" >> "$LOG_FILE"
}

fail() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing command: $1"
}

codesign_environment_report() {
  [ "$CODESIGN_ENV_REPORT" = "1" ] || return 0
  local identities keychain_status
  identities="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>&1 || true)"
  keychain_status="$(security show-keychain-info "$KEYCHAIN_PATH" 2>&1 || true)"
  log "Codesign environment report (report-only; does not verify private-key ACL or run codesign):"
  printf '%s\n' "$identities" | while read -r line; do log "  identity: $line"; done
  log "  keychain: $KEYCHAIN_PATH"
  log "  keychain status: $keychain_status"
  if ! printf '%s\n' "$identities" | grep -q 'Apple Development:'; then
    log "WARNING: no Apple Development signing identity found in $KEYCHAIN_PATH; xcodebuild signing may fail. Run: security find-identity -v -p codesigning '$KEYCHAIN_PATH'"
  fi
  if printf '%s\n' "$keychain_status" | grep -q 'User interaction is not allowed'; then
    log "WARNING: security show-keychain-info reported user interaction is not allowed for $KEYCHAIN_PATH. If xcodebuild later fails with errSecInternalComponent, unlock the keychain and run: security set-key-partition-list -S apple-tool:,apple:,codesign: -s -t private -k '<Mac login password>' '$KEYCHAIN_PATH'"
  fi
}

find_project_file() {
  if [ -n "$PROJECT_FILE" ]; then
    return
  fi
  local found
  found=$(find "$PROJECT_DIR" -maxdepth 1 -name '*.xcodeproj' -print | head -1 || true)
  [ -n "$found" ] || fail "PROJECT_FILE not set and no .xcodeproj found in $PROJECT_DIR"
  PROJECT_FILE="$(basename "$found")"
}

find_scheme() {
  if [ -n "$SCHEME" ]; then
    return
  fi
  SCHEME=$(xcodebuild -list -json -project "$PROJECT_DIR/$PROJECT_FILE" 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print((d.get("project",{}).get("schemes") or [""])[0])' || true)
  [ -n "$SCHEME" ] || fail "SCHEME not set and no scheme found in $PROJECT_FILE"
}

find_team() {
  if [ -n "$DEVELOPMENT_TEAM" ]; then
    return
  fi
  DEVELOPMENT_TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | grep -oE 'teamID = "([A-Z0-9]+)"' \
    | head -1 \
    | sed 's/teamID = "\([^"]*\)"/\1/' || true)
}

build_args_common=()
set_build_args() {
  build_args_common=()
  if [ -n "$WORKSPACE" ]; then
    build_args_common+=("-workspace" "$WORKSPACE")
  else
    build_args_common+=("-project" "$PROJECT_FILE")
  fi
  build_args_common+=("-scheme" "$SCHEME" "-configuration" "$CONFIGURATION")
  build_args_common+=("APP_BUNDLE_IDENTIFIER=$BUNDLE_ID")
  if [ -n "${APP_GROUP_IDENTIFIER:-}" ]; then
    build_args_common+=("APP_GROUP_IDENTIFIER=$APP_GROUP_IDENTIFIER")
  fi
  if [ -n "$DERIVED_DATA_PATH" ]; then
    build_args_common+=("-derivedDataPath" "$DERIVED_DATA_PATH")
  fi
}

find_device() {
  if [ -n "$DEVICE_ID" ]; then
    return
  fi
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
    | awk -v needle="$DEVICE_NAME_CONTAINS" 'tolower($0) ~ tolower(needle) && $0 ~ /available \(paired\)/ { for (i=1; i<=NF; i++) if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit } }' || true)
  if [ -z "$DEVICE_ID" ]; then
    DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
      | awk '$0 ~ /available \(paired\)/ { for (i=1; i<=NF; i++) if ($i ~ /^[0-9A-Fa-f-]{36}$/) { print $i; exit } }' || true)
  fi
  [ -n "$DEVICE_ID" ] || fail "no available paired Apple TV device found; set DEVICE_ID or DEVICE_NAME_CONTAINS"
}

find_destination() {
  local destination
  destination=$(xcodebuild "${build_args_common[@]}" -showdestinations 2>/dev/null \
    | awk -v id="$DEVICE_ID" '$0 ~ id && $0 ~ /platform:tvOS/ { print; exit }' \
    | sed -n 's/.*{ platform:tvOS, arch:[^,]*, id:\([^,]*\), name:.* }.*/platform=tvOS,id=\1/p' || true)
  if [ -z "$destination" ]; then
    destination="generic/platform=tvOS"
  fi
  echo "$destination"
}

move_cached_profiles() {
  [ "$CLEAR_PROFILE_CACHE" = "1" ] || return 0
  [ -n "$BUNDLE_ID" ] || return 0
  python3 "$PROFILE_TOOL" clear-cache "$BUNDLE_ID"
}

profile_info_for_app() {
  python3 "$PROFILE_TOOL" inspect "$1" "$BUNDLE_ID"
}

app_path_from_build_settings() {
  local settings_args=("${build_args_common[@]}" "-showBuildSettings" "-json")
  if [ -n "$DEVELOPMENT_TEAM" ]; then
    settings_args+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
  fi
  local settings
  settings=$(xcodebuild "${settings_args[@]}" 2>/dev/null) || return 1
  printf '%s\n' "$settings" | python3 -c '
import json, sys
from pathlib import Path
apps = [item["buildSettings"] for item in json.load(sys.stdin)
        if item.get("buildSettings", {}).get("PRODUCT_TYPE") == "com.apple.product-type.application"
        and item["buildSettings"].get("PRODUCT_BUNDLE_IDENTIFIER") == sys.argv[1]]
if len(apps) != 1:
    sys.exit("Expected one application target matching BUNDLE_ID")
print(Path(apps[0]["TARGET_BUILD_DIR"]) / apps[0]["FULL_PRODUCT_NAME"])
' "$BUNDLE_ID"
}

profile_seconds_remaining() {
  python3 - "$1" <<'PY'
import json, sys
try:
    value = json.loads(sys.argv[1]).get('secondsRemaining')
    print(value if value is not None else -1)
except Exception:
    print(-1)
PY
}

profile_ok() {
  python3 - "$1" <<'PY'
import json, sys
try:
    print('yes' if json.loads(sys.argv[1]).get('ok') else 'no')
except Exception:
    print('no')
PY
}

log "=== Apple TV renew started ==="
require_cmd xcodebuild
require_cmd xcrun
require_cmd security
require_cmd python3

cd "$PROJECT_DIR"
find_project_file
find_scheme
find_team
set_build_args

log "Project dir: $PROJECT_DIR"
log "Project file: ${WORKSPACE:-$PROJECT_FILE}"
log "Scheme: $SCHEME"
log "Configuration: $CONFIGURATION"
log "Development team: ${DEVELOPMENT_TEAM:-<project/default>}"
log "Bundle ID override: ${BUNDLE_ID:-<project default>}"
log "Force renew: $FORCE_RENEW"
codesign_environment_report

if [ "$FORCE_RENEW" != "1" ]; then
  if APP_PATH="$(app_path_from_build_settings 2>/dev/null)" && [ -d "$APP_PATH" ]; then
    profile_json="$(profile_info_for_app "$APP_PATH")"
    if [ "$(profile_ok "$profile_json")" = "yes" ]; then
      remaining="$(profile_seconds_remaining "$profile_json")"
      log "All embedded profiles are still valid; shortest lifetime (${remaining}s remaining); skipping. Use --force to build/install anyway."
      printf '%s\n' "$profile_json"
      exit 0
    else
      log "Existing app or extension has an invalid identifier or missing, unreadable, or expired profile; renewing."
    fi
  else
    log "Existing app product not found; renewing."
  fi
fi

find_device
log "Device ID: $DEVICE_ID"

move_cached_profiles | while read -r line; do log "$line"; done

DESTINATION=$(find_destination)
log "xcodebuild destination: $DESTINATION"

build_args=("${build_args_common[@]}" "-destination" "$DESTINATION" "-allowProvisioningUpdates" "ONLY_ACTIVE_ARCH=NO" "CODE_SIGN_STYLE=Automatic")
if [ -n "$DEVELOPMENT_TEAM" ]; then
  build_args+=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
fi
if [ "$ALLOW_PROVISIONING_DEVICE_REGISTRATION" = "1" ]; then
  build_args+=("-allowProvisioningDeviceRegistration")
fi

log "=== Build and sign ==="
xcodebuild clean build "${build_args[@]}" 2>&1 | tee -a "$LOG_FILE" || fail "build/sign failed"

log "=== Locate app product ==="
APP_PATH="$(app_path_from_build_settings)"
[ -d "$APP_PATH" ] || fail "app product not found: $APP_PATH"
log "App path: $APP_PATH"
log "=== Validate all embedded provisioning profiles before installation ==="
profile_json=$(profile_info_for_app "$APP_PATH")
log "Profile: $profile_json"
[ "$(profile_ok "$profile_json")" = "yes" ] || fail "profile validation failed: $profile_json"
remaining="$(profile_seconds_remaining "$profile_json")"
if [ "$remaining" -lt "$MIN_VALID_SECONDS" ]; then
  fail "shortest profile lifetime is not valid long enough: ${remaining}s remaining, need >= ${MIN_VALID_SECONDS}s"
fi

log "=== Install on Apple TV ==="
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1 | tee -a "$LOG_FILE" || fail "install failed"

log "=== Renewal complete ==="
printf '%s\n' "$profile_json"
