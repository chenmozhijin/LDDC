#!/usr/bin/env python3
"""在 macOS system UI runner 被外层 watchdog 中断后补齐失败报告。"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET


SCENARIOS = ("macos_open_panel_select", "macos_open_panel_cancel")


def _atomic_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = path.with_name(f"{path.name}.tmp")
    staging.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    staging.replace(path)


def _resolve_run_root(report_root: Path) -> Path:
    candidates = sorted(
        (
            path
            for path in report_root.glob("platform-macos-*")
            if path.is_dir()
        ),
        key=lambda path: path.stat().st_mtime_ns,
        reverse=True,
    )
    if candidates:
        return candidates[0]
    run_id = f"platform-macos-watchdog-{int(time.time() * 1000)}-{uuid.uuid4().hex[:8]}"
    run_root = report_root / run_id
    run_root.mkdir(parents=True, exist_ok=True)
    return run_root


def _watchdog_message(report_root: Path, step_outcome: str) -> str:
    status_path = report_root / "workflow-watchdog.json"
    if status_path.is_file():
        try:
            status = json.loads(status_path.read_text(encoding="utf-8"))
            return (
                "macOS system UI runner did not complete: "
                f"step={step_outcome}, exit={status.get('exitCode')}, "
                f"timedOut={status.get('timedOut')}, error={status.get('error')}"
            )
        except (OSError, ValueError, TypeError):
            pass
    return f"macOS system UI runner did not complete: step={step_outcome}"


def _fallback_evidence(run_id: str, scenario: str, message: str) -> dict:
    return {
        "runId": run_id,
        "scenario": scenario,
        "profile": "platform",
        "platform": "macos",
        "framework": "integration_test+xcuitest",
        "steps": [
            {
                "step": "macos_system_ui_report_finalize",
                "success": False,
                "error": message,
            }
        ],
        "capabilityEvidence": {},
        "resources": {"baseline": {}, "final": {}, "thresholds": {}},
        "artifacts": [],
        "extra": {
            "infrastructureFailure": message,
            "failureClass": "watchdog_interruption",
            "resourceMeasurementStatus": "not_exercised_before_test_start",
        },
    }


def _report_pair_is_valid(
    scenario_report: Path,
    junit_report: Path,
    *,
    run_id: str,
    scenario: str,
) -> bool:
    try:
        payload = json.loads(scenario_report.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            return False
        if payload.get("schemaVersion") != 2:
            return False
        if payload.get("runId") != run_id:
            return False
        if payload.get("scenario") != scenario:
            return False
        if payload.get("profile") != "platform":
            return False
        if payload.get("platform") != "macos":
            return False
        if payload.get("framework") != "integration_test+xcuitest":
            return False
        root = ET.parse(junit_report).getroot()
        return root.tag in {"testsuite", "testsuites"}
    except (OSError, ValueError, TypeError, json.JSONDecodeError, ET.ParseError):
        return False


def finalize(args: argparse.Namespace) -> int:
    root = Path(__file__).resolve().parents[2]
    report_root = (root / args.report_root).resolve()
    report_root.mkdir(parents=True, exist_ok=True)
    run_root = _resolve_run_root(report_root)
    run_id = run_root.name
    scenario_dir = run_root / "scenarios"
    junit_dir = run_root / "junit"
    raw_dir = run_root / "raw"
    attachment_dir = run_root / "attachments" / "watchdog"
    for directory in (scenario_dir, junit_dir, raw_dir, attachment_dir):
        directory.mkdir(parents=True, exist_ok=True)

    message = _watchdog_message(report_root, args.step_outcome)
    normalizer = root / "tool/test/normalize_integration_report.py"
    matrix = root / "tool/test/platform_capability_matrix.json"
    finalization_failed = False
    for scenario in SCENARIOS:
        scenario_report = scenario_dir / f"{scenario}.json"
        junit_report = junit_dir / f"{scenario}.xml"
        if scenario_report.is_file() and junit_report.is_file():
            continue
        evidence = attachment_dir / f"lddc-evidence-{scenario}.json"
        summary = raw_dir / f"{scenario}.xcresult.summary.json"
        _atomic_json(evidence, _fallback_evidence(run_id, scenario, message))
        _atomic_json(
            summary,
            {
                "totalTestCount": 0,
                "passedTests": 0,
                "failedTests": 1,
                "skippedTests": 0,
                "error": message,
            },
        )
        completed = subprocess.run(
            [
                sys.executable,
                str(normalizer),
                "--scenario-report",
                str(scenario_report),
                "--raw-report",
                str(summary),
                "--raw-report-type",
                "xcresult-summary",
                "--framework",
                "integration_test+xcuitest",
                "--exit-code",
                "1",
                "--evidence",
                str(evidence),
                "--matrix",
                str(matrix),
                "--run-id",
                run_id,
                "--scenario",
                scenario,
                "--profile",
                "platform",
                "--platform",
                "macos",
                "--failure-junit",
                str(junit_report),
            ],
            check=False,
        )
        if completed.returncode != 0:
            finalization_failed = True

    for scenario in SCENARIOS:
        if not _report_pair_is_valid(
            scenario_dir / f"{scenario}.json",
            junit_dir / f"{scenario}.xml",
            run_id=run_id,
            scenario=scenario,
        ):
            finalization_failed = True
    return 1 if finalization_failed else 0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--report-root",
        default="lddc/build/integration_reports/macos-native",
    )
    parser.add_argument("--step-outcome", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    raise SystemExit(finalize(_parse_args()))
