#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026
# SPDX-License-Identifier: GPL-3.0-only
"""生成 ruby 模块 Python 基线向量（供 Flutter 侧差分测试）。"""

from __future__ import annotations

import ast
import argparse
import sys
import os
import platform
import tempfile
from pathlib import Path
from typing import Any

from python_baseline.baseline_writer import BaselineWriteOptions, BaselineWriter


def _resolve_original_repo() -> Path:
    script_path = Path(__file__).resolve()
    workspace_root = script_path.parents[3]
    original_repo = workspace_root / "LDDC"
    ruby_path = original_repo / "LDDC" / "core" / "ruby" / "__init__.py"
    if not ruby_path.exists():
        msg = f"未找到Python版 ruby 模块: {ruby_path}"
        raise FileNotFoundError(msg)
    return original_repo


def _extract_test_cases(path: Path) -> list[tuple[str, str, str]]:
    source = path.read_text(encoding="utf-8")
    module = ast.parse(source, filename=str(path))
    for node in module.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "test_cases":
                    values = ast.literal_eval(node.value)
                    extracted: list[tuple[str, str, str]] = []
                    for item in values:
                        if (
                            isinstance(item, (tuple, list))
                            and len(item) >= 3
                            and isinstance(item[0], str)
                            and isinstance(item[1], str)
                            and isinstance(item[2], str)
                        ):
                            extracted.append((item[0], item[1], item[2]))
                    return extracted
    msg = f"未在文件中找到 test_cases: {path}"
    raise ValueError(msg)


ORIGINAL_REPO = _resolve_original_repo()
sys.path.insert(0, str(ORIGINAL_REPO))

# Python 版 ruby 模块导入 logger，Windows 下会打开真实用户日志文件。
# 基线生成器只需要纯算法结果，因此把路径探测隔离到临时 HOME，避免与正在运行
# 的 LDDC 抢同一个日志文件。
_baseline_home = Path(tempfile.gettempdir()) / "lddc-python-baseline-home"
_baseline_home.mkdir(parents=True, exist_ok=True)
os.environ["HOME"] = str(_baseline_home)
Path.home = classmethod(lambda cls: _baseline_home)  # type: ignore[method-assign]
platform.system = lambda: "Linux"  # type: ignore[assignment]

from LDDC.common.models import FSLyricsLine, FSLyricsWord  # noqa: E402
from LDDC.core.ruby import generate_ruby  # noqa: E402
from LDDC.core.ruby.romaji_converter import roma_to_hiragana  # noqa: E402


def _to_fs_line(text: str) -> FSLyricsLine:
    return FSLyricsLine(0, 0, [FSLyricsWord(0, 0, text)])


def _build_generate_ruby_vectors() -> list[dict[str, Any]]:
    tests_root = ORIGINAL_REPO / "tests"
    base_cases = _extract_test_cases(tests_root / "test_ruby_generator.py")
    extra_cases = _extract_test_cases(tests_root / "ruby_test_cases.py")

    vectors: list[dict[str, Any]] = []
    for name, orig_text, roma_text in [*base_cases, *extra_cases]:
        orig_line = _to_fs_line(orig_text)
        roma_line = _to_fs_line(roma_text)
        output = generate_ruby(orig_line, roma_line)
        vectors.append(
            {
                "name": name,
                "origText": orig_text,
                "romaText": roma_text,
                "expected": [[start, end, ruby] for start, end, ruby in output],
            },
        )
    return vectors


def _build_roma_to_hiragana_vectors() -> list[dict[str, str]]:
    inputs = [
        "watashi",
        "shin'ichi",
        "ko-hi-",
        "seigi cha seigi",
        "fi na a re",
        "zutto",
        "sempai no shimbun",
        "yukoo",
        "a i shi te ru",
        "maboroshi",
    ]
    return [{"input": text, "expected": roma_to_hiragana(text)} for text in inputs]


def _build_payload() -> dict[str, Any]:
    return {
        "meta": {
            "source": "LDDC/LDDC/core/ruby/*",
        },
        "vectors": {
            "generate_ruby": _build_generate_ruby_vectors(),
            "roma_to_hiragana": _build_roma_to_hiragana_vectors(),
        },
    }


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只校验基线是否最新，不写文件")
    parser.add_argument("--dry-run", action="store_true", help="生成并校验内容，但不替换目标文件")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    payload = _build_payload()
    output_path = Path(__file__).resolve().parents[1] / "test" / "resources" / "ruby" / "python_ruby_vectors.json"
    BaselineWriter(BaselineWriteOptions(check=args.check, dry_run=args.dry_run)).write_json(output_path, payload)


if __name__ == "__main__":
    main()
