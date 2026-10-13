#!/usr/bin/env python3
"""Build on one disposable tvOS simulator; run targeted tests or opt into the full matrix."""

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
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
        target = requested_version or (f"{latest_major}.x" if latest_major else "")
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


@contextmanager
def build_directory(requested_path):
    repo_key = hashlib.sha256(str(REPO).encode()).hexdigest()[:12]
    directory = (Path(requested_path) if requested_path else
                 Path(tempfile.gettempdir()) / "MoviePilot-TV-tests" / repo_key / "DerivedData").resolve()
    directory.mkdir(parents=True, exist_ok=True)
    # Reuse incremental build artifacts, but never overlap two runner invocations.
    with (directory.parent / (directory.name + ".lock")).open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(f"测试构建目录正在使用，请等待该任务结束或指定另一目录：{directory}") from error
        print(f"独立构建目录：{directory}", flush=True)
        yield directory


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", help="指定一个 tvOS 版本；日常默认使用最新可用版本")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--full", action="store_true", help="提交验收：完整构建与全套测试；默认运行三版本矩阵")
    mode.add_argument("--only-testing", action="append", default=[], metavar="TEST_ID",
                      help="只构建测试宿主并运行指定用例，默认单版本")
    parser.add_argument("--include-backend-tests", action="store_true",
                        help="包含真实后端套件；仍遵守其独立开关与目标限制")
    parser.add_argument("--skip-build", action="store_true",
                        help="全量模式跳过依赖解析与 Debug clean build；测试宿主仍会构建")
    parser.add_argument("--derived-data-path", help="专用构建缓存目录，默认与日常 Xcode 隔离")
    parser.add_argument("--result-bundle-path")
    args = parser.parse_args(argv)
    if not args.full and not args.only_testing and (args.skip_build or args.include_backend_tests):
        parser.error("运行测试须指定 --only-testing；仅提交验收使用 --full")
    with build_directory(args.derived_data_path) as directory:
        args.derived_data_path = directory
        return run_selected(args)


def run_selected(args):
    # Selection happens before any device is created. No existing device ID is accepted.
    runtimes = json.loads(run(["xcrun", "simctl", "list", "runtimes", "-j"], capture=True))
    if args.runtime:
        selections = [select_runtime(runtimes["runtimes"], args.runtime)]
    elif args.full:
        selections = [
            select_runtime(runtimes["runtimes"], "18.5"),
            select_runtime(runtimes["runtimes"], "26.5"),
            select_runtime(runtimes["runtimes"], latest_major=27),
        ]
    else:
        selections = [select_runtime(runtimes["runtimes"])]
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
            # A compile/resolve/setup failure blocks validation on every runtime.
            if args.include_backend_tests or error.cmd[:2] != ["xcodebuild", "test-without-building"]:
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
        common += ["-derivedDataPath", str(args.derived_data_path)]
        if args.full and not args.skip_build:
            run(["xcodebuild", "-resolvePackageDependencies", *common])
            run(["xcodebuild", "clean", "build", "-configuration", "Debug", *common])
        elif not args.full and not args.only_testing:
            run(["xcodebuild", "build", "-configuration", "Debug", *common])
            return
        run(["xcodebuild", "build-for-testing", "-configuration", "Testing", *common])
        test = [
            "xcodebuild", "test-without-building", "-configuration", "Testing", *common,
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
