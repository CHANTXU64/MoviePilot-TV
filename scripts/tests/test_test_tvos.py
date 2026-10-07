"""Exercise the test entry point with command substitutes; no user's simulator is touched."""

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "scripts/test-tvos.py"
OWNED_DEVICE = "11111111-2222-4333-8444-555555555555"
COMMAND = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["TVOS_RUNNER_TEST_DIR"])
args = sys.argv[1:]
tool = Path(sys.argv[0]).name
with (root / "calls.jsonl").open("a") as log:
    log.write(json.dumps({"tool": tool, "args": args}) + "\n")
mode = os.environ.get("TVOS_RUNNER_TEST_MODE", "success")
owned = "11111111-2222-4333-8444-555555555555"
if tool == "xcrun":
    if args == ["simctl", "list", "runtimes", "-j"]:
        runtime = {"identifier": "com.apple.CoreSimulator.SimRuntime.tvOS-27-0",
                   "version": "27.0", "isAvailable": True,
                   "supportedDeviceTypes": [{"identifier": "type.apple-tv", "name": "Apple TV",
                                              "productFamily": "Apple TV"}]}
        print(json.dumps({"runtimes": [] if mode == "no_runtime" else [runtime]}))
    elif args[:2] == ["simctl", "create"]:
        print(owned)
    elif args in [["simctl", "shutdown", owned], ["simctl", "delete", owned]]:
        pass
    else:
        raise SystemExit("Unexpected simulator operation: " + str(args))
elif tool == "xcodebuild":
    if mode == "build_failure" and "build" in args:
        sys.exit(65)
    if "test" in args:
        if mode == "test_failure":
            sys.exit(65)
        if mode == "interrupt":
            (root / "test-started").touch()
            time.sleep(60)
'''


class TestTVOSRunnerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        for tool in ("xcrun", "xcodebuild"):
            path = self.root / tool
            path.write_text(COMMAND)
            path.chmod(0o755)
        self.environment = dict(os.environ, TVOS_RUNNER_TEST_DIR=str(self.root),
                                PATH=str(self.root) + os.pathsep + os.environ["PATH"])
        # A user's persistent state must survive every run, including failure and cancellation.
        self.sentinel = self.root / "daily-simulator-data"
        self.sentinel.write_text("saved session and password")

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_script(self, mode="success", *arguments):
        self.environment["TVOS_RUNNER_TEST_MODE"] = mode
        return subprocess.run([sys.executable, str(SCRIPT), *arguments], env=self.environment,
                              capture_output=True, text=True, timeout=20)

    def assert_owned_cleanup(self):
        mutations = [call["args"] for call in self.calls()
                     if call["tool"] == "xcrun" and call["args"][1] in ("shutdown", "delete", "erase")]
        self.assertEqual(mutations, [["simctl", "shutdown", OWNED_DEVICE],
                                     ["simctl", "delete", OWNED_DEVICE]])
        self.assertEqual(self.sentinel.read_text(), "saved session and password")

    def test_success_builds_debug_and_tests_isolated_configuration(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [call["args"] for call in self.calls() if call["tool"] == "xcodebuild"]
        self.assertIn("-resolvePackageDependencies", builds[0])
        self.assertIn("Debug", builds[1])
        test = builds[2]
        self.assertEqual(test[test.index("-configuration") + 1], "Testing")
        self.assertEqual(test[test.index("-destination") + 1],
                         f"platform=tvOS Simulator,id={OWNED_DEVICE}")
        self.assertEqual(test[test.index("-parallel-testing-enabled") + 1], "NO")
        self.assertEqual(test[test.index("-maximum-concurrent-test-simulator-destinations") + 1], "1")
        self.assertIn("CODE_SIGNING_ALLOWED=YES", test)
        self.assertIn("CODE_SIGN_IDENTITY=-", test)
        self.assertEqual(len([arg for arg in test if arg.startswith("-skip-testing:")]), 3)
        self.assert_owned_cleanup()

    def test_build_failure_cleans_only_owned_device_without_starting_tests(self):
        result = self.run_script("build_failure")
        self.assertEqual(result.returncode, 65)
        self.assertFalse(any("test" in call["args"] for call in self.calls()))
        self.assert_owned_cleanup()

    def test_test_failure_cleans_only_owned_device(self):
        result = self.run_script("test_failure", "--skip-build")
        self.assertEqual(result.returncode, 65)
        self.assert_owned_cleanup()

    def test_cancellation_stops_child_and_cleans_only_owned_device(self):
        self.environment["TVOS_RUNNER_TEST_MODE"] = "interrupt"
        process = subprocess.Popen([sys.executable, str(SCRIPT), "--skip-build"],
                                   env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True)
        try:
            deadline = time.monotonic() + 10
            while not (self.root / "test-started").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / "test-started").exists())
            process.send_signal(signal.SIGTERM)
            _, errors = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 130, errors)
            self.assert_owned_cleanup()
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_no_runtime_does_not_create_or_clean_any_device(self):
        result = self.run_script("no_runtime")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.calls()), 1)

    def test_backend_suites_require_explicit_opt_in(self):
        result = self.run_script("success", "--skip-build", "--include-backend-tests",
                                 "--only-testing", "MoviePilot-TV-Tests/BackendCompatibilityReadOnlyTests")
        self.assertEqual(result.returncode, 0, result.stderr)
        test = next(call["args"] for call in self.calls() if call["tool"] == "xcodebuild")
        self.assertFalse(any(arg.startswith("-skip-testing:") for arg in test))
        self.assertIn("-only-testing:MoviePilot-TV-Tests/BackendCompatibilityReadOnlyTests", test)
        self.assert_owned_cleanup()

    def test_existing_destination_cannot_be_passed_to_runner(self):
        result = self.run_script("success", "--destination", "platform=tvOS Simulator,name=Apple TV")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
