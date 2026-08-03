#!/usr/bin/env python3
"""交叉核对场景 JSON、能力矩阵、runner 状态和 JUnit，拒绝 integration 假绿。"""

from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from capability_matrix import (
    MATRIX_PATH,
    CapabilityMatrixError,
    load_matrix,
    resolve_contract,
)


VIEWPORT_SCENARIOS = {
    "batch_convert_flow",
    "local_match_flow",
    "open_lyrics_flow",
    "platform_capability_smoke",
    "screenshot_capability",
    "search_collection_flow",
    "search_song_flow",
    "settings_about_flow",
}
DESKTOP_PLATFORMS = {"windows", "macos", "linux"}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def _verify_capabilities(
    payload: dict,
    *,
    expected: dict[str, dict],
    report_name: str,
) -> list[str]:
    actual = payload.get("capabilities")
    if not isinstance(actual, dict):
        return [f"{report_name}: 缺少 capabilities"]

    failures: list[str] = []
    if set(actual) != set(expected):
        failures.append(f"{report_name}: capability 字段集合与矩阵不一致")
    for name, expected_state in expected.items():
        state = actual.get(name)
        if not isinstance(state, dict):
            failures.append(f"{report_name}: {name} 不是结构化能力对象")
            continue
        if set(state) != {"mode", "required", "applicable", "reason", "evidence"}:
            failures.append(f"{report_name}: {name} 字段集合不完整")
            continue
        for key in ("mode", "required", "applicable", "reason"):
            if state.get(key) != expected_state.get(key):
                failures.append(
                    f"{report_name}: {name}.{key}={state.get(key)!r}，"
                    f"预期 {expected_state.get(key)!r}"
                )
        evidence = state.get("evidence")
        if not isinstance(evidence, list):
            failures.append(f"{report_name}: {name}.evidence 不是数组")
            continue
        if not expected_state["applicable"] and evidence:
            failures.append(f"{report_name}: 不适用能力 {name} 不能包含证据")
        for index, entry in enumerate(evidence):
            action = entry.get("action") if isinstance(entry, dict) else None
            if not isinstance(action, str) or not action.strip():
                failures.append(f"{report_name}: {name}.evidence[{index}] 缺少 action")
        if expected_state["required"]:
            if expected_state["mode"] == "notExercised":
                failures.append(f"{report_name}: required 能力 {name} 不能 notExercised")
            if expected_state["mode"] == "real" and not evidence:
                failures.append(f"{report_name}: {name}=real 但没有真实调用证据")
    return failures


def _verify_runner(payload: dict, report_name: str) -> list[str]:
    runner = payload.get("runner")
    if not isinstance(runner, dict):
        return [f"{report_name}: 缺少 runner"]
    failures: list[str] = []
    exit_code = runner.get("exitCode")
    if not isinstance(exit_code, int) or isinstance(exit_code, bool):
        failures.append(f"{report_name}: runner.exitCode 无效")
    if runner.get("testStarted") is not True:
        failures.append(f"{report_name}: 原始报告没有 testStart")
    report_type = runner.get("originalReportType")
    if not isinstance(report_type, str) or not report_type.strip():
        failures.append(f"{report_name}: 缺少原始报告类型")
    action_count = runner.get("nativeActionCount")
    if not isinstance(action_count, int) or isinstance(action_count, bool) or action_count < 0:
        failures.append(f"{report_name}: nativeActionCount 无效")
        return failures

    actual_actions = 0
    capabilities = payload.get("capabilities")
    if isinstance(capabilities, dict):
        for state in capabilities.values():
            if isinstance(state, dict) and state.get("mode") == "real":
                evidence = state.get("evidence")
                if isinstance(evidence, list):
                    actual_actions += len(evidence)
    if action_count != actual_actions:
        failures.append(
            f"{report_name}: nativeActionCount={action_count}，实际证据数={actual_actions}"
        )

    passed = payload.get("status") == "passed" and payload.get("success") is True
    if passed and exit_code != 0:
        failures.append(f"{report_name}: 场景报告通过但 runner 退出码为 {exit_code}")
    if not passed and exit_code == 0:
        failures.append(f"{report_name}: runner 退出码为 0 但场景报告未通过")
    return failures


def _verify_resources_and_artifacts(payload: dict, report_name: str) -> list[str]:
    failures: list[str] = []
    resources = payload.get("resources")
    if not isinstance(resources, dict) or set(resources) != {
        "baseline",
        "final",
        "thresholds",
    }:
        failures.append(f"{report_name}: resources 结构不完整")
    elif any(not isinstance(resources[key], dict) for key in resources):
        failures.append(f"{report_name}: resources 子项必须为对象")
    else:
        baseline = resources["baseline"]
        final = resources["final"]
        thresholds = resources["thresholds"]
        for name, threshold in thresholds.items():
            if not isinstance(threshold, (int, float)) or isinstance(threshold, bool):
                failures.append(f"{report_name}: resources.thresholds.{name} 无效")
                continue
            if name not in baseline:
                failures.append(f"{report_name}: resources.baseline 缺少 {name}")
            value = final.get(name)
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                failures.append(f"{report_name}: resources.final.{name} 无效")
            elif value > threshold:
                failures.append(
                    f"{report_name}: resources.final.{name}={value} 超过阈值 {threshold}"
                )

    artifacts = payload.get("artifacts")
    if not isinstance(artifacts, list):
        failures.append(f"{report_name}: artifacts 必须为数组")
        return failures
    for index, artifact in enumerate(artifacts):
        if not isinstance(artifact, dict) or set(artifact) != {"name", "size", "sha256"}:
            failures.append(f"{report_name}: artifacts[{index}] 字段无效")
            continue
        if not isinstance(artifact["name"], str) or not artifact["name"].strip():
            failures.append(f"{report_name}: artifacts[{index}].name 无效")
        size = artifact["size"]
        if not isinstance(size, int) or isinstance(size, bool) or size < 0:
            failures.append(f"{report_name}: artifacts[{index}].size 无效")
        sha256 = artifact["sha256"]
        if not isinstance(sha256, str) or not SHA256_PATTERN.fullmatch(sha256):
            failures.append(f"{report_name}: artifacts[{index}].sha256 无效")
        if "path" in artifact:
            failures.append(f"{report_name}: artifact 禁止保存本地路径")
    return failures


def _number(mapping: object, key: str) -> float | None:
    if not isinstance(mapping, dict):
        return None
    value = mapping.get(key)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return float(value)
    return None


def _verify_viewport(payload: dict, platform: str, report_name: str) -> list[str]:
    scenario = payload.get("scenario")
    if scenario not in VIEWPORT_SCENARIOS:
        return []
    extra = payload.get("extra")
    viewport = extra.get("viewport") if isinstance(extra, dict) else None
    if not isinstance(viewport, dict):
        return [f"{report_name}: UI 场景缺少 viewport 证据"]
    logical = viewport.get("logicalSize")
    physical = viewport.get("physicalSize")
    width = _number(logical, "width")
    height = _number(logical, "height")
    physical_width = _number(physical, "width")
    physical_height = _number(physical, "height")
    dpr = viewport.get("devicePixelRatio")
    if (
        width is None
        or height is None
        or physical_width is None
        or physical_height is None
        or not isinstance(dpr, (int, float))
        or min(width, height, physical_width, physical_height, float(dpr)) <= 0
    ):
        return [f"{report_name}: viewport 尺寸或 DPR 无效"]

    failures: list[str] = []
    if platform in DESKTOP_PLATFORMS:
        contract = viewport.get("desktopContract")
        expected = contract.get("expectedContentSize") if isinstance(contract, dict) else None
        expected_width = _number(expected, "width")
        expected_height = _number(expected, "height")
        if expected_width is None or expected_height is None:
            failures.append(f"{report_name}: 桌面 viewport 缺少预期内容区")
        elif abs(width - expected_width) > 2 or abs(height - expected_height) > 2:
            failures.append(
                f"{report_name}: 桌面内容区 {width:g}x{height:g} "
                f"不匹配契约 {expected_width:g}x{expected_height:g}"
            )
        if abs(width / height - 16 / 9) > 0.02:
            failures.append(f"{report_name}: 桌面内容区未保持 16:9")
        if not isinstance(viewport.get("windowBounds"), dict) or not isinstance(
            viewport.get("displayVisibleBounds"), dict
        ):
            failures.append(f"{report_name}: 桌面 viewport 缺少原生窗口或工作区")
    elif platform in {"android", "ios"} and width >= 980:
        failures.append(f"{report_name}: 手机 E2E 误进入桌面宽度 {width:g}")
    return failures


def _junit_failures(junit_path: Path, report_name: str) -> list[str]:
    if not junit_path.is_file():
        return [f"{report_name}: 缺少 JUnit {junit_path.name}"]
    try:
        root = ET.parse(junit_path).getroot()
    except (OSError, ET.ParseError) as error:
        return [f"{report_name}: JUnit 不可读: {error}"]
    suites = [root] if root.tag == "testsuite" else list(root.findall("testsuite"))
    if not suites:
        return [f"{report_name}: JUnit 没有 testsuite"]
    failures = sum(int(suite.get("failures", "0")) for suite in suites)
    errors = sum(int(suite.get("errors", "0")) for suite in suites)
    skipped = sum(int(suite.get("skipped", "0")) for suite in suites)
    tests = sum(int(suite.get("tests", "0")) for suite in suites)
    result: list[str] = []
    if tests <= 0:
        result.append(f"{report_name}: JUnit 没有执行测试")
    if failures or errors:
        result.append(f"{report_name}: JUnit 包含 failures={failures}, errors={errors}")
    if skipped:
        result.append(f"{report_name}: JUnit 包含 skipped={skipped}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True, type=Path)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--matrix", type=Path, default=MATRIX_PATH)
    parser.add_argument("--junit-directory", type=Path)
    args = parser.parse_args()

    report_paths = sorted(args.directory.glob("*.json"))
    failures: list[str] = []
    try:
        matrix = load_matrix(args.matrix)
    except (OSError, json.JSONDecodeError, CapabilityMatrixError) as error:
        print(f"ERROR: 能力矩阵不可用: {error}", file=sys.stderr)
        return 1
    if not report_paths:
        failures.append("没有生成任何场景 JSON 报告")

    for path in report_paths:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            failures.append(f"{path.name}: 报告不可读: {error}")
            continue
        if not isinstance(payload, dict):
            failures.append(f"{path.name}: 报告顶层必须为对象")
            continue
        if payload.get("schemaVersion") != 2:
            failures.append(f"{path.name}: schemaVersion 不是 2")
        if payload.get("runId") != args.run_id:
            failures.append(f"{path.name}: runId 不匹配")
        if payload.get("profile") != args.profile:
            failures.append(f"{path.name}: profile 不匹配")
        if payload.get("platform") != args.platform:
            failures.append(f"{path.name}: platform 不匹配")
        scenario = payload.get("scenario")
        framework = payload.get("framework")
        if not isinstance(scenario, str) or not scenario.strip():
            failures.append(f"{path.name}: scenario 无效")
            continue
        if not isinstance(framework, str) or not framework.strip():
            failures.append(f"{path.name}: framework 无效")
            continue
        if not payload.get("steps"):
            failures.append(f"{path.name}: 没有执行场景步骤")
        if payload.get("status") != "passed" or payload.get("success") is not True:
            failures.append(f"{path.name}: 场景状态不是 passed")
        if payload.get("coverageStatus") != "executed":
            failures.append(f"{path.name}: 场景被跳过、阻塞或降级")
        try:
            expected = resolve_contract(
                matrix,
                profile=args.profile,
                platform=args.platform,
                scenario=scenario,
                framework=framework,
            )
        except CapabilityMatrixError as error:
            failures.append(f"{path.name}: {error}")
            continue
        failures.extend(
            _verify_capabilities(payload, expected=expected, report_name=path.name)
        )
        failures.extend(_verify_runner(payload, path.name))
        failures.extend(_verify_resources_and_artifacts(payload, path.name))
        failures.extend(_verify_viewport(payload, args.platform, path.name))
        if args.junit_directory is not None:
            failures.extend(
                _junit_failures(args.junit_directory / f"{scenario}.xml", path.name)
            )

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    print(f"integration reports passed: {len(report_paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
