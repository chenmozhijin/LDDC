#!/usr/bin/env python3
"""检查发布元数据、平台标识和模板残留。"""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path

from PIL import Image

# 版本号单一真源检查复用生成脚本的推导逻辑，避免校验与生成各写一份实现。
sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_app_metadata import expected_metadata_text  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
WORKSPACE_ROOT = ROOT.parent
METADATA_PATH = ROOT / "tool" / "release_metadata.json"
APP_METADATA_PATH = ROOT / "lib" / "src" / "core" / "app_metadata.dart"


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _load_metadata() -> dict[str, str]:
    return json.loads(_read_text(METADATA_PATH))


def _failures_from_forbidden_text() -> list[str]:
    forbidden = [
        "com.example",
        "A new Flutter project.",
        "flutter create template",
        "testExample()",
        "Runner.app",
        "lddc.app",
        "signingConfigs.getByName(\"debug\")",
        "assets/tray_icon.ico",
    ]
    files = [
        ROOT / "analysis_options.yaml",
        ROOT / "pubspec.yaml",
        ROOT / "android" / "app" / "build.gradle.kts",
        ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml",
        ROOT / "android" / "app" / "src" / "debug" / "AndroidManifest.xml",
        ROOT / "android" / "app" / "src" / "profile" / "AndroidManifest.xml",
        ROOT / "android" / "gradle.properties",
        ROOT / "ios" / "Runner" / "Info.plist",
        ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj",
        ROOT
        / "ios"
        / "Runner.xcodeproj"
        / "xcshareddata"
        / "xcschemes"
        / "Runner.xcscheme",
        ROOT / "ios" / "RunnerTests" / "RunnerTests.swift",
        ROOT / "macos" / "Runner" / "Configs" / "AppInfo.xcconfig",
        ROOT / "macos" / "Runner" / "Info.plist",
        ROOT / "macos" / "Runner" / "Release.entitlements",
        ROOT / "macos" / "Runner" / "DebugProfile.entitlements",
        ROOT / "macos" / "Runner.xcodeproj" / "project.pbxproj",
        ROOT
        / "macos"
        / "Runner.xcodeproj"
        / "xcshareddata"
        / "xcschemes"
        / "Runner.xcscheme",
        ROOT / "macos" / "RunnerTests" / "RunnerTests.swift",
        ROOT / "linux" / "CMakeLists.txt",
        ROOT / "linux" / "runner" / "my_application.cc",
        ROOT / "web" / "index.html",
        ROOT / "web" / "manifest.json",
        ROOT / "windows" / "runner" / "Runner.rc",
    ]
    failures: list[str] = []
    for path in files:
        # Debug/Profile manifest 可能由 Gradle 合并流程生成；缺失时跳过文本扫描，
        # 不把可选生成文件误报成发布元数据错误。
        if not path.is_file():
            continue
        text = _read_text(path)
        for token in forbidden:
            if token in text:
                failures.append(f"{path.relative_to(ROOT)} 仍包含模板/风险文本：{token}")
    return failures


def _check_text_values(metadata: dict[str, str]) -> list[str]:
    failures: list[str] = []
    app_id = metadata["appId"]
    display_name = metadata["displayName"]
    if app_id not in _read_text(ROOT / "android" / "app" / "build.gradle.kts"):
        failures.append("Android applicationId 未使用统一 appId")
    if app_id not in _read_text(ROOT / "linux" / "CMakeLists.txt"):
        failures.append("Linux APPLICATION_ID 未使用统一 appId")
    if app_id not in _read_text(ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj"):
        failures.append("iOS Xcode project 未使用统一 appId")
    if app_id not in _read_text(ROOT / "macos" / "Runner" / "Configs" / "AppInfo.xcconfig"):
        failures.append("macOS AppInfo 未使用统一 appId")
    if display_name not in _read_text(ROOT / "web" / "manifest.json"):
        failures.append("Web manifest 未使用统一显示名")
    return failures


def _check_plist_values(metadata: dict[str, str]) -> list[str]:
    failures: list[str] = []
    app_id = metadata["appId"]
    display_name = metadata["displayName"]
    ios_info = plistlib.loads((ROOT / "ios" / "Runner" / "Info.plist").read_bytes())
    if ios_info.get("CFBundleDisplayName") != display_name:
        failures.append("iOS CFBundleDisplayName 不正确")
    if ios_info.get("CFBundleName") != display_name:
        failures.append("iOS CFBundleName 不正确")

    mac_release = plistlib.loads((ROOT / "macos" / "Runner" / "Release.entitlements").read_bytes())
    for key in [
        "com.apple.security.app-sandbox",
        "com.apple.security.network.client",
        "com.apple.security.files.user-selected.read-write",
    ]:
        if mac_release.get(key) is not True:
            failures.append(f"macOS Release.entitlements 缺少 {key}")

    ios_project = _read_text(ROOT / "ios" / "Runner.xcodeproj" / "project.pbxproj")
    if f"{app_id}.RunnerTests" not in ios_project:
        failures.append("iOS RunnerTests bundle id 未按统一 appId 派生")
    return failures


def _check_icon(path: Path, expected_size: int) -> str | None:
    if not path.is_file():
        return f"缺少图标：{path.relative_to(ROOT)}"
    with Image.open(path) as image:
        if image.size != (expected_size, expected_size):
            return f"{path.relative_to(ROOT)} 尺寸应为 {expected_size}x{expected_size}，实际为 {image.size}"
    return None


def _check_icons() -> list[str]:
    checks = [
        (ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-mdpi" / "ic_launcher.png", 48),
        (ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-hdpi" / "ic_launcher.png", 72),
        (ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-xhdpi" / "ic_launcher.png", 96),
        (ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-xxhdpi" / "ic_launcher.png", 144),
        (ROOT / "android" / "app" / "src" / "main" / "res" / "mipmap-xxxhdpi" / "ic_launcher.png", 192),
        (ROOT / "web" / "favicon.png", 32),
        (ROOT / "web" / "icons" / "Icon-192.png", 192),
        (ROOT / "web" / "icons" / "Icon-512.png", 512),
        (ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset" / "Icon-App-1024x1024@1x.png", 1024),
        (ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset" / "app_icon_1024.png", 1024),
        (ROOT / "assets" / "tray_icon.png", 256),
    ]
    failures = [failure for path, size in checks if (failure := _check_icon(path, size))]
    if not (ROOT / "windows" / "runner" / "resources" / "app_icon.ico").is_file():
        failures.append("缺少 Windows runner app_icon.ico")
    if (ROOT / "assets" / "tray_icon.ico").exists():
        failures.append("Windows 专用 .ico 不应留在 Flutter 全平台 assets 目录")
    windows_cmake = _read_text(ROOT / "windows" / "CMakeLists.txt")
    required_tray_bundle_rules = [
        "runner/resources/app_icon.ico",
        'RENAME "tray_icon.ico"',
        "FLUTTER_ASSET_DIR_NAME}/assets",
    ]
    if not all(rule in windows_cmake for rule in required_tray_bundle_rules):
        failures.append(
            "Windows 构建必须把 runner ico 复制为 flutter_assets/assets/tray_icon.ico"
        )
    return failures


def _check_android_manifest() -> list[str]:
    manifest = _read_text(ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml")
    if "android.permission.INTERNET" not in manifest:
        return ["Android main manifest 缺少 INTERNET 权限"]
    return []


def _check_version_single_source() -> list[str]:
    """校验版本号只有一个真源：pubspec.yaml。

    Dart 常量必须等于生成结果；各平台原生字段必须引用 Flutter 由 pubspec 派生的
    FLUTTER_BUILD_NAME/FLUTTER_BUILD_NUMBER，不允许出现手写字面量——否则应用显示的
    版本、系统属性里的版本和发布包文件名会互相矛盾。
    """
    failures: list[str] = []

    # 1. Dart 常量必须与 pubspec 生成结果一致（生成物漂移由 CI --check 兜底，这里双重保险）。
    expected = expected_metadata_text()
    actual = _read_text(APP_METADATA_PATH) if APP_METADATA_PATH.is_file() else ""
    if actual != expected:
        failures.append(
            "app_metadata.dart 与 pubspec.yaml 版本不一致："
            "请运行 python tool/generate_app_metadata.py"
        )

    # 2. macOS：应用与测试 target 都必须引用 Flutter 派生变量，且不得残留字面量。
    macos_project = _read_text(ROOT / "macos" / "Runner.xcodeproj" / "project.pbxproj")
    if 'MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";' not in macos_project:
        failures.append('macOS 工程缺少 MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)"')
    if 'CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";' not in macos_project:
        failures.append('macOS 工程缺少 CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"')
    if "MARKETING_VERSION = 1.0;" in macos_project or "CURRENT_PROJECT_VERSION = 1;" in macos_project:
        failures.append("macOS 工程仍存在手写的版本字面量")

    # 3. iOS：Info.plist 必须继续引用 Flutter 派生变量。
    ios_info = plistlib.loads((ROOT / "ios" / "Runner" / "Info.plist").read_bytes())
    if ios_info.get("CFBundleShortVersionString") != "$(FLUTTER_BUILD_NAME)":
        failures.append("iOS CFBundleShortVersionString 未引用 FLUTTER_BUILD_NAME")
    if ios_info.get("CFBundleVersion") != "$(FLUTTER_BUILD_NUMBER)":
        failures.append("iOS CFBundleVersion 未引用 FLUTTER_BUILD_NUMBER")

    # 4. Android：版本名/版本号必须来自 Flutter 工具链，而不是手写常量。
    gradle = _read_text(ROOT / "android" / "app" / "build.gradle.kts")
    if "versionName = flutter.versionName" not in gradle:
        failures.append("Android versionName 未使用 flutter.versionName")
    if "versionCode = flutter.versionCode" not in gradle:
        failures.append("Android versionCode 未使用 flutter.versionCode")

    return failures


def main() -> int:
    metadata = _load_metadata()
    failures = []
    failures.extend(_failures_from_forbidden_text())
    failures.extend(_check_text_values(metadata))
    failures.extend(_check_plist_values(metadata))
    failures.extend(_check_android_manifest())
    failures.extend(_check_icons())
    failures.extend(_check_version_single_source())
    if failures:
        for failure in failures:
            print(f"[FAIL] {failure}", file=sys.stderr)
        return 1
    print("发布元数据检查通过。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
