#!/usr/bin/env python3
"""把 Flutter 或原生框架结果规范化为统一场景报告。"""

from __future__ import annotations

import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from capability_matrix import MATRIX_PATH, load_matrix, resolve_contract


def _flutter_jsonl_started(path: Path) -> bool:
    if not path.is_file():
        return False
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(event, dict) and event.get("type") == "testStart":
            return True
    return False


def _jsonl_test_summary(path: Path) -> tuple[bool, int]:
    if not path.is_file():
        return False, 0
    started = False
    skipped = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "testStart":
            started = True
        elif event.get("type") == "testDone" and (
            event.get("skipped") is True or event.get("result") == "skipped"
        ):
            skipped += 1
    return started, skipped


def _xml_test_summary(path: Path, report_type: str) -> tuple[bool, int]:
    if not path.is_file():
        return False, 0
    root = ET.parse(path).getroot()
    if report_type in {"android-junit-xml", "pytest-junit"}:
        suites = [root] if root.tag == "testsuite" else list(root.findall("testsuite"))
        tests = sum(int(suite.get("tests", "0")) for suite in suites)
        skipped = sum(int(suite.get("skipped", "0")) for suite in suites)
        return tests > 0, skipped
    if report_type == "trx":
        namespace = {"trx": "http://microsoft.com/schemas/VisualStudio/TeamTest/2010"}
        results = root.findall(".//trx:UnitTestResult", namespace)
        skipped = sum(result.get("outcome") == "NotExecuted" for result in results)
        return bool(results), skipped
    raise ValueError(f"不支持的 XML 报告类型: {report_type}")


def _xcresult_summary(path: Path) -> tuple[bool, int]:
    if not path.is_file():
        return False, 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        return False, 0
    total = payload.get("totalTestCount", payload.get("testsCount", 0))
    skipped = payload.get("skippedTests", payload.get("skippedTestCount", 0))
    return isinstance(total, int) and total > 0, skipped if isinstance(skipped, int) else 0


def _real_action_count(capabilities: object) -> int:
    if not isinstance(capabilities, dict):
        return 0
    count = 0
    for state in capabilities.values():
        if not isinstance(state, dict) or state.get("mode") != "real":
            continue
        evidence = state.get("evidence")
        if isinstance(evidence, list):
            count += len(evidence)
    return count


def _write_atomic(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def _write_failure_junit(path: Path, scenario: str, message: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    suite = ET.Element(
        "testsuite", name=scenario, tests="1", failures="1", errors="0"
    )
    case = ET.SubElement(suite, "testcase", classname="integration.infrastructure", name=scenario)
    failure = ET.SubElement(case, "failure", message=message)
    failure.text = message
    ET.ElementTree(suite).write(path, encoding="utf-8", xml_declaration=True)


def _write_infrastructure_failure(args: argparse.Namespace, error: Exception) -> None:
    if not all((args.run_id, args.scenario, args.profile, args.platform)):
        return
    message = f"集成报告规范化失败: {error}"
    payload = {
        "schemaVersion": 2,
        "runId": args.run_id,
        "scenario": args.scenario,
        "profile": args.profile,
        "platform": args.platform,
        "framework": args.framework,
        "capabilities": {},
        "resources": {"baseline": {}, "final": {}, "thresholds": {}},
        "runner": {
            "exitCode": args.exit_code,
            "originalReportType": args.raw_report_type,
            "testStarted": _flutter_jsonl_started(args.raw_report),
            "nativeActionCount": 0,
        },
        "artifacts": [],
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "steps": [
            {
                "name": "collect_and_normalize_report",
                "success": False,
                "error": message,
            }
        ],
        "status": "failed",
        "coverageStatus": "notExercised",
        "success": False,
        "extra": {"infrastructureFailure": message},
    }
    _write_atomic(args.scenario_report, payload)
    if args.failure_junit is not None:
        _write_failure_junit(args.failure_junit, args.scenario, message)


def _merge_external_evidence(
    payload: dict[str, Any], evidence_path: Path, framework: str
) -> None:
    evidence: Any = json.loads(evidence_path.read_text(encoding="utf-8"))
    if not isinstance(evidence, dict):
        raise SystemExit("外部 evidence 顶层必须为对象")
    for field in ("runId", "scenario", "profile", "platform", "framework"):
        if evidence.get(field) != payload.get(field):
            raise SystemExit(f"外部 evidence 的 {field} 与 Flutter 场景报告不一致")
    if evidence.get("framework") != framework:
        raise SystemExit("外部 evidence framework 与 runner 不一致")

    capabilities = payload.get("capabilities")
    raw_evidence = evidence.get("capabilityEvidence")
    if not isinstance(capabilities, dict) or not isinstance(raw_evidence, dict):
        raise SystemExit("联合场景缺少 capabilities 或 capabilityEvidence")
    unknown = set(raw_evidence).difference(capabilities)
    if unknown:
        raise SystemExit(f"外部 evidence 包含矩阵未声明能力: {sorted(unknown)}")
    for name, entries in raw_evidence.items():
        if not isinstance(entries, list) or any(
            not isinstance(entry, dict) for entry in entries
        ):
            raise SystemExit(f"外部 capabilityEvidence.{name} 必须为对象数组")
        state = capabilities.get(name)
        if not isinstance(state, dict) or state.get("mode") != "real":
            raise SystemExit(f"外部 evidence 不能为非 real 能力 {name} 提供证据")
        current = state.setdefault("evidence", [])
        if not isinstance(current, list):
            raise SystemExit(f"Flutter capability {name} evidence 必须为数组")
        current.extend(entries)

    external_steps = evidence.get("steps")
    steps = payload.get("steps")
    if not isinstance(external_steps, list) or not external_steps:
        raise SystemExit("外部 evidence 没有场景步骤")
    if not isinstance(steps, list):
        raise SystemExit("Flutter 场景 steps 必须为数组")
    steps.extend(external_steps)

    artifacts = payload.get("artifacts")
    external_artifacts = evidence.get("artifacts", [])
    if not isinstance(artifacts, list) or not isinstance(external_artifacts, list):
        raise SystemExit("联合场景 artifacts 必须为数组")
    artifacts.extend(external_artifacts)

    resources = payload.get("resources")
    external_resources = evidence.get("resources", {})
    if not isinstance(resources, dict) or not isinstance(external_resources, dict):
        raise SystemExit("联合场景 resources 必须为对象")
    for section in ("baseline", "final", "thresholds"):
        target = resources.setdefault(section, {})
        source = external_resources.get(section, {})
        if not isinstance(target, dict) or not isinstance(source, dict):
            raise SystemExit(f"联合场景 resources.{section} 必须为对象")
        for key, value in source.items():
            if key in target and target[key] != value:
                raise SystemExit(f"资源证据冲突: {section}.{key}")
            target[key] = value

    extra = payload.get("extra")
    external_extra = evidence.get("extra", {})
    if not isinstance(extra, dict) or not isinstance(external_extra, dict):
        raise SystemExit("联合场景 extra 必须为对象")
    extra["externalNativeEvidence"] = external_extra


def _normalize_flutter(args: argparse.Namespace) -> None:
    if not args.scenario_report.is_file():
        raise SystemExit(f"场景报告不存在: {args.scenario_report.name}")
    payload: Any = json.loads(args.scenario_report.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit("场景报告顶层必须为对象")
    if payload.get("schemaVersion") != 2:
        raise SystemExit("场景报告 schemaVersion 必须为 2")
    if payload.get("framework") != args.framework:
        raise SystemExit("场景报告 framework 与 runner 不一致")
    if args.evidence is not None:
        if not args.evidence.is_file():
            raise SystemExit("联合场景缺少外部 evidence JSON")
        _merge_external_evidence(payload, args.evidence, args.framework)
    test_started = _flutter_jsonl_started(args.raw_report)
    steps = payload.get("steps")
    step_failed = not isinstance(steps, list) or any(
        not isinstance(step, dict) or step.get("success") is not True
        for step in steps
    )
    passed = (
        args.exit_code == 0
        and test_started
        and payload.get("success") is True
        and not step_failed
    )
    flutter_reported_success = payload.get("success") is True
    payload["runner"] = {
        "exitCode": args.exit_code,
        "originalReportType": args.raw_report_type,
        "testStarted": test_started,
        "nativeActionCount": _real_action_count(payload.get("capabilities")),
    }
    payload["status"] = "passed" if passed else "failed"
    payload["success"] = passed
    _write_atomic(args.scenario_report, payload)
    if not passed and args.failure_junit is not None:
        message = (
            "联合场景最终状态失败: "
            f"exitCode={args.exit_code}, testStarted={test_started}, "
            f"flutterSuccess={flutter_reported_success}"
        )
        _write_failure_junit(args.failure_junit, str(payload.get("scenario")), message)


def _normalize_native(args: argparse.Namespace) -> None:
    if args.evidence is None or not args.evidence.is_file():
        raise SystemExit("原生框架必须提供可读 evidence JSON")
    evidence: Any = json.loads(args.evidence.read_text(encoding="utf-8"))
    if not isinstance(evidence, dict):
        raise SystemExit("evidence 顶层必须为对象")
    required_fields = ("runId", "scenario", "profile", "platform", "framework")
    for field in required_fields:
        if not isinstance(evidence.get(field), str) or not evidence[field].strip():
            raise SystemExit(f"evidence 缺少 {field}")
    if evidence["framework"] != args.framework:
        raise SystemExit("evidence framework 与 runner 不一致")

    if args.raw_report_type == "xcresult-summary":
        test_started, skipped = _xcresult_summary(args.raw_report)
    elif args.raw_report_type == "dart-jsonl":
        test_started, skipped = _jsonl_test_summary(args.raw_report)
    else:
        test_started, skipped = _xml_test_summary(args.raw_report, args.raw_report_type)
    expected = resolve_contract(
        load_matrix(args.matrix),
        profile=evidence["profile"],
        platform=evidence["platform"],
        scenario=evidence["scenario"],
        framework=evidence["framework"],
    )
    raw_evidence = evidence.get("capabilityEvidence", {})
    if not isinstance(raw_evidence, dict):
        raise SystemExit("capabilityEvidence 必须为对象")
    unknown = set(raw_evidence).difference(expected)
    if unknown:
        raise SystemExit(f"evidence 包含矩阵未声明能力: {sorted(unknown)}")
    capabilities = {
        name: {**state, "evidence": raw_evidence.get(name, [])}
        for name, state in expected.items()
    }
    steps = evidence.get("steps")
    if not isinstance(steps, list) or not steps:
        raise SystemExit("原生 evidence 没有场景步骤")
    step_failed = any(
        not isinstance(step, dict) or step.get("success") is not True for step in steps
    )
    passed = args.exit_code == 0 and test_started and skipped == 0 and not step_failed
    payload = {
        "schemaVersion": 2,
        "runId": evidence["runId"],
        "scenario": evidence["scenario"],
        "profile": evidence["profile"],
        "platform": evidence["platform"],
        "framework": evidence["framework"],
        "capabilities": capabilities,
        "resources": evidence.get(
            "resources", {"baseline": {}, "final": {}, "thresholds": {}}
        ),
        "runner": {
            "exitCode": args.exit_code,
            "originalReportType": args.raw_report_type,
            "testStarted": test_started,
            "nativeActionCount": _real_action_count(capabilities),
        },
        "artifacts": evidence.get("artifacts", []),
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "steps": steps,
        "status": "passed" if passed else "failed",
        "coverageStatus": "skipped" if skipped else "executed",
        "success": passed,
        "extra": evidence.get("extra", {}),
    }
    _write_atomic(args.scenario_report, payload)
    if not passed and args.failure_junit is not None:
        message = (
            "原生场景最终状态失败: "
            f"exitCode={args.exit_code}, testStarted={test_started}, "
            f"skipped={skipped}, stepFailed={step_failed}"
        )
        _write_failure_junit(args.failure_junit, str(evidence["scenario"]), message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario-report", required=True, type=Path)
    parser.add_argument("--raw-report", required=True, type=Path)
    parser.add_argument(
        "--raw-report-type",
        required=True,
        choices=[
            "flutter-jsonl",
            "dart-jsonl",
            "android-junit-xml",
            "pytest-junit",
            "trx",
            "xcresult-summary",
        ],
    )
    parser.add_argument("--framework", required=True)
    parser.add_argument("--exit-code", required=True, type=int)
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--matrix", type=Path, default=MATRIX_PATH)
    parser.add_argument("--run-id")
    parser.add_argument("--scenario")
    parser.add_argument("--profile")
    parser.add_argument("--platform")
    parser.add_argument("--failure-junit", type=Path)
    args = parser.parse_args()

    try:
        if args.raw_report_type == "flutter-jsonl":
            _normalize_flutter(args)
        else:
            _normalize_native(args)
    except SystemExit as error:
        _write_infrastructure_failure(args, error)
        print(f"ERROR: 集成报告规范化失败: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, json.JSONDecodeError, ET.ParseError) as error:
        _write_infrastructure_failure(args, error)
        print(f"ERROR: 集成报告规范化失败: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
