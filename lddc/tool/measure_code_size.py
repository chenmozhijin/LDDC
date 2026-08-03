#!/usr/bin/env python3
"""统计当前 Git 工作区代码量变化。

该工具只读仓库状态，不修改任何文件。它把手写生产 Dart、测试、生成物、
文档、平台模板等分开统计，避免把 l10n 生成代码或测试向量误当成业务膨胀。
"""

from __future__ import annotations

import argparse
import subprocess
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GIT_ROOT = REPO_ROOT.parent
BASELINE_PRODUCTION_FILES = 399
BASELINE_PRODUCTION_LINES = 80_761
PRODUCTION_NET_HARD_LIMIT = 2_500


@dataclass(frozen=True)
class Change:
    scope: str
    category: str
    added: int
    deleted: int
    path: str

    @property
    def net(self) -> int:
        return self.added - self.deleted


def run_git(*args: str) -> list[str]:
    result = subprocess.run(
        [
            "git",
            "-c",
            "safe.directory=D:/yy/project/lyric/LDDC/LDDC-flutter",
            "-C",
            str(GIT_ROOT),
            *args,
        ],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return result.stdout.splitlines()


def category(path: str) -> str:
    if path.startswith("lddc/lib/src/core/i18n/l10n/") and path.endswith(".arb"):
        return "l10n_arb"
    if path.startswith("lddc/lib/src/core/i18n/l10n/app_localizations") and path.endswith(".dart"):
        return "generated_l10n"
    if path.endswith(".g.dart") and path.startswith(("lddc/lib/", "packages/")):
        return "generated_dart"
    if path.startswith(("lddc/lib/", "packages/")) and "/lib/" in path and path.endswith(".dart"):
        return "production_dart"
    if path.startswith(("lddc/test/resources/", "packages/")) and "/test/resources/" in path:
        return "test_vectors"
    if path.startswith("lddc/test/") or (
        path.startswith("packages/") and "/test/" in path
    ):
        return "test_code"
    if path.startswith("lddc/integration_test/"):
        return "integration_test"
    if path.startswith("examples/") and "/lib/" in path and path.endswith(".dart"):
        return "consumer_example"
    if path.startswith("examples/") and "/test/" in path and path.endswith(".dart"):
        return "consumer_test"
    if path.startswith(("lddc/android/", "lddc/ios/", "lddc/macos/", "lddc/linux/", "lddc/windows/", "lddc/web/")):
        return "platform_native"
    if path.startswith("docs/") or path.endswith("/README.md"):
        return "docs"
    if path.startswith(("lddc/tool/", "tool/")):
        return "tools"
    if path.startswith("lddc/assets/") or (
        path.startswith("packages/") and "/assets/" in path
    ):
        return "assets"
    if path.endswith(("pubspec.yaml", "pubspec.lock", "analysis_options.yaml")):
        return "project_config"
    if path.startswith("lddc/") and path.split("/", 2)[1] in {
        "l10n.yaml",
        ".metadata",
        ".gitignore",
    }:
        return "project_config"
    if path in {".gitignore", "pubspec.yaml", "pubspec.lock", "analysis_options.yaml"}:
        return "project_config"
    return "other"


def iter_dart_files(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return [
        path
        for path in root.rglob("*.dart")
        if ".dart_tool" not in path.parts and "build" not in path.parts
    ]


def current_inventory() -> list[Change]:
    """按稳定目录扫描当前代码，避免工作树暂存状态影响预算口径。"""

    roots = [
        GIT_ROOT / "lddc" / "lib",
        GIT_ROOT / "lddc" / "test",
        GIT_ROOT / "lddc" / "integration_test",
    ]
    roots.extend((GIT_ROOT / "packages").glob("*/lib"))
    roots.extend((GIT_ROOT / "packages").glob("*/test"))
    roots.extend((GIT_ROOT / "examples").glob("*/lib"))
    roots.extend((GIT_ROOT / "examples").glob("*/test"))

    inventory: list[Change] = []
    seen: set[Path] = set()
    for root in roots:
        for full_path in iter_dart_files(root):
            resolved = full_path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            path = full_path.relative_to(GIT_ROOT).as_posix()
            if category(path) in {"generated_dart", "generated_l10n"}:
                continue
            # 既有 80,761 行基线按非空手写行统计；空白排版不应消耗生产预算。
            with full_path.open("r", encoding="utf-8") as source:
                lines = sum(1 for line in source if line.strip())
            inventory.append(
                Change(
                    scope="current",
                    category=category(path),
                    added=lines,
                    deleted=0,
                    path=path,
                )
            )
    return inventory


def read_numstat(scope: str, *args: str) -> list[Change]:
    changes: list[Change] = []
    for line in run_git(*args):
        parts = line.split("\t")
        if len(parts) < 3 or parts[0] == "-":
            continue
        changes.append(
            Change(
                scope=scope,
                category=category(parts[2]),
                added=int(parts[0]),
                deleted=int(parts[1]),
                path=parts[2],
            )
        )
    return changes


def read_untracked() -> list[Change]:
    changes: list[Change] = []
    for path in run_git("ls-files", "--others", "--exclude-standard"):
        full_path = GIT_ROOT / path
        try:
            added = sum(1 for _ in full_path.open("r", encoding="utf-8"))
        except UnicodeDecodeError:
            continue
        changes.append(
            Change(
                scope="untracked",
                category=category(path),
                added=added,
                deleted=0,
                path=path,
            )
        )
    return changes


def summarize(changes: list[Change], key: str) -> list[tuple[str, int, int, int, int]]:
    buckets: dict[str, list[Change]] = {}
    for change in changes:
        buckets.setdefault(getattr(change, key), []).append(change)
    rows: list[tuple[str, int, int, int, int]] = []
    for name, group in buckets.items():
        added = sum(item.added for item in group)
        deleted = sum(item.deleted for item in group)
        rows.append((name, len(group), added, deleted, added - deleted))
    return sorted(rows, key=lambda row: row[4], reverse=True)


def print_table(title: str, rows: list[tuple[str, int, int, int, int]]) -> None:
    print(f"\n## {title}")
    print("| name | files | added | deleted | net |")
    print("|---|---:|---:|---:|---:|")
    for name, files, added, deleted, net in rows:
        print(f"| {name} | {files} | {added} | {deleted} | {net} |")


def main() -> None:
    parser = argparse.ArgumentParser(description="统计 LDDC Flutter 工作区代码量变化")
    parser.add_argument(
        "--recent-only",
        action="store_true",
        help="只统计未暂存 tracked diff 和未跟踪文件，不包含已暂存新增",
    )
    args = parser.parse_args()

    inventory = current_inventory()
    print_table("current workspace inventory", summarize(inventory, "category"))
    production = [
        change for change in inventory if change.category == "production_dart"
    ]
    production_files = len(production)
    production_lines = sum(change.added for change in production)
    production_net = production_lines - BASELINE_PRODUCTION_LINES
    print("\n## production budget")
    print(f"- files: {production_files} (baseline {BASELINE_PRODUCTION_FILES})")
    print(f"- lines: {production_lines:,} (baseline {BASELINE_PRODUCTION_LINES:,})")
    print(f"- net lines: {production_net:+,}")
    print(
        "- hard limit: "
        f"{PRODUCTION_NET_HARD_LIMIT:+,} "
        f"({'PASS' if production_net <= PRODUCTION_NET_HARD_LIMIT else 'FAIL'})"
    )

    changes: list[Change] = []
    changes.extend(read_numstat("unstaged_tracked", "diff", "--numstat"))
    changes.extend(read_untracked())
    if not args.recent_only:
        changes.extend(read_numstat("staged", "diff", "--cached", "--numstat"))

    print_table("by scope", summarize(changes, "scope"))
    print_table("by category", summarize(changes, "category"))

    hand_written = [
        change
        for change in changes
        if change.category
        in {
            "production_dart",
            "test_code",
            "integration_test",
            "consumer_example",
            "consumer_test",
        }
    ]
    print_table("hand written code only", summarize(hand_written, "category"))


if __name__ == "__main__":
    main()
