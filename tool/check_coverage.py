#!/usr/bin/env python3
"""检查 LCOV 行、分支和改动行覆盖率，缺失生产文件不能静默通过。"""

from __future__ import annotations

import argparse
import fnmatch
import json
import posixpath
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path


GENERATED_PATTERNS = (
    "*.g.dart",
    "*.freezed.dart",
    "*/l10n/app_localizations*.dart",
)


@dataclass
class CoverageFile:
    lines: dict[int, int] = field(default_factory=dict)
    branches: dict[tuple[int, str, str], int] = field(default_factory=dict)


def normalize_path(value: str) -> str:
    return posixpath.normpath(value.replace("\\", "/").removeprefix("./"))


def is_generated(path: str) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in GENERATED_PATTERNS)


def qualify_source(source: str, prefix: str) -> str | None:
    normalized = normalize_path(source)
    normalized_prefix = normalize_path(prefix).strip("./")
    is_absolute = re.match(r"^[A-Za-z]:/|^/", normalized) is not None
    if is_absolute:
        if normalized_prefix:
            # Dart VM 会把被测 package 依赖的其他 package 也写进同一 LCOV。
            # 只有绝对路径最后一次出现当前 scope 目录时才归入本 scope；使用
            # rfind 可避免应用目录 `lddc` 误命中仓库上层同名目录。
            haystack = f"/{normalized}"
            marker = f"/{normalized_prefix}/"
            marker_index = haystack.casefold().rfind(marker.casefold())
            if marker_index < 0:
                return None
            normalized = haystack[marker_index + 1 :]
        else:
            marker_index = normalized.rfind("/lib/")
            if marker_index >= 0:
                normalized = normalized[marker_index + 1 :]
    elif normalized_prefix:
        if normalized.startswith(f"{normalized_prefix}/"):
            pass
        elif normalized.startswith("lib/"):
            normalized = f"{normalized_prefix}/{normalized}"
        else:
            # 已带其他 workspace package 前缀的相对路径同样属于依赖源码。
            return None
    return normalize_path(normalized)


def parse_input_spec(value: str) -> tuple[Path, str]:
    if "=" not in value:
        return Path(value), ""
    path, prefix = value.rsplit("=", 1)
    return Path(path), prefix


def find_missing_sources(
    coverage: dict[str, CoverageFile], source_specs: list[str]
) -> list[str]:
    missing: list[str] = []
    for raw_spec in source_specs:
        root, prefix = parse_input_spec(raw_spec)
        if not root.is_dir():
            missing.append(f"<source-root-not-found:{root}>")
            continue
        for path in root.rglob("*.dart"):
            relative = normalize_path(str(path.relative_to(root)))
            qualified = normalize_path(f"{prefix}/{relative}") if prefix else relative
            if is_generated(qualified):
                continue
            if qualified not in coverage and source_has_executable_code(path):
                missing.append(qualified)
    return sorted(missing)


def source_has_executable_code(path: Path) -> bool:
    source = path.read_text(encoding="utf-8")
    if path.name.endswith(("_web.dart", "_stub.dart")):
        return False
    source_without_directives = re.sub(
        r"(?ms)^\s*(?:import|export|part)\b.*?;",
        "",
        source,
    )
    # 纯 barrel、类型声明和常量文件不会产生 VM 行覆盖记录。只要求含控制流、
    # 返回、异常或表达式函数体的文件进入 LCOV，避免把不可执行行算作漏测。
    return bool(
        re.search(
            r"(?:=>|\b(?:return|throw|if|for|while|switch|try|await|yield)\b)",
            source_without_directives,
        )
    )


def parse_lcov(path: Path, prefix: str) -> dict[str, CoverageFile]:
    files: dict[str, CoverageFile] = {}
    current: CoverageFile | None = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if raw_line.startswith("SF:"):
            source = qualify_source(raw_line[3:], prefix)
            current = (
                None
                if source is None or is_generated(source)
                else files.setdefault(source, CoverageFile())
            )
        elif current is not None and raw_line.startswith("DA:"):
            line, hits, *_ = raw_line[3:].split(",")
            line_number = int(line)
            current.lines[line_number] = max(current.lines.get(line_number, 0), int(hits))
        elif current is not None and raw_line.startswith("BRDA:"):
            line, block, branch, hits = raw_line[5:].split(",")
            key = (int(line), block, branch)
            parsed_hits = 0 if hits == "-" else int(hits)
            current.branches[key] = max(current.branches.get(key, 0), parsed_hits)
    return files


def merge_coverage(target: dict[str, CoverageFile], source: dict[str, CoverageFile]) -> None:
    for path, incoming in source.items():
        merged = target.setdefault(path, CoverageFile())
        for line, hits in incoming.lines.items():
            merged.lines[line] = max(merged.lines.get(line, 0), hits)
        for branch, hits in incoming.branches.items():
            merged.branches[branch] = max(merged.branches.get(branch, 0), hits)


def percentage(hit: int, total: int) -> float:
    return 100.0 if total == 0 else hit * 100.0 / total


def parse_diff(path: Path) -> dict[str, dict[int, str]]:
    changed: dict[str, dict[int, str]] = {}
    current_path: str | None = None
    next_line: int | None = None
    hunk_pattern = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if raw_line.startswith("+++ "):
            candidate = raw_line[4:].strip()
            current_path = None if candidate == "/dev/null" else normalize_path(candidate.removeprefix("b/"))
            next_line = None
            continue
        match = hunk_pattern.match(raw_line)
        if match:
            next_line = int(match.group(1))
            continue
        if current_path is None or next_line is None:
            continue
        if raw_line.startswith("+") and not raw_line.startswith("+++"):
            changed.setdefault(current_path, {})[next_line] = raw_line[1:]
            next_line += 1
        elif raw_line.startswith("-") and not raw_line.startswith("---"):
            continue
        elif not raw_line.startswith("\\"):
            next_line += 1
    return changed


def looks_executable(content: str) -> bool:
    stripped = content.strip()
    if not stripped:
        return False
    ignored_prefixes = (
        "//",
        "///",
        "/*",
        "*",
        "*/",
        "import ",
        "export ",
        "part ",
        "library ",
        "@",
    )
    return not stripped.startswith(ignored_prefixes) and stripped not in {"{", "}", "};"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", action="append", required=True, help="LCOV路径[=仓库前缀]")
    parser.add_argument("--minimum-line", type=float)
    parser.add_argument("--minimum-branch", type=float)
    parser.add_argument("--threshold-config", type=Path)
    parser.add_argument("--scope")
    parser.add_argument(
        "--require-source-root",
        action="append",
        default=[],
        help="要求进入 LCOV 的源码目录[=仓库前缀]",
    )
    parser.add_argument("--diff", type=Path)
    parser.add_argument("--minimum-changed-line", type=float, default=80.0)
    args = parser.parse_args()

    minimum_line = args.minimum_line
    minimum_branch = args.minimum_branch
    minimum_changed_line = args.minimum_changed_line
    if args.threshold_config is not None:
        thresholds = json.loads(args.threshold_config.read_text(encoding="utf-8"))
        minimum_changed_line = float(thresholds["changedLines"])
        if args.scope is not None:
            scope = thresholds["scopes"].get(args.scope)
            if scope is None:
                parser.error(f"threshold config 不包含 scope={args.scope}")
            minimum_line = float(scope["minimumLine"])
            minimum_branch = float(scope["minimumBranch"])

    coverage: dict[str, CoverageFile] = {}
    failures: list[str] = []
    for raw_spec in args.input:
        path, prefix = parse_input_spec(raw_spec)
        if not path.is_file():
            failures.append(f"覆盖率文件不存在: {path}")
            continue
        merge_coverage(coverage, parse_lcov(path, prefix))

    line_total = sum(len(item.lines) for item in coverage.values())
    line_hit = sum(sum(hits > 0 for hits in item.lines.values()) for item in coverage.values())
    branch_total = sum(len(item.branches) for item in coverage.values())
    branch_hit = sum(sum(hits > 0 for hits in item.branches.values()) for item in coverage.values())
    line_rate = percentage(line_hit, line_total)
    branch_rate = percentage(branch_hit, branch_total)
    print(f"line coverage: {line_hit}/{line_total} ({line_rate:.2f}%)")
    print(f"branch coverage: {branch_hit}/{branch_total} ({branch_rate:.2f}%)")

    if line_total == 0:
        failures.append("LCOV 没有行覆盖数据")
    if minimum_line is not None and line_rate < minimum_line:
        failures.append(f"行覆盖率 {line_rate:.2f}% 低于 {minimum_line:.2f}%")
    if minimum_branch is not None:
        if branch_total == 0:
            failures.append("要求分支门槛但 LCOV 没有 BRDA 数据")
        elif branch_rate < minimum_branch:
            failures.append(f"分支覆盖率 {branch_rate:.2f}% 低于 {minimum_branch:.2f}%")

    missing_sources = find_missing_sources(coverage, args.require_source_root)
    if missing_sources:
        preview = ", ".join(missing_sources[:20])
        suffix = "" if len(missing_sources) <= 20 else f" 等 {len(missing_sources)} 个文件"
        failures.append(f"生产源码没有进入 LCOV: {preview}{suffix}")

    if args.diff is not None and args.diff.is_file():
        changed = parse_diff(args.diff)
        changed_total = 0
        changed_hit = 0
        missing_files: list[str] = []
        for source_path, lines in changed.items():
            if not source_path.endswith(".dart") or "/lib/" not in f"/{source_path}":
                continue
            if is_generated(source_path):
                continue
            item = coverage.get(source_path)
            if item is None:
                if any(looks_executable(content) for content in lines.values()):
                    missing_files.append(source_path)
                continue
            for line_number in lines:
                if line_number not in item.lines:
                    continue
                changed_total += 1
                changed_hit += item.lines[line_number] > 0
        changed_rate = percentage(changed_hit, changed_total)
        print(f"changed line coverage: {changed_hit}/{changed_total} ({changed_rate:.2f}%)")
        if missing_files:
            failures.append("改动的生产文件完全没有覆盖记录: " + ", ".join(sorted(missing_files)))
        if changed_total > 0 and changed_rate < minimum_changed_line:
            failures.append(
                f"改动行覆盖率 {changed_rate:.2f}% 低于 {minimum_changed_line:.2f}%"
            )

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
