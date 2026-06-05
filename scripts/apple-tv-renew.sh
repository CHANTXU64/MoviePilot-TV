#!/bin/bash
# Build, sign, install, and validate a tvOS app for Apple TV development use.
#
# This script is intentionally generic: configure it with environment variables
# instead of hardcoding a personal Apple ID, Team ID, Bundle ID, or device.
#
# Required by default:
#   - Run from a tvOS Xcode project repo, or set PROJECT_DIR.
#   - Set BUNDLE_ID unless the Xcode project already contains the desired value.
#
# Common example:
#   PROJECT_DIR="$HOME/code/MoviePilot-TV" \
#   PROJECT_FILE="MoviePilot-TV.xcodeproj" \
#   SCHEME="MoviePilot-TV" \
#   BUNDLE_ID="org.example.MoviePilotTV" \
#   ./scripts/apple-tv-renew.sh

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'EOF'
Usage: scripts/apple-tv-renew.sh

Build, sign, install, and validate a tvOS app on a paired Apple TV.
Configure with environment variables:
  PROJECT_DIR, PROJECT_FILE, WORKSPACE, SCHEME, CONFIGURATION
  BUNDLE_ID, DEVELOPMENT_TEAM, DEVICE_ID, DEVICE_NAME_CONTAINS
  CLEAR_PROFILE_CACHE=1, MIN_VALID_SECONDS=432000
EOF
  exit 0
fi

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PROJECT_FILE="${PROJECT_FILE:-}"
WORKSPACE="${WORKSPACE:-}"
SCHEME="${SCHEME:-}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUNDLE_ID="${BUNDLE_ID:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
DEVICE_ID="${DEVICE_ID:-}"
DEVICE_NAME_CONTAINS="${DEVICE_NAME_CONTAINS:-Apple TV}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-}"
ALLOW_PROVISIONING_DEVICE_REGISTRATION="${ALLOW_PROVISIONING_DEVICE_REGISTRATION:-1}"
CLEAR_PROFILE_CACHE="${CLEAR_PROFILE_CACHE:-0}"
MIN_VALID_SECONDS="${MIN_VALID_SECONDS:-432000}" # 5 days
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
  if [ -z "$DEVELOPMENT_TEAM" ]; then
    DEVELOPMENT_TEAM=$(security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*Apple Development: .* (\([A-Z0-9][A-Z0-9]*\)).*/\1/p' \
      | head -1 || true)
  fi
  [ -n "$DEVELOPMENT_TEAM" ] || fail "DEVELOPMENT_TEAM not set and could not infer it from Xcode accounts or signing identities"
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
  [ -n "$DERIVED_DATA_PATH" ] && build_args_common+=("-derivedDataPath" "$DERIVED_DATA_PATH")
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
  python3 - "$BUNDLE_ID" <<'PY'
import plistlib, shutil, subprocess, sys
from datetime import datetime
from pathlib import Path
bundle_id = sys.argv[1]
cache_dir = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
backup_dir = Path('/tmp/apple-tv-renew-profile-backups') / datetime.now().strftime('%Y%m%d_%H%M%S')
moved = 0
if cache_dir.exists():
    backup_dir.mkdir(parents=True, exist_ok=True)
    for path in cache_dir.glob('*.mobileprovision'):
        try:
            data = subprocess.check_output(['security', 'cms', '-D', '-i', str(path)], stderr=subprocess.DEVNULL)
            profile = plistlib.loads(data)
        except Exception:
            continue
        app_id = (profile.get('Entitlements') or {}).get('application-identifier', '')
        if app_id.endswith('.' + bundle_id):
            shutil.move(str(path), str(backup_dir / path.name))
            moved += 1
print(f'moved {moved} cached profile(s) to {backup_dir}' if moved else 'moved 0 cached profiles')
PY
}

profile_info_for_app() {
  local app_path="$1"
  python3 - "$app_path" <<'PY'
import json, plistlib, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
app = Path(sys.argv[1])
profile = app / 'embedded.mobileprovision'
if not profile.exists():
    print(json.dumps({'ok': False, 'error': 'embedded.mobileprovision not found', 'path': str(profile)}))
    sys.exit(0)
data = subprocess.check_output(['security', 'cms', '-D', '-i', str(profile)], stderr=subprocess.DEVNULL)
p = plistlib.loads(data)
ent = p.get('Entitlements') or {}
exp = p.get('ExpirationDate')
if exp and exp.tzinfo is None:
    exp = exp.replace(tzinfo=timezone.utc)
remaining = int((exp - datetime.now(timezone.utc)).total_seconds()) if exp else None
print(json.dumps({
    'ok': True,
    'name': p.get('Name'),
    'uuid': p.get('UUID'),
    'creationDate': p.get('CreationDate').isoformat() if p.get('CreationDate') else None,
    'expirationDate': exp.isoformat() if exp else None,
    'secondsRemaining': remaining,
    'applicationIdentifier': ent.get('application-identifier'),
    'teamIdentifier': ent.get('com.apple.developer.team-identifier'),
    'profilePath': str(profile),
}, ensure_ascii=False))
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
find_device
set_build_args

log "Project dir: $PROJECT_DIR"
log "Project file: ${WORKSPACE:-$PROJECT_FILE}"
log "Scheme: $SCHEME"
log "Configuration: $CONFIGURATION"
log "Development team: $DEVELOPMENT_TEAM"
log "Bundle ID override: ${BUNDLE_ID:-<project default>}"
log "Device ID: $DEVICE_ID"

move_cached_profiles | while read -r line; do log "$line"; done

DESTINATION=$(find_destination)
log "xcodebuild destination: $DESTINATION"

build_args=("${build_args_common[@]}" "-destination" "$DESTINATION" "-allowProvisioningUpdates" "ONLY_ACTIVE_ARCH=NO" "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM" "CODE_SIGN_STYLE=Automatic")
if [ "$ALLOW_PROVISIONING_DEVICE_REGISTRATION" = "1" ]; then
  build_args+=("-allowProvisioningDeviceRegistration")
fi
if [ -n "$BUNDLE_ID" ]; then
  build_args+=("PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID")
fi

log "=== Build and sign ==="
xcodebuild clean build "${build_args[@]}" 2>&1 | tee -a "$LOG_FILE" || fail "build/sign failed"

log "=== Locate app product ==="
settings=$(xcodebuild "${build_args_common[@]}" -configuration "$CONFIGURATION" -showBuildSettings \
  ${BUNDLE_ID:+PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID"} \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" 2>/dev/null)
TARGET_BUILD_DIR=$(printf '%s\n' "$settings" | awk -F ' = ' '/ TARGET_BUILD_DIR / {print $2; exit}')
WRAPPER_NAME=$(printf '%s\n' "$settings" | awk -F ' = ' '/ WRAPPER_NAME / {print $2; exit}')
[ -n "$TARGET_BUILD_DIR" ] || fail "TARGET_BUILD_DIR not found"
[ -n "$WRAPPER_NAME" ] || WRAPPER_NAME="$SCHEME.app"
APP_PATH="$TARGET_BUILD_DIR/$WRAPPER_NAME"
[ -d "$APP_PATH" ] || fail "app product not found: $APP_PATH"
log "App path: $APP_PATH"

log "=== Install on Apple TV ==="
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1 | tee -a "$LOG_FILE" || fail "install failed"

log "=== Validate embedded provisioning profile ==="
profile_json=$(profile_info_for_app "$APP_PATH")
log "Profile: $profile_json"
remaining=$(python3 - "$profile_json" <<'PY'
import json, sys
print(json.loads(sys.argv[1]).get('secondsRemaining') or -1)
PY
)
if [ "$remaining" -lt "$MIN_VALID_SECONDS" ]; then
  fail "profile is not valid long enough: ${remaining}s remaining, need >= ${MIN_VALID_SECONDS}s"
fi

log "=== Renewal complete ==="
printf '%s\n' "$profile_json"
