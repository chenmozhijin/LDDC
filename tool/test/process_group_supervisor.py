#!/usr/bin/env python3
"""在 POSIX CI 中以独立进程组运行并有界回收一条命令。"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from typing import IO, Any


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = path.with_name(f"{path.name}.tmp")
    staging.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    os.replace(staging, path)


def _group_snapshot(process_group_id: int) -> tuple[int, int]:
    """返回进程组当前进程数与 RSS 总和；采样失败时不伪造资源通过。"""

    try:
        completed = subprocess.run(
            ["/bin/ps", "-axo", "pid=,pgid=,rss="],
            check=True,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return -1, -1

    process_count = 0
    rss_kib = 0
    for raw_line in completed.stdout.splitlines():
        fields = raw_line.split()
        if len(fields) != 3:
            continue
        try:
            _, pgid, rss = (int(value) for value in fields)
        except ValueError:
            continue
        if pgid == process_group_id:
            process_count += 1
            rss_kib += rss
    return process_count, rss_kib * 1024


def _wait_until_process_and_group_empty(
    process: subprocess.Popen[bytes],
    process_group_id: int,
    timeout: float,
) -> bool:
    deadline = time.monotonic() + max(timeout, 0.0)
    while time.monotonic() < deadline:
        process_exited = process.poll() is not None
        process_count, _ = _group_snapshot(process_group_id)
        if process_exited and process_count == 0:
            return True
        time.sleep(0.05)
    process_exited = process.poll() is not None
    process_count, _ = _group_snapshot(process_group_id)
    return process_exited and process_count == 0


def _signal_group(process_group_id: int, value: signal.Signals) -> bool:
    try:
        os.killpg(process_group_id, value)
        return True
    except ProcessLookupError:
        return False


def _stop_group(
    process: subprocess.Popen[bytes],
    process_group_id: int,
    grace_seconds: float,
) -> tuple[bool, bool]:
    terminate_sent = _signal_group(process_group_id, signal.SIGTERM)
    if _wait_until_process_and_group_empty(process, process_group_id, grace_seconds):
        return terminate_sent, False

    kill_sent = _signal_group(process_group_id, signal.SIGKILL)
    _wait_until_process_and_group_empty(process, process_group_id, grace_seconds)
    return terminate_sent, kill_sent


def _normalized_exit_code(return_code: int | None) -> int:
    if return_code is None:
        return 125
    if return_code < 0:
        return min(255, 128 + abs(return_code))
    return min(255, return_code)


def _open_output(path: str | None) -> IO[bytes] | None:
    if not path:
        return None
    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    return output_path.open("wb")


def run_supervised(args: argparse.Namespace) -> int:
    if os.name != "posix":
        raise RuntimeError("process_group_supervisor 只能在 POSIX 平台运行")
    command = list(args.command)
    if command and command[0] == "--":
        command.pop(0)
    if not command:
        raise ValueError("缺少被监督命令")

    status_path = Path(args.status)
    started_wall = time.time()
    started_monotonic = time.monotonic()
    deadline = started_monotonic + args.timeout
    interrupted_signal: int | None = None
    process: subprocess.Popen[bytes] | None = None
    process_group_id: int | None = None
    stdout_handle: IO[bytes] | None = None
    stderr_handle: IO[bytes] | None = None
    timed_out = False
    terminate_sent = False
    kill_sent = False
    peak_rss_bytes: int | None = None
    peak_process_count: int | None = None
    error: str | None = None

    def remember_signal(value: int, _frame: object) -> None:
        nonlocal interrupted_signal
        interrupted_signal = value

    previous_term = signal.signal(signal.SIGTERM, remember_signal)
    previous_int = signal.signal(signal.SIGINT, remember_signal)
    try:
        stdout_handle = _open_output(args.stdout)
        stderr_handle = _open_output(args.stderr)
        process = subprocess.Popen(
            command,
            cwd=args.cwd,
            stdin=subprocess.DEVNULL,
            stdout=stdout_handle,
            stderr=stderr_handle,
            start_new_session=True,
        )
        process_group_id = os.getpgid(process.pid)
        next_sample = started_monotonic
        next_heartbeat = started_monotonic
        while process.poll() is None:
            now = time.monotonic()
            if interrupted_signal is not None or now >= deadline:
                timed_out = interrupted_signal is None
                terminate_sent, kill_sent = _stop_group(
                    process,
                    process_group_id,
                    args.grace,
                )
                break
            if now >= next_sample:
                process_count, rss_bytes = _group_snapshot(process_group_id)
                if process_count >= 0:
                    peak_process_count = max(peak_process_count or 0, process_count)
                if rss_bytes >= 0:
                    peak_rss_bytes = max(peak_rss_bytes or 0, rss_bytes)
                next_sample = now + 1
            if now >= next_heartbeat:
                elapsed = round(now - started_monotonic, 1)
                print(
                    "macOS process supervisor heartbeat: "
                    f"phase={args.phase} elapsed={elapsed}s pid={process.pid} "
                    f"pgid={process_group_id} peakProcesses={peak_process_count} "
                    f"peakRss={peak_rss_bytes}",
                    flush=True,
                )
                next_heartbeat = now + 10
            time.sleep(0.1)

        # 主进程正常退出后也必须清理由它留在同一组内的后代，不能只看 leader。
        final_count, _ = _group_snapshot(process_group_id)
        if final_count > 0:
            residual_term, residual_kill = _stop_group(
                process,
                process_group_id,
                args.grace,
            )
            terminate_sent = terminate_sent or residual_term
            kill_sent = kill_sent or residual_kill
        final_count, final_rss_bytes = _group_snapshot(process_group_id)
        if final_count != 0:
            error = f"进程组仍残留 {final_count} 个进程"

        if timed_out:
            exit_code = 124
        elif interrupted_signal is not None:
            exit_code = min(255, 128 + interrupted_signal)
        elif error is not None:
            exit_code = 125
        else:
            exit_code = _normalized_exit_code(process.returncode)
        payload = {
            "schemaVersion": 1,
            "phase": args.phase,
            "command": Path(command[0]).name,
            "startedAtUnix": started_wall,
            "durationSeconds": round(time.monotonic() - started_monotonic, 3),
            "childPid": process.pid,
            "processGroupId": process_group_id,
            "timedOut": timed_out,
            "interruptedSignal": interrupted_signal,
            "terminateSent": terminate_sent,
            "killSent": kill_sent,
            "exitCode": exit_code,
            "peakProcessCount": peak_process_count,
            "peakRssBytes": peak_rss_bytes,
            "finalProcessCount": final_count,
            "finalRssBytes": final_rss_bytes if final_rss_bytes >= 0 else None,
            "error": error,
        }
        _atomic_write_json(status_path, payload)
        return exit_code
    except BaseException as caught:
        error = f"{type(caught).__name__}: {caught}"
        if process is not None and process_group_id is not None:
            terminate_sent, kill_sent = _stop_group(
                process,
                process_group_id,
                args.grace,
            )
        _atomic_write_json(
            status_path,
            {
                "schemaVersion": 1,
                "phase": args.phase,
                "command": Path(command[0]).name,
                "startedAtUnix": started_wall,
                "durationSeconds": round(time.monotonic() - started_monotonic, 3),
                "childPid": process.pid if process is not None else None,
                "processGroupId": process_group_id,
                "timedOut": timed_out,
                "interruptedSignal": interrupted_signal,
                "terminateSent": terminate_sent,
                "killSent": kill_sent,
                "exitCode": 125,
                "peakProcessCount": peak_process_count,
                "peakRssBytes": peak_rss_bytes,
                "finalProcessCount": None,
                "finalRssBytes": None,
                "error": error,
            },
        )
        print(f"process_group_supervisor failed: {error}", file=sys.stderr, flush=True)
        return 125
    finally:
        signal.signal(signal.SIGTERM, previous_term)
        signal.signal(signal.SIGINT, previous_int)
        if stdout_handle is not None:
            stdout_handle.close()
        if stderr_handle is not None:
            stderr_handle.close()


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--phase", required=True)
    parser.add_argument("--timeout", type=float, required=True)
    parser.add_argument("--grace", type=float, default=5)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--status", required=True)
    parser.add_argument("--stdout")
    parser.add_argument("--stderr")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    if args.timeout <= 0 or args.grace <= 0:
        parser.error("timeout 和 grace 必须大于 0")
    return args


def main(argv: list[str] | None = None) -> int:
    return run_supervised(_parse_args(sys.argv[1:] if argv is None else argv))


if __name__ == "__main__":
    raise SystemExit(main())
