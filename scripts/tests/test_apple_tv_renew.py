import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "scripts/apple-tv-renew.sh"

# Exercise the real renewal entry point with local command substitutes. Real
# Xcode artifact IDs and physical installation are validated separately.
COMMAND = r'''#!/usr/bin/env python3
import datetime
import json
import os
from pathlib import Path
import plistlib
import sys

root = Path(os.environ["RENEW_TEST_DIR"])
args = sys.argv[1:]
tool = Path(sys.argv[0]).name
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool": tool, "args": args}) + "\n")

def write_products(app_id, extension_id):
    app = root / "Products/MoviePilot-TV.app"
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

    def run_renew(self, *, force=True, collision=False):
        env = os.environ.copy()
        env.update({
            "PATH": str(self.bin) + os.pathsep + env["PATH"],
            "PROJECT_DIR": str(REPO), "PROJECT_FILE": "MoviePilot-TV.xcodeproj",
            "WORKSPACE": "", "SCHEME": "MoviePilot-TV", "CONFIGURATION": "Release",
            "BUNDLE_ID": self.bundle_id, "DEVELOPMENT_TEAM": "TEAM",
            "DEVICE_ID": "fixture-device", "CODESIGN_ENV_REPORT": "0",
            "CLEAR_PROFILE_CACHE": "0", "MIN_VALID_SECONDS": "432000",
            "DERIVED_DATA_PATH": str(self.root / "DerivedData"),
            "LOG_FILE": str(self.root / "renew.log"), "RENEW_TEST_DIR": str(self.root),
            "RENEW_TEST_COLLISION": "1" if collision else "0",
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
        self.assertIn("bundle identifier validation failed", result.stdout)
        self.assertFalse(any(c["tool"] == "xcrun" for c in self.calls()))

    def test_valid_main_profile_does_not_skip_a_colliding_extension(self):
        first = self.run_renew(collision=True)
        self.assertNotEqual(first.returncode, 0)
        (self.root / "calls.jsonl").write_text("")
        result = self.run_renew(force=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(c["tool"] == "xcodebuild" and "build" in c["args"] for c in self.calls()))
        self.assertTrue(any(c["tool"] == "xcrun" for c in self.calls()))


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcodebuild"), "requires Xcode")
class ProjectBundleIdentifierTests(unittest.TestCase):
    def assert_configuration(self, configuration):
        result = subprocess.run([
            "xcodebuild", "-project", str(REPO / "MoviePilot-TV.xcodeproj"),
            "-alltargets", "-configuration", configuration, "-showBuildSettings", "-json",
            "APP_BUNDLE_IDENTIFIER=com.example.MoviePilotTV", "-skipPackagePluginValidation",
        ], capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr)
        identifiers = {
            target["target"]: target["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"]
            for target in json.loads(result.stdout)
            if "PRODUCT_BUNDLE_IDENTIFIER" in target.get("buildSettings", {})
        }
        self.assertEqual(identifiers["MoviePilot-TV"], "com.example.MoviePilotTV")
        self.assertEqual(identifiers["MoviePilot-TV-TopShelf"], "com.example.MoviePilotTV.TopShelf")

    def test_debug_targets_derive_distinct_bundle_identifiers(self):
        self.assert_configuration("Debug")

    def test_release_targets_derive_distinct_bundle_identifiers(self):
        self.assert_configuration("Release")


if __name__ == "__main__":
    unittest.main()
