#!/usr/bin/env python3
"""将 Dart/Flutter JSON 事件流转换为始终可落盘的 JUnit 报告。"""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def convert(input_path: Path, output_path: Path) -> int:
    tests: dict[int, dict[str, object]] = {}
    errors: dict[int, list[str]] = {}
    parse_errors: list[str] = []

    if input_path.is_file():
        for line_number, raw_line in enumerate(
            input_path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            if not raw_line.strip():
                continue
            try:
                event = json.loads(raw_line)
            except json.JSONDecodeError as error:
                parse_errors.append(f"第 {line_number} 行 JSON 损坏: {error}")
                continue
            event_type = event.get("type")
            if event_type == "testStart":
                test = event.get("test") or {}
                test_id = test.get("id")
                if isinstance(test_id, int):
                    tests[test_id] = {
                        "name": str(test.get("name") or f"test-{test_id}"),
                        "url": str(test.get("url") or ""),
                        "start": int(event.get("time") or 0),
                        "done": False,
                    }
            elif event_type == "error":
                test_id = event.get("testID")
                if isinstance(test_id, int):
                    detail = str(event.get("error") or "测试失败")
                    stack = str(event.get("stackTrace") or "")
                    errors.setdefault(test_id, []).append(f"{detail}\n{stack}".strip())
            elif event_type == "testDone":
                test_id = event.get("testID")
                if isinstance(test_id, int) and test_id in tests:
                    tests[test_id].update(
                        {
                            "done": True,
                            "result": str(event.get("result") or "error"),
                            "end": int(event.get("time") or 0),
                            "skipped": bool(event.get("skipped")),
                            "hidden": bool(event.get("hidden")),
                        }
                    )

    suite = ET.Element("testsuite", name=input_path.stem)
    failures = 0
    skipped = 0
    emitted = 0
    for test_id, test in tests.items():
        if test.get("hidden"):
            continue
        emitted += 1
        start = int(test.get("start") or 0)
        end = int(test.get("end") or start)
        case = ET.SubElement(
            suite,
            "testcase",
            name=str(test["name"]),
            classname=str(test.get("url") or input_path.stem),
            time=f"{max(0, end - start) / 1000:.3f}",
        )
        if test.get("skipped") or test.get("result") == "skipped":
            skipped += 1
            ET.SubElement(case, "skipped", message="测试被跳过")
        elif not test.get("done") or test.get("result") != "success":
            failures += 1
            message = "\n\n".join(errors.get(test_id, []))
            if not test.get("done"):
                message = (message + "\n测试进程未发送 testDone").strip()
            failure = ET.SubElement(case, "failure", message="测试失败或未完成")
            failure.text = message

    for message in parse_errors:
        emitted += 1
        failures += 1
        case = ET.SubElement(suite, "testcase", name="json-report-parse")
        failure = ET.SubElement(case, "failure", message="JSON 报告损坏")
        failure.text = message

    no_tests = emitted == 0
    if no_tests:
        emitted = 1
        failures += 1
        case = ET.SubElement(suite, "testcase", name="test-infrastructure")
        failure = ET.SubElement(case, "failure", message="没有执行任何测试")
        failure.text = f"未从 {input_path} 读取到已开始的测试"

    suite.set("tests", str(emitted))
    suite.set("failures", str(failures))
    suite.set("skipped", str(skipped))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(output_path, encoding="utf-8", xml_declaration=True)
    return 1 if parse_errors or no_tests or failures > 0 else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    return convert(args.input, args.output)


if __name__ == "__main__":
    sys.exit(main())
