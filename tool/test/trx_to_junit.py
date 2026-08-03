#!/usr/bin/env python3
"""将 Visual Studio TRX 结果转换为统一报告校验器使用的 JUnit XML。"""

from __future__ import annotations

import argparse
import xml.etree.ElementTree as ET
from datetime import timedelta
from pathlib import Path


TRX_NAMESPACE = {"trx": "http://microsoft.com/schemas/VisualStudio/TeamTest/2010"}


def _duration_seconds(value: str | None) -> str:
    if not value:
        return "0"
    try:
        hours, minutes, seconds = value.split(":", 2)
        duration = timedelta(
            hours=int(hours),
            minutes=int(minutes),
            seconds=float(seconds),
        )
        return f"{duration.total_seconds():.6f}".rstrip("0").rstrip(".")
    except (TypeError, ValueError):
        return "0"


def convert(source: Path, target: Path, scenario: str) -> None:
    root = ET.parse(source).getroot()
    results = root.findall(".//trx:UnitTestResult", TRX_NAMESPACE)
    if not results:
        raise ValueError("TRX 没有 UnitTestResult，不能生成空的 JUnit 成功报告")

    suite = ET.Element("testsuite", {"name": scenario})
    failures = 0
    errors = 0
    skipped = 0
    total_time = 0.0
    for result in results:
        duration = _duration_seconds(result.get("duration"))
        total_time += float(duration)
        case = ET.SubElement(
            suite,
            "testcase",
            {
                "classname": result.get("testName", scenario),
                "name": result.get("testName", scenario),
                "time": duration,
            },
        )
        outcome = result.get("outcome", "")
        if outcome == "Passed":
            continue
        if outcome == "NotExecuted":
            skipped += 1
            ET.SubElement(case, "skipped", {"message": "TRX outcome=NotExecuted"})
            continue

        error_info = result.find("./trx:Output/trx:ErrorInfo", TRX_NAMESPACE)
        message = ""
        stack_trace = ""
        if error_info is not None:
            message_node = error_info.find("trx:Message", TRX_NAMESPACE)
            stack_node = error_info.find("trx:StackTrace", TRX_NAMESPACE)
            message = message_node.text if message_node is not None and message_node.text else ""
            stack_trace = stack_node.text if stack_node is not None and stack_node.text else ""
        if outcome == "Failed":
            failures += 1
            node = ET.SubElement(case, "failure", {"message": message or "MSTest failed"})
        else:
            errors += 1
            node = ET.SubElement(
                case,
                "error",
                {"message": message or f"未知 TRX outcome={outcome}"},
            )
        node.text = stack_trace

    suite.set("tests", str(len(results)))
    suite.set("failures", str(failures))
    suite.set("errors", str(errors))
    suite.set("skipped", str(skipped))
    suite.set("time", f"{total_time:.6f}".rstrip("0").rstrip("."))
    target.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(suite, space="  ")
    ET.ElementTree(suite).write(target, encoding="utf-8", xml_declaration=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--scenario", required=True)
    args = parser.parse_args()
    convert(args.input, args.output, args.scenario)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
