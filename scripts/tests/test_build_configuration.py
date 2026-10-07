"""Check resolved Xcode settings, including a future release from the shared version source."""

import functools
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
CONFIGURATIONS = ("Debug", "Release", "Testing")


def settings(configuration, project):
    result = subprocess.run([
        "xcodebuild", "-project", str(project), "-alltargets", "-configuration", configuration,
        "-showBuildSettings", "-json", "-skipPackagePluginValidation",
    ], capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return {target["target"]: target["buildSettings"] for target in json.loads(result.stdout)}


@functools.lru_cache(maxsize=None)
def current_settings(configuration):
    return settings(configuration, REPO / "MoviePilot-TV.xcodeproj")


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("xcodebuild"), "requires Xcode")
class SharedBuildConfigurationTests(unittest.TestCase):
    def test_all_configurations_share_version_and_keep_separate_identities(self):
        source = (REPO / "Configuration/Base.xcconfig").read_text()
        expected_version = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", source, re.MULTILINE).group(1)
        for configuration in CONFIGURATIONS:
            with self.subTest(configuration=configuration):
                targets = current_settings(configuration)
                app = targets["MoviePilot-TV"]
                extension = targets["MoviePilot-TV-TopShelf"]
                identifier = "org.chantxu.MoviePilot-TV" + (".Testing" if configuration == "Testing" else "")
                scheme = "moviepilot-tv-tests" if configuration == "Testing" else "moviepilot-tv"
                self.assertEqual(app["PRODUCT_BUNDLE_IDENTIFIER"], identifier)
                self.assertEqual(extension["PRODUCT_BUNDLE_IDENTIFIER"], identifier + ".TopShelf")
                for target in (app, extension):
                    self.assertEqual(target["MARKETING_VERSION"], expected_version)
                    self.assertEqual(target["APP_GROUP_IDENTIFIER"], "group." + identifier)
                    self.assertEqual(target["APP_URL_SCHEME"], scheme)
                self.assertEqual(targets["MoviePilot-TV-Tests"]["MARKETING_VERSION"], "1.0")
                if configuration == "Testing":
                    self.assertIn("TESTING", app["SWIFT_ACTIVE_COMPILATION_CONDITIONS"].split())
                else:
                    self.assertNotIn("TESTING", app.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split())

    def test_changing_only_base_version_updates_app_and_extension_in_every_configuration(self):
        with tempfile.TemporaryDirectory(prefix="moviepilot-version-settings-") as directory:
            root = Path(directory)
            project = root / "MoviePilot-TV.xcodeproj"
            shutil.copytree(REPO / "MoviePilot-TV.xcodeproj", project,
                            ignore=shutil.ignore_patterns("xcuserdata"))
            shutil.copytree(REPO / "Configuration", root / "Configuration")
            for name in ("MoviePilot-TV", "MoviePilot-TV-Tests", "TopShelfShared", "MoviePilot-TV-TopShelf"):
                (root / name).symlink_to(REPO / name, target_is_directory=True)
            base = root / "Configuration/Base.xcconfig"
            base.write_text(re.sub(r"^MARKETING_VERSION\s*=.*$", "MARKETING_VERSION = 9.8.7",
                                   base.read_text(), flags=re.MULTILINE))
            for configuration in CONFIGURATIONS:
                with self.subTest(configuration=configuration):
                    targets = settings(configuration, project)
                    for name in ("MoviePilot-TV", "MoviePilot-TV-TopShelf"):
                        self.assertEqual(targets[name]["MARKETING_VERSION"], "9.8.7")
                    self.assertEqual(targets["MoviePilot-TV-Tests"]["MARKETING_VERSION"], "1.0")


if __name__ == "__main__":
    unittest.main()
