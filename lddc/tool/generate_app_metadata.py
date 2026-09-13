#!/usr/bin/env python3
"""从 pubspec.yaml 生成应用版本常量，保证版本号只有一个真源。

背景：版本号此前在三处各自维护（pubspec.yaml 的 `version`、Dart 常量
`kLddcVersion`、macOS 工程的 `MARKETING_VERSION`），三者可能互相矛盾。现在
约定 pubspec.yaml 是唯一真源：

- `kLddcVersion` = `'v' + pubspec.version 去掉 +build 段`，保留预发布段
  （例：`0.10.0-alpha.1+1` → `v0.10.0-alpha.1`）。预发布段必须保留，因为更新
  检查按 SemVer 预发布规则比较（`app_update_checker_common.dart`）。
- macOS/iOS/Android 的原生版本字段统一引用 Flutter 由 pubspec 派生的
  `FLUTTER_BUILD_NAME` / `FLUTTER_BUILD_NUMBER`，不再手写字面量。

用法：
    python tool/generate_app_metadata.py          # 写入生成文件
    python tool/generate_app_metadata.py --check  # 只校验是否与 pubspec 一致
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
PUBSPEC_PATH = APP_ROOT / "pubspec.yaml"
OUTPUT_PATH = APP_ROOT / "lib" / "src" / "core" / "app_metadata.dart"

# Dart pub 的版本格式：主.次.补丁（可带预发布段），可选 +构建号。
_VERSION_PATTERN = re.compile(
    r"^(?P<base>\d+\.\d+\.\d+)(?:-(?P<prerelease>[0-9A-Za-z.-]+))?(?:\+(?P<build>[0-9A-Za-z.-]+))?$"
)

_TEMPLATE = """\
// GENERATED CODE - DO NOT MODIFY BY HAND.
// 由 tool/generate_app_metadata.py 从 pubspec.yaml 的 version 字段生成。

/// 应用级元数据。
///
/// 版本号会被 About 页、桌面服务信息和歌词导出注释共同使用，因此不能放在
/// converter 模块里；否则只想显示版本号的页面也会被迫依赖歌词转换实现。
///
/// 单一真源是 `pubspec.yaml` 的 `version`：这里保留 `v` 前缀与预发布段，
/// 但去掉 `+build` 构建号（例：`0.10.0-alpha.1+1` → `v0.10.0-alpha.1`）。
const String kLddcVersion = 'v{version}';
"""


def _read_pubspec_version() -> str:
    """读取 pubspec.yaml 顶层的 version 字段。

    只做正则解析顶层标量，避免为此引入 PyYAML 依赖；pubspec 的 `version`
    必须是顶层键，因此匹配行首缩进为零的写法即可。
    """
    match = re.search(r"^version:\s*(\S+)\s*$", PUBSPEC_PATH.read_text(encoding="utf-8"), re.MULTILINE)
    if match is None:
        msg = f"{PUBSPEC_PATH} 缺少顶层 version 字段"
        raise ValueError(msg)
    return match.group(1)


def _split_version(raw: str) -> tuple[str, str | None, str | None]:
    """拆出 (主.次.补丁, 预发布段, 构建段)，格式不合法时直接报错。"""
    match = _VERSION_PATTERN.match(raw)
    if match is None:
        msg = f"pubspec 的 version 不符合 Dart 版本格式: {raw}"
        raise ValueError(msg)
    return match.group("base"), match.group("prerelease"), match.group("build")


def render_metadata(version_raw: str) -> str:
    """把 pubspec 版本渲染成生成文件内容。"""
    base, prerelease, _build = _split_version(version_raw)
    label = f"{base}-{prerelease}" if prerelease else base
    return _TEMPLATE.format(version=label)


def expected_metadata_text() -> str:
    """按当前 pubspec 计算期望的生成文件内容（供本脚本与发布元数据检查共用）。"""
    return render_metadata(_read_pubspec_version())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="只校验生成文件是否与 pubspec 一致，不写入",
    )
    args = parser.parse_args()

    expected = expected_metadata_text()

    if args.check:
        actual = OUTPUT_PATH.read_text(encoding="utf-8") if OUTPUT_PATH.is_file() else ""
        if actual != expected:
            print(
                f"[FAIL] {OUTPUT_PATH} 与 pubspec.yaml 的版本不一致；"
                "请运行 python tool/generate_app_metadata.py 后提交生成结果。",
                file=sys.stderr,
            )
            return 1
        print("应用版本常量与 pubspec 一致。")
        return 0

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    # 固定使用 LF，避免不同平台的换行差异进入候选文件。
    OUTPUT_PATH.write_text(expected, encoding="utf-8", newline="\n")
    print(f"已写入 {OUTPUT_PATH.relative_to(APP_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
