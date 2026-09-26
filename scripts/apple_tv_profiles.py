"""Inspect the provisioning profiles of an app and its embedded extensions."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import shutil
import subprocess


def belongs_to_app(identifier, app_identifier):
    return isinstance(identifier, str) and (
        identifier == app_identifier or identifier.startswith(app_identifier + ".")
    )


def bundle_identifiers(app, expected):
    bundles = [app, *sorted((app / "PlugIns").rglob("*.appex"))]
    identifiers = {}
    for bundle in bundles:
        with (bundle / "Info.plist").open("rb") as source:
            identifier = plistlib.load(source).get("CFBundleIdentifier")
        valid = identifier == expected if bundle == app else (
            belongs_to_app(identifier, expected) and identifier != expected
        )
        if not valid or identifier in identifiers.values():
            raise ValueError(f"Invalid bundle identifier for {bundle.name}: {identifier!r}")
        identifiers[bundle] = identifier
    return identifiers


def read_profile(path):
    data = subprocess.check_output(
        ["security", "cms", "-D", "-i", str(path)], stderr=subprocess.DEVNULL
    )
    profile = plistlib.loads(data)
    if not isinstance(profile, dict):
        raise ValueError("Provisioning profile is not a dictionary")
    return profile


def profile_info(bundle, identifier, now):
    path = bundle / "embedded.mobileprovision"
    result = {"bundleIdentifier": identifier, "profilePath": str(path), "ok": False}
    try:
        if not path.is_file():
            raise ValueError("embedded.mobileprovision not found")
        profile = read_profile(path)
        expiration = profile.get("ExpirationDate")
        if not isinstance(expiration, datetime):
            raise ValueError("Missing or invalid ExpirationDate")
        if expiration.tzinfo is None:
            expiration = expiration.replace(tzinfo=timezone.utc)
        remaining = int((expiration - now).total_seconds())
        result.update(
            name=profile.get("Name"), expirationDate=expiration.isoformat(),
            secondsRemaining=remaining, ok=remaining > 0,
        )
        if remaining <= 0:
            result["error"] = "Provisioning profile is expired"
    except (OSError, ValueError, TypeError, subprocess.SubprocessError) as exc:
        result["error"] = str(exc)
    return result


def inspect_app(app, expected):
    try:
        identifiers = bundle_identifiers(app, expected)
    except (OSError, ValueError, TypeError, AttributeError) as exc:
        return {"ok": False, "error": str(exc), "secondsRemaining": None}
    now = datetime.now(timezone.utc)
    profiles = [profile_info(bundle, identifier, now) for bundle, identifier in identifiers.items()]
    remaining = [profile.get("secondsRemaining") for profile in profiles]
    return {
        "ok": all(profile["ok"] for profile in profiles),
        "secondsRemaining": min(remaining) if all(value is not None for value in remaining) else None,
        "profiles": profiles,
    }


def move_cached_profiles(identifier, cache_dir, backup_dir):
    moved = 0
    for path in cache_dir.glob("*.mobileprovision"):
        try:
            profile = read_profile(path)
            application_id = (profile.get("Entitlements") or {}).get("application-identifier", "")
            # A profile App ID contains its prefix followed by the bundle ID.
            bundle_id = application_id.partition(".")[2]
        except (OSError, ValueError, TypeError, AttributeError, subprocess.SubprocessError):
            continue
        if belongs_to_app(bundle_id, identifier):
            backup_dir.mkdir(parents=True, exist_ok=True)
            shutil.move(str(path), str(backup_dir / path.name))
            moved += 1
    return moved


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect")
    inspect.add_argument("app", type=Path)
    inspect.add_argument("bundle_id")
    clear = commands.add_parser("clear-cache")
    clear.add_argument("bundle_id")
    args = parser.parse_args()
    if args.command == "inspect":
        print(json.dumps(inspect_app(args.app, args.bundle_id), ensure_ascii=False))
    else:
        cache = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
        backup = Path("/tmp/apple-tv-renew-profile-backups") / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        moved = move_cached_profiles(args.bundle_id, cache, backup)
        print(f"moved {moved} cached profile(s) to {backup}" if moved else "moved 0 cached profiles")


if __name__ == "__main__":
    main()
