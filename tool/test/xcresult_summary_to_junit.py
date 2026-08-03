#!/usr/bin/env python3
"""将 xcresulttool 的稳定 summary JSON 转换为最小 JUnit。"""

from __future__ import annotations

import argparse
import json
import xml.etree.ElementTree as ET
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--scenario", required=True)
    args = parser.parse_args()

    payload = json.loads(args.input.read_text(encoding="utf-8"))
    total = int(payload.get("totalTestCount", payload.get("testsCount", 0)))
    failed = int(payload.get("failedTests", payload.get("failedTestCount", 0)))
    skipped = int(payload.get("skippedTests", payload.get("skippedTestCount", 0)))
    passed = int(payload.get("passedTests", payload.get("passedTestCount", 0)))
    suite = ET.Element(
        "testsuite",
        {
            "name": args.scenario,
            "tests": str(total),
            "failures": str(failed),
            "errors": "0",
            "skipped": str(skipped),
        },
    )
    case = ET.SubElement(suite, "testcase", {"classname": "RunnerUITests", "name": args.scenario})
    if skipped:
        ET.SubElement(case, "skipped")
    elif failed or passed <= 0:
        failure = ET.SubElement(case, "failure", {"message": "XCUITest failed"})
        failure.text = json.dumps(payload, ensure_ascii=False)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(args.output, encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
