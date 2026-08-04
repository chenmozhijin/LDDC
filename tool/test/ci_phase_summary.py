#!/usr/bin/env python3
"""汇总 CI 必需阶段，并在任一阶段未成功时返回失败。"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path


KNOWN_OUTCOMES = {"success", "failure", "skipped", "cancelled"}


@dataclass(frozen=True)
class Phase:
    phase_id: str
    label: str
    outcome: str


def parse_phase(value: str) -> Phase:
    parts = value.split("|", 2)
    if len(parts) != 3 or not parts[0].strip() or not parts[1].strip():
        raise ValueError("phase 必须使用 id|显示名称|outcome 格式")
    raw_outcome = parts[2].strip().lower()
    outcome = raw_outcome if raw_outcome in KNOWN_OUTCOMES else "missing"
    return Phase(parts[0].strip(), parts[1].strip(), outcome)


def render_summary(title: str, phases: list[Phase]) -> str:
    def escape(value: str) -> str:
        return value.replace("|", "\\|").replace("\n", " ")

    passed = all(phase.outcome == "success" for phase in phases)
    rows = [
        f"### {escape(title)}",
        "",
        "| Required phase | ID | Outcome |",
        "| --- | --- | --- |",
    ]
    rows.extend(
        f"| {escape(phase.label)} | `{escape(phase.phase_id)}` | `{phase.outcome}` |"
        for phase in phases
    )
    rows.extend(("", f"Required result: `{'success' if passed else 'failure'}`", ""))
    return "\n".join(rows)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    parser.add_argument("--phase", action="append", required=True)
    args = parser.parse_args(argv)

    try:
        phases = [parse_phase(value) for value in args.phase]
    except ValueError as error:
        parser.error(str(error))
    summary = render_summary(args.title, phases)
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with Path(summary_path).open("a", encoding="utf-8", newline="\n") as output:
            output.write(summary)
    else:
        print(summary, end="")

    failed = [phase for phase in phases if phase.outcome != "success"]
    if failed:
        details = ", ".join(
            f"{phase.phase_id}={phase.outcome}" for phase in failed
        )
        print(f"ERROR: required CI phase failed or was not executed: {details}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
