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

def write_products(app_id, extension_id):
    app = root / "Products/MoviePilot-TV.app"
    if app.exists():
        shutil.rmtree(app)
    extension = app / "PlugIns/MoviePilot-TV-TopShelf.appex"
    for bundle, identifier in [(app, app_id), (extension, extension_id)]:
        bundle.mkdir(parents=True, exist_ok=True)
        (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identifier}))
        profile = {
            "Name": "Renewal regression fixture", "UUID": "fixture",
            "ExpirationDate": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=10),
            "Entitlements": {"application-identifier": "TEAM." + identifier},
        }
        (bundle / "embedded.mobileprovision").write_bytes(plistlib.dumps(profile))
    path = extension / "embedded.mobileprovision"
    mode = os.environ.get("RENEW_TEST_EXTENSION_PROFILE", "valid")
    if mode == "missing":
        path.unlink()
    elif mode == "unreadable":
        path.write_bytes(b"not a provisioning profile")
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
    if "-showBuildSettings" in args:
        def target(name, kind, identifier, product):
            return {"target": name, "buildSettings": {
                "PRODUCT_TYPE": kind, "PRODUCT_BUNDLE_IDENTIFIER": identifier,
                "TARGET_BUILD_DIR": str(root / "Products"), "FULL_PRODUCT_NAME": product,
            }}
        # An extension may precede the app in the settings output.
        print(json.dumps([
            target("MoviePilot-TV-TopShelf", "com.apple.product-type.app-extension", extension_id, "MoviePilot-TV-TopShelf.appex"),
            target("MoviePilot-TV", "com.apple.product-type.application", app_id, "MoviePilot-TV.app"),
        ]))
    elif "-showdestinations" in args:
        print("{ platform:tvOS, arch:arm64, id:fixture-device, name:Apple TV }")
    elif "build" in args:
        if os.environ.get("RENEW_TEST_COLLISION") == "1":
            extension_id = app_id
        write_products(app_id, extension_id)
    else:
        sys.exit("Unexpected xcodebuild invocation")
elif tool == "security" and args[:1] == ["cms"]:
    sys.stdout.buffer.write(Path(args[args.index("-i") + 1]).read_bytes())
elif tool == "xcrun" and args[:4] == ["devicectl", "device", "install", "app"]:
    app = Path(args[-1])
    assert app.name == "MoviePilot-TV.app"
    print("Installed fixture app")
else:
    sys.exit("Unexpected command: " + tool + " " + repr(args))
'''


class AppleTVRenewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="renew tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for tool in ("xcodebuild", "xcrun", "security"):
            path = self.bin / tool
            path.write_text(COMMAND)
            path.chmod(0o755)
        self.bundle_id = "com.example.MoviePilotTV"

    def run_renew(self, *, force=True, collision=False, extension_profile="valid", app_group=""):
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
        })
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
