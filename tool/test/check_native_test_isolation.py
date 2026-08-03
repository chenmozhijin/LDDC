#!/usr/bin/env python3
"""静态校验原生 UI 测试依赖与发布配置隔离。"""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _balanced_openstep(text: str) -> bool:
    braces = 0
    in_string = False
    escaped = False
    for character in text:
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "{":
            braces += 1
        elif character == "}":
            braces -= 1
            if braces < 0:
                return False
    return braces == 0 and not in_string


def failures() -> list[str]:
    problems: list[str] = []
    pubspec = (ROOT / "lddc/pubspec.yaml").read_text(encoding="utf-8")
    lockfile = (ROOT / "pubspec.lock").read_text(encoding="utf-8")
    if re.search(r"(?m)^\s*(?:patrol|maestro)\s*:", pubspec):
        problems.append("pubspec 禁止 Patrol/Maestro 依赖")
    if re.search(r"(?m)^\s{2}(?:patrol|maestro)\s*:", lockfile):
        problems.append("lockfile 禁止 Patrol/Maestro 包")
    if (ROOT / "lddc/patrol_test").exists() or (ROOT / "lddc/maestro").exists():
        problems.append("仓库残留 Patrol/Maestro 测试目录")

    gradle = (ROOT / "lddc/android/app/build.gradle.kts").read_text(encoding="utf-8")
    for dependency in (
        'androidTestImplementation("androidx.test:core:1.7.0")',
        'androidTestImplementation("androidx.test:runner:1.7.0")',
        'androidTestImplementation("androidx.test:rules:1.7.0")',
        'androidTestImplementation("androidx.test.uiautomator:uiautomator:2.4.0")',
        'androidTestUtil("androidx.test:orchestrator:1.6.1")',
    ):
        if dependency not in gradle:
            problems.append(f"Android 测试依赖未锁定: {dependency}")
    if 'name == "debugRuntimeClasspath"' not in gradle or "releaseRuntimeClasspath" in gradle:
        problems.append("Android runner 对齐必须只作用于 Debug/AndroidTest")
    root_gradle = (ROOT / "lddc/android/build.gradle.kts").read_text(encoding="utf-8")
    for marker in (
        'project.name == "integration_test"',
        'val apiConfiguration = configurations.getByName("api")',
        'dependency.group?.startsWith("androidx.test") == true',
        "misplacedTestDependencies.forEach(apiConfiguration.dependencies::remove)",
        'name == "debugCompileClasspath"',
        'dependencies.add("compileOnly", "androidx.test:runner:1.7.0")',
        'dependencies.add("compileOnly", "androidx.test:rules:1.7.0")',
        'dependencies.add("compileOnly", "androidx.test.espresso:espresso-core:3.7.0")',
    ):
        if marker not in root_gradle:
            problems.append(f"integration_test 测试依赖未与主 APK 隔离: {marker}")
    if "releaseCompileClasspath" in root_gradle or "releaseRuntimeClasspath" in root_gradle:
        problems.append("integration_test runner 固定不得触及 Release 配置")
    android_platform_test = (
        ROOT
        / "lddc/android/app/src/androidTest/kotlin/com/cmzj/lddc/"
        "DocumentsUiPlatformPocTest.kt"
    ).read_text(encoding="utf-8")
    android_activity = (
        ROOT / "lddc/android/app/src/main/kotlin/com/cmzj/lddc/MainActivity.kt"
    ).read_text(encoding="utf-8")
    android_fd_handler = (
        ROOT
        / "lddc/android/app/src/main/kotlin/com/cmzj/lddc/"
        "SafFileDescriptorChannelHandler.kt"
    ).read_text(encoding="utf-8")
    android_picker_registry = (
        ROOT
        / "lddc/android/app/src/main/kotlin/com/cmzj/lddc/"
        "PickerPendingRequestRegistry.kt"
    ).read_text(encoding="utf-8")
    android_fd_tests = (
        ROOT
        / "lddc/android/app/src/test/kotlin/com/cmzj/lddc/"
        "SafFileDescriptorChannelHandlerTest.kt"
    ).read_text(encoding="utf-8")
    android_picker_tests = (
        ROOT
        / "lddc/android/app/src/test/kotlin/com/cmzj/lddc/"
        "PickerPendingRequestRegistryTest.kt"
    ).read_text(encoding="utf-8")
    for marker in (
        "SafFileDescriptorChannelHandler(",
        "AndroidSafFileDescriptorGateway(contentResolver, ::queryDisplayName)",
        "PickerPendingRequestRegistry()",
        "pendingPickers.completeDestroyedRequests()",
    ):
        if marker not in android_activity:
            problems.append(f"Android MainActivity 缺少生产通道委托: {marker}")
    for marker in (
        'result.error("permission_denied"',
        'result.error("file_not_found"',
        'result.error("fd_registry_conflict"',
        "ownedFileDescriptors.closeAll()",
    ):
        if marker not in android_fd_handler:
            problems.append(f"Android SAF fd handler 缺少错误/资源边界: {marker}")
    for marker in ('result.error("busy"', 'result.error("activity_destroyed"'):
        if marker not in android_picker_registry:
            problems.append(f"Android picker registry 缺少状态错误映射: {marker}")
    for marker in (
        '"permission_denied"',
        '"file_not_found"',
        '"fd_registry_conflict"',
    ):
        if marker not in android_fd_tests:
            problems.append(f"Android SAF fd 单测缺少错误断言: {marker}")
    for marker in ('"busy"', '"activity_destroyed"', "throwOnError = true"):
        if marker not in android_picker_tests:
            problems.append(f"Android picker 单测缺少状态断言: {marker}")
    for marker in (
        "saf_fd_taglib_read_embedded_lyrics",
        "saf_read_write_fd_tag_saved",
        "saved_tag_reopened_after_activity_recreation",
        "recordSelectedArtifact()",
        "documentsUiSavesLyricsAndReadsBackRealOutput",
        "documentsui_create_document",
        "documentsUiPersistsAndReleasesTreePermission",
        "pick_tree_and_persist_permission_round_trip",
        "saf_fd_permission_denied",
        "saf_fd_file_not_found",
        "METHOD_GRANT_MISSING_AUDIO",
        "METHOD_REVOKE_URI",
    ):
        if marker not in android_platform_test:
            problems.append(f"Android 原生媒体读写场景缺少: {marker}")

    release_plist = (ROOT / "lddc/ios/Runner/Info.plist").read_text(encoding="utf-8")
    test_plist = (ROOT / "lddc/ios/RunnerPlatformTests-Info.plist").read_text(
        encoding="utf-8"
    )
    if "UIFileSharingEnabled" in release_plist:
        problems.append("iOS Release Info.plist 禁止测试文件共享配置")
    if "UIFileSharingEnabled" not in test_plist:
        problems.append("iOS PlatformTest Info.plist 缺少文件共享配置")
    try:
        ET.parse(ROOT / "lddc/ios/Runner/Info.plist")
        ET.parse(ROOT / "lddc/ios/RunnerPlatformTests-Info.plist")
        scheme = ET.parse(
            ROOT
            / "lddc/ios/Runner.xcodeproj/xcshareddata/xcschemes/RunnerPlatformTests.xcscheme"
        )
        test_action = scheme.getroot().find("TestAction")
        if test_action is None or test_action.get("buildConfiguration") != "PlatformTest":
            problems.append("iOS UI scheme 必须使用 PlatformTest 配置")
        testable = scheme.getroot().find(".//TestableReference")
        if testable is None or testable.get("parallelizable") != "NO":
            problems.append("iOS UI tests 必须禁用并行执行")
    except ET.ParseError as error:
        problems.append(f"iOS plist/scheme XML 无效: {error}")

    project = (ROOT / "lddc/ios/Runner.xcodeproj/project.pbxproj").read_text(
        encoding="utf-8"
    )
    if not _balanced_openstep(project):
        problems.append("iOS project.pbxproj 花括号或字符串不平衡")
    for marker in (
        'name = RunnerUITests;',
        'productType = "com.apple.product-type.bundle.ui-testing";',
        'INFOPLIST_FILE = "RunnerPlatformTests-Info.plist";',
        "PRODUCT_BUNDLE_IDENTIFIER = com.cmzj.lddc.platformtests;",
    ):
        if marker not in project:
            problems.append(f"iOS PlatformTest 工程缺少: {marker}")
    if project.count('INFOPLIST_FILE = "RunnerPlatformTests-Info.plist";') != 1:
        problems.append("测试 Info.plist 只能由单一 PlatformTest app 配置引用")
    ios_ui_test = (ROOT / "lddc/ios/RunnerUITests/RunnerUITests.swift").read_text(
        encoding="utf-8"
    )
    ios_app_delegate = (ROOT / "lddc/ios/Runner/AppDelegate.swift").read_text(
        encoding="utf-8"
    )
    ios_unit_tests = (ROOT / "lddc/ios/RunnerTests/RunnerTests.swift").read_text(
        encoding="utf-8"
    )
    for marker in (
        "security_scoped_fd_read_embedded_lyrics",
        "read_write_fd_tag_saved",
        "saved_tag_reopened_after_app_restart",
        "openLyricsSaveTagSucceeded",
    ):
        if marker not in ios_ui_test and marker not in (
            ROOT / "lddc/lib/src/core/accessibility/app_action_semantics.dart"
        ).read_text(encoding="utf-8"):
            problems.append(f"iOS 原生媒体读写场景缺少: {marker}")
    for marker in (
        "final class IOSOpenedAudioFileRegistry",
        "openedFiles.close(fileDescriptor: fileDescriptor)",
        "openedFiles.closeAll()",
        "fd_registry_conflict",
        "final class IOSPendingExportFileStore",
        "pendingExportFileStore.cleanupStaleExports()",
    ):
        if marker not in ios_app_delegate:
            problems.append(f"iOS fd 所有权注册表缺少: {marker}")
    for marker in (
        "testOpenedAudioFileRegistryClosesOwnedDescriptorsIdempotently",
        "testOpenedAudioFileRegistryCloseAllReleasesEveryDescriptor",
        "Darwin.fcntl",
        "testPendingExportStorePreservesUserFileNameAndCleansUniqueDirectory",
        "testPendingExportStoreRemovesStaleFilesAtNextLaunch",
    ):
        if marker not in ios_unit_tests:
            problems.append(f"iOS fd 注册表单测缺少: {marker}")
    for marker in (
        "testDocumentPickerExportsLyricsFile",
        "testDocumentPickerExportCancellationCleansTemporaryFile",
        "testTerminatedExportIsCleanedOnNextLaunch",
        "stale_export_removed_on_next_launch",
    ):
        if marker not in ios_ui_test:
            problems.append(f"iOS 导出与清理场景缺少: {marker}")

    capability_matrix = json.loads(
        (ROOT / "tool/test/platform_capability_matrix.json").read_text(encoding="utf-8")
    )
    matrix_scenarios = {
        (contract.get("platform"), contract.get("scenario"))
        for contract in capability_matrix.get("contracts", [])
        if isinstance(contract, dict)
    }
    android_runner = (ROOT / "tool/test/run_android_platform_tests.ps1").read_text(
        encoding="utf-8"
    )
    ios_runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
        encoding="utf-8"
    )
    for platform, source, runner, scenarios in (
        (
            "android",
            android_platform_test,
            android_runner,
            (
                "android_documentsui_select",
                "android_documentsui_cancel",
                "android_documentsui_save",
                "android_documentsui_tree",
                "android_documentsui_lifecycle",
            ),
        ),
        (
            "ios",
            ios_ui_test,
            ios_runner,
            (
                "ios_document_picker_select",
                "ios_document_picker_cancel",
                "ios_document_picker_export",
                "ios_document_picker_export_cancel",
                "ios_document_picker_export_termination",
            ),
        ),
    ):
        for scenario in scenarios:
            if scenario not in source:
                problems.append(f"{platform} 原生测试缺少场景名: {scenario}")
            if scenario not in runner:
                problems.append(f"{platform} runner 缺少场景: {scenario}")
            if (platform, scenario) not in matrix_scenarios:
                problems.append(f"{platform} 能力矩阵缺少场景: {scenario}")

    macos_project = (ROOT / "lddc/macos/Runner.xcodeproj/project.pbxproj").read_text(
        encoding="utf-8"
    )
    if not _balanced_openstep(macos_project):
        problems.append("macOS project.pbxproj 花括号或字符串不平衡")
    for marker in (
        'name = RunnerUITests;',
        'productType = "com.apple.product-type.bundle.ui-testing";',
        "PRODUCT_BUNDLE_IDENTIFIER = com.cmzj.lddc.RunnerUITests;",
    ):
        if marker not in macos_project:
            problems.append(f"macOS UI 测试工程缺少: {marker}")
    try:
        macos_scheme = ET.parse(
            ROOT
            / "lddc/macos/Runner.xcodeproj/xcshareddata/xcschemes/RunnerPlatformTests.xcscheme"
        )
        testable = macos_scheme.getroot().find(".//TestableReference")
        if testable is None or testable.get("parallelizable") != "NO":
            problems.append("macOS UI tests 必须禁用并行执行")
    except ET.ParseError as error:
        problems.append(f"macOS UI scheme XML 无效: {error}")
    macos_release_entitlements = (
        ROOT / "lddc/macos/Runner/Release.entitlements"
    ).read_text(encoding="utf-8")
    if "com.apple.security.network.server" not in macos_release_entitlements:
        problems.append("macOS Release 缺少桌面歌词 loopback 服务监听权限")
    if "com.apple.security.cs.allow-jit" in macos_release_entitlements:
        problems.append("macOS Release 禁止携带 Debug JIT 权限")

    windows_project = (
        ROOT / "lddc/windows/RunnerPlatformTests/RunnerPlatformTests.csproj"
    ).read_text(encoding="utf-8")
    for dependency in (
        '<PackageReference Include="FlaUI.Core" Version="5.0.0" />',
        '<PackageReference Include="FlaUI.UIA3" Version="5.0.0" />',
    ):
        if dependency not in windows_project:
            problems.append(f"Windows UI 测试依赖未锁定: {dependency}")
    windows_lock = json.loads(
        (ROOT / "lddc/windows/RunnerPlatformTests/packages.lock.json").read_text(
            encoding="utf-8"
        )
    )
    target_dependencies = next(iter(windows_lock.get("dependencies", {}).values()), {})
    for package in ("FlaUI.Core", "FlaUI.UIA3"):
        state = target_dependencies.get(package, {})
        if state.get("resolved") != "5.0.0" or not state.get("contentHash"):
            problems.append(f"Windows NuGet lock 未固定 {package}=5.0.0")
    windows_cmake = (ROOT / "lddc/windows/CMakeLists.txt").read_text(encoding="utf-8")
    if "RunnerPlatformTests" in windows_cmake or "FlaUI" in windows_cmake:
        problems.append("Windows Release CMake 禁止引用 FlaUI 测试项目")
    windows_test = (
        ROOT / "lddc/windows/RunnerPlatformTests/FileDialogPlatformTests.cs"
    ).read_text(encoding="utf-8")
    for forbidden in (
        "Application.Launch",
        "Keyboard.",
        "NavigateToOpenLyrics",
        "LDDC_WINDOWS_APP_EXE",
    ):
        if forbidden in windows_test:
            problems.append(f"Windows FlaUI 禁止驱动 Flutter 应用控件: {forbidden}")
    for required in (
        'HybridFramework = "integration_test+flaui-uia3"',
        'ControlType.Edit',
        'ControlType.Button',
        'WindowsPlatformTestEnvironment.Required("LDDC_NATIVE_SYNC_DIR")',
    ):
        if required not in windows_test:
            problems.append(f"Windows FlaUI 缺少原生对话框边界约束: {required}")
    windows_flutter_test = (
        ROOT / "lddc/integration_test/windows_file_dialog_platform_test.dart"
    ).read_text(encoding="utf-8")
    for required in (
        "useRealFilePicker: true",
        "LDDC_WINDOWS_NATIVE_SYNC_DIR",
        "file_selector_selection_returned_to_flutter",
        "file_selector_cancel_and_reopen_returned_to_flutter",
    ):
        if required not in windows_flutter_test:
            problems.append(f"Windows Flutter 平台场景缺少真实边界断言: {required}")
    windows_runner = (ROOT / "tool/test/run_windows_platform_tests.ps1").read_text(
        encoding="utf-8"
    )
    for required in (
        "integration_test+flaui-uia3",
        "windows_file_dialog_platform_test.dart",
        "LDDC_IT_WORKSPACE_ROOT",
        "LDDC_WINDOWS_NATIVE_SYNC_DIR",
        "Assert-PassingTrx",
    ):
        if required not in windows_runner:
            problems.append(f"Windows hybrid runner 缺少协同门禁: {required}")
    for forbidden in ("$env:APPDATA =", "$env:LOCALAPPDATA =", "$env:TEMP ="):
        if forbidden in windows_runner:
            problems.append(f"Windows hybrid runner 禁止改写 Flutter 工具环境: {forbidden}")

    linux_requirement = (
        ROOT / "tool/test/requirements-linux-platform.txt"
    ).read_text(encoding="utf-8").strip()
    expected_dogtail = (
        "dogtail==2.0.4 "
        "--hash=sha256:d477989b46c97fdef9df683b4bd750bc4529f15742a8b97886bbbfa6cdb8e02c"
    )
    if linux_requirement != expected_dogtail:
        problems.append("Linux Dogtail 必须固定为 2.0.4 并校验官方 wheel SHA-256")
    linux_cmake = (ROOT / "lddc/linux/CMakeLists.txt").read_text(encoding="utf-8")
    if "platform_tests" in linux_cmake or "dogtail" in linux_cmake.lower():
        problems.append("Linux Release CMake 禁止引用 Dogtail 测试代码")

    workflow_dir = ROOT / ".github/workflows"
    expected_workflows = {
        "code-quality.yml": (
            "name: Code Quality",
            ("static-and-unit:",),
        ),
        "cross-platform-validation.yml": (
            "name: Cross-Platform Validation",
            (
                "windows-validation:",
                "macos-validation:",
                "linux-validation:",
                "android-validation:",
                "ios-validation:",
                "experimental-web:",
            ),
        ),
        "performance-regression.yml": (
            "name: Performance and Resource Regression",
            (
                "algorithm-benchmarks:",
                "desktop-resource-stress:",
                "media-resource-stress:",
            ),
        ),
        "lyrics-service-compatibility.yml": (
            "name: Lyrics Service Compatibility",
            ("lyrics-service-compatibility:",),
        ),
    }
    actual_workflows = {path.name for path in workflow_dir.glob("*.yml")}
    if actual_workflows != set(expected_workflows):
        problems.append(
            "CI workflow 集合必须严格保持四项职责分层: "
            f"actual={sorted(actual_workflows)}"
        )
    for filename, (display_name, jobs) in expected_workflows.items():
        path = workflow_dir / filename
        if not path.is_file():
            continue
        source = path.read_text(encoding="utf-8")
        if display_name not in source:
            problems.append(f"{filename} 缺少固定显示名: {display_name}")
        for job in jobs:
            if f"  {job}" not in source:
                problems.append(f"{filename} 缺少固定 job: {job}")
        if "schedule:" in source or "cron:" in source:
            problems.append(f"{filename} 禁止定时触发")

    workflow = (workflow_dir / "cross-platform-validation.yml").read_text(
        encoding="utf-8"
    )
    protocol_pubspec = (
        ROOT / "packages/lddc_desktop_protocol/pubspec.yaml"
    ).read_text(encoding="utf-8")
    if re.search(r"(?m)^\s+(?:flutter|dart_taglib|native_assets_cli):", protocol_pubspec):
        problems.append("桌面 IPC 协议包禁止依赖 Flutter 或 native asset")
    protocol_test = ROOT / (
        "packages/lddc_desktop_protocol/platform_test/"
        "desktop_real_process_e2e_test.dart"
    )
    if not protocol_test.is_file():
        problems.append("桌面 IPC 协议包缺少真实进程 E2E")
    media_test = ROOT / (
        "packages/lddc_lyrics_runtime/platform_test/"
        "platform_media_resource_test.dart"
    )
    if not media_test.is_file():
        problems.append("runtime 包缺少真实媒体资源测试")
    media_runner = (ROOT / "tool/test/run_platform_media_resource.ps1").read_text(
        encoding="utf-8"
    )
    for marker in (
        '[ValidateSet("windows", "macos", "linux")]',
        "[ValidateSet(3, 20)]",
        "$process.Kill($true)",
        "native_test_sandboxes",
        "StartsWith($sandboxParent",
    ):
        if marker not in media_runner:
            problems.append(f"媒体资源 runner 缺少有界执行或清理约束: {marker}")
    process_runner = (ROOT / "tool/test/run_desktop_process_e2e.ps1").read_text(
        encoding="utf-8"
    )
    process_preflight = process_runner.find('if ($Platform -eq "windows")')
    process_run_id = process_runner.find('$runId = "platform-$Platform-process')
    if process_preflight < 0 or process_run_id < 0 or process_preflight > process_run_id:
        problems.append("桌面进程 runner 必须在创建 runId 目录前检查全局单实例前置条件")
    for marker in (
        "StartsWith($sandboxParent",
        "Remove-Item -LiteralPath $sandboxRoot -Recurse -Force",
        "$process.Kill($true)",
        "lddc/build/production_e2e/windows/lddc.exe",
        "lddc/build/production_e2e/macos/LDDC.app/Contents/MacOS/LDDC",
        "lddc/build/production_e2e/linux/lddc",
    ):
        if marker not in process_runner:
            problems.append(f"桌面进程 runner 缺少有界执行或清理约束: {marker}")
    android_ci_runner = (
        ROOT / "tool/test/run_android_ci_validation.sh"
    ).read_text(encoding="utf-8")
    for marker in (
        "android-jvm",
        "android-offline",
        "android-platform",
        "android-uiautomator",
        "run_android_platform_tests.ps1",
        "android-phases.json",
    ):
        if marker not in android_ci_runner:
            problems.append(f"Android CI runner 缺少阶段或报告聚合: {marker}")
    for marker in (
        "windows-validation:",
        "macos-validation:",
        "linux-validation:",
        "android-validation:",
        "ios-validation:",
        "experimental-web:",
        "run_android_ci_validation.sh",
        "run_ios_platform_tests.ps1",
        "run_windows_platform_tests.ps1",
        "run_macos_platform_tests.ps1",
        "run_linux_platform_tests.sh",
        "run_desktop_process_e2e.ps1",
        "Snapshot Windows production application",
        "Snapshot macOS production application",
        "Snapshot Linux production application",
        "-AppExe lddc/build/production_e2e/windows/lddc.exe",
        "-AppExe lddc/build/production_e2e/macos/LDDC.app/Contents/MacOS/LDDC",
        "-AppExe lddc/build/production_e2e/linux/lddc",
        "run_platform_media_resource.ps1",
        "Run iOS native unit tests",
        "-scheme Runner",
    ):
        if marker not in workflow:
            problems.append(f"跨平台验证 workflow 缺少原生平台入口: {marker}")
    performance_workflow = (
        ROOT / ".github/workflows/performance-regression.yml"
    ).read_text(encoding="utf-8")
    if "media-resource-stress:" not in performance_workflow or (
        "run_platform_media_resource.ps1 -Platform ${{ matrix.platform }} -LoopCount 20"
        not in performance_workflow
    ):
        problems.append("性能回归 workflow 缺少三桌面媒体 20 轮资源测试")
    return problems


def main() -> int:
    problems = failures()
    if problems:
        for problem in problems:
            print(f"ERROR: {problem}", file=sys.stderr)
        return 1
    print("native test isolation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
