from __future__ import annotations

import hashlib
import json
import os
import signal
import subprocess
import time
from pathlib import Path
from typing import Callable

from dogtail import rawinput, tree
from dogtail.predicate import GenericPredicate


NAV_OPEN_LYRICS = "lddc.nav.open_lyrics"
OPEN_SONG_FILE = "lddc.open_lyrics.open_song_file"


class Evidence:
    def __init__(self, scenario: str) -> None:
        self.scenario = scenario
        self.actions: dict[str, list[dict[str, object]]] = {}
        self.artifacts: list[dict[str, object]] = []

    def add(self, capability: str, action: str) -> None:
        self.actions.setdefault(capability, []).append({"action": action})

    def add_fixture(self, fixture: Path) -> None:
        payload = fixture.read_bytes()
        self.artifacts.append(
            {
                "name": fixture.name,
                "size": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            }
        )

    def write(self, failure: BaseException | None, process_count: int) -> None:
        output_dir = Path(_required_environment("LDDC_NATIVE_EVIDENCE_DIR"))
        output_dir.mkdir(parents=True, exist_ok=True)
        if process_count < 0:
            # 无法读取 ps 时按残留处理，不能用未知状态伪装成 0。
            process_count = 1
        payload = {
            "runId": _required_environment("LDDC_IT_RUN_ID"),
            "scenario": self.scenario,
            "profile": "platform",
            "platform": "linux",
            "framework": "dogtail-atspi",
            "steps": [
                {
                    "step": self.scenario,
                    "success": failure is None,
                    "error": (
                        None
                        if failure is None
                        else f"{type(failure).__name__}: {failure}"
                    ),
                }
            ],
            "capabilityEvidence": self.actions,
            "resources": {
                "baseline": {"childProcessCount": 0},
                "final": {"childProcessCount": process_count},
                "thresholds": {"childProcessCount": 0},
            },
            "artifacts": self.artifacts,
            "extra": {},
        }
        target = output_dir / f"{self.scenario}.json"
        temporary = target.with_suffix(".json.tmp")
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, target)


def _required_environment(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"缺少环境变量 {name}")
    return value


def _stop_process_group(process: subprocess.Popen[bytes]) -> bool:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return True
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        # 正常终止超时后必须清理整个会话，避免 Flutter 插件子进程留在 Xvfb/DBus 会话中。
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=5)
    try:
        os.killpg(process.pid, 0)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False
    return False


def _count_process_group(process_group_id: int) -> int:
    """读取当前进程组中的真实进程数，避免用测试步骤反推资源状态。"""
    try:
        output = subprocess.check_output(
            ["ps", "-eo", "pid=,pgid="], text=True, stderr=subprocess.DEVNULL
        )
    except (OSError, subprocess.CalledProcessError):
        return -1
    return sum(
        1
        for line in output.splitlines()
        if len(line.split()) == 2 and line.split()[1].isdigit()
        and int(line.split()[1]) == process_group_id
    )


def _wait_for_accessible_application(process: subprocess.Popen[bytes]) -> object:
    """等待 Flutter 注册到 AT-SPI；启动竞态必须有界失败。"""
    deadline = time.monotonic() + 30
    last_error: BaseException | None = None
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(
                f"LDDC 进程在 AT-SPI 注册前退出，退出码={process.returncode}"
            )
        try:
            return tree.root.application(
                os.environ.get("LDDC_LINUX_ACCESSIBLE_APP_NAME", "lddc")
            )
        except BaseException as error:
            last_error = error
            time.sleep(0.25)
    raise TimeoutError(f"等待 LDDC AT-SPI 应用节点超时: {last_error}")


def _run_reported(
    scenario: str,
    action: Callable[[object, Evidence], None],
) -> None:
    executable = Path(_required_environment("LDDC_LINUX_APP_EXE")).resolve()
    fixture = Path(_required_environment("LDDC_FIXTURE_PATH")).resolve()
    pid_file = Path(_required_environment("LDDC_NATIVE_PID_FILE"))
    log_dir = Path(_required_environment("LDDC_NATIVE_LOG_DIR"))
    log_dir.mkdir(parents=True, exist_ok=True)
    evidence = Evidence(scenario)
    failure: BaseException | None = None
    process: subprocess.Popen[bytes] | None = None
    process_exited = False
    process_count = 0
    with (log_dir / f"{scenario}-app.log").open("wb") as log:
        try:
            process = subprocess.Popen(
                [str(executable)],
                cwd=executable.parent,
                env=os.environ.copy(),
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
            )
            pid_file.write_text(str(process.pid), encoding="ascii")
            app = _wait_for_accessible_application(process)
            evidence.add("desktopProcess", "production_executable_launched")
            evidence.add("windowHost", "atspi_application_discovered")
            action(app, evidence)
        except BaseException as error:
            failure = error
        finally:
            if process is not None:
                process_exited = _stop_process_group(process)
                process_count = _count_process_group(process.pid)
            pid_file.unlink(missing_ok=True)

    if process_exited:
        evidence.add("resourceCleanup", "process_group_and_dialogs_closed")
    elif failure is None:
        failure = AssertionError("LDDC Linux 进程组没有回到基线")
    evidence.write(failure, process_count)
    if failure is not None:
        raise failure


def _open_file_chooser(app: object) -> object:
    # Dogtail 2.0.4 自带 identifier predicate；找不到时必须失败，禁止回退到本地化名称或坐标。
    navigation = app.find_child(GenericPredicate(identifier=NAV_OPEN_LYRICS))
    navigation.click()
    open_song = app.find_child(GenericPredicate(identifier=OPEN_SONG_FILE))
    open_song.click()
    return tree.root.find_child(GenericPredicate(role_name="file chooser"))


def test_gtk_file_chooser_selects_fixture() -> None:
    def action(app: object, evidence: Evidence) -> None:
        fixture = Path(_required_environment("LDDC_FIXTURE_PATH")).resolve()
        chooser = _open_file_chooser(app)
        rawinput.key_combo("<Control>l")
        rawinput.type_text(str(fixture.parent))
        rawinput.press_key("enter")
        chooser.find_child(GenericPredicate(name=fixture.name)).click()
        chooser.find_child(GenericPredicate(name="Open", role_name="push button")).click()
        result = app.find_child(GenericPredicate(identifier=OPEN_SONG_FILE))
        if not result.showing:
            raise AssertionError("选择文件后 Flutter 打开歌曲动作没有保持可见")
        evidence.add("filePicker", "gtk_file_chooser_select_audio")
        evidence.add("nativeChannels", "flutter_picker_round_trip")
        evidence.add_fixture(fixture)

    _run_reported("linux_gtk_file_chooser_select", action)


def test_gtk_file_chooser_cancellation_returns_to_flutter() -> None:
    def action(app: object, evidence: Evidence) -> None:
        chooser = _open_file_chooser(app)
        chooser.find_child(
            GenericPredicate(name="Cancel", role_name="push button")
        ).click()
        app.find_child(GenericPredicate(identifier=OPEN_SONG_FILE))
        evidence.add("filePicker", "gtk_file_chooser_cancel")
        evidence.add("nativeChannels", "flutter_picker_cancel_round_trip")

    _run_reported("linux_gtk_file_chooser_cancel", action)
