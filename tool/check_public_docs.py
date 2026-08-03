#!/usr/bin/env python3
"""确保公开 Markdown 只包含稳定、面向用户且不泄露本机信息的内容。"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXPECTED_DOCS = {
    "getting-started.md",
    "settings.md",
    "lyrics-formats.md",
    "platforms.md",
    "troubleshooting.md",
    "privacy.md",
}
PUBLIC_MARKDOWN = {
    "README.md",
    "README.en.md",
    *(f"docs/{name}" for name in EXPECTED_DOCS),
}
PROHIBITED_TERMS = (
    ".internal_docs",
    "implementation_status",
    "GitHub Actions",
    "进行中项",
    "待办项",
    "审计记录",
    "维护者操作",
)
LOCAL_PATH_PATTERN = re.compile(r"(?:[A-Za-z]:\\|/Users/[^/]+/|/home/[^/]+/)")


def _candidate_markdown() -> set[str]:
    result = subprocess.run(
        [
            "git",
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            "*.md",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return {
        item.replace("\\", "/")
        for item in result.stdout.decode("utf-8").split("\0")
        if item
    }


def main() -> int:
    failures: list[str] = []
    docs_dir = ROOT / "docs"
    actual_docs = {path.name for path in docs_dir.glob("*.md")}
    if actual_docs - EXPECTED_DOCS:
        failures.append(
            "docs 包含未登记的公共文档: "
            f"unexpected={sorted(actual_docs - EXPECTED_DOCS)}"
        )

    candidate_markdown = _candidate_markdown()
    if candidate_markdown - PUBLIC_MARKDOWN:
        failures.append(
            "候选 Markdown 包含未登记的公共文档: "
            f"unexpected={sorted(candidate_markdown - PUBLIC_MARKDOWN)}"
        )

    # 公共文档允许在首次整理阶段暂时为空；重新编写后只允许恢复到登记集合。
    public_files = [
        path
        for path in (ROOT / "README.md", ROOT / "README.en.md")
        if path.is_file()
    ]
    public_files.extend(sorted(docs_dir.glob("*.md")))
    for path in public_files:
        if not path.is_file():
            failures.append(f"缺少公开文档: {path.relative_to(ROOT)}")
            continue
        text = path.read_text(encoding="utf-8")
        if LOCAL_PATH_PATTERN.search(text):
            failures.append(f"{path.relative_to(ROOT)} 包含本机绝对路径")
        for term in PROHIBITED_TERMS:
            if term.casefold() in text.casefold():
                failures.append(f"{path.relative_to(ROOT)} 包含内部术语: {term}")

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    print(f"public docs passed: {len(public_files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
