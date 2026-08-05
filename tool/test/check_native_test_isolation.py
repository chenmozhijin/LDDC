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
        'By.res("android", "aerr_wait")',
        "handledSystemAnr || device.hasObject(By.pkg(APP_PACKAGE))",
        "device.currentPackageName == APP_PACKAGE",
        "Until.gone(systemAnrWaitSelector)",
    ):
        if marker not in android_platform_test:
            problems.append(f"Android 前台状态机缺少严格 ANR/前台约束: {marker}")
    wait_button_index = android_platform_test.find("val waitButton =")
    foreground_index = android_platform_test.find(
        "device.currentPackageName == APP_PACKAGE"
    )
    if (
        wait_button_index >= 0
        and foreground_index >= 0
        and wait_button_index > foreground_index
    ):
        problems.append("Android 前台状态机必须先处理系统模态层，再判断 LDDC 可操作")
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
        if scheme.getroot().find(".//EnvironmentVariables") is not None:
            problems.append("iOS UI scheme 禁止保留未生效的 build-setting 环境映射")
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
    # Runner 是 Xcode target 名，Swift 实际模块名由 PRODUCT_MODULE_NAME 决定。
    # 四个应用配置必须显式锁定为 LDDC，避免产品名调整后单测导入再次漂移。
    if project.count("PRODUCT_MODULE_NAME = LDDC;") != 4:
        problems.append("iOS 四个应用配置必须显式固定 PRODUCT_MODULE_NAME=LDDC")
    ios_ui_test = (ROOT / "lddc/ios/RunnerUITests/RunnerUITests.swift").read_text(
        encoding="utf-8"
    )
    ios_app_delegate = (ROOT / "lddc/ios/Runner/AppDelegate.swift").read_text(
        encoding="utf-8"
    )
    ios_unit_tests = (ROOT / "lddc/ios/RunnerTests/RunnerTests.swift").read_text(
        encoding="utf-8"
    )
    if "@testable import LDDC" not in ios_unit_tests:
        problems.append("iOS RunnerTests 必须导入实际 Swift 模块 LDDC")
    if "@testable import Runner" in ios_unit_tests:
        problems.append("iOS RunnerTests 禁止导入旧模板模块 Runner")
    for marker in (
        "let errorValue: Any = failure.map",
        '"error": errorValue,',
        "private func testFailure(_ message: String) -> NSError",
    ):
        if marker not in ios_ui_test:
            problems.append(f"iOS XCUITest evidence JSON 缺少稳定类型处理: {marker}")
    if '"error": failure.map' in ios_ui_test:
        problems.append("iOS XCUITest 禁止让 Swift 推断 String/NSNull 混合表达式")
    if "throw failure(" in ios_ui_test:
        problems.append("iOS XCUITest 禁止把局部 failure 变量误当成错误构造函数")
    if "#if LDDC_PLATFORM_TEST" not in ios_app_delegate:
        problems.append("iOS 匿名 fixture 写入器必须只编译进 PlatformTest app")
    platform_test_flag = (
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG LDDC_PLATFORM_TEST";'
    )
    if project.count(platform_test_flag) != 1:
        problems.append("iOS PlatformTest Swift 编译条件必须只出现在测试 app 配置一次")
    for marker in (
        "security_scoped_fd_read_embedded_lyrics",
        "read_write_fd_tag_saved",
        "saved_tag_reopened_after_app_restart",
        "openLyricsSaveTagSucceeded",
        "LDDC_PLATFORM_TEST_FIXTURE_BASE64",
        "LDDC_PLATFORM_TEST_RESET_FIXTURES",
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
        "systemPickerRoots",
        '"On My iPhone"',
        'private let platformTestDisplayName = "LDDC Platform Tests"',
        "if documents.state != .notRunning",
        "executionTimeAllowance = 120",
    ):
        if marker not in ios_ui_test:
            problems.append(f"iOS 导出与清理场景缺少: {marker}")
    if "documents.wait(for: .runningForeground" in ios_ui_test:
        problems.append("iOS Document Picker 禁止依赖 DocumentsApp 前台进程状态")

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
    for marker in (
        '"-test-timeouts-enabled", "YES"',
        '"-maximum-test-execution-time-allowance", "$ScenarioTimeoutSeconds"',
    ):
        if marker not in ios_runner:
            problems.append(f"iOS XCUITest runner 缺少原生执行超时: {marker}")
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
    # UI test bundle 只通过 XCTest 启动 Runner，不应继承应用 CocoaPods 的
    # plugin linker 参数。否则测试二进制会直接依赖 desktop_multi_window 等
    # framework，而这些 framework 只应嵌入被测应用，运行时会导致 bundle 加载失败。
    for marker in (
        'FRAMEWORK_SEARCH_PATHS = "";',
        'LIBRARY_SEARCH_PATHS = "";',
        'OTHER_LDFLAGS = "";',
    ):
        if macos_project.count(marker) < 3:
            problems.append(f"macOS UI 测试 target 未隔离第三方链接参数: {marker}")
    try:
        macos_scheme = ET.parse(
            ROOT
            / "lddc/macos/Runner.xcodeproj/xcshareddata/xcschemes/RunnerPlatformTests.xcscheme"
        )
        testable = macos_scheme.getroot().find(".//TestableReference")
        if testable is None or testable.get("parallelizable") != "NO":
            problems.append("macOS UI tests 必须禁用并行执行")
        if macos_scheme.getroot().find(".//EnvironmentVariables") is not None:
            problems.append("macOS UI scheme 禁止保留未生效的 build-setting 环境映射")
    except ET.ParseError as error:
        problems.append(f"macOS UI scheme XML 无效: {error}")
    macos_release_entitlements = (
        ROOT / "lddc/macos/Runner/Release.entitlements"
    ).read_text(encoding="utf-8")
    if "com.apple.security.network.server" not in macos_release_entitlements:
        problems.append("macOS Release 缺少桌面歌词 loopback 服务监听权限")
    if "com.apple.security.cs.allow-jit" in macos_release_entitlements:
        problems.append("macOS Release 禁止携带 Debug JIT 权限")
    macos_unit_tests = (ROOT / "lddc/macos/RunnerTests/RunnerTests.swift").read_text(
        encoding="utf-8"
    )
    if "@testable import LDDC" not in macos_unit_tests:
        problems.append("macOS RunnerTests 必须导入实际 Swift 模块 LDDC")
    if "@testable import Runner" in macos_unit_tests:
        problems.append("macOS RunnerTests 禁止导入旧模板模块 Runner")
    if "testHiddenDesktopServiceSurvivesLastWindowBeingHidden" not in macos_unit_tests:
        problems.append("macOS RunnerTests 缺少隐藏服务生命周期断言")

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
                "macos-system-ui-validation:",
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
    quality_workflow = (workflow_dir / "code-quality.yml").read_text(
        encoding="utf-8"
    )
    if workflow.count("tool/test/ci_phase_summary.py") != 6:
        problems.append("五个平台及独立 macOS 系统 UI job 必须统一使用 CI required phase 汇总器")
    if quality_workflow.count("tool/test/ci_phase_summary.py") != 1:
        problems.append("Code Quality 必须使用统一 CI required phase 汇总器")
    if "validation-failure" in workflow or "Upload failed" in workflow:
        problems.append("平台 artifact 必须使用条件 diagnostics 命名，禁止固定 failure 命名")
    if workflow.count("steps.required_outcomes.outcome != 'success'") != 6:
        problems.append("五个平台及独立 macOS 系统 UI diagnostics 必须仅在 required phase 失败时上传")
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
    else:
        protocol_test_source = protocol_test.read_text(encoding="utf-8")
        if len(re.findall(r"(?m)^\s*test\(", protocol_test_source)) != 1:
            problems.append("桌面真实进程文件必须只包含一个会生成 evidence 的业务场景")
        if "probeMacOsControlEndpoint(controlFile)" not in protocol_test_source:
            problems.append("macOS 真实进程 E2E 缺少 control endpoint 直接探针")
    control_probe_test = ROOT / (
        "packages/lddc_desktop_protocol/test/macos_control_probe_test.dart"
    )
    if not control_probe_test.is_file():
        problems.append("桌面协议普通测试缺少 macOS control 端口语义回归")
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
    service_bootstrap = (
        ROOT
        / "lddc/lib/src/platform/desktop/service_host/desktop_service_bootstrap_io.dart"
    ).read_text(encoding="utf-8")
    for marker in (
        "final class DesktopMacOsSingletonBootstrapPort",
        "FileLock.exclusive",
        "InternetAddress.loopbackIPv4",
        "lddc.macos_singleton_control",
        "resolveMacOsControlEndpointFile",
        "resolveMacOsControlLockFile",
    ):
        if marker not in service_bootstrap:
            problems.append(f"macOS 单实例控制缺少无路径上限实现: {marker}")
    if "Platform.isLinux || Platform.isMacOS" in service_bootstrap:
        problems.append("macOS 禁止继续复用受 sun_path 长度限制的 Linux Unix socket")
    process_preflight = process_runner.find(
        'if ($Platform -in @("windows", "macos"))'
    )
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
        "Library/Containers/com.cmzj.lddc/Data",
        "macos-container-backup-$($directory.Name)",
        "$macosContainerState | Where-Object",
        "Move-Item -LiteralPath $state.Backup",
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
        "-StartupTimeoutSeconds 180",
        "run_android_platform_tests.ps1",
        "android-phases.json",
    ):
        if marker not in android_ci_runner:
            problems.append(f"Android CI runner 缺少阶段或报告聚合: {marker}")
    for marker in (
        "windows-validation:",
        "macos-validation:",
        "macos-system-ui-validation:",
        "linux-validation:",
        "android-validation:",
        "ios-validation:",
        "experimental-web:",
        "run_android_ci_validation.sh",
        "run_ios_platform_tests.ps1",
        "run_windows_platform_tests.ps1",
        "run_macos_platform_tests.ps1",
        "run_desktop_process_e2e.ps1",
        "Snapshot Windows production application",
        "Snapshot macOS production application",
        "-AppExe lddc/build/production_e2e/windows/lddc.exe",
        "-AppExe lddc/build/production_e2e/macos/LDDC.app/Contents/MacOS/LDDC",
        "Record Linux multi-window known issue",
        "MixinNetwork/flutter-plugins#448/#488",
        "multi-window runtime remains a manual known issue and is not reported as passed",
        "run_platform_media_resource.ps1",
        "Run iOS native unit tests",
        "--phase ios-native-unit",
        "Restore iOS debug application after Flutter integration",
        "flutter build ios --debug --simulator",
        "--phase ios-debug-rebuild",
        "--timeout 900",
        "-scheme Runner",
    ):
        if marker not in workflow:
            problems.append(f"跨平台验证 workflow 缺少原生平台入口: {marker}")
    # Flutter Linux 的 Semantics identifier 当前没有进入 AT-SPI 子树。
    # hosted CI 不得用坐标脚本伪造覆盖，但 Dogtail 场景和固定依赖仍需保留，
    # 便于在具备可访问性桥接的真实桌面环境中人工执行。
    if "Dogtail 脚本继续保留供人工环境验证" not in workflow:
        problems.append("Linux Dogtail 必须在 workflow 中明确标记为人工验证")
    linux_start = workflow.find("  linux-validation:")
    android_start = workflow.find("  android-validation:")
    if linux_start >= 0 and android_start > linux_start:
        linux_job = workflow[linux_start:android_start]
        for forbidden in (
            "run_desktop_process_e2e.ps1 -Platform linux",
            "steps.desktop_process.outcome",
            "Snapshot Linux production application",
        ):
            if forbidden in linux_job:
                problems.append(
                    f"Linux 已知多窗口问题不得继续作为 hosted 必需门禁: {forbidden}"
                )
    if "run_macos_platform_tests.ps1 -BuildOnly" in workflow:
        problems.append("hosted macOS 不得用 build-only 替代真实 XCUITest")
    macos_runner = (ROOT / "tool/test/run_macos_platform_tests.ps1").read_text(
        encoding="utf-8"
    )
    for marker in (
        '@("build", "macos", "--debug", "--config-only")',
        'Phase "flutter-macos-config"',
        "test-without-building",
        "macos_open_panel_select",
        "macos_open_panel_cancel",
        "Invoke-BoundedProcess",
        "Start-SupervisedProcess",
        "process_group_supervisor.py",
        "Register-OwnedProcessTree",
        "Wait-ForOwnedProcessBaseline",
        'ExpectedState "app_ready"',
        '$payload.resources["final"]["childProcessCount"] = $FinalChildProcessCount',
    ):
        if marker not in macos_runner:
            problems.append(f"macOS XCUITest runner 缺少真实运行契约: {marker}")
    if '@("build", "macos", "--debug")' in macos_runner:
        problems.append("macOS hybrid runner 不得在 build-for-testing 前重复完整 Debug 构建")
    if workflow.count("run_macos_platform_tests.ps1") != 1:
        problems.append("macOS hybrid runner 必须只在独立 system UI job 中执行一次")
    for required in (
        "process_group_supervisor.py",
        "--phase macos-system-ui-workflow",
        "--timeout 900",
        "workflow-watchdog.json",
        "finalize_macos_system_ui_reports.py",
        "steps.report_finalize.outcome",
    ):
        if required not in workflow:
            problems.append(f"macOS system UI workflow 缺少外层进程组 watchdog: {required}")
    for forbidden in (
        "& flutter build macos",
        "& xcodebuild build-for-testing",
        "& xcodebuild test-without-building",
        "& xcrun xcresulttool",
    ):
        if forbidden in macos_runner:
            problems.append(f"macOS hybrid 外部进程禁止绕过硬超时执行器: {forbidden}")
    if ".WaitForExit()" in macos_runner or "Kill($true)" in macos_runner:
        problems.append("macOS hybrid runner 禁止无界 WaitForExit 或递归 Kill 后无界等待")
    macos_start = workflow.find("  macos-validation:")
    macos_system_ui_start = workflow.find("  macos-system-ui-validation:")
    linux_start = workflow.find("  linux-validation:")
    if 0 <= macos_start < macos_system_ui_start < linux_start:
        macos_job = workflow[macos_start:macos_system_ui_start]
        macos_system_ui_job = workflow[macos_system_ui_start:linux_start]
        if "run_macos_platform_tests.ps1" in macos_job:
            problems.append("macOS 应用 job 禁止内嵌 system UI runner")
        for required in (
            "run_desktop_process_e2e.ps1 -Platform macos",
            "run_platform_media_resource.ps1 -Platform macos",
            "Run macOS native unit tests",
            "--phase macos-native-unit",
            "steps.native_unit.outcome",
        ):
            if required not in macos_job:
                problems.append(f"macOS 应用 job 缺少独立平台证据: {required}")
        for forbidden in (
            "run_desktop_process_e2e.ps1",
            "run_platform_media_resource.ps1",
        ):
            if forbidden in macos_system_ui_job:
                problems.append(f"macOS system UI job 禁止混入应用资源场景: {forbidden}")
    else:
        problems.append("macOS 应用与 system UI job 顺序或边界无效")
    macos_ui_tests = (ROOT / "lddc/macos/RunnerUITests/RunnerUITests.swift").read_text(
        encoding="utf-8"
    )
    for required in (
        "XCUIApplication(url:",
        "app.activate()",
        "isOriginalApplicationStillRunning",
        "waitForRunningApplication",
        "NSWorkspace.shared.runningApplications",
        "currentPanelServices",
        'state: "native_ready"',
        'state: "native_completed"',
        "attachedToExistingApplication",
        "usedExactApplicationURL",
    ):
        if required not in macos_ui_tests:
            problems.append(f"macOS hybrid XCUITest 缺少附着运行中应用契约: {required}")
    for forbidden in (
        ".launch()",
        "--lddc-enable-accessibility-for-ui-test",
        "lddc-open-lyrics",
    ):
        if forbidden in macos_ui_tests:
            problems.append(f"macOS hybrid XCUITest 禁止启动应用或查询 Flutter 控件: {forbidden}")
    for required in (
        "integration_test/macos_file_dialog_platform_test.dart",
        "LDDC_MACOS_HYBRID_SYNC_DIR",
        "Wait-ForHybridState",
        "state.runId -ne $runId",
        "state.scenario -ne $Scenario",
        "Copy-Item -LiteralPath $fixtureSource -Destination $fixture",
        "Write-InfrastructureFailureReports",
        "TEST_RUNNER_LDDC_IT_RUN_ID",
        "TEST_RUNNER_LDDC_FIXTURE_PATH",
        "TEST_RUNNER_LDDC_MACOS_HYBRID_SYNC_DIR",
    ):
        if required not in macos_runner:
            problems.append(f"macOS hybrid runner 缺少协同或失败报告契约: {required}")
    ios_runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
        encoding="utf-8"
    )
    for required in (
        "Get-SimulatorMetadata",
        'simulator = $simulatorMetadata',
        '$simulatorMetadata.configuredLanguage = "en"',
        '$simulatorMetadata.configuredLocale = "en_US"',
        '"-parallel-testing-enabled", "NO"',
        "Get-PlatformTestContainer",
        "Add-PostconditionFailure",
        "if ($testExitCode -eq 0)",
        "--exit-code $effectiveExitCode",
        "TEST_RUNNER_LDDC_IT_RUN_ID",
        "TEST_RUNNER_LDDC_FIXTURE_SIZE",
        "TEST_RUNNER_LDDC_FIXTURE_SHA256",
        "TEST_RUNNER_LDDC_FIXTURE_BASE64",
        "Invoke-BoundedNativeCommand",
        'Phase "ios-xcuitest-build-for-testing"',
        'Phase "ios-xcresult-summary-$scenario"',
        'Phase "ios-xcresult-attachments-$scenario"',
        "$reportingErrors.Count -gt 0",
    ):
        if required not in ios_runner:
            problems.append(f"iOS runner 缺少 Simulator 证据或串行测试契约: {required}")
    for forbidden in (
        "& xcodebuild build-for-testing",
        "& xcodebuild test-without-building",
        "& xcrun xcresulttool",
    ):
        if forbidden in ios_runner:
            problems.append(f"iOS 外部 Xcode/报告进程禁止绕过硬超时执行器: {forbidden}")
    if "-parallel-testing-enabled NO" not in workflow:
        problems.append("iOS native XCTest 必须禁用并行执行")
    for manual_linux_asset in (
        ROOT / "tool/test/run_linux_platform_tests.sh",
        ROOT / "tool/test/requirements-linux-platform.txt",
    ):
        if not manual_linux_asset.is_file():
            problems.append(f"Linux 人工平台测试资产缺失: {manual_linux_asset.name}")
    integration_runner = (ROOT / "tool/test/run_real_integration.ps1").read_text(
        encoding="utf-8"
    )
    for marker in (
        "[int]$StartupTimeoutSeconds = 300",
        "[int]$TargetTimeoutSeconds = 1200",
        "Test-ScenarioExecutionStarted",
        'StartsWith("loading ")',
        '"code_cache/$ContainerReportDir/$Scenario.json"',
        "Test-IosSimulatorReady",
        "Test-AndroidDeviceReady",
        "Reset-AndroidInfrastructureAttempt",
        "adb -s $Device get-state",
        "adb -s $Device shell getprop sys.boot_completed",
        "adb -s $Device shell am force-stop com.cmzj.lddc",
        "adb -s $Device forward --remove-all",
        "$testExitCode = 126",
        "$process.Kill($true)",
        "return 124",
        "return 125",
    ):
        if marker not in integration_runner:
            problems.append(f"真实集成 runner 缺少 target 级硬超时或进程树清理: {marker}")
    windows_main = (ROOT / "lddc/windows/runner/main.cpp").read_text(
        encoding="utf-8"
    )
    windows_flutter_window = (
        ROOT / "lddc/windows/runner/flutter_window.cpp"
    ).read_text(encoding="utf-8")
    # 直接检查析构作用域与 COM 清理的代码顺序，避免把可维护的中文说明误当成
    # 机器协议。FlutterWindow 必须先离开局部作用域，之后才能释放 COM apartment。
    windows_lifecycle_pattern = re.compile(
        r"int exit_code = EXIT_SUCCESS;\s*"
        r"\{.*?FlutterWindow window\(project, should_show_main_window\);.*?"
        r"\n\s*\}\s*"
        r"if \(SUCCEEDED\(com_result\)\) \{\s*"
        r"::CoUninitialize\(\);",
        re.DOTALL,
    )
    if windows_lifecycle_pattern.search(windows_main) is None:
        problems.append("Windows runner 必须在 CoUninitialize 前析构主窗口和 Flutter engine")
    if "return exit_code;" not in windows_main:
        problems.append("Windows runner 必须保留消息循环退出码")
    if "FlutterWindow::~FlutterWindow()" not in windows_flutter_window or (
        "flutter_controller_.reset();" not in windows_flutter_window
    ):
        problems.append("Windows 主窗口析构必须先清空 controller 再删除原生 Flutter view")
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
