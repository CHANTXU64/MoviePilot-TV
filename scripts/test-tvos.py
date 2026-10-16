#!/usr/bin/env python3
"""Build on disposable tvOS simulators; run targeted tests or the full matrix.

The offline matrix runs tvOS 18.5, 26.5, and the latest 27.x at the same time.
Each version keeps its own DerivedData so the builds do not share build.db.
XCTest inside one version stays serial. Real-backend runs stay one version at a time.
"""

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
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed


REPO = Path(__file__).resolve().parents[1]
PRINT_LOCK = threading.Lock()
BACKEND_SUITES = (
    "BackendCompatibilityReadOnlyTests",
    "BackendCompatibilityPermissionBehaviorTests",
    "BackendCompatibilitySideEffectTests",
)


def emit(message, *, error=False):
    with PRINT_LOCK:
        print(message, file=sys.stderr if error else sys.stdout, flush=True)


class Gate:
    """Tracks child process groups so one version can stop the others."""

    def __init__(self):
        self._lock = threading.Lock()
        self._groups = set()
        self._starting = 0
        self.setup_error = None
        self.cleanup_error = None
        self.cancelling = False

    def begin(self):
        """Reserve a start. False means cancellation already won."""
        with self._lock:
            if self.cancelling:
                return False
            self._starting += 1
            return True

    def abort_start(self):
        with self._lock:
            self._starting -= 1

    def add(self, pid):
        with self._lock:
            self._starting -= 1
            self._groups.add(pid)
            kill = self.cancelling
        # Registration and cancellation share this lock. A cancel that already
        # observed an empty set still has to stop a process that registers now.
        if kill:
            _signal_groups([pid], signal.SIGTERM)

    def discard(self, pid):
        with self._lock:
            self._groups.discard(pid)

    def is_cancelling(self):
        with self._lock:
            return self.cancelling

    def note(self, error):
        """Classify a worker failure. Return 'abort', 'cleanup', 'test', or 'ignore'."""
        setup = aborts_parallel_matrix(error.cmd)
        with self._lock:
            if self.setup_error is not None or self.cancelling:
                if (setup and not _is_signal(error) and self.setup_error is not None
                        and _is_signal(self.setup_error)):
                    self.setup_error = error
                return "ignore"
            if setup:
                self.setup_error = error
                self.cancelling = True
                return "abort"
            if error.cmd[:3] == ["xcrun", "simctl", "delete"]:
                if self.cleanup_error is None:
                    self.cleanup_error = error
                return "cleanup"
            return "test"

    def cancel_children(self):
        # A start reserved by begin() has no pid yet. Returning while that count
        # is non-zero drops the process that is between Popen and add().
        with self._lock:
            self.cancelling = True
        deadline = time.monotonic() + 15
        while True:
            with self._lock:
                pids = list(self._groups)
                starting = self._starting
            if not pids and os.environ.get("TVOS_RUNNER_TEST_DIR"):
                marker = os.environ.get("TVOS_RUNNER_TEST_CANCEL_EMPTY")
                if marker:
                    Path(marker).write_text("empty\n")
            if pids:
                _signal_groups(pids, signal.SIGTERM)
            if not pids and starting == 0:
                return
            if time.monotonic() >= deadline:
                if pids:
                    _signal_groups(pids, signal.SIGKILL)
                return
            time.sleep(0.05)


def _is_signal(error):
    return error.returncode < 0 or error.returncode in (130, 143)


def aborts_parallel_matrix(command):
    """A failed prepare step stops the other versions. Cleanup does not."""
    if len(command) < 2:
        return False
    if command[0] == "xcodebuild" and command[1] in (
            "-resolvePackageDependencies", "build", "build-for-testing"):
        return True
    return command[:3] == ["xcrun", "simctl", "create"]


def _signal_groups(pids, sig):
    for pid in pids:
        # A version that already exited can make killpg return EPERM on macOS.
        try:
            os.killpg(pid, sig)
        except OSError:
            pass


def _wait_for_test_gap(command, gate):
    # The substitute holds the runner between two commands so a sibling failure
    # can arrive while this version has no child process.
    needle = os.environ.get("TVOS_RUNNER_TEST_GAP_ON")
    gap = os.environ.get("TVOS_RUNNER_TEST_GAP_FILE")
    if not needle or not gap or not os.environ.get("TVOS_RUNNER_TEST_DIR") or needle not in command:
        return
    Path(gap).write_text("waiting\n")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if gate is not None and gate.is_cancelling():
            return
        time.sleep(0.01)


def _wait_to_register(command):
    # Holds the runner after Popen and before Gate.add, while cancellation can
    # observe an empty registry. Only the substitute sets these variables.
    # Each spawned process appends one line so a peer can wait until every
    # version is inside this window, not merely until the first one arrives.
    needle = os.environ.get("TVOS_RUNNER_TEST_REGISTER_GAP_ON")
    gap = os.environ.get("TVOS_RUNNER_TEST_REGISTER_GAP_FILE")
    if not needle or not gap or not os.environ.get("TVOS_RUNNER_TEST_DIR") or needle not in command:
        return
    with Path(gap).open("a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        handle.write("spawned\n")
        handle.flush()
    release = os.environ.get("TVOS_RUNNER_TEST_CANCEL_EMPTY")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if release and Path(release).exists():
            return
        time.sleep(0.01)


def _stop_process(process):
    # The child is its own session. Kill the group, then force it if it stays.
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except OSError:
        pass
    try:
        process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except OSError:
            pass
        process.wait()


def run(command, *, capture=False, check=True, quiet=False, env=None, gate=None, prefix=None):
    _wait_for_test_gap(command, gate)
    if gate is not None and not gate.begin():
        raise subprocess.CalledProcessError(-signal.SIGTERM, command)
    # begin() reserved a slot. Any exit before add() must release it, and must
    # also stop a process that already exists but is not registered yet.
    reservation = gate is not None
    stdout = subprocess.PIPE if capture or prefix else None
    if quiet:
        stderr = subprocess.DEVNULL
    elif prefix:
        stderr = subprocess.STDOUT
    else:
        stderr = None
    process = None
    registered = False
    try:
        process = subprocess.Popen(
            command, cwd=REPO, start_new_session=True, stdout=stdout, stderr=stderr,
            text=True, env=env,
        )
        _wait_to_register(command)
        if gate is not None:
            gate.add(process.pid)
            reservation = False
            registered = True
        if prefix and process.stdout is not None:
            for line in process.stdout:
                with PRINT_LOCK:
                    sys.stdout.write(prefix + line)
                    sys.stdout.flush()
            returncode = process.wait()
            output = None
        else:
            output, _ = process.communicate()
            returncode = process.returncode
    except BaseException:
        if reservation and gate is not None:
            gate.abort_start()
        if process is not None:
            _stop_process(process)
        raise
    finally:
        if registered and gate is not None:
            gate.discard(process.pid)
    if check and returncode:
        raise subprocess.CalledProcessError(returncode, command)
    return output if capture else returncode


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
        emit(f"独立构建目录：{directory}")
        yield directory


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", help="指定一个 tvOS 版本；日常默认使用最新可用版本")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--full", action="store_true",
                      help="提交验收：完整构建与全套测试；默认三个 tvOS 版本并行")
    mode.add_argument("--only-testing", action="append", default=[], metavar="TEST_ID",
                      help="只构建测试宿主并运行指定用例，默认单版本")
    parser.add_argument("--include-backend-tests", action="store_true",
                        help="包含真实后端套件；矩阵改为逐版本运行")
    parser.add_argument("--skip-build", action="store_true",
                        help="仅用于 --full：跳过依赖解析与 Debug 构建；测试宿主仍会构建")
    parser.add_argument("--serial", action="store_true",
                        help="离线三版本矩阵改为逐个运行；真实后端矩阵始终逐个运行")
    parser.add_argument("--derived-data-path", help="专用构建缓存目录，默认与日常 Xcode 隔离")
    parser.add_argument("--result-bundle-path", help="测试结果包路径；只构建时不产生结果包")
    args = parser.parse_args(argv)
    runs_tests = args.full or args.only_testing
    if not runs_tests and (args.skip_build or args.include_backend_tests or args.result_bundle_path):
        parser.error("运行测试须指定 --only-testing；仅提交验收使用 --full")
    if args.skip_build and not args.full:
        parser.error("--skip-build 只用于 --full；定向测试始终构建测试宿主")
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
    versions = [runtime["version"] for runtime, _ in selections]
    emit("tvOS 测试版本：" + "、".join(versions))
    parallel = len(selections) > 1 and not args.serial and not args.include_backend_tests
    if parallel:
        code = run_parallel(args, selections)
    else:
        code = run_serial(args, selections)
    return code


def result_path_for(args, runtime, count):
    if not args.result_bundle_path:
        return None
    result_path = Path(args.result_bundle_path).resolve()
    if count > 1:
        result_path = result_path.with_name(
            f"{result_path.stem}-tvos-{runtime['version']}{result_path.suffix}")
    return result_path


def run_serial(args, selections):
    failures = []
    for runtime, device in selections:
        result_path = result_path_for(args, runtime, len(selections))
        try:
            derived = Path(args.derived_data_path) / f"tvos-{runtime['version']}"
            run_on_simulator(args, runtime, device, result_path, derived)
        except subprocess.CalledProcessError as error:
            # A compile/resolve/setup failure blocks validation on every runtime.
            if args.include_backend_tests or error.cmd[:2] != ["xcodebuild", "test-without-building"]:
                raise
            failures.append((runtime["version"], error.returncode))
            emit(f"tvOS {runtime['version']} 验证失败（退出码 {error.returncode}）。", error=True)
    if failures:
        emit("未通过的 tvOS 版本：" + "、".join(version for version, _ in failures), error=True)
        return failures[0][1]
    return 0


def run_parallel(args, selections):
    packages_dir = None
    if args.full and not args.skip_build:
        packages_dir = Path(args.derived_data_path) / "SourcePackages"
        resolve_packages(packages_dir)
    gate = Gate()
    failures = []
    failure_lock = threading.Lock()
    emit("并行运行：" + "、".join(runtime["version"] for runtime, _ in selections))

    def worker(runtime, device):
        prefix = f"[tvOS {runtime['version']}] "
        derived = Path(args.derived_data_path) / f"tvos-{runtime['version']}"
        try:
            run_on_simulator(
                args, runtime, device, result_path_for(args, runtime, len(selections)),
                derived, packages_dir=packages_dir, gate=gate, prefix=prefix,
            )
        except subprocess.CalledProcessError as error:
            kind = gate.note(error)
            if kind == "abort":
                emit(f"tvOS {runtime['version']} 构建或准备失败，停止其余版本。", error=True)
                gate.cancel_children()
            elif kind == "test":
                with failure_lock:
                    failures.append((runtime["version"], error.returncode))
                emit(f"tvOS {runtime['version']} 验证失败（退出码 {error.returncode}）。", error=True)
        except BaseException:
            gate.cancel_children()
            raise

    with ThreadPoolExecutor(max_workers=len(selections)) as pool:
        futures = [pool.submit(worker, runtime, device) for runtime, device in selections]
        try:
            for future in as_completed(futures):
                future.result()
        except BaseException:
            gate.cancel_children()
            raise
    if gate.setup_error:
        raise gate.setup_error
    if failures:
        emit("未通过的 tvOS 版本：" + "、".join(version for version, _ in failures), error=True)
        return failures[0][1]
    if gate.cleanup_error:
        raise gate.cleanup_error
    return 0


def resolve_packages(packages_dir):
    # Keep resolution out of every tvos-<version> build.db, and out of Xcode's
    # daily DerivedData. The parent directory is the runner's locked cache.
    run([
        "xcodebuild", "-resolvePackageDependencies",
        "-project", "MoviePilot-TV.xcodeproj", "-scheme", "MoviePilot-TV",
        "-clonedSourcePackagesDirPath", str(packages_dir),
        "-derivedDataPath", str(packages_dir.parent / "package-resolution"),
        "-skipPackagePluginValidation",
    ])


def package_flags(packages_dir):
    if packages_dir is None:
        return []
    return [
        "-clonedSourcePackagesDirPath", str(packages_dir),
        "-disableAutomaticPackageResolution",
    ]


def run_on_simulator(args, runtime, device, result_path, derived_path, packages_dir=None, gate=None, prefix=""):
    simulator = None
    simulator_name = f"MoviePilot-TV Tests tvOS {runtime['version']} {uuid.uuid4().hex}"
    creation_started = False
    try:
        creation_started = True
        created_device = run([
            "xcrun", "simctl", "create", simulator_name,
            device["identifier"], runtime["identifier"],
        ], capture=True, gate=gate).strip()
        simulator = str(uuid.UUID(created_device)).upper()
        emit(f"{prefix}专用测试模拟器：{device['name']} / tvOS {runtime['version']} / {simulator}")
        common = [
            "-project", "MoviePilot-TV.xcodeproj", "-scheme", "MoviePilot-TV",
            "-destination", f"platform=tvOS Simulator,id={simulator}",
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "-skipPackagePluginValidation",
            "-derivedDataPath", str(derived_path),
            *package_flags(packages_dir),
        ]
        if args.full and not args.skip_build:
            if packages_dir is None:
                run(["xcodebuild", "-resolvePackageDependencies", *common], gate=gate, prefix=prefix)
            run(["xcodebuild", "build", "-configuration", "Debug", *common], gate=gate, prefix=prefix)
        elif not args.full and not args.only_testing:
            run(["xcodebuild", "build", "-configuration", "Debug", *common], gate=gate, prefix=prefix)
            return
        run(["xcodebuild", "build-for-testing", "-configuration", "Testing", *common], gate=gate, prefix=prefix)
        test = [
            "xcodebuild", "test-without-building", "-configuration", "Testing", *common,
            "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
            "-collect-test-diagnostics", "never",
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
        run(test, env=test_environment, gate=gate, prefix=prefix)
    finally:
        pending_error = sys.exc_info()[1]
        if creation_started and simulator is None:
            # Creation may have succeeded before stdout validation or interruption failed.
            # Recover only the exact name, runtime and device type generated by this invocation.
            try:
                simulator = find_created_simulator(
                    simulator_name, runtime["identifier"], device["identifier"])
            except (ValueError, RuntimeError, KeyError, subprocess.CalledProcessError) as error:
                emit(f"无法确认本次测试设备，未执行删除：{error}", error=True)
        if simulator:
            # Never use erase, shutdown all, delete all, or a destination passed by the caller.
            try:
                # Cleanup stays out of the cancel gate. Stopping a sibling build must not
                # kill the simctl process that removes this run's simulator.
                run(["xcrun", "simctl", "shutdown", simulator], check=False, quiet=True)
                run(["xcrun", "simctl", "delete", simulator])
            except (OSError, subprocess.CalledProcessError) as error:
                emit(f"无法清理本次测试模拟器 {simulator}：{error}", error=True)
                if pending_error is None:
                    raise
            else:
                emit(f"{prefix}已清理本次创建的测试模拟器：{simulator}")


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
        emit(str(error), error=True)
        sys.exit(1)
