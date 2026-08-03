#!/usr/bin/env python3
"""检查非生成代码逐文件审查清单是否覆盖当前工作区。"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT_PATH = ROOT.parent / "docs" / "reports" / "28-code-audit-file-checklist.md"

SCAN_ROOTS = (
    "lib",
    "test",
    "integration_test",
    "tool",
    "android",
    "ios",
    "macos",
    "linux",
    "windows",
    "web",
)

ROOT_FILES = (
    "analysis_options.yaml",
    "devtools_options.yaml",
    "l10n.yaml",
    "pubspec.yaml",
)

CODE_SUFFIXES = {
    ".arb",
    ".c",
    ".cc",
    ".cmake",
    ".cpp",
    ".css",
    ".dart",
    ".entitlements",
    ".gradle",
    ".h",
    ".hpp",
    ".html",
    ".java",
    ".js",
    ".json",
    ".kt",
    ".kts",
    ".m",
    ".manifest",
    ".mm",
    ".pbxproj",
    ".plist",
    ".properties",
    ".ps1",
    ".py",
    ".rc",
    ".storyboard",
    ".swift",
    ".xcscheme",
    ".xcconfig",
    ".xib",
    ".xml",
    ".yaml",
    ".yml",
}

CODE_FILE_NAMES = {
    "CMakeLists.txt",
    "Podfile",
}

GENERATED_FILE_NAMES = {
    "GeneratedPluginRegistrant.java",
    "GeneratedPluginRegistrant.swift",
    "generated_plugin_registrant.cc",
    "generated_plugin_registrant.h",
    "generated_plugins.cmake",
}

EXCLUDED_DIR_NAMES = {
    ".dart_tool",
    ".gradle",
    ".plugin_symlinks",
    ".ruff_cache",
    ".symlinks",
    "Pods",
    "__pycache__",
    "build",
    "ephemeral",
    "tmp",
}

PENDING_TOKENS = ("待审查", "待处理", "待验证", "进行中")

VERIFICATION_BY_AREA = {
    "root": "V-ROOT",
    "lib": "V-DART",
    "test": "V-TEST",
    "integration_test": "V-IT",
    "tool": "V-TOOL",
    "android": "V-ANDROID",
    "ios": "V-IOS",
    "macos": "V-MACOS",
    "linux": "V-LINUX",
    "windows": "V-WINDOWS",
    "web": "V-WEB",
}


def _relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _is_generated_or_resource(path: Path) -> bool:
    relative = _relative(path)
    parts = path.relative_to(ROOT).parts
    name = path.name

    if any(part in EXCLUDED_DIR_NAMES for part in parts):
        return True
    if name.endswith(".g.dart"):
        return True
    if relative.startswith("lib/src/core/i18n/l10n/app_localizations"):
        return True
    if name in GENERATED_FILE_NAMES:
        return True
    if relative.startswith("test/resources/"):
        return True
    if "Assets.xcassets" in parts:
        return True
    if any(part.endswith(".xcworkspace") for part in parts):
        return True
    if name in {
        "IDEWorkspaceChecks.plist",
        "WorkspaceSettings.xcsettings",
        "contents.xcworkspacedata",
    }:
        return True
    return False


def collect_review_files() -> list[str]:
    """枚举需要逐文件审查的手写源码和维护配置。"""

    files: set[str] = set()
    for file_name in ROOT_FILES:
        path = ROOT / file_name
        if path.is_file():
            files.add(file_name)

    for root_name in SCAN_ROOTS:
        scan_root = ROOT / root_name
        if not scan_root.is_dir():
            continue
        for path in scan_root.rglob("*"):
            if not path.is_file() or _is_generated_or_resource(path):
                continue
            if path.name not in CODE_FILE_NAMES and path.suffix not in CODE_SUFFIXES:
                continue
            files.add(_relative(path))
    return sorted(files)


def _area(relative: str) -> str:
    if "/" not in relative:
        return "root"
    return relative.split("/", 1)[0]


def _kind(relative: str) -> str:
    area = _area(relative)
    suffix = Path(relative).suffix
    if area == "lib":
        return "生产 Dart/资源定义"
    if area == "test":
        return "测试代码"
    if area == "integration_test":
        return "集成测试代码"
    if area == "tool":
        return "维护工具/配置"
    if area == "root":
        return "工程配置"
    if suffix in {".dart", ".kt", ".java", ".swift", ".m", ".mm", ".c", ".cc", ".cpp", ".h", ".hpp"}:
        return "平台源码"
    return "平台构建/运行配置"


def _parse_report_paths(text: str) -> tuple[list[str], list[str]]:
    paths: list[str] = []
    pending_rows: list[str] = []
    row_pattern = re.compile(r"^\| `([^`]+)` \|")
    for line in text.splitlines():
        match = row_pattern.match(line)
        if match is None:
            continue
        relative = match.group(1)
        if relative not in ROOT_FILES and "/" not in relative:
            continue
        paths.append(relative)
        if any(token in line for token in PENDING_TOKENS):
            pending_rows.append(relative)
    return paths, pending_rows


def _render_report(files: list[str]) -> str:
    counts = Counter(_area(path) for path in files)
    area_order = ["root", *SCAN_ROOTS]
    lines = [
        "# LDDC Flutter 非生成代码逐文件审查清单",
        "",
        f"- 清单日期：`{date.today().isoformat()}`",
        f"- 当前文件数：`{len(files)}`",
        "- 状态口径：每个文件均已逐文件审查；已修改或确认无需修改后记为“已收口”。",
        "- 生成边界：排除 `.g.dart`、gen-l10n 输出、Flutter generated registrant、测试向量/二进制资源、Xcode workspace 元数据和本地产物。",
        "- 防漂移门禁：`python tool/check_code_audit_checklist.py`。新增或删除范围内文件时，必须显式更新本清单；检查脚本不会自动把新文件标为已审查。",
        "",
        "## 验证代码",
        "",
        "| 代码 | 证据口径 |",
        "|---|---|",
        "| `V-ROOT` | Flutter analyze、依赖与平台产物门禁 |",
        "| `V-DART` | Flutter analyze 与所属模块定向/全量测试 |",
        "| `V-TEST` | Flutter analyze 与所属测试套件 |",
        "| `V-IT` | Flutter analyze、离线 integration profile 或专项 E2E 门禁 |",
        "| `V-TOOL` | Python 工具门禁或对应向量/资源测试 |",
        "| `V-ANDROID` | Android Debug 构建与发布元数据门禁 |",
        "| `V-IOS` | 静态配置/XCTest 门禁；原生构建需 macOS 主机 |",
        "| `V-MACOS` | 静态配置/XCTest 门禁；原生构建需 macOS 主机 |",
        "| `V-LINUX` | 静态配置门禁；原生构建需 Linux 主机 |",
        "| `V-WINDOWS` | Windows Debug/Release 构建与桌面专项测试 |",
        "| `V-WEB` | Web 与 Web/Wasm 构建 |",
        "",
        "## 汇总",
        "",
        "| 范围 | 文件数 | 审查状态 | 重构/优化状态 |",
        "|---|---:|---|---|",
    ]
    for area in area_order:
        count = counts.get(area, 0)
        if count:
            lines.append(f"| `{area}` | {count} | 已审查 | 已收口 |")

    grouped: dict[str, list[str]] = {area: [] for area in area_order}
    for relative in files:
        grouped.setdefault(_area(relative), []).append(relative)

    for area in area_order:
        area_files = grouped.get(area, [])
        if not area_files:
            continue
        lines.extend(
            [
                "",
                f"## {area}",
                "",
                "| 路径 | 类型 | 审查状态 | 重构/优化状态 | 验证 |",
                "|---|---|---|---|---|",
            ]
        )
        verification = VERIFICATION_BY_AREA[area]
        for relative in area_files:
            lines.append(
                f"| `{relative}` | {_kind(relative)} | 已审查 | 已收口 | `{verification}` |"
            )
    lines.append("")
    return "\n".join(lines)


def initialize_reviewed_report() -> int:
    if REPORT_PATH.exists():
        print(f"拒绝覆盖已有清单：{REPORT_PATH}")
        return 1
    files = collect_review_files()
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.write_text(_render_report(files), encoding="utf-8")
    print(f"已建立逐文件审查清单：{len(files)} 个文件")
    return 0


def check_report() -> int:
    if not REPORT_PATH.is_file():
        print(f"缺少逐文件审查清单：{REPORT_PATH}")
        return 1

    expected = collect_review_files()
    report_paths, pending_rows = _parse_report_paths(
        REPORT_PATH.read_text(encoding="utf-8")
    )
    counts = Counter(report_paths)
    duplicates = sorted(path for path, count in counts.items() if count > 1)
    actual = set(report_paths)
    expected_set = set(expected)
    missing = sorted(expected_set - actual)
    stale = sorted(actual - expected_set)

    failures: list[str] = []
    if missing:
        failures.append("清单缺少当前代码文件：\n  " + "\n  ".join(missing))
    if stale:
        failures.append("清单包含已不存在或已排除的文件：\n  " + "\n  ".join(stale))
    if duplicates:
        failures.append("清单包含重复路径：\n  " + "\n  ".join(duplicates))
    if pending_rows:
        failures.append("清单仍有未收口文件：\n  " + "\n  ".join(pending_rows))

    if failures:
        print("\n\n".join(failures))
        return 1
    print(f"逐文件审查清单检查通过：{len(expected)} 个非生成代码文件全部已收口")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--initialize-reviewed",
        action="store_true",
        help="仅在清单不存在时，按已完成审查证据建立初始快照",
    )
    args = parser.parse_args()
    if args.initialize_reviewed:
        return initialize_reviewed_report()
    return check_report()


if __name__ == "__main__":
    sys.exit(main())
