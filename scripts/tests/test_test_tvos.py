"""Exercise the test entry point with command substitutes; no user's simulator is touched."""

import fcntl
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
OWNED_DEVICE = "11111111-22AA-4333-8444-555555555555"
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
    log.write(json.dumps({"tool": tool, "args": args, "test_environment": {
        key: value for key, value in os.environ.items() if key.startswith("TEST_RUNNER_MOVIEPILOT_COMPAT_")
    }}) + "\n")
mode = os.environ.get("TVOS_RUNNER_TEST_MODE", "success")
state = root / "created.json"
owned = json.loads(state.read_text())["udid"] if state.exists() else "11111111-22AA-4333-8444-555555555555"
if tool == "xcrun":
    if args == ["simctl", "list", "runtimes", "-j"]:
        versions = json.loads(os.environ.get("TVOS_RUNNER_TEST_VERSIONS", '["18.5","26.5","27.0","27.2","27.10","28.0"]'))
        unavailable = json.loads(os.environ.get("TVOS_RUNNER_TEST_UNAVAILABLE", '[]'))
        no_device = os.environ.get("TVOS_RUNNER_TEST_NO_DEVICE")
        runtimes = [{"identifier": "com.apple.CoreSimulator.SimRuntime.tvOS-" + version.replace(".", "-"),
                     "version": version, "isAvailable": version not in unavailable,
                     "supportedDeviceTypes": [] if version == no_device else [
                         {"identifier": "type.apple-tv", "name": "Apple TV", "productFamily": "Apple TV"}]}
                    for version in versions]
        print(json.dumps({"runtimes": [] if mode == "no_runtime" else runtimes}))
    elif args[:2] == ["simctl", "create"]:
        count = sum(1 for line in (root / "calls.jsonl").read_text().splitlines()
                    if json.loads(line)["args"][:2] == ["simctl", "create"])
        owned = f"11111111-22AA-4333-8444-{555555555554 + count}"
        (root / "created.json").write_text(json.dumps({"name":args[2], "udid":owned,
            "deviceTypeIdentifier":args[3], "runtime":args[4]}))
        if mode == "create_failure_after_creation":
            sys.exit(1)
        if mode == "interrupt_during_create":
            (root / "create-started").touch()
            time.sleep(60)
        print("all" if mode in ("invalid_create_output", "ambiguous_create_output") else owned)
    elif args == ["simctl", "list", "devices", "-j"]:
        device=json.loads((root / "created.json").read_text())
        runtime=device.pop("runtime")
        daily={"name":"Daily Apple TV", "udid":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
               "deviceTypeIdentifier":device["deviceTypeIdentifier"]}
        matches=[device, daily]
        if mode == "ambiguous_create_output":
            matches.append(dict(device,udid="bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"))
        print(json.dumps({"devices":{runtime:matches}}))
    elif args in [["simctl", "shutdown", owned], ["simctl", "delete", owned]]:
        if args[1] == "delete" and os.environ.get("TVOS_RUNNER_TEST_DELETE_FAILURE"):
            sys.exit(1)
    else:
        raise SystemExit("Unexpected simulator operation: " + str(args))
elif tool == "xcodebuild":
    current_runtime = json.loads(state.read_text())["runtime"]
    selected_failure = os.environ.get("TVOS_RUNNER_TEST_FAIL_RUNTIME")
    if selected_failure and current_runtime.endswith(selected_failure.replace(".", "-")) and "test-without-building" in args:
        sys.exit(65)
    if mode == "build_failure" and "build" in args:
        sys.exit(65)
    if mode == "test_build_failure" and "build-for-testing" in args:
        sys.exit(65)
    if mode == "resolve_failure" and "-resolvePackageDependencies" in args:
        sys.exit(65)
    if "test-without-building" in args:
        if mode == "test_failure":
            sys.exit(65)
        if mode == "interrupt" and not (root / "test-started").exists():
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
                                PATH=str(self.root) + os.pathsep + os.environ["PATH"], TMPDIR=str(self.root))
        # A user's persistent state must survive every run, including failure and cancellation.
        self.sentinel = self.root / "daily-simulator-data"
        self.sentinel.write_text("saved session and password")

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def run_script(self, mode="success", *arguments, matrix=False, full=True):
        self.environment["TVOS_RUNNER_TEST_MODE"] = mode
        runtime_args = [] if matrix or "--runtime" in arguments else ["--runtime", "27.0"]
        full_args = ["--full"] if full and "--only-testing" not in arguments else []
        return subprocess.run([sys.executable, str(SCRIPT), *runtime_args, *full_args, *arguments], env=self.environment,
                              capture_output=True, text=True, timeout=20)

    def assert_owned_cleanup(self):
        mutations = [call["args"] for call in self.calls()
                     if call["tool"] == "xcrun" and call["args"][1] in ("shutdown", "delete", "erase")]
        self.assertEqual(mutations, [["simctl", "shutdown", OWNED_DEVICE],
                                     ["simctl", "delete", OWNED_DEVICE]])
        self.assertEqual(self.sentinel.read_text(), "saved session and password")

    def test_default_only_builds_latest_runtime_in_separate_incremental_directory(self):
        result = self.run_script(full=False, matrix=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [call["args"] for call in self.calls() if call["tool"] == "xcodebuild"]
        self.assertEqual(len(builds), 1)
        self.assertEqual(builds[0][0], "build")
        self.assertIn("Debug", builds[0])
        self.assertNotIn("clean", builds[0])
        self.assertNotIn("test-without-building", builds[0])
        derived = Path(builds[0][builds[0].index("-derivedDataPath") + 1])
        self.assertIn("MoviePilot-TV-tests", derived.parts)
        self.assertTrue(derived.is_relative_to(self.root.resolve()))
        creates = [call["args"] for call in self.calls() if call["args"][:2] == ["simctl", "create"]]
        self.assertEqual(len(creates), 1)
        self.assertTrue(creates[0][4].endswith("tvOS-28-0"))
        self.assert_owned_cleanup()

    def test_targeted_tests_use_one_runtime_and_do_not_build_debug(self):
        result = self.run_script("success", "--only-testing", "MoviePilot-TV-Tests/TestIsolationTests", matrix=True, full=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [call["args"] for call in self.calls() if call["tool"] == "xcodebuild"]
        self.assertEqual([args[0] for args in builds], ["build-for-testing", "test-without-building"])
        self.assertIn("-only-testing:MoviePilot-TV-Tests/TestIsolationTests", builds[1])
        self.assertTrue(all("Testing" in args for args in builds))
        self.assert_owned_cleanup()

    def test_all_build_stages_fail_fast_before_later_versions_or_tests(self):
        for mode in ("resolve_failure", "build_failure", "test_build_failure"):
            with self.subTest(mode=mode):
                (self.root / "calls.jsonl").unlink(missing_ok=True)
                result = self.run_script(mode, matrix=True)
                self.assertEqual(result.returncode, 65, result.stderr)
                self.assertEqual(sum(call["args"][:2] == ["simctl", "create"] for call in self.calls()), 1)
                self.assertFalse(any("test-without-building" in call["args"] for call in self.calls()))
                self.assert_owned_cleanup()

    def test_custom_derived_data_is_shared_by_stages_and_lock_is_released(self):
        derived = self.root / "build-cache"
        for mode in ("build_failure", "success"):
            result = self.run_script(mode, "--derived-data-path", str(derived))
            self.assertEqual(result.returncode, 65 if mode == "build_failure" else 0, result.stderr)
        builds = [call["args"] for call in self.calls() if call["tool"] == "xcodebuild"]
        self.assertTrue(all(args[args.index("-derivedDataPath") + 1] == str(derived.resolve()) for args in builds))

    def test_busy_build_directory_exits_before_creating_simulator(self):
        derived = self.root / "build-cache"
        with (self.root / "build-cache.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = self.run_script("success", "--derived-data-path", str(derived), full=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn("构建目录正在使用", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_skip_build_cannot_implicitly_start_full_tests(self):
        result = self.run_script("success", "--skip-build", full=False)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_options_without_effect_are_rejected_before_any_command(self):
        for arguments in (("--skip-build", "--only-testing", "MoviePilot-TV-Tests/TestIsolationTests"),
                          ("--result-bundle-path", str(self.root / "results.xcresult"))):
            with self.subTest(arguments=arguments):
                result = self.run_script("success", *arguments, full=False)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(self.calls(), [])

    def test_success_builds_debug_and_tests_isolated_configuration(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        builds = [call["args"] for call in self.calls() if call["tool"] == "xcodebuild"]
        self.assertIn("-resolvePackageDependencies", builds[0])
        self.assertIn("Debug", builds[1])
        self.assertIn("build-for-testing", builds[2])
        test = builds[3]
        self.assertEqual(test[test.index("-configuration") + 1], "Testing")
        self.assertEqual(test[test.index("-destination") + 1],
                         f"platform=tvOS Simulator,id={OWNED_DEVICE}")
        self.assertEqual(test[test.index("-parallel-testing-enabled") + 1], "NO")
        self.assertEqual(test[test.index("-maximum-concurrent-test-simulator-destinations") + 1], "1")
        self.assertIn("CODE_SIGNING_ALLOWED=YES", test)
        self.assertIn("CODE_SIGN_IDENTITY=-", test)
        self.assertEqual(len([arg for arg in test if arg.startswith("-skip-testing:")]), 3)
        self.assert_owned_cleanup()

    def test_default_matrix_builds_and_tests_each_runtime_with_separate_results(self):
        result = self.run_script("success", "--result-bundle-path", str(self.root / "results.xcresult"), matrix=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        creates = [call["args"] for call in calls if call["args"][:2] == ["simctl", "create"]]
        versions = ["18.5", "26.5", "27.10"]
        self.assertEqual([args[4] for args in creates],
                         ["com.apple.CoreSimulator.SimRuntime.tvOS-" + v.replace(".", "-") for v in versions])
        builds = [call["args"] for call in calls if call["tool"] == "xcodebuild"]
        self.assertEqual(len(builds), 12)
        tests = [args for args in builds if "test-without-building" in args]
        destinations = [args[args.index("-destination") + 1] for args in tests]
        self.assertEqual(len(set(destinations)), 3)
        for index, (version, test) in enumerate(zip(versions, tests)):
            self.assertEqual(test[test.index("-resultBundlePath") + 1],
                             str((self.root / f"results-tvos-{version}.xcresult").resolve()))
            self.assertIn("Testing", test)
            self.assertIn("CODE_SIGNING_ALLOWED=YES", test)
            self.assertIn("CODE_SIGN_IDENTITY=-", test)
            self.assertEqual(test[test.index("-parallel-testing-enabled") + 1], "NO")
            self.assertEqual(test[test.index("-maximum-concurrent-test-simulator-destinations") + 1], "1")
            self.assertEqual(len([arg for arg in test if arg.startswith("-skip-testing:")]), 3)
            self.assertIn("-resolvePackageDependencies", builds[index * 4])
            self.assertIn("Debug", builds[index * 4 + 1])
            self.assertEqual(builds[index * 4 + 1][builds[index * 4 + 1].index("-destination") + 1], destinations[index])
        mutations = [call["args"] for call in calls if call["args"][:2] in (
            ["simctl", "shutdown"], ["simctl", "delete"], ["simctl", "erase"])]
        self.assertEqual(mutations, [action for destination in destinations for action in (
            ["simctl", "shutdown", destination.split("id=")[1]],
            ["simctl", "delete", destination.split("id=")[1]])])
        # A version is cleaned before the next one is created; no concurrent simulator matrix.
        lifecycle = [call["args"][1] for call in calls if call["args"][:2] in (
            ["simctl", "create"], ["simctl", "delete"])]
        self.assertEqual(lifecycle, ["create", "delete"] * 3)
        self.assertEqual(self.sentinel.read_text(), "saved session and password")

    def test_explicit_runtime_runs_only_exact_version_and_keeps_result_path(self):
        self.environment["TVOS_RUNNER_TEST_VERSIONS"] = json.dumps(["27.0", "27.10", "28.0"])
        result_path = str((self.root / "single.xcresult").resolve())
        result = self.run_script("success", "--runtime", "27.0", "--skip-build",
                                 "--result-bundle-path", result_path, matrix=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        creates = [call["args"] for call in self.calls() if call["args"][:2] == ["simctl", "create"]]
        self.assertEqual(len(creates), 1)
        self.assertTrue(creates[0][4].endswith("tvOS-27-0"))
        test = next(call["args"] for call in self.calls() if "test-without-building" in call["args"])
        self.assertEqual(test[test.index("-resultBundlePath") + 1], result_path)
        self.assert_owned_cleanup()

    def test_matrix_rejects_missing_or_unavailable_runtime_before_creating_device(self):
        for versions, unavailable, missing in [
            (["26.5", "27.0"], [], "18.5"),
            (["18.5", "26.5", "27.0"], ["26.5"], "26.5"),
            (["18.5", "26.5", "28.0"], [], "27.x"),
        ]:
            with self.subTest(missing=missing):
                self.environment["TVOS_RUNNER_TEST_VERSIONS"] = json.dumps(versions)
                self.environment["TVOS_RUNNER_TEST_UNAVAILABLE"] = json.dumps(unavailable)
                result = self.run_script(matrix=True)
                self.assertEqual(result.returncode, 1)
                self.assertIn(missing, result.stderr)
        self.assertTrue(all(call["args"] == ["simctl", "list", "runtimes", "-j"] for call in self.calls()))

    def test_matrix_validates_supported_device_before_any_creation(self):
        self.environment["TVOS_RUNNER_TEST_NO_DEVICE"] = "26.5"
        result = self.run_script(matrix=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.calls()), 1)

    def test_matrix_continues_after_offline_failure_and_returns_failure(self):
        self.environment["TVOS_RUNNER_TEST_FAIL_RUNTIME"] = "26.5"
        result = self.run_script("success", "--skip-build", matrix=True)
        self.assertEqual(result.returncode, 65)
        self.assertIn("未通过的 tvOS 版本：26.5", result.stderr)
        tests = [call["args"] for call in self.calls() if "test-without-building" in call["args"]]
        self.assertEqual(len(tests), 3)
        self.assertEqual(sum(call["args"][:2] == ["simctl", "delete"] for call in self.calls()), 3)

    def test_backend_matrix_stops_after_first_failure(self):
        self.environment["TVOS_RUNNER_TEST_FAIL_RUNTIME"] = "18.5"
        result = self.run_script("success", "--skip-build", "--include-backend-tests", matrix=True)
        self.assertEqual(result.returncode, 65)
        self.assertEqual(sum(call["args"][:2] == ["simctl", "create"] for call in self.calls()), 1)
        self.assert_owned_cleanup()

    def test_cancellation_does_not_start_remaining_matrix_versions(self):
        self.assert_matrix_cancellation(signal.SIGTERM)

    def test_sigint_does_not_start_remaining_matrix_versions(self):
        self.assert_matrix_cancellation(signal.SIGINT)

    def test_sigterm_with_delete_failure_does_not_start_remaining_matrix_versions(self):
        self.environment["TVOS_RUNNER_TEST_DELETE_FAILURE"] = "1"
        self.assert_matrix_cancellation(signal.SIGTERM)

    def test_sigint_with_delete_failure_does_not_start_remaining_matrix_versions(self):
        self.environment["TVOS_RUNNER_TEST_DELETE_FAILURE"] = "1"
        self.assert_matrix_cancellation(signal.SIGINT)

    def assert_matrix_cancellation(self, signum):
        self.environment["TVOS_RUNNER_TEST_MODE"] = "interrupt"
        process = subprocess.Popen([sys.executable, str(SCRIPT), "--full", "--skip-build"],
                                   env=self.environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 10
            while not (self.root / "test-started").exists() and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / "test-started").exists())
            process.send_signal(signum)
            output, errors = process.communicate(timeout=10)
            creates = [call["args"] for call in self.calls() if call["args"][:2] == ["simctl", "create"]]
            self.assertEqual(process.returncode, 130, f"{creates}\n{errors}")
            self.assertEqual([args[4] for args in creates], ["com.apple.CoreSimulator.SimRuntime.tvOS-18-5"])
            self.assertEqual(sum(call["tool"] == "xcodebuild" for call in self.calls()), 2)
            self.assert_owned_cleanup()
            if self.environment.get("TVOS_RUNNER_TEST_DELETE_FAILURE"):
                self.assertIn("无法清理本次测试模拟器", errors)
                self.assertIn(OWNED_DEVICE, errors)
                self.assertNotIn("已清理本次创建的测试模拟器", output)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_cleanup_failure_is_reported_as_failure(self):
        self.environment["TVOS_RUNNER_TEST_DELETE_FAILURE"] = "1"
        result = self.run_script("success", "--skip-build")
        self.assertEqual(result.returncode, 1)
        self.assertIn("无法清理本次测试模拟器", result.stderr)
        self.assertIn(OWNED_DEVICE, result.stderr)
        self.assertNotIn("已清理本次创建的测试模拟器", result.stdout)
        self.assert_owned_cleanup()

    def test_test_failure_is_not_replaced_by_cleanup_failure(self):
        self.environment["TVOS_RUNNER_TEST_DELETE_FAILURE"] = "1"
        result = self.run_script("test_failure", "--skip-build")
        self.assertEqual(result.returncode, 65)
        self.assertIn("无法清理本次测试模拟器", result.stderr)
        self.assert_owned_cleanup()

    def test_build_failure_cleans_only_owned_device_without_starting_tests(self):
        result = self.run_script("build_failure")
        self.assertEqual(result.returncode, 65)
        self.assertFalse(any("test-without-building" in call["args"] for call in self.calls()))
        self.assert_owned_cleanup()

    def test_compatibility_overrides_reach_xctest_without_rewriting_env_file(self):
        self.environment["MOVIEPILOT_COMPAT_ENV_FILE"] = "/tmp/config with spaces.env"
        self.environment["MOVIEPILOT_COMPAT_ENABLE_SIDE_EFFECTS"] = "false"
        result = self.run_script("success", "--include-backend-tests",
                                 "--only-testing", "MoviePilot-TV-Tests/BackendCompatibilityReadOnlyTests")
        self.assertEqual(result.returncode, 0, result.stderr)
        test = next(call for call in self.calls() if call["tool"] == "xcodebuild" and "test-without-building" in call["args"])
        self.assertEqual(test["test_environment"]["TEST_RUNNER_MOVIEPILOT_COMPAT_ENV_FILE"],
                         "/tmp/config with spaces.env")
        self.assertEqual(test["test_environment"]["TEST_RUNNER_MOVIEPILOT_COMPAT_ENABLE_SIDE_EFFECTS"], "false")
        self.assert_owned_cleanup()

    def test_test_failure_cleans_only_owned_device(self):
        result = self.run_script("test_failure", "--skip-build")
        self.assertEqual(result.returncode, 65)
        self.assert_owned_cleanup()

    def test_cancellation_stops_child_and_cleans_only_owned_device(self):
        self.environment["TVOS_RUNNER_TEST_MODE"] = "interrupt"
        process = subprocess.Popen([sys.executable, str(SCRIPT), "--full", "--runtime", "27.0", "--skip-build"],
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
        result = self.run_script("success", "--include-backend-tests",
                                 "--only-testing", "MoviePilot-TV-Tests/BackendCompatibilityReadOnlyTests")
        self.assertEqual(result.returncode, 0, result.stderr)
        test = next(call["args"] for call in self.calls() if "test-without-building" in call["args"])
        self.assertFalse(any(arg.startswith("-skip-testing:") for arg in test))
        self.assertIn("-only-testing:MoviePilot-TV-Tests/BackendCompatibilityReadOnlyTests", test)
        self.assert_owned_cleanup()

    def test_cancellation_during_create_recovers_only_owned_device(self):
        self.environment["TVOS_RUNNER_TEST_MODE"]="interrupt_during_create"
        process=subprocess.Popen([sys.executable,str(SCRIPT),"--full","--runtime","27.0","--skip-build"],env=self.environment,
                                 stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            deadline=time.monotonic()+10
            while not (self.root / "create-started").exists() and time.monotonic()<deadline:
                time.sleep(0.02)
            self.assertTrue((self.root / "create-started").exists())
            process.send_signal(signal.SIGTERM)
            _,errors=process.communicate(timeout=10)
            self.assertEqual(process.returncode,130,errors)
            self.assert_owned_cleanup()
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_invalid_create_output_recovers_only_owned_device(self):
        result=self.run_script("invalid_create_output", "--skip-build")
        self.assertEqual(result.returncode,1)
        self.assert_owned_cleanup()
        self.assertTrue(any(call["args"]==["simctl","list","devices","-j"] for call in self.calls()))

    def test_create_failure_after_creation_recovers_owned_device(self):
        result=self.run_script("create_failure_after_creation", "--skip-build")
        self.assertEqual(result.returncode,1)
        self.assert_owned_cleanup()

    def test_ambiguous_device_identity_does_not_delete_any_device(self):
        result=self.run_script("ambiguous_create_output", "--skip-build")
        self.assertEqual(result.returncode,1)
        self.assertIn("身份不唯一",result.stderr)
        self.assertFalse(any(call["args"][1] in ("shutdown","delete","erase")
                             for call in self.calls() if call["tool"]=="xcrun"))
        self.assertEqual(self.sentinel.read_text(),"saved session and password")

    def test_existing_destination_cannot_be_passed_to_runner(self):
        result = self.run_script("success", "--destination", "platform=tvOS Simulator,name=Apple TV")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
