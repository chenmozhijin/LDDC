#!/usr/bin/env python3
"""静态校验原生 UI 测试依赖与发布配置隔离。"""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def invalid_descendant_element_types(source: str) -> list[str]:
    """返回 descendants(matching:) 中误用的集合属性名。"""

    return re.findall(
        r"descendants\s*\(\s*matching\s*:\s*\."
        r"(otherElements|buttons|cells|staticTexts|links|sheets|touchBars)\b",
        source,
    )


def ios_picker_state_machine_failures(source: str) -> list[str]:
    """校验 iOS 系统 Picker 场景不会跳过生产转换或点击禁用控件。"""

    problems: list[str] = []
    required_markers = (
        "private func convertLoadedLyrics(",
        'let convert = app.descendants(matching: .any)[convertIdentifier]',
        "if saveFile.exists, saveFile.isEnabled, saveTag.exists, saveTag.isEnabled",
        "picker.application.textFields.matching(",
        'NSPredicate(format: "identifier == %@", exportFileNameIdentifier)',
        "XCUIKeyboardKey.delete.rawValue",
        "waitForStringValue(fileName, equals: exportBaseName",
        'action: "document_picker_export_name_replaced"',
        "private func dismissKeyboardTutorialIfPresented(",
        'private let keyboardTutorialMessage = "Speed up your typing by sliding your finger across the letters to compose a word."',
        "let tutorialAppeared = message.waitForExistence(timeout: 2)",
        'action: "keyboard_tutorial_dismissed"',
        "let resumedPicker = try waitForSystemPicker(app: launchedApp, timeout: 5)",
        'let save = try requireTypedButton(named: "Save", in: resumedPicker, timeout: 15)',
        'action: "document_picker_export_save_tapped"',
        "picker.application.otherElements.matching(",
        "let cancelButtons = pickerElements(",
        "if cancelButtons.count == 1",
        "waitForSelectedFixture(app: app, timeout: 5)",
        "retainedFixture.doubleTap()",
        'action: "document_picker_selected_fixture_double_tap_activated"',
        "let value = preview.value as? String",
        "if element.exists, element.isHittable, element.isEnabled",
        "element.waitForExistence(timeout: 3), element.isHittable, element.isEnabled",
        "(!requireHittable || ($0.isHittable && $0.isEnabled))",
    )
    for marker in required_markers:
        if marker not in source:
            problems.append(f"iOS Picker 状态机缺少强契约: {marker}")

    scenario_contracts = (
        ("testDocumentPickerSelectsSeededAudio", "saveTag.tap()"),
        ("testDocumentPickerExportsLyricsFile", "openExportPicker(app: launchedApp)"),
        (
            "testDocumentPickerExportCancellationCleansTemporaryFile",
            "openExportPicker(app: launchedApp)",
        ),
        ("testTerminatedExportIsCleanedOnNextLaunch", "openExportPicker(app: launchedApp)"),
    )
    for method, protected_action in scenario_contracts:
        method_match = re.search(
            rf"  func {re.escape(method)}\(\) throws \{{(?P<body>[\s\S]*?)(?=\n  (?:func|private func) )",
            source,
        )
        if method_match is None:
            problems.append(f"iOS Picker 状态机缺少场景方法: {method}")
            continue
        body = method_match.group("body")
        conversion_index = body.find(
            "try convertLoadedLyrics(app: launchedApp, actions: &actions)"
        )
        action_index = body.find(protected_action)
        if conversion_index < 0 or action_index < 0 or conversion_index > action_index:
            problems.append(f"iOS 场景 {method} 必须先完成生产歌词转换再执行保存动作")

    export_match = re.search(
        r"  func testDocumentPickerExportsLyricsFile\(\) throws \{"
        r"(?P<body>[\s\S]*?)(?=\n  (?:func|private func) )",
        source,
    )
    if export_match is not None:
        export_body = export_match.group("body")
        ordered_markers = (
            "try replaceExportBaseName(in: picker)",
            "try dismissKeyboardTutorialIfPresented(in: picker, actions: &actions)",
            "let resumedPicker = try waitForSystemPicker(app: launchedApp, timeout: 5)",
            'let save = try requireTypedButton(named: "Save", in: resumedPicker, timeout: 15)',
            "save.tap()",
        )
        marker_positions = [export_body.find(marker) for marker in ordered_markers]
        if any(position < 0 for position in marker_positions) or marker_positions != sorted(
            marker_positions
        ):
            problems.append("iOS 导出必须先改名、关闭首次键盘教学层，再点击已启用的 Save")

    for forbidden in (
        "retainedFixture.tap()",
        'action: "document_picker_fixture_cell_reactivated"',
        'action: "document_picker_fixture_cell_double_tap_reactivated"',
        "picker.root.swipeDown()",
        "waitForKeyboardTutorialToDisappear(",
    ):
        if forbidden in source:
            problems.append(f"iOS Picker 状态机禁止旧 fallback: {forbidden}")
    return problems


def macos_hybrid_source_failures(flutter_source: str, ui_test_source: str) -> list[str]:
    """校验 macOS hybrid 的单向握手和 Swift 逃逸闭包契约。"""

    problems: list[str] = []
    for marker in (
        "OperationEdgeTracker",
        "operationEdges.started",
        "state: 'picker_requested'",
        "operationEdges.completed",
        "state: 'flutter_completed'",
        "stateSubscription.close()",
    ):
        if marker not in flutter_source:
            problems.append(f"macOS hybrid Flutter 缺少边沿握手契约: {marker}")
    ordered_flutter_markers = (
        "operationEdges.started",
        "state: 'picker_requested'",
        "operationEdges.completed",
        "state: 'flutter_completed'",
    )
    marker_positions = [flutter_source.find(marker) for marker in ordered_flutter_markers]
    if any(position < 0 for position in marker_positions) or marker_positions != sorted(
        marker_positions
    ):
        problems.append("macOS hybrid 必须先观察打开边沿、发布请求，再观察完成边沿并发布结果")
    if "self.addAction(&actions, capability: capability, action: action)" not in ui_test_source:
        problems.append("macOS XCUITest 逃逸闭包调用实例方法时必须显式使用 self")
    return problems


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
        '"hosted_system_anr"',
        '"documents_ui_failure"',
        '"application_failure"',
        '"resource_cleanup_failure"',
        '"nativeActionCount" to nativeActionCount',
        "detectHostedSystemAnr()",
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
    open_lyrics_page = (
        ROOT / "lddc/lib/src/features/open_lyrics/presentation/open_lyrics_page.dart"
    ).read_text(encoding="utf-8")
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
        'private let documentBrowsingRootPrefix = "DOC.browsingRoot Source: "',
        "typedSystemPickerRoot(in: app)",
        'application.otherElements["Browse View (Picker)"]',
        'NSPredicate(format: "identifier BEGINSWITH %@", documentBrowsingRootPrefix)',
        "let application: XCUIApplication",
        "picker.application.buttons.matching(",
        "picker.application.cells.matching(",
        "picker.application.links.matching(",
        "requireUniquePickerElement(",
        "elementBelongsToPicker(",
        "CGPoint(x: elementFrame.midX, y: elementFrame.midY)",
        'private let fixtureAccessibilityName = "audio_sample, mp3"',
        'private let saveTagFailedIdentifier = "lddc.open_lyrics.notice.saveTagFailed"',
        "waitForSaveTagResult(app: launchedApp, timeout: 20)",
        "requireFixtureCell(app: app",
        'rootIdentifier.hasSuffix(", Title: \\(platformTestDisplayName)")',
        'action: "document_picker_fixture_cell_tapped"',
        'action: "document_picker_selected_fixture_double_tap_activated"',
        "redactDynamicPaths",
        'requireTypedButton(named: "Browse"',
        'requireTypedButton(named: "Save"',
        'private let previewIdentifier = "lddc.open_lyrics.preview"',
        'app.otherElements[previewIdentifier]',
        'private let fixtureLyricsAccessibilityPattern = #"^\\[00:00\\.\\d{2,3}\\]Hello LDDC$"#',
        "waitForPreviewLyricsValue(preview: preview",
        "let value = preview.value as? String",
        "private func dismissKeyboardTutorialIfPresented(",
        'action: "keyboard_tutorial_dismissed"',
        "let resumedPicker = try waitForSystemPicker(app: launchedApp, timeout: 5)",
        "cancelSystemPicker(app: launchedApp, returnControl: openSong)",
        "cancelSystemPicker(app: launchedApp, returnControl: saveFile)",
        '"On My iPhone"',
        '"DOC.sidebar.item.On My iPhone"',
        "requireOnMyIPhoneLocation(in: picker",
        'private let platformTestDisplayName = "LDDC Platform Tests"',
        "if documents.state != .notRunning",
        "executionTimeAllowance = 120",
    ):
        if marker not in ios_ui_test:
            problems.append(f"iOS 导出与清理场景缺少: {marker}")
    if "documents.wait(for: .runningForeground" in ios_ui_test:
        problems.append("iOS Document Picker 禁止依赖 DocumentsApp 前台进程状态")
    if "modeTabBar.isHittable" in ios_ui_test or "waitForHittable(modeTabBar" in ios_ui_test:
        problems.append("iOS Document Picker 禁止要求 TabBar 父代理自身可命中")
    invalid_descendant_types = invalid_descendant_element_types(ios_ui_test)
    if invalid_descendant_types:
        problems.append(
            "iOS XCUITest descendants(matching:) 必须使用 XCUIElement.ElementType 单数枚举，"
            f"禁止集合属性名 .{invalid_descendant_types[0]}"
        )
    problems.extend(ios_picker_state_machine_failures(ios_ui_test))
    for marker in (
        "identifier: AppSemanticsIdentifiers.openLyricsPreview",
        "value: _previewSemanticsValue(state.previewText)",
        "static const int _semanticsPreviewLimit = 256",
        "LineSplitter.split(text)",
        ".take(_semanticsPreviewLimit + 1)",
    ):
        if marker not in open_lyrics_page:
            problems.append(f"Flutter 歌词预览缺少稳定且有界的结果语义: {marker}")
    for forbidden in (
        "systemPickerRoots",
        "pickerElement(",
        "findSystemPickerElement",
        "requireSystemPickerElement",
        'picker.root.buttons["Browse"]',
        'picker.root.buttons["Cancel"]',
        "picker.root.buttons.matching(",
        "picker.root.cells.matching(",
        "picker.root.links.matching(",
        ".sheets",
        "let backButton =",
        "backButton.tap()",
        "label CONTAINS[c]",
        "identifier CONTAINS[c]",
        '"nativeWindowCount"',
        "waitForSystemPickerToClose(",
        "preview.descendants(matching:",
        "app.otherElements.matching(predicate).allElementsBoundByIndex",
    ):
        if forbidden in ios_ui_test:
            problems.append(f"iOS Document Picker 禁止宽泛选择或 sheet fallback: {forbidden}")

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
    for marker in (
        "Test-ShouldRetryAndroidScenario",
        "Restart-HostedAndroidEmulator",
        'FailureCategory -eq "hosted_system_anr"',
        "NativeActionCount -eq 0",
        'getprop sys.boot_completed',
        "android-instrumentation-missing",
        "--failure-junit $junitPath",
        "$overallStatus = 1",
    ):
        if marker not in android_runner:
            problems.append(f"Android runner 缺少 ANR 分类、单次恢复或失败收集约束: {marker}")
    if "Android instrumentation 两次启动均未生成 JUnit XML" in android_runner:
        problems.append("Android runner 禁止因单场景缺报告而短路其他场景")
    ios_runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
        encoding="utf-8"
    )
    for marker in (
        '"-test-timeouts-enabled", "YES"',
        '"-maximum-test-execution-time-allowance", "$ScenarioTimeoutSeconds"',
        "$xcodeResultFinalizationTimeoutSeconds = $ScenarioTimeoutSeconds + 90",
        "-TimeoutSeconds $xcodeResultFinalizationTimeoutSeconds",
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
    if "PropertyListSerialization.propertyList(\n      from: data,\n      options: [],\n      format: nil\n    )" not in macos_unit_tests:
        problems.append("macOS RunnerTests 必须使用当前 SDK 的完整 plist 读取签名")

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

    cross_platform_path = workflow_dir / "cross-platform-validation.yml"
    quality_path = workflow_dir / "code-quality.yml"
    # 工作流缺失本身已经由上面的集合门禁报告。这里继续使用空源码完成其余
    # 静态审计，避免实验分支或误删文件时由 FileNotFoundError 遮蔽其他问题。
    workflow = (
        cross_platform_path.read_text(encoding="utf-8")
        if cross_platform_path.is_file()
        else ""
    )
    quality_workflow = (
        quality_path.read_text(encoding="utf-8") if quality_path.is_file() else ""
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
        "FlutterStartupTimeoutSeconds",
        "Get-SupervisorResidualCount",
        "Wait-ForLddcProcessBaseline",
        '/usr/bin/plutil -extract CFBundleIdentifier raw',
        '$bundleIdentifier.Trim() -ne "com.cmzj.lddc"',
        'ExpectedState "picker_requested"',
        "-TimeoutSeconds $FlutterStartupTimeoutSeconds",
        'ExpectedState "flutter_completed"',
        '$payload.resources["final"]["childProcessCount"] = $FinalChildProcessCount',
    ):
        if marker not in macos_runner:
            problems.append(f"macOS XCUITest runner 缺少真实运行契约: {marker}")
    if "Wait-ForFlutterTestStart" in macos_runner:
        problems.append("macOS hybrid 禁止把 Dart testStart 当作应用就绪门禁")
    if '@("build", "macos", "--debug")' in macos_runner:
        problems.append("macOS hybrid runner 不得在 build-for-testing 前重复完整 Debug 构建")
    for forbidden in ("Register-OwnedProcessTree", "Wait-ForOwnedProcessBaseline"):
        if forbidden in macos_runner:
            problems.append(f"macOS hybrid runner 禁止使用会误算 Xcode 系统服务的 PID 快照: {forbidden}")
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
        for job_name, job in (
            ("macOS 应用 job", macos_job),
            ("macOS system UI job", macos_system_ui_job),
        ):
            for marker in (
                "runs-on: macos-26",
                "LDDC_XCODE_VERSION: '26.6'",
                'developer_dir="/Applications/Xcode_${LDDC_XCODE_VERSION}.app/Contents/Developer"',
                'sudo xcode-select --switch "$developer_dir"',
                'xcode_version_output="$(xcodebuild -version)"',
                'actual_build_version="$(awk \'/^Build version / { print $3 }\'',
            ):
                if marker not in job:
                    problems.append(f"{job_name} 缺少固定 Xcode 预检契约: {marker}")
    else:
        problems.append("macOS 应用与 system UI job 顺序或边界无效")
    macos_ui_tests = (ROOT / "lddc/macos/RunnerUITests/RunnerUITests.swift").read_text(
        encoding="utf-8"
    )
    desktop_launch_parser = (
        ROOT
        / "lddc/lib/src/platform/desktop/service_host/desktop_service_launch_arguments.dart"
    ).read_text(encoding="utf-8")
    desktop_launch_tests = (
        ROOT
        / "lddc/test/platform/desktop/service_host/desktop_service_launch_arguments_test.dart"
    ).read_text(encoding="utf-8")
    for host_argument in (
        "-NSTreatUnknownArgumentsAsOpen",
        "-ApplePersistenceIgnoreState",
    ):
        if f"case '{host_argument}':" not in desktop_launch_parser:
            problems.append(f"桌面启动参数解析器缺少已知 AppKit 宿主参数: {host_argument}")
        if desktop_launch_tests.count(host_argument) < 4:
            problems.append(f"桌面启动参数测试未覆盖顺序、边界和真实宿主序列: {host_argument}")
    for marker in (
        "已观测 AppKit 宿主参数在不同组合顺序和重复注入下保持可解析",
        "ApplePersistenceIgnoreState 缺失值不会吞掉后续 LDDC 参数",
        "ApplePersistenceIgnoreState 非法值仍然严格失败",
        "AppKit 宿主参数缺少值时不吞掉后续 LDDC 参数",
        "AppKit 宿主参数后的非布尔值仍严格报错",
    ):
        if marker not in desktop_launch_tests:
            problems.append(f"桌面启动参数缺少 hosted 边界测试: {marker}")
    macos_flutter_test = (
        ROOT / "lddc/integration_test/macos_file_dialog_platform_test.dart"
    ).read_text(encoding="utf-8")
    problems.extend(macos_hybrid_source_failures(macos_flutter_test, macos_ui_tests))
    for required in (
        "OperationEdgeTracker",
        "operationEdges.started",
        "operationEdges.completed",
        "stateSubscription.close()",
        "state: 'picker_requested'",
        "state: 'flutter_completed'",
        "state: 'flutter_failed'",
        "expect(completedState.inputType, OpenLyricsInputType.songFile)",
        "expect(completedState.inputName, 'audio_sample.mp3')",
        "expect(completedState.rawText, contains('Hello LDDC'))",
        "'noticeCode': failedState.notice?.code.name ?? 'null'",
        "timeout: runtime.defaultStepTimeout",
        "Error.throwWithStackTrace(error, stackTrace)",
    ):
        if required not in macos_flutter_test:
            problems.append(f"macOS hybrid Flutter 单写状态机缺少: {required}")
    for forbidden in (
        "state: 'app_ready'",
        "state: 'native_ready'",
        "state: 'native_completed'",
        "state: 'native_failed'",
        "timeout: const Duration(seconds: 30)",
    ):
        if forbidden in macos_flutter_test:
            problems.append(f"macOS hybrid Flutter 禁止旧双向握手状态: {forbidden}")
    for required in (
        "XCUIApplication(url:",
        'private let appBundleIdentifier = "com.cmzj.lddc"',
        "Bundle(url: bundleURL)?.bundleIdentifier == appBundleIdentifier",
        "runningApplication.bundleIdentifier == appBundleIdentifier",
        "waitForRunningApplication",
        "NSWorkspace.shared.runningApplications",
        "currentPanelServices",
        'application.bundleIdentifier == "com.apple.appkit.xpc.openAndSavePanelService"',
        "fixtureURL.deletingLastPathComponent().path",
        'NSPredicate(format: "value == %@", directoryName)',
        "selectedDirectory.firstMatch.isSelected",
        "panel.application.typeKey(.rightArrow, modifierFlags: [])",
        'NSPredicate(format: "value == %@", fixtureName)',
        "waitForExactlyOneHittableElement",
        'panel.application.sheets["GoToWindow"]',
        'goToFolder.textFields["PathTextField"]',
        "waitForHittableElement(pathField, timeout: 10)",
        "waitForStringValue(pathField, equals: fixtureDirectory, timeout: 10)",
        "pathField.typeKey(.return, modifierFlags: [])",
        "waitForElementToDisappear(goToFolder, timeout: 10)",
        'lddc-macos-go-to-folder-accessibility.txt',
        'pathField.click()',
        'pathField.typeKey("a", modifierFlags: [.command])',
        "waitForSelectedElement([fixture]",
        "openButton.isEnabled",
        "openButton.click()",
        'recordAction("filePicker", "fixture_selected")',
        'recordAction("filePicker", "open_button_clicked")',
        "hasOpenPanel(panel.application)",
        'expectedState: "picker_requested"',
        "self.addAction(&actions, capability: capability, action: action)",
        'addAction(&actions, capability: "filePicker", action: action)',
        "attachedToExistingApplication",
        "usedExactApplicationURL",
        '"changedApplicationActivationState": false',
    ):
        if required not in macos_ui_tests:
            problems.append(f"macOS hybrid XCUITest 缺少附着运行中应用契约: {required}")
    for forbidden in (
        ".launch()",
        ".activate()",
        "writeSyncState",
        "writeFailureState",
        'expectedState: "flutter_completed"',
        'state.state == "flutter_completed"',
        '"app_ready"',
        '"native_ready"',
        '"native_completed"',
        '"native_failed"',
        "--lddc-enable-accessibility-for-ui-test",
        "lddc-open-lyrics",
        "pathField.typeText(fixturePath)",
        'panel.application.typeKey(.enter',
        "goToFolder.touchBars",
        "goButton.click()",
        "panel.application.typeKey(.return, modifierFlags: [])",
        "panel.root.outlineRows.firstMatch",
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
        "if ($xcodeExitCode -ne 0)",
        "Resolve-UniqueBuildArtifact",
        "-and [string]::IsNullOrWhiteSpace($runnerFailureMessage)",
        "-and [string]::IsNullOrWhiteSpace($xcresultReportError)",
        "-and $evidenceCandidates.Count -eq 1",
        "$xcodeReportDrainSeconds = 30",
        "$reportDrainAttempted = $true",
        '"flutter_failed_xcresult_drain_expired"',
        "reportDrainAttempted = $ReportDrainAttempted",
        "$hybridNativeActionTimeoutSeconds = 90",
        "LDDC_IT_STEP_TIMEOUT_MS=$($hybridNativeActionTimeoutSeconds * 1000)",
        "Get-XcresultFailureMessage",
        "Get-FlutterScenarioFailureMessage",
        "Resolve-FallbackFailureMessage",
        "diagnostics = $state.diagnostics",
        "$hybridNativeActionTimeoutSeconds + $xcodeReportDrainSeconds",
        'diagnostics=$diagnosticText',
        "Assert-FlutterCompletionState",
        "inputPathPresent",
        "rawTextContainsFixture",
    ):
        if required not in macos_runner:
            problems.append(f"macOS hybrid runner 缺少协同或失败报告契约: {required}")
    for scenario, method in (
        ("macos_open_panel_select", "testOpenPanelSelectsFixture"),
        ("macos_open_panel_cancel", "testOpenPanelCancellationReturnsToFlutter"),
    ):
        pair_pattern = re.compile(
            rf'Name = "{re.escape(scenario)}"[\s\S]{{0,200}}Method = "{re.escape(method)}"'
        )
        if pair_pattern.search(macos_runner) is None:
            problems.append(f"macOS runner 场景与 XCTest 方法映射错误: {scenario} -> {method}")
        if f"func {method}()" not in macos_ui_tests or f'"{scenario}"' not in macos_ui_tests:
            problems.append(f"macOS XCUITest 缺少场景实现: {scenario} -> {method}")
    if '$runnerTerminationReason = "flutter_failed_xcresult_drain"' in macos_runner:
        problems.append("macOS runner 禁止把自然完成的 xcresult 收尾误记为主动终止")
    for environment_name in (
        "LDDC_IT_RUN_ID",
        "LDDC_FIXTURE_PATH",
        "LDDC_MACOS_HYBRID_SYNC_DIR",
    ):
        if f"TEST_RUNNER_{environment_name}" not in macos_runner:
            problems.append(f"macOS runner 缺少 XCTest 环境变量: {environment_name}")
        if f'["{environment_name}"]' not in macos_ui_tests:
            problems.append(f"macOS XCUITest 未读取 runner 环境变量: {environment_name}")
    for unused_environment_name in (
        "TEST_RUNNER_LDDC_FIXTURE_SIZE",
        "TEST_RUNNER_LDDC_FIXTURE_SHA256",
    ):
        if unused_environment_name in macos_runner:
            problems.append(f"macOS runner 禁止注入 XCUITest 未消费变量: {unused_environment_name}")
    ios_runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
        encoding="utf-8"
    )
    macos_finalizer = (
        ROOT / "tool/test/finalize_macos_system_ui_reports.py"
    ).read_text(encoding="utf-8")
    for marker in (
        "_report_pair_is_valid",
        'payload.get("schemaVersion") != 2',
        'payload.get("runId") != run_id',
        'payload.get("scenario") != scenario',
        'payload.get("profile") != "platform"',
        'payload.get("platform") != "macos"',
        'payload.get("framework") != "integration_test+xcuitest"',
        "ET.parse(junit_report)",
        "return 1 if finalization_failed else 0",
    ):
        if marker not in macos_finalizer:
            problems.append(f"macOS report finalizer 缺少报告完整性契约: {marker}")
    if 'args.step_outcome == "success"' in macos_finalizer:
        problems.append("macOS report finalizer 禁止重复承担 system UI 业务结果门禁")
    ios_simulator_creator = (
        ROOT / "tool/test/create_ios_simulator.sh"
    ).read_text(encoding="utf-8")
    for marker in (
        'expected_runtime_version="${LDDC_IOS_RUNTIME_VERSION:-26.5}"',
        'expected_runtime_major="${expected_runtime_version%%.*}"',
        'expected_xcode_version="${LDDC_XCODE_VERSION:-26.6}"',
        'xcode_version_output="$(xcodebuild -version)"',
        'xcode_version_number="$(awk \'/^Xcode / { print $2 }\'',
        'xcode_build_version="$(awk \'/^Build version / { print $3 }\'',
        '"$xcode_version_number" != "$expected_xcode_version"',
        'xcode_major="${xcode_version_number%%.*}"',
        '"$xcode_major" != "$expected_runtime_major"',
        '--arg expectedVersion "$expected_runtime_version"',
        'select(.version == $expectedVersion)',
        'xcode_version="$(tr \'\\n\' \' \' <<<"$xcode_version_output"',
        'if [[ -n "${GITHUB_ENV:-}" ]]',
        'trap - ERR',
        'run_ios_platform_tests.ps1 -Device',
    ):
        if marker not in ios_simulator_creator:
            problems.append(f"iOS Simulator 创建器缺少运行时锁定或元数据: {marker}")
    for required in (
        "Get-SimulatorMetadata",
        "simctl list runtimes --json",
        "runtimeVersion = [string]$runtimeInfo.version",
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
        'Phase "ios-flutter-config"',
        '@("build", "ios", "--debug", "--simulator", "--config-only")',
        'Phase "ios-pod-install"',
        '@("install", "--project-directory=ios")',
        'Phase "ios-xcresult-summary-$scenario"',
        'Phase "ios-xcresult-attachments-$scenario"',
        "$reportingErrors.Count -gt 0",
        "Add-RunnerEvidence",
        "postconditionStatus",
        "runner-fallback.json",
        "无法增补 Simulator evidence",
        "无法写入 runner evidence",
        "hostArchitecture",
        "xcodeVersion",
        "iOS hosted Xcode 漂移",
        "iOS Simulator runtime 漂移",
        "arch=$hostArchitecture",
        "Resolve-UniqueBuildArtifact",
        "iOS Xcode DerivedData 超出测试构建根",
        '$exportedFiles.Count -ne 1',
        '.Extension.Equals(".lrc", [StringComparison]::OrdinalIgnoreCase)',
        '$exportedText.Contains("Hello LDDC", [StringComparison]::Ordinal)',
        'Get-FileHash -LiteralPath $exportedFile.FullName -Algorithm SHA256',
        'resourceMeasurementStatus = "not_exercised_before_test_start"',
        '$activeInfrastructureFailureClass = "build_failure"',
        "$infrastructureFailureMessage = $null",
        "Write-InfrastructureFailureReports `\n    -Message $infrastructureFailureMessage",
    ):
        if required not in ios_runner:
            problems.append(f"iOS runner 缺少 Simulator 证据或串行测试契约: {required}")
    for forbidden in (
        "& xcodebuild build-for-testing",
        "& xcodebuild test-without-building",
        "& xcrun xcresulttool",
        'Filter "*.xctestrun" | Select-Object -First 1',
        'Filter "LDDC.app" | Select-Object -First 1',
        "applicationProcessCount",
    ):
        if forbidden in ios_runner:
            problems.append(f"iOS 外部 Xcode/报告进程禁止绕过硬超时执行器: {forbidden}")
    for scenario, method in (
        ("ios_document_picker_select", "testDocumentPickerSelectsSeededAudio"),
        ("ios_document_picker_cancel", "testDocumentPickerCancellationReturnsToFlutter"),
        ("ios_document_picker_export", "testDocumentPickerExportsLyricsFile"),
        (
            "ios_document_picker_export_cancel",
            "testDocumentPickerExportCancellationCleansTemporaryFile",
        ),
        (
            "ios_document_picker_export_termination",
            "testTerminatedExportIsCleanedOnNextLaunch",
        ),
    ):
        pair_pattern = re.compile(
            rf'Name = "{re.escape(scenario)}"[\s\S]{{0,160}}Method = "{re.escape(method)}"'
        )
        if pair_pattern.search(ios_runner) is None:
            problems.append(f"iOS runner 场景与 XCTest 方法映射错误: {scenario} -> {method}")
        if f"func {method}()" not in ios_ui_test or f'"{scenario}"' not in ios_ui_test:
            problems.append(f"iOS XCUITest 缺少场景实现: {scenario} -> {method}")
    for environment_name in (
        "LDDC_IT_RUN_ID",
        "LDDC_FIXTURE_SIZE",
        "LDDC_FIXTURE_SHA256",
        "LDDC_FIXTURE_BASE64",
    ):
        if f"TEST_RUNNER_{environment_name}" not in ios_runner:
            problems.append(f"iOS runner 缺少 XCTest 环境变量: {environment_name}")
        if f'["{environment_name}"]' not in ios_ui_test:
            problems.append(f"iOS XCUITest 未读取 runner 环境变量: {environment_name}")
    if "-parallel-testing-enabled NO" not in workflow:
        problems.append("iOS native XCTest 必须禁用并行执行")
    simulator_creator = (ROOT / "tool/test/create_ios_simulator.sh").read_text(
        encoding="utf-8"
    )
    for marker in (
        'host_arch="$(uname -m)"',
        'echo "IOS_HOST_ARCH=$host_arch"',
        "hostArchitecture",
    ):
        if marker not in simulator_creator:
            problems.append(f"iOS Simulator 创建器缺少宿主架构证据: {marker}")
    for marker in (
        'state="$(xcrun simctl list devices --json',
        'Shutdown) xcrun simctl boot "$DEVICE_ID"',
        'Booting|Booted)',
        'arch=$IOS_HOST_ARCH',
    ):
        if marker not in workflow:
            problems.append(f"iOS native unit 测试缺少状态感知启动契约: {marker}")
    if 'simctl boot "$DEVICE_ID" || true' in workflow:
        problems.append("iOS Simulator 启动错误不得通过 || true 吞掉")
    ios_job_start = workflow.find("  ios-validation:")
    ios_job_end = workflow.find("  experimental-web:")
    if 0 <= ios_job_start < ios_job_end:
        ios_job = workflow[ios_job_start:ios_job_end]
        for marker in (
            "runs-on: macos-26",
            "LDDC_XCODE_VERSION: '26.6'",
            "LDDC_IOS_RUNTIME_VERSION: '26.5'",
            'developer_dir="/Applications/Xcode_${LDDC_XCODE_VERSION}.app/Contents/Developer"',
            'sudo xcode-select --switch "$developer_dir"',
            'xcode_version_output="$(xcodebuild -version)"',
            'actual_build_version="$(awk \'/^Build version / { print $3 }\'',
            "simctl list runtimes available -j",
            '--arg version "$LDDC_IOS_RUNTIME_VERSION"',
            "bash tool/test/create_ios_simulator.sh",
        ):
            if marker not in ios_job:
                problems.append(f"iOS hosted job 缺少固定 runner/runtime 契约: {marker}")
        simulator_index = ios_job.find("Create and boot a compatible iOS simulator")
        system_ui_index = ios_job.find("Run iOS Document Picker automation")
        release_index = ios_job.find("Build iOS release without codesigning")
        if not (0 <= simulator_index < system_ui_index < release_index):
            problems.append("iOS Document Picker 必须在 simulator 创建后、昂贵构建与业务阶段前执行")
    else:
        problems.append("iOS hosted job 边界无效")
    if "xcodebuild -version |" in workflow or "xcodebuild -version |" in ios_simulator_creator:
        problems.append("Apple 版本预检必须先完整读取 xcodebuild 输出，禁止提前关闭管道")
    for manual_linux_asset in (
        ROOT / "tool/test/run_linux_platform_tests.sh",
        ROOT / "tool/test/requirements-linux-platform.txt",
    ):
        if not manual_linux_asset.is_file():
            problems.append(f"Linux 人工平台测试资产缺失: {manual_linux_asset.name}")
    integration_runner = (ROOT / "tool/test/run_real_integration.ps1").read_text(
        encoding="utf-8"
    )
    integration_drivers = (
        ROOT / "lddc/integration_test/support/integration_drivers.dart"
    ).read_text(encoding="utf-8")
    integration_driver_tests = (
        ROOT / "lddc/test/integration_support/integration_drivers_test.dart"
    ).read_text(encoding="utf-8")
    if "_waitTransientOverlaysToSettle" in integration_drivers or (
        re.search(r"\u7b49\u5f85.*SnackBar.*\u6d88\u5931", integration_drivers) is not None
    ):
        problems.append("Flutter 集成驱动禁止把全局 SnackBar 消失当作点击前置条件")
    local_match_toggle = re.search(
        r"Future<void> toggleSkipExisting\(\) async \{(?P<body>.*?)\n  \}",
        integration_drivers,
        re.DOTALL,
    )
    if local_match_toggle is None:
        problems.append("Local Match 集成驱动缺少跳过已有歌词操作")
    else:
        toggle_body = local_match_toggle.group("body")
        for marker in (
            "tile.evaluate().length != 1",
            "tileWidget is! CheckboxListTile",
            "tileWidget.onChanged == null",
            "await tapVisible(tester, tile",
        ):
            if marker not in toggle_body:
                problems.append(f"Local Match 跳过已有歌词缺少真实 keyed tile 门禁: {marker}")
        if any(
            marker in toggle_body
            for marker in ("find.descendant(", "find.byType(Checkbox)", ".title", "find.byWidget(")
        ):
            problems.append("Local Match 跳过已有歌词禁止回退到子 Checkbox 或动态标题 Widget")
    integration_sources = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (ROOT / "lddc/integration_test").rglob("*.dart")
    )
    if re.search(r"warnIfMissed\s*:\s*false", integration_sources):
        problems.append("Flutter 集成测试禁止吞掉 tap hit-test 失败")
    for marker in (
        "持续 SnackBar 不阻塞未被遮挡的本地匹配操作",
        "tapVisible 拒绝点击被真实遮罩层覆盖的控件",
        "tapVisible 拒绝静默选择重复匹配的目标",
    ):
        if marker not in integration_driver_tests:
            problems.append(f"Flutter 点击驱动缺少严格行为回归: {marker}")
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
    performance_path = ROOT / ".github/workflows/performance-regression.yml"
    performance_workflow = (
        performance_path.read_text(encoding="utf-8")
        if performance_path.is_file()
        else ""
    )
    if "media-resource-stress:" not in performance_workflow or (
        "run_platform_media_resource.ps1 -Platform ${{ matrix.platform }} -LoopCount 20"
        not in performance_workflow
    ):
        problems.append("性能回归 workflow 缺少三桌面媒体 20 轮资源测试")
    pre_submit = (ROOT / "tool/test/run_pre_submit_checks.ps1").read_text(
        encoding="utf-8"
    )
    for marker in (
        "dart-format",
        "dart-analyze",
        "python-quality-tests",
        "python-compileall",
        "native-test-isolation",
        "powershell-ast",
        "workflow-yaml",
        "git-diff-check",
        "git-hygiene",
        "windows-local-match-integration",
        "apple-native-ui",
        "linux-dogtail-ui",
        "status = \"hosted-only\"",
        "$overallExitCode = 1",
        "manifest.json",
    ):
        if marker not in pre_submit:
            problems.append(f"pre-submit runner 缺少严格门禁契约: {marker}")
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
