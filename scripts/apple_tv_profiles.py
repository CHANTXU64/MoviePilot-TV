"""Inspect the provisioning profiles of an app and its embedded extensions."""

import argparse
from datetime import datetime, timezone
import fnmatch
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


APP_GROUPS = "com.apple.security.application-groups"
TEAM_IDENTIFIER = "com.apple.developer.team-identifier"
TOP_SHELF_POINT = "com.apple.tv-top-shelf"


def read_info(bundle):
    with (bundle / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if not isinstance(info, dict):
        raise ValueError(f"Invalid Info.plist: {bundle}")
    return info


def configured_group(bundle):
    value = read_info(bundle).get("TopShelfAppGroupIdentifier")
    if (not isinstance(value, str) or not value.startswith("group.") or len(value) <= 6
            or "$" in value or any(character.isspace() for character in value)):
        raise ValueError(f"Missing or invalid TopShelfAppGroupIdentifier: {bundle}")
    return value


def read_entitlements(bundle):
    data = subprocess.check_output(
        ["codesign", "--display", "--entitlements", "-", "--xml", str(bundle)],
        stderr=subprocess.DEVNULL,
    )
    result = plistlib.loads(data)
    if not isinstance(result, dict):
        raise ValueError(f"Missing code-signing entitlements: {bundle}")
    return result


def verify_signature(bundle):
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(bundle)],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )


def verify_profile_signer(bundle, profile):
    with tempfile.TemporaryDirectory(prefix="moviepilot-signing-cert-") as temporary:
        prefix = Path(temporary) / "certificate-"
        subprocess.run(
            ["codesign", "--display", f"--extract-certificates={prefix}", str(bundle)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        certificate = Path(str(prefix) + "0")
        allowed = profile.get("DeveloperCertificates")
        if (not certificate.is_file() or not isinstance(allowed, list)
                or certificate.read_bytes() not in allowed):
            raise ValueError("Actual signing certificate is not authorized by the profile")


def belongs_to_app(identifier, app_identifier):
    return isinstance(identifier, str) and (
        identifier == app_identifier or identifier.startswith(app_identifier + ".")
    )


def bundle_identifiers(app, expected, require_top_shelf=False):
    bundles = [app, *sorted((app / "PlugIns").rglob("*.appex"))]
    identifiers = {}
    for bundle in bundles:
        identifier = read_info(bundle).get("CFBundleIdentifier")
        valid = identifier == expected if bundle == app else (
            belongs_to_app(identifier, expected) and identifier != expected
        )
        if not valid or identifier in identifiers.values():
            raise ValueError(f"Invalid bundle identifier for {bundle.name}: {identifier!r}")
        identifiers[bundle] = identifier
    if require_top_shelf:
        extensions = [bundle for bundle in identifiers if bundle != app
                      and read_info(bundle).get("NSExtension", {}).get("NSExtensionPointIdentifier") == TOP_SHELF_POINT]
        if len(extensions) != 1:
            raise ValueError("Expected exactly one embedded Top Shelf extension")
    return identifiers


def read_profile(path):
    data = subprocess.check_output(
        ["security", "cms", "-D", "-i", str(path)], stderr=subprocess.DEVNULL
    )
    profile = plistlib.loads(data)
    if not isinstance(profile, dict):
        raise ValueError("Provisioning profile is not a dictionary")
    return profile


def profile_info(bundle, identifier, now, expected_group=None, expected_team=None):
    path = bundle / "embedded.mobileprovision"
    result = {"bundleIdentifier": identifier, "profilePath": str(path), "ok": False}
    try:
        if not path.is_file():
            raise ValueError("embedded.mobileprovision not found")
        profile = read_profile(path)
        verify_signature(bundle)
        verify_profile_signer(bundle, profile)
        signed = read_entitlements(bundle)
        allowed = profile.get("Entitlements")
        if not isinstance(allowed, dict):
            raise ValueError("Profile has no entitlements")
        application_id = signed.get("application-identifier")
        profile_id = allowed.get("application-identifier")
        if (not isinstance(application_id, str) or "*" in application_id
                or application_id.partition(".")[2] != identifier
                or not isinstance(profile_id, str)
                or not fnmatch.fnmatchcase(application_id, profile_id)):
            raise ValueError("Code signature/profile App ID does not match the bundle")
        team = signed.get(TEAM_IDENTIFIER)
        if (not isinstance(team, str) or not team or allowed.get(TEAM_IDENTIFIER) != team
                or team not in profile.get("TeamIdentifier", [])
                or (expected_team and team != expected_team)):
            raise ValueError("Code signature/profile signing team does not match")
        group = configured_group(bundle)
        if expected_group and group != expected_group:
            raise ValueError("Built App Group does not match the requested configuration")
        for label, entitlements in (("Code signature", signed), ("Profile", allowed)):
            groups = entitlements.get(APP_GROUPS)
            if not isinstance(groups, list) or group not in groups:
                raise ValueError(f"{label} does not authorize the configured App Group")
        result.update(appGroupIdentifier=group, teamIdentifier=team)
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


def inspect_app(app, expected, expected_group=None, expected_team=None, require_top_shelf=False):
    try:
        identifiers = bundle_identifiers(app, expected, require_top_shelf)
        group = expected_group or configured_group(app)
    except (OSError, ValueError, TypeError, AttributeError) as exc:
        return {"ok": False, "error": str(exc), "secondsRemaining": None}
    now = datetime.now(timezone.utc)
    profiles = [profile_info(bundle, identifier, now, group, expected_team)
                for bundle, identifier in identifiers.items()]
    remaining = [profile.get("secondsRemaining") for profile in profiles]
    same_team = len({profile.get("teamIdentifier") for profile in profiles}) == 1
    report = {
        "ok": all(profile["ok"] for profile in profiles) and same_team,
        "secondsRemaining": min(remaining) if all(value is not None for value in remaining) else None,
        "profiles": profiles,
    }
    if all(profile["ok"] for profile in profiles) and not same_team:
        report["error"] = "App and embedded extensions use different signing teams"
    return report


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
    inspect.add_argument("--app-group")
    inspect.add_argument("--team")
    inspect.add_argument("--require-top-shelf", action="store_true")
    clear = commands.add_parser("clear-cache")
    clear.add_argument("bundle_id")
    args = parser.parse_args()
    if args.command == "inspect":
        print(json.dumps(inspect_app(args.app, args.bundle_id, args.app_group, args.team,
                                     args.require_top_shelf), ensure_ascii=False))
    else:
        cache = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
        backup = Path("/tmp/apple-tv-renew-profile-backups") / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        moved = move_cached_profiles(args.bundle_id, cache, backup)
        print(f"moved {moved} cached profile(s) to {backup}" if moved else "moved 0 cached profiles")


if __name__ == "__main__":
    main()
