import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("package_ipa", SCRIPTS / "package-ipa.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)
from apple_tv_profiles import verify_profile_signer


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("codesign") and shutil.which("xcrun"),
                     "requires macOS signing tools")
class PackageIPATests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ipa signing test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Input/MoviePilot TV.app"
        self.extension = self.app / "PlugIns/TopShelf.appex"
        self.group = "group.com.example.MoviePilot"
        source = self.root / "main.c"
        source.write_text("int main(void) { return 0; }\n")
        executable = self.root / "Fixture"
        subprocess.run(["xcrun", "--sdk", "macosx", "clang", str(source), "-o", str(executable)],
                       check=True, capture_output=True)
        for bundle, identifier in [(self.app, "com.example.MoviePilot"),
                                   (self.extension, "com.example.MoviePilot.TopShelf")]:
            bundle.mkdir(parents=True)
            info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "Fixture",
                    "CFBundlePackageType": "APPL" if bundle == self.app else "XPC!",
                    "CFBundleVersion": "1", "TopShelfAppGroupIdentifier": self.group}
            if bundle == self.extension:
                info["NSExtension"] = {"NSExtensionPointIdentifier": "com.apple.tv-top-shelf"}
            (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
            shutil.copy2(executable, bundle / "Fixture")
            (bundle / "embedded.mobileprovision").write_bytes(b"private profile fixture")

    def test_ipa_preserves_extractable_shared_entitlements_in_both_bundles(self):
        output = self.root / "Output/MoviePilot-TV-unsigned.ipa"
        report = package.package_app(self.app, output)
        self.assertEqual(report["embeddedExtensionCount"], 1)
        with zipfile.ZipFile(output) as archive:
            self.assertFalse(any(name.endswith("embedded.mobileprovision") for name in archive.namelist()))
            archive.extractall(self.root / "Extracted")
        copied = self.root / "Extracted/Payload/MoviePilot TV.app"
        report = package.validate_resignable_app(copied)
        self.assertEqual(report["appGroupIdentifier"], self.group)
        for bundle in [copied, copied / "PlugIns/TopShelf.appex"]:
            self.assertEqual(package.read_entitlements(bundle), {package.APP_GROUPS: [self.group]})
            with self.assertRaisesRegex(ValueError, "Actual signing certificate"):
                verify_profile_signer(bundle, {"DeveloperCertificates": [b"unrelated certificate"]})
        # Packaging must not alter the build product or copy its private profile.
        self.assertTrue((self.app / "embedded.mobileprovision").exists())
        self.assertFalse((self.app / "_CodeSignature").exists())

    def test_missing_extension_or_mismatched_group_cannot_replace_an_existing_ipa(self):
        output = self.root / "Existing.ipa"
        output.write_bytes(b"previous package")
        info_path = self.extension / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["TopShelfAppGroupIdentifier"] = "group.com.example.Other"
        info_path.write_bytes(plistlib.dumps(info))
        with self.assertRaises(ValueError):
            package.package_app(self.app, output)
        self.assertEqual(output.read_bytes(), b"previous package")
        shutil.rmtree(self.extension)
        with self.assertRaises(ValueError):
            package.package_app(self.app, output)
        self.assertEqual(output.read_bytes(), b"previous package")

    def test_signature_without_group_is_rejected_by_artifact_validation(self):
        output = self.root / "App.ipa"
        package.package_app(self.app, output)
        with zipfile.ZipFile(output) as archive:
            archive.extractall(self.root / "Extracted")
        copied = self.root / "Extracted/Payload/MoviePilot TV.app"
        extension = copied / "PlugIns/TopShelf.appex"
        subprocess.run(["codesign", "--force", "--sign", "-", str(extension)], check=True, capture_output=True)
        with self.assertRaises((ValueError, plistlib.InvalidFileException, subprocess.CalledProcessError)):
            package.validate_resignable_app(copied)


if __name__ == "__main__":
    unittest.main()
