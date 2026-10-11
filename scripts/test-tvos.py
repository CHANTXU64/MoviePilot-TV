#!/usr/bin/env python3
"""Build and test on a fresh, disposable tvOS simulator, never a user's device."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import uuid


REPO = Path(__file__).resolve().parents[1]
BACKEND_SUITES = (
    "BackendCompatibilityReadOnlyTests",
    "BackendCompatibilityPermissionBehaviorTests",
    "BackendCompatibilitySideEffectTests",
)


def run(command, *, capture=False, check=True, quiet=False, env=None):
    process = subprocess.Popen(
        command, cwd=REPO, start_new_session=True,
        stdout=subprocess.PIPE if capture else (subprocess.DEVNULL if quiet else None),
        stderr=subprocess.DEVNULL if quiet else None, text=True, env=env,
    )
    try:
        output, _ = process.communicate()
    except BaseException:
        # Stop our entire build process group before deleting its simulator.
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise
    if check and process.returncode:
        raise subprocess.CalledProcessError(process.returncode, command)
    return output if capture else process.returncode


def select_runtime(runtimes, requested_version=None, latest_major=None):
    candidates = [
        runtime for runtime in runtimes
        if runtime.get("isAvailable")
        and ".tvOS-" in runtime["identifier"]
        and (requested_version is None or runtime["version"] == requested_version)
        and (latest_major is None or int(runtime["version"].split(".")[0]) == latest_major)
    ]
    if not candidates:
        target = requested_version or f"{latest_major}.x"
        raise RuntimeError(f"没有可用的 tvOS {target} Simulator runtime。")
    runtime = max(candidates, key=lambda value: tuple(map(int, value["version"].split("."))))
    devices = [
        device for device in runtime.get("supportedDeviceTypes", [])
        if device.get("productFamily") == "Apple TV"
    ]
    if not devices:
        raise RuntimeError("所选 tvOS runtime 没有支持的 Apple TV 设备类型。")
    return runtime, devices[0]


def find_created_simulator(name, runtime_identifier, device_type_identifier):
    inventory = json.loads(run(["xcrun", "simctl", "list", "devices", "-j"], capture=True))
    matches = [device for device in inventory.get("devices", {}).get(runtime_identifier, [])
               if device.get("name") == name
               and device.get("deviceTypeIdentifier") == device_type_identifier]
    if len(matches) > 1:
        raise RuntimeError("本次测试模拟器身份不唯一，未执行清理。")
    return str(uuid.UUID(matches[0]["udid"])).upper() if matches else None


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", help="仅运行指定 tvOS 版本；默认依次运行 18.5、26.5 和最新已安装的 27.x")
    parser.add_argument("--only-testing", action="append", default=[], metavar="TEST_ID")
    parser.add_argument("--include-backend-tests", action="store_true",
                        help="包含真实后端套件；仍遵守其独立开关与目标限制")
    parser.add_argument("--skip-build", action="store_true",
                        help="跳过依赖解析与 Debug clean build；Testing 测试仍会构建宿主")
    parser.add_argument("--derived-data-path")
    parser.add_argument("--result-bundle-path")
    args = parser.parse_args(argv)
    # Selection happens before any device is created. No existing device ID is accepted.
    runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "-j"], capture=True))
    selections = (
        [select_runtime(runtimes["runtimes"], args.runtime)] if args.runtime else [
            select_runtime(runtimes["runtimes"], "18.5"),
            select_runtime(runtimes["runtimes"], "26.5"),
            select_runtime(runtimes["runtimes"], latest_major=27),
        ]
    )
    print("tvOS 测试版本：" + "、".join(runtime["version"] for runtime, _ in selections), flush=True)
    failures = []
    for runtime, device in selections:
        result_path = Path(args.result_bundle_path).resolve() if args.result_bundle_path else None
        if result_path and len(selections) > 1:
            result_path = result_path.with_name(
                f"{result_path.stem}-tvos-{runtime['version']}{result_path.suffix}")
        try:
            run_on_simulator(args, runtime, device, result_path)
        except subprocess.CalledProcessError as error:
            if args.include_backend_tests:
                raise
            failures.append((runtime["version"], error.returncode))
            print(f"tvOS {runtime['version']} 验证失败（退出码 {error.returncode}）。", file=sys.stderr)
    if failures:
        print("未通过的 tvOS 版本：" + "、".join(version for version, _ in failures), file=sys.stderr)
        return failures[0][1]
    return 0


def run_on_simulator(args, runtime, device, result_path):
    simulator = None
    simulator_name = f"MoviePilot-TV Tests tvOS {runtime['version']} {uuid.uuid4().hex}"
    creation_started = False
    try:
        creation_started = True
        created_device = run([
            "xcrun", "simctl", "create", simulator_name,
            device["identifier"], runtime["identifier"],
        ], capture=True).strip()
        simulator = str(uuid.UUID(created_device)).upper()
        print(f"专用测试模拟器：{device['name']} / tvOS {runtime['version']} / {simulator}", flush=True)
        common = [
            "-project", "MoviePilot-TV.xcodeproj", "-scheme", "MoviePilot-TV",
            "-destination", f"platform=tvOS Simulator,id={simulator}",
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "-skipPackagePluginValidation",
        ]
        if args.derived_data_path:
            common += ["-derivedDataPath", str(Path(args.derived_data_path).resolve())]
        if not args.skip_build:
            run(["xcodebuild", "-resolvePackageDependencies", *common])
            run(["xcodebuild", "clean", "build", "-configuration", "Debug", *common])
        test = [
            "xcodebuild", "test", "-configuration", "Testing", *common,
            "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
        ]
        if not args.include_backend_tests:
            test += [f"-skip-testing:MoviePilot-TV-Tests/{suite}" for suite in BACKEND_SUITES]
        test += [f"-only-testing:{test_id}" for test_id in args.only_testing]
        if result_path:
            test += ["-resultBundlePath", str(result_path)]
        test_environment = dict(os.environ)
        # xcodebuild forwards TEST_RUNNER_ variables to the XCTest process.
        for key, value in os.environ.items():
            if key.startswith("MOVIEPILOT_COMPAT_"):
                test_environment[f"TEST_RUNNER_{key}"] = value
        run(test, env=test_environment)
    finally:
        pending_error = sys.exc_info()[1]
        if creation_started and simulator is None:
            # Creation may have succeeded before stdout validation or interruption failed.
            # Recover only the exact name, runtime and device type generated by this invocation.
            try:
                simulator = find_created_simulator(
                    simulator_name, runtime["identifier"], device["identifier"])
            except (ValueError, RuntimeError, KeyError, subprocess.CalledProcessError) as error:
                print(f"无法确认本次测试设备，未执行删除：{error}", file=sys.stderr)
        if simulator:
            # Never use erase, shutdown all, delete all, or a destination passed by the caller.
            try:
                run(["xcrun", "simctl", "shutdown", simulator], check=False, quiet=True)
                run(["xcrun", "simctl", "delete", simulator])
            except (OSError, subprocess.CalledProcessError) as error:
                print(f"无法清理本次测试模拟器 {simulator}：{error}", file=sys.stderr)
                if pending_error is None:
                    raise
            else:
                print(f"已清理本次创建的测试模拟器：{simulator}", flush=True)


def interrupted(signum, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
    except (RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
