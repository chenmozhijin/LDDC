#!/usr/bin/env python3
"""检查候选 Git 文件，阻止缓存、密钥、本机路径和用户数据进入仓库。"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
FORBIDDEN_PARTS = {
    ".dart_tool",
    ".internal_docs",
    ".gradle",
    ".idea",
    "build",
    "coverage",
    "Pods",
    "test-results",
    "reports",
    "screenshots",
    "tmp",
}
FORBIDDEN_SUFFIXES = {
    ".log",
    ".pid",
    ".key",
    ".p12",
    ".pfx",
    ".jks",
    ".keystore",
    ".pem",
}
TEXT_SUFFIXES = {
    ".dart",
    ".kt",
    ".swift",
    ".cpp",
    ".cc",
    ".h",
    ".py",
    ".ps1",
    ".sh",
    ".yaml",
    ".yml",
    ".json",
    ".arb",
    ".md",
    ".txt",
    ".xml",
    ".gradle",
    ".kts",
}
LOCAL_PATH_PATTERN = re.compile(r"(?:[A-Za-z]:\\(?:Users|yy)\\|/Users/[^/]+/|/home/[^/]+/)")
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{24,}\b"),
)
ACTION_USES_PATTERN = re.compile(r"^\s*(?:-\s*)?uses:\s*([^\s#]+)", re.MULTILINE)
STABLE_MAJOR_ACTION_PATTERN = re.compile(r"^[^@\s]+@v[1-9][0-9]*$")
PYTHON_VECTOR_REFERENCE_PATTERN = re.compile(
    r"python_[a-z0-9_]*vectors\.json", re.IGNORECASE
)
PYTHON_VECTOR_ARTIFACT_PATTERNS = (
    re.compile(r"python_[a-z0-9_]*vectors\.json", re.IGNORECASE),
    re.compile(r"generate_[a-z0-9_]*vectors\.py", re.IGNORECASE),
    re.compile(r"[a-z0-9_]*vector_harness\.dart", re.IGNORECASE),
)
RUBY_VECTOR_ALLOWLIST = {
    "lddc/tool/generate_ruby_vectors.py",
    "packages/lddc_lyrics_core/test/resources/ruby/python_ruby_vectors.json",
    "packages/lddc_lyrics_core/test/ruby/ruby_engine_vector_test.dart",
    "packages/lddc_lyrics_core/test/support/ruby/ruby_vector_harness.dart",
}
SANITIZED_FIXTURE_SINGLE_LIMIT = 64 * 1024
SANITIZED_FIXTURE_TOTAL_LIMIT = 512 * 1024
BROAD_DATABASE_IGNORE_PATTERNS = {
    "*.db",
    "*.sqlite",
    "*.sqlite3",
    "**/*.db",
    "**/*.sqlite",
    "**/*.sqlite3",
}
SANITIZED_FIXTURE_FORBIDDEN_KEYS = {
    "accesskey",
    "authorization",
    "cookie",
    "deviceid",
    "fingerprint",
    "imei",
    "mid",
    "path",
    "qimei",
    "query",
    "requestbody",
    "requesturl",
    "songid",
    "token",
    "url",
}
URL_PATTERN = re.compile(r"https?://", re.IGNORECASE)
CONTENT_ALLOWLIST = {
    "lddc/test/infra/storage/app_storage_paths_io_test.dart": (
        "C:\\Users\\Test",
        "/home/tester",
    ),
    "packages/lddc_lyrics_runtime/lib/src/api/translate/google_request_executor.dart": (
        "AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520",
    ),
    "packages/lddc_lyrics_runtime/test/translate/translate_request_executors_test.dart": (
        "AIzaSy123456789012345678901234567890123",
    ),
}
SELF_SCANNING_TOOLS = {
    "tool/check_git_hygiene.py",
    "tool/check_public_docs.py",
    "tool/test/test_quality_tools.py",
}


def candidate_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return sorted({item for item in result.stdout.decode("utf-8").split("\0") if item})


def invalid_action_references(text: str) -> list[str]:
    references: list[str] = []
    for reference in ACTION_USES_PATTERN.findall(text):
        # 本地 Action 由当前提交本身固定；docker URI 不属于 GitHub Action
        # 仓库引用。其他外部引用统一使用可读的稳定大版本标签，补丁更新由
        # 上游维护该标签，跨大版本升级由维护者显式审查。
        if reference.startswith(("./", "docker://")):
            continue
        if not STABLE_MAJOR_ACTION_PATTERN.fullmatch(reference):
            references.append(reference)
    return references


def broad_database_ignore_patterns(text: str) -> list[str]:
    """拒绝会把合法测试数据库 fixture 一并隐藏的宽泛忽略规则。"""
    patterns: list[str] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("!"):
            continue
        if line in BROAD_DATABASE_IGNORE_PATTERNS:
            patterns.append(line)
    return sorted(set(patterns))


def invalid_python_vector_artifacts(files: list[str]) -> list[str]:
    """只允许 Ruby 保留 Python 同步基线及其专用测试基础设施。"""
    failures: list[str] = []
    for relative in files:
        normalized = relative.replace("\\", "/")
        if normalized in RUBY_VECTOR_ALLOWLIST:
            continue
        name = Path(normalized).name
        if any(pattern.fullmatch(name) for pattern in PYTHON_VECTOR_ARTIFACT_PATTERNS):
            failures.append(normalized)
    return sorted(failures)


def invalid_python_vector_references(relative: str, text: str) -> list[str]:
    normalized = relative.replace("\\", "/")
    if normalized in RUBY_VECTOR_ALLOWLIST:
        return []
    return sorted(set(PYTHON_VECTOR_REFERENCE_PATTERN.findall(text)))


def sanitized_fixture_failures(relative: str, path: Path) -> list[str]:
    """校验可提交的脱敏真实结构，避免来源信息和大型正文混入仓库。"""
    if not path.name.startswith("sanitized_") or path.suffix != ".json":
        return []
    failures: list[str] = []
    if path.stat().st_size > SANITIZED_FIXTURE_SINGLE_LIMIT:
        failures.append(
            f"脱敏 fixture 超过 {SANITIZED_FIXTURE_SINGLE_LIMIT} 字节: {relative}"
        )
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        return [f"脱敏 fixture 不是合法 UTF-8 JSON: {relative}: {error}"]
    if not isinstance(payload, dict) or not isinstance(payload.get("cases"), list):
        failures.append(f"脱敏 fixture 缺少 cases 数组: {relative}")
        return failures

    def inspect(value: object, location: str) -> None:
        if isinstance(value, dict):
            for raw_key, child in value.items():
                key = str(raw_key)
                normalized_key = re.sub(r"[^a-z0-9]", "", key.lower())
                if normalized_key in SANITIZED_FIXTURE_FORBIDDEN_KEYS:
                    failures.append(
                        f"脱敏 fixture 包含禁止字段 {key}: {relative}:{location}"
                    )
                if key == "lyrics" and isinstance(child, dict):
                    total_lines = sum(
                        len(lines) for lines in child.values() if isinstance(lines, list)
                    )
                    if total_lines > 32:
                        failures.append(
                            f"脱敏 fixture 歌词行数超过 32: {relative}:{location}"
                        )
                    for language, lines in child.items():
                        if isinstance(lines, list) and len(lines) > 8:
                            failures.append(
                                f"脱敏 fixture 单语言超过 8 行: "
                                f"{relative}:{location}.{language}"
                            )
                inspect(child, f"{location}.{key}")
            return
        if isinstance(value, list):
            for index, child in enumerate(value):
                inspect(child, f"{location}[{index}]")
            return
        if isinstance(value, str):
            if len(value) > 4096:
                failures.append(f"脱敏 fixture 单字段文本过长: {relative}:{location}")
            if LOCAL_PATH_PATTERN.search(value) or URL_PATTERN.search(value):
                failures.append(f"脱敏 fixture 包含路径或 URL: {relative}:{location}")

    cases = payload["cases"]
    if not cases:
        failures.append(f"脱敏 fixture cases 不能为空: {relative}")
    for index, item in enumerate(cases):
        if not isinstance(item, dict):
            failures.append(f"脱敏 fixture case 不是对象: {relative}:cases[{index}]")
            continue
        origin_class = item.get("originClass")
        if not isinstance(origin_class, str) or not origin_class.startswith("sanitized-"):
            failures.append(
                f"脱敏 fixture case 缺少匿名 originClass: {relative}:cases[{index}]"
            )
        inspect(item, f"cases[{index}]")
    return failures


def main() -> int:
    failures: list[str] = []
    files = candidate_files()
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    for pattern in broad_database_ignore_patterns(gitignore):
        failures.append(
            "数据库忽略规则过宽，会隐藏 test/data fixture: " f"{pattern}"
        )
    for relative in invalid_python_vector_artifacts(files):
        failures.append(f"除 Ruby 外禁止保留 Python vector 产物: {relative}")
    sanitized_total = sum(
        (ROOT / relative).stat().st_size
        for relative in files
        if Path(relative).name.startswith("sanitized_")
        and Path(relative).suffix == ".json"
        and (ROOT / relative).is_file()
    )
    if sanitized_total > SANITIZED_FIXTURE_TOTAL_LIMIT:
        failures.append(
            f"脱敏 fixture 总量超过 {SANITIZED_FIXTURE_TOTAL_LIMIT} 字节: "
            f"actual={sanitized_total}"
        )
    for relative in files:
        path = ROOT / relative
        parts = set(Path(relative).parts)
        if parts & FORBIDDEN_PARTS:
            failures.append(f"禁止目录进入候选文件: {relative}")
            continue
        if path.suffix in FORBIDDEN_SUFFIXES or path.name.startswith(".env"):
            failures.append(f"本地配置或密钥文件进入候选文件: {relative}")
            continue
        if path.name in {"key.properties", "local.properties"}:
            failures.append(f"本地平台配置进入候选文件: {relative}")
            continue
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES or path.stat().st_size > 2_000_000:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            failures.append(f"文本扩展名文件不是 UTF-8: {relative}")
            continue
        for allowed_value in CONTENT_ALLOWLIST.get(relative, ()):
            text = text.replace(allowed_value, "<allowed-fixture>")
        if relative in SELF_SCANNING_TOOLS:
            continue
        for reference in invalid_python_vector_references(relative, text):
            failures.append(f"除 Ruby 外禁止引用 Python vector: {relative}: {reference}")
        failures.extend(sanitized_fixture_failures(relative, path))
        if LOCAL_PATH_PATTERN.search(text):
            failures.append(f"候选文本包含本机绝对路径: {relative}")
        if any(pattern.search(text) for pattern in SECRET_PATTERNS):
            failures.append(f"候选文本疑似包含密钥: {relative}")
        if relative.startswith(".github/workflows/"):
            for reference in invalid_action_references(text):
                failures.append(
                    f"GitHub Action 未使用稳定大版本标签: {relative}: {reference}"
                )
        if any(line.endswith((" ", "\t")) for line in text.splitlines()):
            failures.append(f"候选文本包含行尾空白: {relative}")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    print(f"git hygiene passed: {len(files)} candidate files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
