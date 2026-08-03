#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (C) 2026
# SPDX-License-Identifier: GPL-3.0-only
"""校验所有 ARB 的键、占位符、locale 和翻译完整性。"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
L10N_ROOT = PACKAGE_ROOT / "lib" / "src" / "core" / "i18n" / "l10n"
ARB_PATHS = (
    L10N_ROOT / "app_en.arb",
    L10N_ROOT / "app_zh.arb",
    L10N_ROOT / "app_zh_Hans.arb",
    L10N_ROOT / "app_zh_Hant.arb",
    L10N_ROOT / "app_ru.arb",
    L10N_ROOT / "app_ja.arb",
    L10N_ROOT / "app_ko.arb",
)
EXPECTED_LOCALES = ("en", "zh", "zh_Hans", "zh_Hant", "ru", "ja", "ko")
_IDENTIFIER_PATTERN = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
_PLACEHOLDER_PATTERN = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\s*(?:[,}])")
_ICU_CONTROL_PATTERN = re.compile(
    r"\{([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(plural|selectordinal|select)\s*,"
)
_HTML_TAG_PATTERN = re.compile(r"(?<!%)<\s*(/?)\s*([A-Za-z][A-Za-z0-9-]*)\b[^>]*>")
_FILE_TEMPLATE_TOKEN_PATTERN = re.compile(r"%<([A-Za-z_][A-Za-z0-9_]*)>")
_SIMPLIFIED_ONLY_MARKERS = frozenset("这为发后里录选择设错误词体开关档载页显隐应试线数据储进导删")
_TRADITIONAL_ONLY_MARKERS = frozenset("這為發後裡錄選擇設錯誤詞體開關檔載頁顯隱應試線數據儲進導刪")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fix-unused",
        action="store_true",
        help="从所有 locale 同时删除没有 Dart 使用点的消息及其 @ 元数据",
    )
    return parser.parse_args()


def _load_arb(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        msg = f"ARB 根节点必须是对象: {path}"
        raise TypeError(msg)
    return payload


def _message_keys(payload: dict[str, Any]) -> set[str]:
    return {key for key in payload if not key.startswith("@")}


def _message_metadata(payload: dict[str, Any], key: str) -> dict[str, Any] | None:
    metadata = payload.get(f"@{key}")
    if metadata is None:
        return None
    if not isinstance(metadata, dict):
        msg = f"@{key} 必须是对象"
        raise TypeError(msg)
    return metadata


def _placeholder_metadata(payload: dict[str, Any], key: str) -> dict[str, Any]:
    metadata = _message_metadata(payload, key)
    if metadata is None:
        return {}
    placeholders = metadata.get("placeholders", {})
    if not isinstance(placeholders, dict):
        msg = f"@{key}.placeholders 必须是对象"
        raise TypeError(msg)
    return placeholders


def _message_placeholders(payload: dict[str, Any], key: str) -> set[str]:
    message = payload[key]
    if not isinstance(message, str):
        msg = f"消息 {key} 必须是字符串"
        raise TypeError(msg)
    return set(_PLACEHOLDER_PATTERN.findall(message))


def _message_structure(
    message: str,
) -> tuple[set[tuple[str, str]], list[tuple[str, str]], list[str], int]:
    icu_controls = {
        (match.group(1), match.group(2)) for match in _ICU_CONTROL_PATTERN.finditer(message)
    }
    html_tags = [
        (match.group(1), match.group(2).lower())
        for match in _HTML_TAG_PATTERN.finditer(message)
    ]
    # 文件名模板 token 会直接交给格式化器解析，翻译 token 名会让界面展示
    # 一个无法使用的模板。因此这里保留顺序和重复次数，确保所有语言与英文契约一致。
    file_template_tokens = _FILE_TEMPLATE_TOKEN_PATTERN.findall(message)
    return icu_controls, html_tags, file_template_tokens, message.count("\n")


def _validate_message_text(path: Path, key: str, message: str) -> None:
    if "\r" in message:
        raise ValueError(f"locale 消息包含 CR 换行: {path}, {key}")
    if any(ord(char) < 32 and char not in {"\n", "\t"} for char in message):
        raise ValueError(f"locale 消息包含非法控制字符: {path}, {key}")
    if message.count("`") % 2 != 0 or message.count("**") % 2 != 0:
        raise ValueError(f"locale Markdown 定界符不配对: {path}, {key}")


def _validate_payloads(payloads: list[dict[str, Any]]) -> set[str]:
    reference_keys = _message_keys(payloads[0])
    for path, payload, expected_locale in zip(
        ARB_PATHS,
        payloads,
        EXPECTED_LOCALES,
        strict=True,
    ):
        if payload.get("@@locale") != expected_locale:
            msg = f"ARB locale 不正确: {path}, expected={expected_locale}"
            raise ValueError(msg)
    for path, payload in zip(ARB_PATHS[1:], payloads[1:], strict=True):
        keys = _message_keys(payload)
        if keys != reference_keys:
            missing = sorted(reference_keys - keys)
            extra = sorted(keys - reference_keys)
            msg = f"ARB 键不一致: {path}, missing={missing}, extra={extra}"
            raise ValueError(msg)

    for key in sorted(reference_keys):
        reference_text = payloads[0][key]
        if not isinstance(reference_text, str) or not reference_text.strip():
            msg = f"模板消息不能为空: {ARB_PATHS[0]}, {key}"
            raise ValueError(msg)
        _validate_message_text(ARB_PATHS[0], key, reference_text)
        reference_message = _message_placeholders(payloads[0], key)
        reference_structure = _message_structure(reference_text)
        reference_metadata = _message_metadata(payloads[0], key)
        reference_placeholders = _placeholder_metadata(payloads[0], key)
        if reference_message != set(reference_placeholders):
            msg = (
                f"模板消息与 @ 元数据 placeholder 不一致: {key}, "
                f"message={sorted(reference_message)}, "
                f"metadata={sorted(reference_placeholders)}"
            )
            raise ValueError(msg)

        for path, payload in zip(ARB_PATHS[1:], payloads[1:], strict=True):
            message = payload[key]
            if not isinstance(message, str) or not message.strip():
                msg = f"locale 消息不能为空: {path}, {key}"
                raise ValueError(msg)
            _validate_message_text(path, key, message)
            message_placeholders = _message_placeholders(payload, key)
            metadata = _message_metadata(payload, key)
            metadata_placeholders = _placeholder_metadata(payload, key)
            if (metadata is None) != (reference_metadata is None):
                msg = f"locale @ 元数据存在性不一致: {path}, {key}"
                raise ValueError(msg)
            if message_placeholders != reference_message:
                msg = (
                    f"locale placeholder 不一致: {path}, {key}, "
                    f"expected={sorted(reference_message)}, actual={sorted(message_placeholders)}"
                )
                raise ValueError(msg)
            if metadata_placeholders != reference_placeholders:
                msg = (
                    f"locale @ 元数据 placeholder 不一致: {path}, {key}, "
                    f"expected={reference_placeholders}, actual={metadata_placeholders}"
                )
                raise ValueError(msg)
            if _message_structure(message) != reference_structure:
                msg = f"locale ICU/HTML/换行结构不一致: {path}, {key}"
                raise ValueError(msg)

    hans = payloads[2]
    hant = payloads[3]
    for key in sorted(reference_keys):
        hans_message = str(hans[key])
        hant_message = str(hant[key])
        if _TRADITIONAL_ONLY_MARKERS.intersection(hans_message):
            msg = f"简体中文包含繁体特征字: {ARB_PATHS[2]}, {key}"
            raise ValueError(msg)
        if _SIMPLIFIED_ONLY_MARKERS.intersection(hant_message):
            msg = f"繁体中文包含简体特征字: {ARB_PATHS[3]}, {key}"
            raise ValueError(msg)
    return reference_keys


def _collect_dart_identifiers() -> set[str]:
    identifiers: set[str] = set()
    for root_name in ("lib", "test", "integration_test"):
        root = PACKAGE_ROOT / root_name
        for path in root.rglob("*.dart"):
            if path.name.endswith(".g.dart") or path.name.startswith("app_localizations"):
                continue
            source = path.read_text(encoding="utf-8")
            identifiers.update(_IDENTIFIER_PATTERN.findall(source))
    return identifiers


def _write_arb(path: Path, payload: dict[str, Any]) -> None:
    content = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    path.write_text(content, encoding="utf-8", newline="\n")


def main() -> int:
    args = _parse_args()
    payloads = [_load_arb(path) for path in ARB_PATHS]
    message_keys = _validate_payloads(payloads)
    used_identifiers = _collect_dart_identifiers()
    unused_keys = sorted(message_keys - used_identifiers)

    if unused_keys and not args.fix_unused:
        print(f"发现 {len(unused_keys)} 个未使用 ARB 消息: {', '.join(unused_keys)}")
        return 1

    if args.fix_unused:
        for payload in payloads:
            for key in unused_keys:
                payload.pop(key, None)
                payload.pop(f"@{key}", None)
        for path, payload in zip(ARB_PATHS, payloads, strict=True):
            _write_arb(path, payload)
        _validate_payloads(payloads)

    print(
        f"ARB 校验通过: locales={len(payloads)}, messages={len(message_keys) - len(unused_keys)}, "
        f"removed={len(unused_keys)}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
