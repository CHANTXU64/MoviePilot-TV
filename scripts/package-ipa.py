#!/usr/bin/env python3
"""Package a tvOS IPA with local signing metadata for downstream re-signing."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from apple_tv_profiles import (
    APP_GROUPS, bundle_identifiers, configured_group, read_entitlements, read_info, verify_signature,
)


def validate_resignable_app(app):
    identifier = read_info(app).get("CFBundleIdentifier")
    bundles = bundle_identifiers(app, identifier, require_top_shelf=True)
    group = configured_group(app)
    for bundle in bundles:
        if configured_group(bundle) != group:
            raise ValueError("App and embedded extensions must use the same App Group")
        if (bundle / "embedded.mobileprovision").exists():
            raise ValueError("A redistributable IPA must not contain a developer's profile")
        verify_signature(bundle)
        entitlements = read_entitlements(bundle)
        if entitlements != {APP_GROUPS: [group]}:
            raise ValueError(f"Unexpected re-signing entitlements: {bundle.name}")
    return {"bundleIdentifier": identifier, "appGroupIdentifier": group,
            "embeddedExtensionCount": len(bundles) - 1}


def package_app(source, output):
    source, output = source.resolve(), output.resolve()
    identifier = read_info(source).get("CFBundleIdentifier")
    bundle_identifiers(source, identifier, require_top_shelf=True)
    group = configured_group(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="moviepilot-ipa-", dir=output.parent) as temporary:
        root = Path(temporary)
        app = root / "Payload" / source.name
        shutil.copytree(source, app, symlinks=True)
        entitlements_path = root / "resigning-entitlements.plist"
        entitlements_path.write_bytes(plistlib.dumps({APP_GROUPS: [group]}))
        bundles = bundle_identifiers(app, identifier, require_top_shelf=True)
        for bundle in bundles:
            if configured_group(bundle) != group:
                raise ValueError("App and embedded extensions must use the same App Group")
            (bundle / "embedded.mobileprovision").unlink(missing_ok=True)

        # Sign from the inside out. Frameworks/dylibs never inherit app entitlements.
        nested = set(app.rglob("*.dylib")) | set(app.rglob("*.framework")) | set(bundles)
        for path in sorted(nested, key=lambda path: (-len(path.parts), str(path))):
            args = ["codesign", "--force", "--sign", "-", "--timestamp=none"]
            if path in bundles:
                args += ["--entitlements", str(entitlements_path), "--generate-entitlement-der"]
            subprocess.run([*args, str(path)], check=True)
        report = validate_resignable_app(app)
        staged = root / output.name
        subprocess.run(["zip", "-qry", str(staged), "Payload"], cwd=root, check=True)
        os.replace(staged, output)
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(package_app(args.app, args.output)))


if __name__ == "__main__":
    main()
