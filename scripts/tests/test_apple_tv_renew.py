import json
from datetime import datetime, timedelta
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "scripts/apple-tv-renew.sh"
profile_spec = importlib.util.spec_from_file_location("apple_tv_profiles", REPO / "scripts/apple_tv_profiles.py")
profiles = importlib.util.module_from_spec(profile_spec)
profile_spec.loader.exec_module(profiles)

# Exercise the real renewal entry point with local command substitutes. Real
# Xcode artifact IDs and physical installation are validated separately.
COMMAND = r'''#!/usr/bin/env python3
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys

root = Path(os.environ["RENEW_TEST_DIR"])
args = sys.argv[1:]
tool = Path(sys.argv[0]).name
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool": tool, "args": args}) + "\n")

def write_products(app_id, extension_id, group, team):
    app = root / "Products/MoviePilot-TV.app"
    if app.exists():
        shutil.rmtree(app)
    extension = app / "PlugIns/MoviePilot-TV-TopShelf.appex"
    for bundle, identifier in [(app, app_id), (extension, extension_id)]:
        bundle.mkdir(parents=True, exist_ok=True)
        info = {"CFBundleIdentifier": identifier, "TopShelfAppGroupIdentifier": group}
        if bundle == extension:
            info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.tv-top-shelf"}
        (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
        entitlements = {"application-identifier": "PREFIX." + identifier,
                        "com.apple.developer.team-identifier": team,
                        "com.apple.security.application-groups": [group]}
        (bundle / "signed-entitlements.plist").write_bytes(plistlib.dumps(entitlements))
        (bundle / "signature-valid").write_text("yes")
        (bundle / "signing-certificate").write_bytes(b"fixture developer certificate")
        profile = {
            "Name": "Renewal regression fixture", "UUID": "fixture",
            "ExpirationDate": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=10),
            "Entitlements": entitlements, "TeamIdentifier": [team],
            "DeveloperCertificates": [b"fixture developer certificate"],
        }
        (bundle / "embedded.mobileprovision").write_bytes(plistlib.dumps(profile))
    path = extension / "embedded.mobileprovision"
    mode = os.environ.get("RENEW_TEST_EXTENSION_PROFILE", "valid")
    if mode == "missing":
        path.unlink()
    elif mode == "unreadable":
        path.write_bytes(b"not a provisioning profile")
    elif mode == "wrong_app":
        profile["Entitlements"]["application-identifier"] = "PREFIX.com.other.App"
        path.write_bytes(plistlib.dumps(profile))
    elif mode == "wrong_team":
        profile["Entitlements"]["com.apple.developer.team-identifier"] = "OTHERTEAM"
        path.write_bytes(plistlib.dumps(profile))
    elif mode == "missing_group":
        profile["Entitlements"].pop("com.apple.security.application-groups")
        path.write_bytes(plistlib.dumps(profile))
    elif mode == "unsigned_group":
        entitlements.pop("com.apple.security.application-groups")
        (extension / "signed-entitlements.plist").write_bytes(plistlib.dumps(entitlements))
    elif mode == "bad_signature":
        (extension / "signature-valid").write_text("no")
    elif mode == "adhoc_signature":
        (extension / "signing-certificate").unlink()
    elif mode == "wrong_certificate":
        (extension / "signing-certificate").write_bytes(b"unrelated developer certificate")
    elif mode == "missing_extension":
        shutil.rmtree(extension)
    elif mode != "valid":
        if mode == "missing_expiration":
            profile.pop("ExpirationDate")
        elif mode == "invalid_expiration":
            profile["ExpirationDate"] = "not a date"
        else:
            days = {"expired": -1, "short": 2, "six_days": 6}[mode]
            profile["ExpirationDate"] = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=days)
        path.write_bytes(plistlib.dumps(profile))

if tool == "xcodebuild":
    values = dict(arg.split("=", 1) for arg in args if "=" in arg)
    base = values.get("APP_BUNDLE_IDENTIFIER", "org.chantxu.MoviePilot-TV")
    app_id = values.get("PRODUCT_BUNDLE_IDENTIFIER", base)
    extension_id = values.get("PRODUCT_BUNDLE_IDENTIFIER", base + ".TopShelf")
    group = values.get("APP_GROUP_IDENTIFIER", "group." + base)
    team = values.get("DEVELOPMENT_TEAM", "TEAM")
    scheme = args[args.index("-scheme") + 1] if "-scheme" in args else ""
    if "-list" in args:
        # Swift package schemes are listed before the app scheme, as in Xcode.
        print(json.dumps({"project": {"schemes": json.loads(os.environ["RENEW_TEST_SCHEMES"])}}))
    elif "-showBuildSettings" in args and scheme == os.environ["RENEW_TEST_FAILED_SCHEME"]:
        sys.exit(65)
    elif "-showBuildSettings" in args and scheme == "Flow":
        print(json.dumps([{"target": "Flow", "buildSettings": {
            "PRODUCT_TYPE": "com.apple.product-type.library.static", "PRODUCT_BUNDLE_IDENTIFIER": "Flow",
        }}]))
    elif "-showBuildSettings" in args:
        def target(name, kind, identifier, product):
            return {"target": name, "buildSettings": {
                "PRODUCT_TYPE": kind, "PRODUCT_BUNDLE_IDENTIFIER": identifier,
                "TARGET_BUILD_DIR": str(root / "Products"), "FULL_PRODUCT_NAME": product,
                "APP_GROUP_IDENTIFIER": group, "DEVELOPMENT_TEAM": team,
            }}
        # An extension may precede the app in the settings output.
        print(json.dumps([
            target("MoviePilot-TV-TopShelf", "com.apple.product-type.app-extension", extension_id, "MoviePilot-TV-TopShelf.appex"),
            target("MoviePilot-TV", "com.apple.product-type.application", app_id, "MoviePilot-TV.app"),
        ]))
    elif "-showdestinations" in args:
        print("{ platform:tvOS, arch:arm64, id:" + os.environ["RENEW_TEST_DESTINATION_ID"] + ", name:Apple TV }")
    elif "build" in args:
        if os.environ.get("RENEW_TEST_COLLISION") == "1":
            extension_id = app_id
        write_products(app_id, extension_id, group, team)
    else:
        sys.exit("Unexpected xcodebuild invocation")
elif tool == "security" and args[:1] == ["cms"]:
    sys.stdout.buffer.write(Path(args[args.index("-i") + 1]).read_bytes())
elif tool == "codesign":
    bundle = Path(args[-1])
    if "--verify" in args:
        if (bundle / "signature-valid").read_text() != "yes":
            sys.exit(1)
    elif any(arg.startswith("--extract-certificates=") for arg in args):
        certificate = bundle / "signing-certificate"
        if certificate.exists():
            prefix = next(arg.split("=", 1)[1] for arg in args if arg.startswith("--extract-certificates="))
            Path(prefix + "0").write_bytes(certificate.read_bytes())
    elif "--display" in args:
        sys.stdout.buffer.write((bundle / "signed-entitlements.plist").read_bytes())
    else:
        sys.exit("Unexpected codesign invocation")
elif tool == "xcrun" and args[:3] == ["devicectl", "list", "devices"]:
    print(os.environ["RENEW_TEST_DEVICE_TABLE"])
elif tool == "xcrun" and args[:4] == ["devicectl", "device", "install", "app"]:
    app = Path(args[-1])
    assert app.name == "MoviePilot-TV.app"
    print("Installed fixture app")
elif tool == "defaults" and args == ["read", "com.apple.dt.Xcode", "IDEProvisioningTeamByIdentifier"]:
    print(os.environ["RENEW_TEST_XCODE_TEAMS"])
else:
    sys.exit("Unexpected command: " + tool + " " + repr(args))
'''

# Layout of `xcrun devicectl list devices` on Xcode 26: simulators show a
# 36-character identifier, a physical Apple TV shows its 25-character UDID.
PHYSICAL_UDID = "00008110-0123456789ABCDEF"
DEVICE_TABLE = f"""Name                                      Hostname   Identifier                                    State                Model                                        Reality
---------------------------------------   --------   -------------------------------------------   ------------------   ------------------------------------------   ---------
Apple TV                                             11111111-2222-3333-4444-555555555555 (UDID)   shutdown             Apple TV (AppleTV5,3)                        simulated
Living Room Apple TV                                 {PHYSICAL_UDID} (UDID)              available (paired)   Apple TV 4K (3rd generation) (AppleTV14,1)   physical"""

# `defaults read` output for a free Personal Team; Xcode writes the ID unquoted.
XCODE_TEAMS = """{
    "user@example.com" =     (
                {
            isFreeProvisioningTeam = 1;
            teamID = ABCDE12345;
            teamName = "Example User (Personal Team)";
            teamType = "Personal Team";
        }
    );
}"""


class AppleTVRenewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="renew tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for tool in ("xcodebuild", "xcrun", "security", "codesign", "defaults"):
            path = self.bin / tool
            path.write_text(COMMAND)
            path.chmod(0o755)
        self.bundle_id = "com.example.MoviePilotTV"

    def run_renew(self, *, force=True, collision=False, extension_profile="valid", app_group="", overrides=None):
        env = os.environ.copy()
        env.update({
            "PATH": str(self.bin) + os.pathsep + env["PATH"],
            "PROJECT_DIR": str(REPO), "PROJECT_FILE": "MoviePilot-TV.xcodeproj",
            "WORKSPACE": "", "SCHEME": "MoviePilot-TV", "CONFIGURATION": "Release",
            "BUNDLE_ID": self.bundle_id, "DEVELOPMENT_TEAM": "TEAM",
            "APP_GROUP_IDENTIFIER": app_group,
            "DEVICE_ID": "fixture-device", "CODESIGN_ENV_REPORT": "0",
            "CLEAR_PROFILE_CACHE": "0", "MIN_VALID_SECONDS": "432000",
            "DERIVED_DATA_PATH": str(self.root / "DerivedData"),
            "LOG_FILE": str(self.root / "renew.log"), "RENEW_TEST_DIR": str(self.root),
            "RENEW_TEST_COLLISION": "1" if collision else "0",
            "RENEW_TEST_EXTENSION_PROFILE": extension_profile,
            "RENEW_TEST_DESTINATION_ID": "fixture-device",
            "RENEW_TEST_DEVICE_TABLE": DEVICE_TABLE, "RENEW_TEST_XCODE_TEAMS": XCODE_TEAMS,
            "RENEW_TEST_SCHEMES": json.dumps(["Flow", "MoviePilot-TV", "MoviePilot-TV-TopShelf"]),
            "RENEW_TEST_FAILED_SCHEME": "",
        })
        env.update(overrides or {})
        return subprocess.run(
            ["bash", str(SCRIPT), *(["--force"] if force else [])],
            env=env, capture_output=True, text=True, timeout=20,
        )

    def calls(self):
        return [json.loads(line) for line in (self.root / "calls.jsonl").read_text().splitlines()]

    def test_custom_base_id_reaches_build_and_lookup_then_installs_main_app(self):
        result = self.run_renew()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        build = next(c for c in calls if c["tool"] == "xcodebuild" and "build" in c["args"])
        lookup = next(c for c in calls if "-showBuildSettings" in c["args"])
        for call in (build, lookup):
            self.assertIn("APP_BUNDLE_IDENTIFIER=" + self.bundle_id, call["args"])
            self.assertFalse(any(a.startswith("PRODUCT_BUNDLE_IDENTIFIER=") for a in call["args"]))
        install = next(c for c in calls if c["tool"] == "xcrun")
        self.assertEqual(install["args"][-1], str(self.root / "Products/MoviePilot-TV.app"))
        self.assertIn(self.bundle_id + ".TopShelf", result.stdout)

    def test_readme_usage_detects_app_scheme_paired_device_and_personal_team(self):
        # README usage sets only BUNDLE_ID; detection must work with current Xcode output.
        result = self.run_renew(overrides={
            "SCHEME": "", "DEVICE_ID": "", "DEVELOPMENT_TEAM": "",
            "RENEW_TEST_DESTINATION_ID": PHYSICAL_UDID,
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Scheme: MoviePilot-TV\n", result.stdout)
        self.assertIn("Development team: ABCDE12345\n", result.stdout)
        calls = self.calls()
        build = next(c for c in calls if c["tool"] == "xcodebuild" and "build" in c["args"])
        self.assertEqual(build["args"][build["args"].index("-scheme") + 1], "MoviePilot-TV")
        self.assertIn("DEVELOPMENT_TEAM=ABCDE12345", build["args"])
        self.assertEqual(build["args"][build["args"].index("-destination") + 1], "platform=tvOS,id=" + PHYSICAL_UDID)
        install = next(c for c in calls if c["tool"] == "xcrun" and c["args"][:2] == ["devicectl", "device"])
        self.assertEqual(install["args"][install["args"].index("--device") + 1], PHYSICAL_UDID)

    def test_scheme_detection_continues_after_build_settings_failure(self):
        result = self.run_renew(overrides={
            "SCHEME": "",
            "RENEW_TEST_SCHEMES": json.dumps(["Unavailable", "MoviePilot-TV"]),
            "RENEW_TEST_FAILED_SCHEME": "Unavailable",
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Scheme: MoviePilot-TV\n", result.stdout)
        calls = self.calls()
        lookups = [c for c in calls if c["tool"] == "xcodebuild" and "-showBuildSettings" in c["args"]]
        schemes = [c["args"][c["args"].index("-scheme") + 1] for c in lookups]
        self.assertEqual(schemes[:2], ["Unavailable", "MoviePilot-TV"])
        builds = [c for c in calls if c["tool"] == "xcodebuild" and "build" in c["args"]]
        self.assertEqual(len(builds), 1)
        self.assertEqual(builds[0]["args"][builds[0]["args"].index("-scheme") + 1], "MoviePilot-TV")
        installs = [c for c in calls if c["tool"] == "xcrun"
                    and c["args"][:4] == ["devicectl", "device", "install", "app"]]
        self.assertEqual(len(installs), 1)
        self.assertEqual(installs[0]["args"][-1], str(self.root / "Products/MoviePilot-TV.app"))

    def test_scheme_detection_stops_when_no_app_scheme_matches(self):
        for schemes in (["Flow"], []):
            with self.subTest(schemes=schemes):
                (self.root / "calls.jsonl").write_text("")
                result = self.run_renew(overrides={
                    "SCHEME": "", "RENEW_TEST_SCHEMES": json.dumps(schemes),
                })
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("no scheme in MoviePilot-TV.xcodeproj builds an app with bundle ID "
                              + self.bundle_id, result.stdout)
                calls = self.calls()
                lookups = [c for c in calls if c["tool"] == "xcodebuild" and "-showBuildSettings" in c["args"]]
                self.assertEqual([c["args"][c["args"].index("-scheme") + 1] for c in lookups], schemes)
                self.assertFalse(any(c["tool"] == "xcodebuild" and "build" in c["args"] for c in calls))
                self.assertFalse(any(c["tool"] == "xcrun" and c["args"][:4] == ["devicectl", "device", "install", "app"]
                                     for c in calls))
                self.assertNotIn("Renewal complete", result.stdout)

    def test_device_detection_still_accepts_36_character_identifiers(self):
        identifier = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        table = DEVICE_TABLE.replace(PHYSICAL_UDID + " (UDID)   ", identifier + " (UDID)")
        result = self.run_renew(overrides={"DEVICE_ID": "", "RENEW_TEST_DEVICE_TABLE": table})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        install = next(c for c in self.calls() if c["tool"] == "xcrun" and c["args"][:2] == ["devicectl", "device"])
        self.assertEqual(install["args"][install["args"].index("--device") + 1], identifier)

    def test_device_detection_rejects_non_apple_tv_devices(self):
        for name in ("My iPhone", "Apple TV"):
            with self.subTest(name=name):
                (self.root / "calls.jsonl").write_text("")
                result = self.run_renew(overrides={
                    "DEVICE_ID": "",
                    "RENEW_TEST_DEVICE_TABLE": (
                        f"{name}   {PHYSICAL_UDID} (UDID)   available (paired)   iPhone 15 (iPhone15,4)   physical"
                    ),
                })
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("no available paired Apple TV device found", result.stdout)
                self.assertFalse(any("build" in c["args"] or c["tool"] == "xcrun"
                                     and c["args"][:2] == ["devicectl", "device"] for c in self.calls()))

    def test_device_detection_rejects_simulated_apple_tv(self):
        result = self.run_renew(overrides={
            "DEVICE_ID": "",
            "RENEW_TEST_DEVICE_TABLE": (
                "Apple TV   AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE (UDID)   "
                "available (paired)   Apple TV (AppleTV5,3)   simulated"
            ),
        })
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("no available paired Apple TV device found", result.stdout)
        self.assertFalse(any("build" in c["args"] or c["tool"] == "xcrun"
                             and c["args"][:2] == ["devicectl", "device"] for c in self.calls()))

    def test_device_detection_selects_only_apple_tv_in_mixed_tables(self):
        den_id = "00008110-FEDCBA9876543210"
        for reality_column in (True, False):
            suffix = "   physical" if reality_column else ""
            table = "\n".join([
                f"Apple TV iPhone   00008110-AAAAAAAAAAAAAAAA (UDID)   available (paired)   iPhone 15{suffix}",
                f"Living Room   {PHYSICAL_UDID} (UDID)   available (paired)   Apple TV 4K (3rd generation){suffix}",
                f"Den   {den_id} (UDID)   available (paired)   Apple TV 4K (3rd generation){suffix}",
            ])
            for needle, expected in (("Den", den_id), ("iPhone", PHYSICAL_UDID), ("Missing", PHYSICAL_UDID)):
                with self.subTest(reality_column=reality_column, needle=needle):
                    (self.root / "calls.jsonl").write_text("")
                    result = self.run_renew(overrides={
                        "DEVICE_ID": "", "DEVICE_NAME_CONTAINS": needle,
                        "RENEW_TEST_DEVICE_TABLE": table, "RENEW_TEST_DESTINATION_ID": expected,
                    })
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    calls = self.calls()
                    install = next(c for c in calls if c["tool"] == "xcrun"
                                   and c["args"][:2] == ["devicectl", "device"])
                    self.assertEqual(install["args"][install["args"].index("--device") + 1], expected)
                    build = next(c for c in calls if c["tool"] == "xcodebuild" and "build" in c["args"])
                    self.assertEqual(build["args"][build["args"].index("-destination") + 1], "platform=tvOS,id=" + expected)

    def test_team_detection_still_accepts_quoted_team_ids(self):
        result = self.run_renew(overrides={
            "DEVELOPMENT_TEAM": "", "RENEW_TEST_XCODE_TEAMS": XCODE_TEAMS.replace("ABCDE12345", '"ABCDE12345"'),
        })
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = next(c for c in self.calls() if c["tool"] == "xcodebuild" and "build" in c["args"])
        self.assertIn("DEVELOPMENT_TEAM=ABCDE12345", build["args"])

    def test_explicit_scheme_device_and_team_skip_detection(self):
        result = self.run_renew()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        self.assertFalse(any(c["tool"] == "defaults" for c in calls))
        self.assertFalse(any(c["tool"] == "xcodebuild" and "-list" in c["args"] for c in calls))
        self.assertFalse(any(c["tool"] == "xcrun" and c["args"][:2] == ["devicectl", "list"] for c in calls))
        build = next(c for c in calls if c["tool"] == "xcodebuild" and "build" in c["args"])
        self.assertEqual(build["args"][build["args"].index("-scheme") + 1], "MoviePilot-TV")
        self.assertIn("DEVELOPMENT_TEAM=TEAM", build["args"])
        install = next(c for c in calls if c["tool"] == "xcrun")
        self.assertEqual(install["args"][install["args"].index("--device") + 1], "fixture-device")

    def test_duplicate_extension_id_prevents_install(self):
        result = self.run_renew(collision=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid bundle identifier", result.stdout)
        self.assertFalse(any(c["tool"] == "xcrun" for c in self.calls()))

    def test_valid_main_profile_does_not_skip_a_colliding_extension(self):
        first = self.run_renew(collision=True)
        self.assertNotEqual(first.returncode, 0)
        (self.root / "calls.jsonl").write_text("")
        result = self.run_renew(force=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(c["tool"] == "xcodebuild" and "build" in c["args"] for c in self.calls()))
        self.assertTrue(any(c["tool"] == "xcrun" for c in self.calls()))

    @property
    def app(self):
        return self.root / "Products/MoviePilot-TV.app"

    def test_custom_group_override_reaches_build_and_lookup(self):
        group = "group.com.example.ExistingSharedLibrary"
        result = self.run_renew(app_group=group)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for call in self.calls():
            if call["tool"] == "xcodebuild":
                self.assertIn("APP_GROUP_IDENTIFIER=" + group, call["args"])

    def test_changed_group_rebuilds_instead_of_skipping_valid_old_profiles(self):
        self.assertEqual(self.run_renew(app_group="group.com.example.Old").returncode, 0)
        (self.root / "calls.jsonl").write_text("")
        result = self.run_renew(force=False, app_group="group.com.example.New")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any("build" in call["args"] for call in self.calls()))
        self.assertTrue(any(call["tool"] == "xcrun" for call in self.calls()))
        report = json.loads(result.stdout.splitlines()[-1])
        self.assertTrue(all(p["appGroupIdentifier"] == "group.com.example.New" for p in report["profiles"]))

    def test_valid_dates_do_not_allow_wrong_authorization_or_broken_signatures(self):
        for mode in ("wrong_app", "wrong_team", "missing_group", "unsigned_group", "bad_signature",
                     "adhoc_signature", "wrong_certificate", "missing_extension"):
            with self.subTest(mode=mode):
                (self.root / "calls.jsonl").write_text("")
                result = self.run_renew(extension_profile=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertFalse(any(call["tool"] == "xcrun" for call in self.calls()))

    def test_bad_cached_signature_forces_rebuild(self):
        self.assertEqual(self.run_renew().returncode, 0)
        (self.app / "PlugIns/MoviePilot-TV-TopShelf.appex/signature-valid").write_text("no")
        (self.root / "calls.jsonl").write_text("")
        result = self.run_renew(force=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any("build" in call["args"] for call in self.calls()))

    def test_cached_adhoc_signature_with_valid_profile_forces_rebuild(self):
        self.assertEqual(self.run_renew().returncode, 0)
        (self.app / "PlugIns/MoviePilot-TV-TopShelf.appex/signing-certificate").unlink()
        (self.root / "calls.jsonl").write_text("")
        result = self.run_renew(force=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any("build" in call["args"] for call in self.calls()))
        self.assertTrue(any(call["tool"] == "xcrun" for call in self.calls()))

    def test_device_build_explicitly_keeps_signing_enabled(self):
        result = self.run_renew()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = next(call for call in self.calls() if "build" in call["args"])
        self.assertIn("CODE_SIGNING_ALLOWED=YES", build["args"])
        self.assertIn("CODE_SIGNING_REQUIRED=YES", build["args"])

    def test_only_all_valid_profiles_allow_skipping(self):
        self.assertEqual(self.run_renew().returncode, 0)
        (self.root / "calls.jsonl").write_text("")
        result = self.run_renew(force=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("skipping", result.stdout)
        calls = self.calls()
        self.assertFalse(any(c["tool"] == "xcrun" or "build" in c["args"] for c in calls))
        reads = [c["args"][-1] for c in calls if c["tool"] == "security"]
        self.assertEqual(set(reads), {str(p) for p in self.app.rglob("embedded.mobileprovision")})

    def test_invalid_cached_extension_profiles_trigger_renewal(self):
        for mode in ("expired", "missing", "unreadable", "missing_expiration", "invalid_expiration"):
            with self.subTest(mode=mode):
                self.assertEqual(self.run_renew().returncode, 0)
                path = self.app / "PlugIns/MoviePilot-TV-TopShelf.appex/embedded.mobileprovision"
                if mode == "missing":
                    path.unlink()
                elif mode == "unreadable":
                    path.write_bytes(b"unreadable")
                else:
                    profile = plistlib.loads(path.read_bytes())
                    if mode == "missing_expiration":
                        profile.pop("ExpirationDate")
                    else:
                        profile["ExpirationDate"] = (datetime.now() - timedelta(days=1)
                            if mode == "expired" else "invalid")
                    path.write_bytes(plistlib.dumps(profile))
                (self.root / "calls.jsonl").write_text("")
                result = self.run_renew(force=False)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("skipping", result.stdout)
                self.assertTrue(any("build" in c["args"] for c in self.calls()))
                self.assertTrue(any(c["tool"] == "xcrun" for c in self.calls()))

    def test_every_extension_is_checked_before_skipping(self):
        self.assertEqual(self.run_renew().returncode, 0)
        extra = self.app / "PlugIns/Additional.appex"
        extra.mkdir()
        (extra / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": self.bundle_id + ".Additional"}))
        (self.root / "calls.jsonl").write_text("")
        result = self.run_renew(force=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any("build" in c["args"] for c in self.calls()))
        self.assertNotIn("skipping", result.stdout)

    def test_bad_profiles_in_new_build_cannot_be_installed_or_report_success(self):
        for mode in ("expired", "missing", "unreadable", "missing_expiration", "invalid_expiration", "short"):
            with self.subTest(mode=mode):
                (self.root / "calls.jsonl").write_text("")
                result = self.run_renew(extension_profile=mode)
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn("Renewal complete", result.stdout)
                self.assertFalse(any(c["tool"] == "xcrun" for c in self.calls()))

    def test_report_uses_the_shortest_profile_lifetime(self):
        result = self.run_renew(extension_profile="six_days")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout.splitlines()[-1])
        self.assertGreater(report["secondsRemaining"], 5 * 86400)
        self.assertLessEqual(report["secondsRemaining"], 6 * 86400)
        self.assertEqual(report["secondsRemaining"], min(p["secondsRemaining"] for p in report["profiles"]))

    def test_cache_cleanup_includes_extensions_and_preserves_other_apps(self):
        cache, backup = self.root / "profile cache", self.root / "backup"
        cache.mkdir()
        identifiers = [self.bundle_id, self.bundle_id + ".TopShelf", self.bundle_id + ".Another",
                       self.bundle_id + "Other", "com.example.Unrelated"]
        for i, identifier in enumerate(identifiers):
            (cache / f"{i}.mobileprovision").write_bytes(plistlib.dumps({
                "Entitlements": {"application-identifier": "TEAM." + identifier}}))
        with patch.object(profiles, "read_profile", side_effect=lambda path: plistlib.loads(path.read_bytes())):
            self.assertEqual(profiles.move_cached_profiles(self.bundle_id, cache, backup), 3)
        self.assertEqual({p.name for p in cache.iterdir()}, {"3.mobileprovision", "4.mobileprovision"})
        self.assertEqual({p.name for p in backup.iterdir()}, {"0.mobileprovision", "1.mobileprovision", "2.mobileprovision"})


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcodebuild"), "requires Xcode")
class ProjectBundleIdentifierTests(unittest.TestCase):
    def assert_configuration(self, configuration, group=None):
        result = subprocess.run([
            "xcodebuild", "-project", str(REPO / "MoviePilot-TV.xcodeproj"),
            "-alltargets", "-configuration", configuration, "-showBuildSettings", "-json",
            "APP_BUNDLE_IDENTIFIER=com.example.MoviePilotTV", "-skipPackagePluginValidation",
            *(["APP_GROUP_IDENTIFIER=" + group] if group else []),
        ], capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        identifiers = {
            target["target"]: target["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"]
            for target in json.loads(result.stdout)
            if "PRODUCT_BUNDLE_IDENTIFIER" in target.get("buildSettings", {})
        }
        self.assertEqual(identifiers["MoviePilot-TV"], "com.example.MoviePilotTV")
        self.assertEqual(identifiers["MoviePilot-TV-TopShelf"], "com.example.MoviePilotTV.TopShelf")
        groups = {target["target"]: target["buildSettings"].get("APP_GROUP_IDENTIFIER")
                  for target in json.loads(result.stdout)}
        for target in ("MoviePilot-TV", "MoviePilot-TV-TopShelf"):
            self.assertEqual(groups[target], group or "group.com.example.MoviePilotTV")

    def test_debug_targets_derive_distinct_bundle_identifiers(self):
        self.assert_configuration("Debug")

    def test_release_targets_derive_distinct_bundle_identifiers(self):
        self.assert_configuration("Release")

    def test_both_configurations_accept_a_shared_group_override(self):
        for configuration in ("Debug", "Release"):
            with self.subTest(configuration=configuration):
                self.assert_configuration(configuration, "group.com.example.ExistingSharedLibrary")


if __name__ == "__main__":
    unittest.main()
