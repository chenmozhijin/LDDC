#!/usr/bin/env python3
"""检查三个桌面原生启动器的首选和最小 Flutter 内容区是否一致。"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXPECTED = (1280, 720)
EXPECTED_MINIMUM = (960, 540)


def _extract(path: Path, width_pattern: str, height_pattern: str) -> tuple[int, int]:
    text = path.read_text(encoding="utf-8")
    width_match = re.search(width_pattern, text)
    height_match = re.search(height_pattern, text)
    if width_match is None or height_match is None:
        raise ValueError(f"无法解析桌面窗口契约: {path.relative_to(ROOT)}")
    return int(width_match.group(1)), int(height_match.group(1))


def contract_values() -> tuple[
    dict[str, tuple[int, int]], dict[str, tuple[int, int]]
]:
    values = {
        "windows": _extract(
            ROOT / "lddc/windows/runner/desktop_window_contract.h",
            r"kPreferredMainWindowContentWidth\s*=\s*(\d+)",
            r"kPreferredMainWindowContentHeight\s*=\s*(\d+)",
        ),
        "linux": _extract(
            ROOT / "lddc/linux/runner/my_application.cc",
            r"kPreferredMainWindowContentWidth\s*=\s*(\d+)",
            r"kPreferredMainWindowContentHeight\s*=\s*(\d+)",
        ),
        "macos-swift": _extract(
            ROOT / "lddc/macos/Runner/MainFlutterWindow.swift",
            r"preferredContentSize\s*=\s*NSSize\(width:\s*(\d+)",
            r"preferredContentSize\s*=\s*NSSize\([^\n]+height:\s*(\d+)\)",
        ),
        "macos-xib": _extract(
            ROOT / "lddc/macos/Runner/Base.lproj/MainMenu.xib",
            r'<rect key="contentRect"[^>]+width="(\d+)"',
            r'<rect key="contentRect"[^>]+height="(\d+)"',
        ),
    }
    minimum_values = {
        "windows": _extract(
            ROOT / "lddc/windows/runner/desktop_window_contract.h",
            r"kMinimumMainWindowContentWidth\s*=\s*(\d+)",
            r"kMinimumMainWindowContentHeight\s*=\s*(\d+)",
        ),
        "linux": _extract(
            ROOT / "lddc/linux/runner/my_application.cc",
            r"kMinimumMainWindowContentWidth\s*=\s*(\d+)",
            r"kMinimumMainWindowContentHeight\s*=\s*(\d+)",
        ),
        "macos-swift": _extract(
            ROOT / "lddc/macos/Runner/MainFlutterWindow.swift",
            r"minimumContentSize\s*=\s*NSSize\(width:\s*(\d+)",
            r"minimumContentSize\s*=\s*NSSize\([^\n]+height:\s*(\d+)\)",
        ),
    }
    return values, minimum_values


def main() -> int:
    try:
        values, minimum_values = contract_values()
    except (OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    failures = [
        f"{platform}={size[0]}x{size[1]}"
        for platform, size in values.items()
        if size != EXPECTED
    ]
    if failures:
        print(
            "ERROR: 桌面窗口契约不一致，预期 1280x720: " + ", ".join(failures),
            file=sys.stderr,
        )
        return 1
    minimum_failures = [
        f"{platform}={size[0]}x{size[1]}"
        for platform, size in minimum_values.items()
        if size != EXPECTED_MINIMUM
    ]
    if minimum_failures:
        print(
            "ERROR: 桌面最小窗口契约不一致，预期 960x540: "
            + ", ".join(minimum_failures),
            file=sys.stderr,
        )
        return 1
    print(
        "desktop window contract passed: "
        f"preferred={len(values)} definitions 1280x720, "
        f"minimum={len(minimum_values)} definitions 960x540"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
