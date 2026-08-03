from __future__ import annotations

import argparse
import sys
from pathlib import Path


DESKTOP_PLUGIN_TOKENS = (
    "desktop_multi_window",
    "window_manager",
    "tray_manager",
    "super_drag_and_drop",
    "super_clipboard",
    "super_native_extensions",
    "win32",
)

WINDOWS_REQUIRED_TOKENS = (
    "desktop_multi_window",
    "window_manager",
    "tray_manager",
)

DESKTOP_REQUIRED_TOKENS = (
    "desktop_multi_window",
    "window_manager",
    "tray_manager",
)

SUPER_TOKENS = (
    "super_drag_and_drop",
    "super_clipboard",
    "super_native_extensions",
)


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="ignore")


def scan_tokens(root: Path, patterns: tuple[str, ...]) -> dict[str, list[Path]]:
    hits: dict[str, list[Path]] = {token: [] for token in DESKTOP_PLUGIN_TOKENS}
    for pattern in patterns:
        for path in root.glob(pattern):
            if path.is_dir():
                continue
            text = read_text(path)
            for token in DESKTOP_PLUGIN_TOKENS:
                if token in text:
                    hits[token].append(path)
    return {token: paths for token, paths in hits.items() if paths}


def fail_with_hits(platform: str, hits: dict[str, list[Path]]) -> int:
    if not hits:
        print(f"[ok] {platform}: no desktop plugin token found")
        return 0
    print(f"[fail] {platform}: desktop plugin token found")
    for token, paths in sorted(hits.items()):
        print(f"  {token}")
        for path in paths[:8]:
            print(f"    {path}")
        if len(paths) > 8:
            print(f"    ... {len(paths) - 8} more")
    return 1


def check_android(root: Path) -> int:
    return fail_with_hits(
        "android",
        scan_tokens(
            root,
            (
                "android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java",
                "android/app/src/main/kotlin/**/GeneratedPluginRegistrant.kt",
                "build/app/intermediates/**/GeneratedPluginRegistrant.*",
                "build/app/outputs/**/*.json",
            ),
        ),
    )


def check_web(root: Path) -> int:
    return fail_with_hits(
        "web",
        scan_tokens(
            root,
            (
                "build/web/**/*.js",
                "build/web/**/*.json",
                "build/web/**/*.html",
            ),
        ),
    )


def check_ios(root: Path) -> int:
    return fail_with_hits(
        "ios",
        scan_tokens(
            root,
            (
                "ios/Runner/GeneratedPluginRegistrant.*",
                "ios/Flutter/**/*.xcfilelist",
                "build/ios/**/*.txt",
            ),
        ),
    )


def fail_with_forbidden_tokens(
    platform: str,
    text: str,
    forbidden: tuple[str, ...],
) -> int:
    found = [token for token in forbidden if token in text]
    if not found:
        return 0
    print(f"[fail] {platform}: forbidden plugin token found")
    for token in found:
        print(f"  {token}")
    return 1


def check_windows(root: Path) -> int:
    registrant = root / "windows" / "flutter" / "generated_plugin_registrant.cc"
    text = read_text(registrant)
    missing = [token for token in WINDOWS_REQUIRED_TOKENS if token not in text]
    if missing:
        print("[fail] windows: desktop plugin token missing from registrant")
        for token in missing:
            print(f"  {token}")
        return 1
    forbidden_status = fail_with_forbidden_tokens("windows", text, SUPER_TOKENS)
    if forbidden_status != 0:
        return forbidden_status
    print("[ok] windows: desktop plugins registered")
    return 0


def check_macos(root: Path) -> int:
    registrant = root / "macos" / "Flutter" / "GeneratedPluginRegistrant.swift"
    text = read_text(registrant)
    missing = [token for token in DESKTOP_REQUIRED_TOKENS if token not in text]
    if missing:
        print("[fail] macos: desktop plugin token missing from registrant")
        for token in missing:
            print(f"  {token}")
        return 1
    forbidden_status = fail_with_forbidden_tokens("macos", text, SUPER_TOKENS)
    if forbidden_status != 0:
        return forbidden_status
    print("[ok] macos: desktop plugins registered")
    return 0


def check_linux(root: Path) -> int:
    registrant = root / "linux" / "flutter" / "generated_plugin_registrant.cc"
    cmake = root / "linux" / "flutter" / "generated_plugins.cmake"
    text = read_text(registrant) + "\n" + read_text(cmake)
    missing = [token for token in DESKTOP_REQUIRED_TOKENS if token not in text]
    if missing:
        print("[fail] linux: desktop plugin token missing from registrant")
        for token in missing:
            print(f"  {token}")
        return 1
    forbidden_status = fail_with_forbidden_tokens("linux", text, SUPER_TOKENS)
    if forbidden_status != 0:
        return forbidden_status
    print("[ok] linux: desktop plugins registered")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check platform build artifacts for desktop plugin leakage.",
    )
    parser.add_argument(
        "--platform",
        choices=("android", "ios", "web", "windows", "macos", "linux", "all"),
        default="all",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    args = parser.parse_args()
    root = args.root.resolve()
    checks = {
        "android": check_android,
        "ios": check_ios,
        "web": check_web,
        "windows": check_windows,
        "macos": check_macos,
        "linux": check_linux,
    }
    selected = checks.keys() if args.platform == "all" else (args.platform,)
    status = 0
    for platform in selected:
        status |= checks[platform](root)
    return status


if __name__ == "__main__":
    sys.exit(main())
