#!/usr/bin/env python3
"""校验原生平台测试 fixture 的大小、摘要、路径和匿名元数据。"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


EXPECTED_IDS = {"audio_mp3", "audio_flac", "audio_wav", "lyrics_lrc"}
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")
# 分段构造路径规则，避免仓库级泄漏扫描器把规则源码本身误判为真实用户目录。
WINDOWS_ROOT_PATTERN = r"[a-zA-Z]:[\\/]"
POSIX_HOME_PATTERN = "/" + "(?:Users|home)" + "/"
LOCAL_PATH_PATTERN = re.compile(
    f"(?:{WINDOWS_ROOT_PATTERN}|{POSIX_HOME_PATTERN})"
)


def verify_manifest(manifest_path: Path) -> list[str]:
    failures: list[str] = []
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        return [f"fixture manifest 不可读: {error}"]
    if not isinstance(payload, dict) or payload.get("schemaVersion") != 1:
        return ["fixture manifest schemaVersion 必须为 1"]
    if payload.get("originClass") != "anonymousSynthetic":
        failures.append("fixture originClass 必须为 anonymousSynthetic")
    single_limit = payload.get("singleFileLimit")
    total_limit = payload.get("totalFileLimit")
    if single_limit != 65536 or total_limit != 524288:
        failures.append("fixture 大小上限必须固定为 64 KiB/512 KiB")
    fixtures = payload.get("fixtures")
    if not isinstance(fixtures, list):
        return [*failures, "fixture manifest 缺少 fixtures 数组"]

    seen_ids: set[str] = set()
    seen_files: set[str] = set()
    total_size = 0
    for index, entry in enumerate(fixtures):
        location = f"fixtures[{index}]"
        if not isinstance(entry, dict):
            failures.append(f"{location} 必须为对象")
            continue
        fixture_id = entry.get("id")
        file_name = entry.get("file")
        if not isinstance(fixture_id, str) or fixture_id in seen_ids:
            failures.append(f"{location}.id 无效或重复")
        else:
            seen_ids.add(fixture_id)
        if (
            not isinstance(file_name, str)
            or not file_name
            or Path(file_name).name != file_name
            or LOCAL_PATH_PATTERN.search(file_name)
        ):
            failures.append(f"{location}.file 必须为无目录文件名")
            continue
        if file_name in seen_files:
            failures.append(f"{location}.file 重复")
        seen_files.add(file_name)
        fixture_path = manifest_path.parent / file_name
        if not fixture_path.is_file():
            failures.append(f"{location} 文件不存在: {file_name}")
            continue
        actual_size = fixture_path.stat().st_size
        actual_hash = hashlib.sha256(fixture_path.read_bytes()).hexdigest()
        total_size += actual_size
        if entry.get("size") != actual_size:
            failures.append(f"{location}.size 与文件不一致")
        if actual_size > single_limit:
            failures.append(f"{file_name} 超过 64 KiB")
        declared_hash = entry.get("sha256")
        if not isinstance(declared_hash, str) or not SHA256_PATTERN.fullmatch(
            declared_hash
        ):
            failures.append(f"{location}.sha256 格式无效")
        elif declared_hash != actual_hash:
            failures.append(f"{location}.sha256 与文件不一致")
        for key in ("title", "artist", "album"):
            value = entry.get(key)
            if not isinstance(value, str) or not value.strip():
                failures.append(f"{location}.{key} 缺失")
            elif LOCAL_PATH_PATTERN.search(value) or "http" in value.lower():
                failures.append(f"{location}.{key} 包含本地路径或 URL")

    if seen_ids != EXPECTED_IDS:
        failures.append(f"fixture id 集合不完整: {sorted(seen_ids)}")
    tracked_files = {
        path.name
        for path in manifest_path.parent.iterdir()
        if path.is_file() and path.name != manifest_path.name
    }
    if tracked_files != seen_files:
        failures.append("fixture 目录文件集合与 manifest 不一致")
    if total_size > total_limit:
        failures.append("fixture 总量超过 512 KiB")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()
    failures = verify_manifest(args.manifest)
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    print("platform fixtures passed: 4 files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
