#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026
# SPDX-License-Identifier: GPL-3.0-only
"""从Python版 ruby/dictionary.py 生成 Flutter 侧词典 Dart 文件。"""

from __future__ import annotations

import argparse
import ast
from pathlib import Path

from python_baseline.baseline_writer import BaselineWriteOptions, BaselineWriter


def _resolve_original_dictionary() -> Path:
    script_path = Path(__file__).resolve()
    workspace_root = script_path.parents[3]
    dictionary_path = workspace_root / "LDDC" / "LDDC" / "core" / "ruby" / "dictionary.py"
    if not dictionary_path.exists():
        msg = f"未找到Python版词典文件: {dictionary_path}"
        raise FileNotFoundError(msg)
    return dictionary_path


def _extract_vocab_dict(module: ast.Module) -> dict[str, tuple[str, ...]]:
    for node in module.body:
        if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) and node.target.id == "JP_VOCAB_DICT":
            value = ast.literal_eval(node.value)
            if not isinstance(value, dict):
                msg = "JP_VOCAB_DICT 不是字典"
                raise TypeError(msg)
            return value
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "JP_VOCAB_DICT":
                    value = ast.literal_eval(node.value)
                    if not isinstance(value, dict):
                        msg = "JP_VOCAB_DICT 不是字典"
                        raise TypeError(msg)
                    return value
    msg = "未在 dictionary.py 中找到 JP_VOCAB_DICT"
    raise ValueError(msg)


def _dart_string(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", r"\n")
        .replace("\r", r"\r")
        .replace("\t", r"\t")
    )
    return f"'{escaped}'"


def _render_dictionary(vocab: dict[str, tuple[str, ...]]) -> str:
    lines: list[str] = []
    lines.append("void _populateRubyVocabulary(_TrieNode root) {")
    for word, readings in vocab.items():
        rendered_readings = ", ".join(_dart_string(reading) for reading in readings)
        lines.append(
            "  _insertRubyVocabulary("
            f"root, {_dart_string(word)}, const <String>[{rendered_readings}]);"
        )
    lines.append("}")
    return "\n".join(lines)


def _render_file(vocab: dict[str, tuple[str, ...]]) -> str:
    dictionary_block = _render_dictionary(vocab)
    return (
        "// GENERATED CODE - DO NOT MODIFY BY HAND.\n"
        "// 由 tool/generate_ruby_dictionary_dart.py 从 Python 版 dictionary.py 生成。\n\n"
        "part of 'ruby_dictionary.dart';\n\n"
        f"{dictionary_block}\n"
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="只校验生成 Dart 是否最新，不写文件")
    parser.add_argument("--dry-run", action="store_true", help="生成并校验内容，但不替换目标文件")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    dictionary_path = _resolve_original_dictionary()
    source = dictionary_path.read_text(encoding="utf-8")
    module = ast.parse(source, filename=str(dictionary_path))
    vocab = _extract_vocab_dict(module)

    output_path = Path(__file__).resolve().parents[1] / "lib" / "src" / "core" / "ruby" / "ruby_dictionary_data.g.dart"
    BaselineWriter(BaselineWriteOptions(check=args.check, dry_run=args.dry_run)).write_dart(
        output_path,
        _render_file(vocab),
    )


if __name__ == "__main__":
    main()
