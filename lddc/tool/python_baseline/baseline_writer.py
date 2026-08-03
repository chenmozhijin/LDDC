#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026
# SPDX-License-Identifier: GPL-3.0-only
"""安全写入 Python 基线产物。"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BaselineWriteOptions:
    check: bool = False
    dry_run: bool = False


class BaselineCheckFailed(RuntimeError):
    """`--check` 模式下生成内容与现有基线不一致。"""


class BaselineWriter:
    """原子写入基线文件，避免生成器半写坏提交基线。"""

    def __init__(self, options: BaselineWriteOptions) -> None:
        self._options = options

    def write_json(self, output_path: Path, payload: object) -> None:
        content = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
        self._write_content(output_path, content, kind="json")

    def write_dart(self, output_path: Path, content: str) -> None:
        self._write_content(output_path, content, kind="dart")

    def _write_content(self, output_path: Path, content: str, *, kind: str) -> None:
        output_path = output_path.resolve()
        self._validate_content(content, kind=kind, path=output_path)
        if self._options.check:
            current = output_path.read_text(encoding="utf-8") if output_path.exists() else None
            if current is None or self._normalize_newlines(current) != self._normalize_newlines(content):
                raise BaselineCheckFailed(f"基线文件需要重新生成: {output_path}")
            print(f"基线文件已是最新: {output_path}")
            return
        if self._options.dry_run:
            print(f"dry-run: 已生成并校验内容，不写入: {output_path}")
            return

        output_path.parent.mkdir(parents=True, exist_ok=True)
        tmp_path = output_path.with_name(f".{output_path.name}.tmp")
        with tmp_path.open("w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
        read_back = tmp_path.read_text(encoding="utf-8")
        self._validate_content(read_back, kind=kind, path=tmp_path)
        tmp_path.replace(output_path)
        print(f"已生成基线文件: {output_path}")

    def _validate_content(self, content: str, *, kind: str, path: Path) -> None:
        if not content:
            raise ValueError(f"生成内容为空: {path}")
        if kind == "json":
            json.loads(content)
            return
        if kind == "dart":
            if "generated" not in content.lower() and "do not edit" not in content.lower():
                raise ValueError(f"Dart 生成文件缺少生成提示: {path}")
            return
        raise ValueError(f"未知基线文件类型: {kind}")

    def _normalize_newlines(self, content: str) -> str:
        return content.replace("\r\n", "\n").replace("\r", "\n")
