from __future__ import annotations

import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _load_l10n_checker():
    path = ROOT / "lddc/tool/check_l10n_arb.py"
    spec = importlib.util.spec_from_file_location("check_l10n_arb", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载本地化检查器: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_git_hygiene_checker():
    path = ROOT / "tool/check_git_hygiene.py"
    spec = importlib.util.spec_from_file_location("check_git_hygiene", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 Git 卫生检查器: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_coverage_checker():
    path = ROOT / "tool/check_coverage.py"
    spec = importlib.util.spec_from_file_location("check_coverage", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载覆盖率检查器: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _load_ci_phase_summary():
    path = ROOT / "tool/test/ci_phase_summary.py"
    spec = importlib.util.spec_from_file_location("ci_phase_summary", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 CI 阶段汇总器: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _load_native_isolation_checker():
    path = ROOT / "tool/test/check_native_test_isolation.py"
    spec = importlib.util.spec_from_file_location("check_native_test_isolation", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载原生测试隔离检查器: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _resolved_capabilities(
    *,
    profile: str,
    platform: str,
    scenario: str,
    framework: str = "integration_test",
) -> dict[str, dict[str, object]]:
    path = ROOT / "tool/test/capability_matrix.py"
    spec = importlib.util.spec_from_file_location("capability_matrix", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载能力矩阵解析器: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    resolved = module.resolve_contract(
        module.load_matrix(),
        profile=profile,
        platform=platform,
        scenario=scenario,
        framework=framework,
    )
    return {
        name: {**state, "evidence": []}
        for name, state in resolved.items()
    }


def _complete_scenario_report(
    *,
    profile: str,
    platform: str,
    scenario: str,
    framework: str = "integration_test",
) -> dict[str, object]:
    return {
        "schemaVersion": 2,
        "runId": "quality-test-run",
        "scenario": scenario,
        "profile": profile,
        "platform": platform,
        "framework": framework,
        "gate": "required",
        "steps": [{"step": "opened", "success": True}],
        "status": "passed",
        "coverageStatus": "executed",
        "success": True,
        "capabilities": _resolved_capabilities(
            profile=profile,
            platform=platform,
            scenario=scenario,
            framework=framework,
        ),
        "resources": {"baseline": {}, "final": {}, "thresholds": {}},
        "runner": {
            "exitCode": 0,
            "originalReportType": "flutter-jsonl",
            "testStarted": True,
            "nativeActionCount": 0,
        },
        "artifacts": [],
        "extra": {},
    }


def _load_test_sensitivity_checker():
    path = ROOT / "tool/verify_test_sensitivity.py"
    spec = importlib.util.spec_from_file_location("verify_test_sensitivity", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载测试敏感性检查器: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class QualityToolTests(unittest.TestCase):
    def test_ci_phase_summary_accepts_only_all_success(self) -> None:
        module = _load_ci_phase_summary()
        phases = [
            module.parse_phase("build|Release build|success"),
            module.parse_phase("tests|Platform tests|success"),
        ]

        summary = module.render_summary("Windows validation", phases)

        self.assertIn("Required result: `success`", summary)
        self.assertTrue(all(phase.outcome == "success" for phase in phases))

    def test_ci_phase_summary_preserves_failure_kinds_and_marks_missing(self) -> None:
        module = _load_ci_phase_summary()
        phases = [
            module.parse_phase("failed|Failed phase|failure"),
            module.parse_phase("skipped|Skipped phase|skipped"),
            module.parse_phase("cancelled|Cancelled phase|cancelled"),
            module.parse_phase("missing|Missing phase|"),
        ]

        summary = module.render_summary("Required phases", phases)

        self.assertEqual(
            [phase.outcome for phase in phases],
            ["failure", "skipped", "cancelled", "missing"],
        )
        self.assertIn("Required result: `failure`", summary)

    def test_ci_phase_summary_returns_nonzero_and_writes_failure_summary(self) -> None:
        script = ROOT / "tool/test/ci_phase_summary.py"
        with tempfile.TemporaryDirectory() as temp:
            summary_path = Path(temp) / "step-summary.md"
            environment = os.environ.copy()
            environment["GITHUB_STEP_SUMMARY"] = str(summary_path)

            result = subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--title",
                    "iOS validation",
                    "--phase",
                    "system_ui|Document Picker|skipped",
                ],
                check=False,
                capture_output=True,
                text=True,
                env=environment,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("system_ui=skipped", result.stderr)
            self.assertIn(
                "Required result: `failure`",
                summary_path.read_text(encoding="utf-8"),
            )

    def test_coverage_parser_excludes_dependency_package_sources(self) -> None:
        checker = _load_coverage_checker()
        with tempfile.TemporaryDirectory() as temp:
            lcov = Path(temp) / "lcov.info"
            lcov.write_text(
                "SF:C:\\repo\\packages\\target\\lib\\target.dart\n"
                "DA:1,1\n"
                "end_of_record\n"
                "SF:C:\\repo\\packages\\dependency\\lib\\dependency.dart\n"
                "DA:1,0\n"
                "end_of_record\n"
                "SF:lib\\relative.dart\n"
                "DA:1,1\n"
                "end_of_record\n",
                encoding="utf-8",
            )

            coverage = checker.parse_lcov(lcov, "packages/target")

        self.assertEqual(
            sorted(coverage),
            [
                "packages/target/lib/relative.dart",
                "packages/target/lib/target.dart",
            ],
        )

    def test_test_sensitivity_manifest_targets_unique_source_and_test_text(self) -> None:
        checker = _load_test_sensitivity_checker()
        mutations = checker.load_manifest()

        self.assertEqual(
            [mutation.id for mutation in mutations],
            [
                "algorithm-instrumental-conflict",
                "qm-custom-des-round-count",
                "converter-ass-control-escaping",
            ],
        )
        for mutation in mutations:
            checker.validate_mutation(mutation)

    def test_all_ui_integration_flows_use_scenario_failure_reporting(self) -> None:
        flows = [
            "batch_convert_flow_test.dart",
            "local_match_flow_test.dart",
            "open_lyrics_flow_test.dart",
            "search_collection_flow_test.dart",
            "search_song_flow_test.dart",
            "settings_about_flow_test.dart",
        ]
        for name in flows:
            text = (ROOT / "lddc/integration_test" / name).read_text(encoding="utf-8")
            self.assertIn("await reporter.runScenario", text, name)
            self.assertIn("launchIntegrationApp", text, name)

    def test_desktop_window_contract_matches_all_native_runners(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tool/check_desktop_window_contract.py")],
            check=False,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8"))

    def test_release_metadata_has_no_external_icon_path(self) -> None:
        metadata = json.loads(
            (ROOT / "lddc/tool/release_metadata.json").read_text(encoding="utf-8")
        )
        source_dir = ROOT / "lddc/tool/resources/app_icon"

        self.assertEqual(
            set(metadata),
            {
                "appId",
                "displayName",
                "shortName",
                "publisher",
                "copyright",
                "description",
            },
        )
        self.assertTrue(source_dir.resolve().is_relative_to(ROOT.resolve()))
        self.assertTrue((source_dir / "logo.png").is_file())
        self.assertTrue((source_dir / "logo.ico").is_file())

    def test_git_hygiene_requires_stable_major_action_tags(self) -> None:
        checker = _load_git_hygiene_checker()
        fixed_sha = "a" * 40

        self.assertEqual(
            checker.invalid_action_references(
                "- uses: actions/checkout@v7\n"
                "- uses: owner/action@v2\n"
                "- uses: ./.github/actions/local\n"
            ),
            [],
        )
        self.assertEqual(
            checker.invalid_action_references(
                f"- uses: actions/checkout@{fixed_sha}\n"
                "- uses: owner/action@v2.1.0\n"
                "- uses: owner/action@main\n"
                "- uses: owner/action@latest\n"
            ),
            [
                f"actions/checkout@{fixed_sha}",
                "owner/action@v2.1.0",
                "owner/action@main",
                "owner/action@latest",
            ],
        )

    def test_git_hygiene_rejects_broad_database_ignore_patterns(self) -> None:
        checker = _load_git_hygiene_checker()

        self.assertEqual(
            checker.broad_database_ignore_patterns(
                """
                **/local_song_lyrics.db
                **/cache.sqlite3
                """
            ),
            [],
        )
        self.assertEqual(
            checker.broad_database_ignore_patterns(
                """
                *.db
                **/*.sqlite
                **/*.sqlite3
                """
            ),
            ["**/*.sqlite", "**/*.sqlite3", "*.db"],
        )

    def test_git_hygiene_allows_only_ruby_python_vectors(self) -> None:
        checker = _load_git_hygiene_checker()
        ruby_files = sorted(checker.RUBY_VECTOR_ALLOWLIST)

        self.assertEqual(checker.invalid_python_vector_artifacts(ruby_files), [])
        self.assertEqual(
            checker.invalid_python_vector_artifacts(
                [
                    *ruby_files,
                    "packages/core/test/resources/python_crypto_vectors.json",
                    "tool/generate_converter_vectors.py",
                    "test/support/crypto_vector_harness.dart",
                ]
            ),
            [
                "packages/core/test/resources/python_crypto_vectors.json",
                "test/support/crypto_vector_harness.dart",
                "tool/generate_converter_vectors.py",
            ],
        )
        self.assertEqual(
            checker.invalid_python_vector_references(
                "packages/core/test/crypto_test.dart",
                "load('python_crypto_vectors.json')",
            ),
            ["python_crypto_vectors.json"],
        )
        self.assertEqual(
            checker.invalid_python_vector_references(
                "packages/lddc_lyrics_core/test/ruby/ruby_engine_vector_test.dart",
                "load('python_ruby_vectors.json')",
            ),
            [],
        )

    def test_git_hygiene_validates_sanitized_fixtures(self) -> None:
        checker = _load_git_hygiene_checker()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            valid = root / "sanitized_valid.json"
            valid.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "cases": [
                            {
                                "originClass": "sanitized-unit",
                                "document": {
                                    "lyrics": {"orig": [[0, 1, [[0, 1, "line"]]]]}
                                },
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            invalid = root / "sanitized_invalid.json"
            invalid.write_text(
                json.dumps(
                    {
                        "cases": [
                            {
                                "originClass": "raw-user-record",
                                "songId": "real-id",
                                "url": "https://example.invalid/private",
                            }
                        ]
                    }
                ),
                encoding="utf-8",
            )

            self.assertEqual(
                checker.sanitized_fixture_failures(valid.name, valid),
                [],
            )
            failures = checker.sanitized_fixture_failures(invalid.name, invalid)
            self.assertTrue(any("originClass" in item for item in failures))
            self.assertTrue(any("禁止字段 songId" in item for item in failures))
            self.assertTrue(any("禁止字段 url" in item for item in failures))

    @unittest.skipIf(shutil.which("pwsh") is None, "当前环境没有 PowerShell 7")
    def test_integration_runner_enforces_profile_target_contract(self) -> None:
        runner = ROOT / "tool/test/run_real_integration.ps1"
        base_command = [
            "pwsh",
            "-NoProfile",
            "-File",
            str(runner),
            "-Profile",
            "offline",
            "-Device",
            "contract-device",
            "-Platform",
            "windows",
            "-ValidateOnly",
            "-Targets",
        ]

        accepted = subprocess.run(
            [*base_command, "integration_test/open_lyrics_flow_test.dart"],
            check=False,
            capture_output=True,
        )
        rejected = subprocess.run(
            [*base_command, "integration_test/platform_capability_smoke_test.dart"],
            check=False,
            capture_output=True,
        )

        self.assertEqual(accepted.returncode, 0)
        self.assertNotEqual(rejected.returncode, 0)

    @unittest.skipIf(shutil.which("pwsh") is None, "当前环境没有 PowerShell 7")
    def test_android_runner_only_retries_zero_test_reports(self) -> None:
        runner = ROOT / "tool/test/run_android_platform_tests.ps1"
        result = subprocess.run(
            [
                "pwsh",
                "-NoProfile",
                "-File",
                str(runner),
                "-ValidateReportParser",
            ],
            check=False,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))

    def test_pre_submit_runner_has_strict_local_and_hosted_boundaries(self) -> None:
        runner = (ROOT / "tool/test/run_pre_submit_checks.ps1").read_text(
            encoding="utf-8"
        )
        for marker in (
            "dart-format",
            "dart-analyze",
            "windows-local-match-integration",
            "apple-native-ui",
            "linux-dogtail-ui",
            "manifest.json",
            "status = \"hosted-only\"",
        ):
            self.assertIn(marker, runner)
        # 跳过本地必需项只能产生失败清单，不能把“未运行”伪装成成功。
        self.assertIn("$overallExitCode = 1", runner)
        self.assertIn("调用方显式跳过", runner)

    def test_macos_hybrid_runner_preserves_three_failure_origins(self) -> None:
        runner = (ROOT / "tool/test/run_macos_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        for marker in (
            "$xcodeReportDrainSeconds = 30",
            "$hybridNativeActionTimeoutSeconds + $xcodeReportDrainSeconds",
            'diagnostics=$diagnosticText',
            "$reportDrainAttempted = $true",
            '"flutter_failed_xcresult_drain_expired"',
            '"xctest_failed_flutter_terminated"',
            '"runner_scenario_deadline"',
            '"macOS xcresult summary 缺失或损坏"',
            '"macOS xcresult attachment 导出失败',
            '"runnerClassification"',
            "reportDrainAttempted = $ReportDrainAttempted",
            "-and [string]::IsNullOrWhiteSpace($runnerFailureMessage)",
            "-and [string]::IsNullOrWhiteSpace($xcresultReportError)",
            "-and $evidenceCandidates.Count -eq 1",
        ):
            self.assertIn(marker, runner)
        # 结果包错误只能写诊断字段，不能覆盖 Flutter/XCTest 原始失败原因。
        self.assertNotIn(
            '$runnerFailureMessage = "macOS xcresult attachment 导出失败',
            runner,
        )
        self.assertNotIn(
            '$runnerTerminationReason = "flutter_failed_xcresult_drain"',
            runner,
        )

    def test_macos_hybrid_gate_rejects_missing_edges_and_implicit_self(self) -> None:
        checker = _load_native_isolation_checker()
        flutter_source = (
            ROOT / "lddc/integration_test/macos_file_dialog_platform_test.dart"
        ).read_text(encoding="utf-8")
        ui_test_source = (
            ROOT / "lddc/macos/RunnerUITests/RunnerUITests.swift"
        ).read_text(encoding="utf-8")
        self.assertEqual(
            checker.macos_hybrid_source_failures(flutter_source, ui_test_source),
            [],
        )

        mutations = (
            (flutter_source.replace("operationEdges.started", "true", 1), ui_test_source),
            (flutter_source.replace("operationEdges.completed", "true", 1), ui_test_source),
            (
                flutter_source,
                ui_test_source.replace(
                    "self.addAction(&actions, capability: capability, action: action)",
                    "addAction(&actions, capability: capability, action: action)",
                    1,
                ),
            ),
        )
        for mutated_flutter, mutated_ui_test in mutations:
            self.assertNotEqual(
                checker.macos_hybrid_source_failures(
                    mutated_flutter,
                    mutated_ui_test,
                ),
                [],
            )

    def test_ios_picker_uses_positive_flutter_round_trip_and_stable_fixture(self) -> None:
        source = (ROOT / "lddc/ios/RunnerUITests/RunnerUITests.swift").read_text(
            encoding="utf-8"
        )
        for marker in (
            "private enum SystemPickerDestination: Equatable",
            "private func navigatePickerToFixtureDirectory(",
            "private func navigatePickerToOnMyIPhone(",
            "private func normalizePickerToBrowseRoot(",
            "private func waitForBackNavigation(",
            "private func waitForPickerDestination(",
            "requireFixtureCell(in: picker, timeout: 15)",
            "returnControl: openSong,",
            'action: "document_picker_fixture_cell_tapped"',
            'action: "document_picker_select_audio"',
            "waitForPreviewLyricsValue(preview: preview",
            "let value = preview.value as? String",
            "private func dismissKeyboardTutorialIfPresented(",
            'action: "keyboard_tutorial_dismissed"',
            "let resumedPicker = try waitForSystemPicker(app: launchedApp, timeout: 5)",
            'let save = try requireEnabledTypedButton(named: "Save", in: resumedPicker, timeout: 15)',
            "try waitForTypedCancelButton(",
            "let picker = try normalizePickerToBrowseRoot(app: app)",
            'action: "document_picker_typed_cancel_tapped"',
            "func testDocumentPickerCancellationRound1ReturnsToFlutter() throws",
            "func testDocumentPickerCancellationRound2ReturnsToFlutter() throws",
            "func testDocumentPickerCancellationRound3ReturnsToFlutter() throws",
            "private func runDocumentPickerCancellationRound(",
            'scenario: "ios_document_picker_cancel_1"',
            'scenario: "ios_document_picker_cancel_2"',
            'scenario: "ios_document_picker_cancel_3"',
            'action: "document_picker_cancel_round_\\(round)"',
        ):
            self.assertIn(marker, source)
        self.assertNotIn("isFixtureDirectory(", source)
        self.assertNotIn("waitForCurrentFixtureCell(", source)
        self.assertNotIn("pickerRootIdentity(", source)
        self.assertNotIn("waitForPickerRootChange(", source)
        self.assertNotIn("waitForSystemPickerToClose(", source)
        self.assertNotIn("waitForKeyboardTutorialToDisappear(", source)
        self.assertNotIn("preview.descendants(matching:", source)
        self.assertNotIn(".doubleTap()", source)

    def test_ios_cancellation_round_split_contract_rejects_mutations(self) -> None:
        checker = _load_native_isolation_checker()
        source = (ROOT / "lddc/ios/RunnerUITests/RunnerUITests.swift").read_text(
            encoding="utf-8"
        )
        runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        workflow = (
            ROOT / ".github/workflows/platform-stabilization.yml"
        ).read_text(encoding="utf-8")
        matrix = json.loads(
            (ROOT / "tool/test/platform_capability_matrix.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(checker.ios_picker_state_machine_failures(source), [])
        self.assertEqual(
            checker.ios_cancellation_split_contract_failures(
                runner,
                workflow,
                matrix,
            ),
            [],
        )

        ui_mutations = (
            source.replace(
                'action: "document_picker_cancel_round_\\(round)"',
                'for iteration in 1...3 {\n'
                '        action: "document_picker_cancel_iteration_\\(iteration)"\n'
                "      }",
                1,
            ),
            source.replace(
                "func testDocumentPickerCancellationRound1ReturnsToFlutter() throws",
                "func testDocumentPickerCancellationReturnsToFlutter() throws",
                1,
            ),
            source.replace(
                'scenario: "ios_document_picker_cancel_3"',
                'scenario: "ios_document_picker_cancel_missing"',
                1,
            ),
            source.replace(
                "waitForBackNavigation(",
                "waitForPickerDestination(",
                1,
            ),
            source.replace(
                "if waitForOnMyIPhoneLocation(in: picker, timeout: 0) != nil {",
                "if pickerDestination(picker) == .browseRoot {",
                1,
            ),
        )
        for index, mutation in enumerate(ui_mutations):
            with self.subTest(kind="ui", index=index):
                self.assertNotEqual(mutation, source)
                self.assertNotEqual(
                    checker.ios_picker_state_machine_failures(mutation),
                    [],
                )

        wrong_mapping = runner.replace(
            'Method = "testDocumentPickerCancellationRound2ReturnsToFlutter"',
            'Method = "testDocumentPickerCancellationRound1ReturnsToFlutter"',
            1,
        )
        old_workflow = workflow.replace(
            "-Scenarios $cancelScenarios",
            "-Scenarios ios_document_picker_cancel",
            1,
        )
        missing_round = json.loads(json.dumps(matrix))
        missing_round["contracts"] = [
            contract
            for contract in missing_round["contracts"]
            if contract.get("scenario") != "ios_document_picker_cancel_3"
        ]
        observation_round = json.loads(json.dumps(matrix))
        for contract in observation_round["contracts"]:
            if contract.get("scenario") == "ios_document_picker_cancel_2":
                contract["gate"] = "observation"

        cross_file_mutations = (
            (wrong_mapping, workflow, matrix),
            (runner, old_workflow, matrix),
            (runner, workflow, missing_round),
            (runner, workflow, observation_round),
        )
        for index, (mutated_runner, mutated_workflow, mutated_matrix) in enumerate(
            cross_file_mutations
        ):
            with self.subTest(kind="cross-file", index=index):
                self.assertNotEqual(
                    checker.ios_cancellation_split_contract_failures(
                        mutated_runner,
                        mutated_workflow,
                        mutated_matrix,
                    ),
                    [],
                )

    def test_ios_picker_state_machine_gate_rejects_disabled_and_unconverted_mutations(self) -> None:
        checker = _load_native_isolation_checker()
        source = (ROOT / "lddc/ios/RunnerUITests/RunnerUITests.swift").read_text(
            encoding="utf-8"
        )
        self.assertEqual(checker.ios_picker_state_machine_failures(source), [])

        mutations = (
            source.replace(
                "try convertLoadedLyrics(app: launchedApp, actions: &actions)",
                "// 受控 mutation：跳过转换",
                1,
            ),
            source.replace(
                "if element.exists, element.isHittable, element.isEnabled",
                "if element.exists, element.isHittable",
                1,
            ),
            source.replace(
                "let picker = try navigatePickerToFixtureDirectory(app: app)",
                "let picker = try waitForSystemPicker(app: app, timeout: 5)",
                1,
            ),
            source.replace(
                "returnControl: openSong,\n        timeout: 15",
                "returnControl: nil,\n        timeout: 15",
                1,
            ),
            source.replace("fixture.tap()", "fixture.doubleTap()", 1),
            source.replace(
                "        timeout: 15\n"
                "      ),\n"
                "      \"单击匿名音频后系统 Picker 没有关闭，记录 Files AX 激活观察失败\"",
                "        timeout: 0\n"
                "      ),\n"
                "      \"单击匿名音频后系统 Picker 没有关闭，记录 Files AX 激活观察失败\"",
                1,
            ),
            source.replace(
                "let picker = try navigatePickerToOnMyIPhone(app: launchedApp)",
                "let picker = try waitForSystemPicker(app: launchedApp, timeout: 5)",
                1,
            ),
            source.replace(
                "try dismissKeyboardTutorialIfPresented(in: picker, actions: &actions)",
                "// 受控 mutation：不处理首次键盘教学层",
                1,
            ),
            source.replace(
                "try waitForTypedCancelButton(",
                "try waitForUnsafeCancelButton(",
                1,
            ),
            source.replace(
                'try require(candidates.count < 2, "系统 Picker 的可操作 typed Cancel Button 不是唯一控件")',
                "// 受控 mutation：允许重复 Cancel",
                1,
            ),
            source.replace(
                "let picker = try normalizePickerToBrowseRoot(app: app)",
                "let picker = try waitForSystemPicker(app: app, timeout: 5)",
                1,
            ),
            source.replace(
                "_ = try normalizePickerToBrowseRoot(app: launchedApp)\n"
                "      launchedApp.terminate()",
                "launchedApp.terminate()",
                1,
            ),
        )
        for index, mutation in enumerate(mutations):
            with self.subTest(index=index):
                # 替换表达式本身也必须命中当前源码，避免源码缩进或结构变化后
                # mutation 静默退化为原文，令防回归测试产生假绿。
                self.assertNotEqual(mutation, source)
                self.assertNotEqual(
                    checker.ios_picker_state_machine_failures(mutation),
                    [],
                )

    def test_ios_export_witness_gate_rejects_missing_hash_cleanup_and_path_leaks(self) -> None:
        checker = _load_native_isolation_checker()
        app_delegate = (ROOT / "lddc/ios/Runner/AppDelegate.swift").read_text(
            encoding="utf-8"
        )
        runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            checker.ios_export_witness_failures(app_delegate, runner),
            [],
        )
        mutations = (
            (
                app_delegate.replace("SHA256.hash(data: data)", "Data(data)", 1),
                runner,
            ),
            (
                app_delegate.replace(
                    'payload["cleanupSucceeded"] = true',
                    'payload["cleanupSucceeded"] = false',
                    1,
                ),
                runner,
            ),
            (
                app_delegate.replace(
                    '"fileName": exportedURL.lastPathComponent,',
                    '"path": exportedURL.path,',
                    1,
                ),
                runner,
            ),
            (
                app_delegate.replace(
                    '"fileName": exportedURL.lastPathComponent,',
                    '"url": exportedURL.absoluteString,',
                    1,
                ),
                runner,
            ),
            (
                app_delegate.replace(
                    '"fileName": exportedURL.lastPathComponent,',
                    '"identifier": exportedURL.absoluteString,',
                    1,
                ),
                runner,
            ),
            (
                app_delegate,
                runner.replace(
                    '[Security.Cryptography.SHA256]::HashData($exportedBytes)',
                    '$witness.sha256',
                    1,
                ),
            ),
            (
                app_delegate,
                runner.replace(
                    "Remove-Item -LiteralPath $preScenarioWitness -Force -ErrorAction SilentlyContinue",
                    "# 受控 mutation：保留上一场景 witness",
                    1,
                ),
            ),
        )
        for mutated_app_delegate, mutated_runner in mutations:
            self.assertNotEqual(
                checker.ios_export_witness_failures(
                    mutated_app_delegate,
                    mutated_runner,
                ),
                [],
            )

    def test_ios_delegate_contract_gate_rejects_duplicate_state_and_missing_tests(self) -> None:
        checker = _load_native_isolation_checker()
        app_delegate = (ROOT / "lddc/ios/Runner/AppDelegate.swift").read_text(
            encoding="utf-8"
        )
        unit_tests = (ROOT / "lddc/ios/RunnerTests/RunnerTests.swift").read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            checker.ios_delegate_contract_failures(app_delegate, unit_tests),
            [],
        )
        duplicated_state = app_delegate.replace(
            "private var activePicker: UIDocumentPickerViewController?",
            "private var activePicker: UIDocumentPickerViewController?\n"
            "  private var pendingResult: FlutterResult?",
            1,
        )
        missing_test = unit_tests.replace(
            "testDocumentPickerCoordinatorReportsDescriptorOpenFailure",
            "removedDescriptorOpenFailureContract",
            1,
        )
        self.assertNotEqual(
            checker.ios_delegate_contract_failures(duplicated_state, unit_tests),
            [],
        )
        self.assertNotEqual(
            checker.ios_delegate_contract_failures(app_delegate, missing_test),
            [],
        )

    def test_macos_open_panel_requires_native_return_activation(self) -> None:
        checker = _load_native_isolation_checker()
        flutter_source = (
            ROOT / "lddc/integration_test/macos_file_dialog_platform_test.dart"
        ).read_text(encoding="utf-8")
        source = (ROOT / "lddc/macos/RunnerUITests/RunnerUITests.swift").read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            checker.macos_hybrid_source_failures(flutter_source, source),
            [],
        )
        for marker in (
            'panel.root.staticTexts["sizeAndKind"]',
            "waitForExactlyOneExistingElement(previewName, timeout: 10)",
            'waitForStringValueContaining(sizeAndKind, expected: "MP3", timeout: 10)',
            "fixture.typeKey(.return, modifierFlags: [])",
            'recordAction("filePicker", "fixture_return_activated")',
        ):
            self.assertIn(marker, source)
        self.assertNotIn("openButton.click()", source)

    def test_apple_runners_require_unique_xcode_products(self) -> None:
        for relative in (
            "tool/test/run_macos_platform_tests.ps1",
            "tool/test/run_ios_platform_tests.ps1",
        ):
            runner = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("Resolve-UniqueBuildArtifact", runner, relative)
            self.assertNotIn(
                'Filter "*.xctestrun" | Select-Object -First 1',
                runner,
                relative,
            )
        ios_runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        self.assertNotIn(
            'Filter "LDDC.app" | Select-Object -First 1',
            ios_runner,
        )
        self.assertIn("iOS Xcode DerivedData 超出测试构建根", ios_runner)

    def test_apple_runners_do_not_reassign_validated_parameters(self) -> None:
        checker = _load_native_isolation_checker()
        for relative in (
            "tool/test/run_macos_platform_tests.ps1",
            "tool/test/run_ios_platform_tests.ps1",
        ):
            runner = (ROOT / relative).read_text(encoding="utf-8")
            self.assertEqual(
                checker.validated_powershell_parameter_reassignments(runner),
                [],
                relative,
            )
            mutation = runner.replace(
                "$selectedScenarioEntries = if",
                "$scenarios = if",
                1,
            )
            self.assertEqual(
                checker.validated_powershell_parameter_reassignments(mutation),
                ["Scenarios"],
                relative,
            )

    def test_apple_stabilization_separates_required_and_observation_gates(self) -> None:
        runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        workflow = (
            ROOT / ".github/workflows/platform-stabilization.yml"
        ).read_text(encoding="utf-8")
        for marker in (
            "[string[]]$ObservationScenarios = @()",
            "$observationFilter.Contains($scenario)",
            "Add-ObservationEvidence",
            "$requiredScenarioDir",
            "$requiredJunitDir",
            "$observationFailureDetected = $false",
            "$requiredReports.Count -eq 0 -and $observationFailureDetected",
        ):
            self.assertIn(marker, runner)
        macos_runner = (
            ROOT / "tool/test/run_macos_platform_tests.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("$observationFailureDetected = $false", macos_runner)
        self.assertIn("[switch]$PreserveBuildProducts", runner)
        self.assertIn("[switch]$PreserveBuildProducts", macos_runner)
        self.assertIn(
            "$requiredReports.Count -eq 0 -and $observationFailureDetected",
            macos_runner,
        )
        for marker in (
            "ios-required:",
            "ios-files-observation:",
            "macos-required:",
            "macos-finder-observation:",
            "-ObservationScenarios",
            "run_apple_component_contracts.ps1",
            "-Device $env:DEVICE_ID",
            "-PreserveBuildProducts",
            "-ReportDir build/integration_reports/ios-native/component-contracts",
            "-ReportDir build/integration_reports/macos-native/component-contracts",
            "test-without-building",
            "find lddc/build/native_test_derived_data",
            "flutter build ios --debug --simulator --config-only",
            "flutter build macos --debug --config-only",
            "-only-testing:RunnerTests/IOSDocumentPickerCoordinatorTests",
            "-only-testing:RunnerTests/IOSDocumentPickerResourceTests",
        ):
            self.assertIn(marker, workflow)
        self.assertNotIn("-ExperimentalScenarios", workflow)
        self.assertNotIn("mapfile", workflow)
        self.assertIn('while IFS= read -r item; do xctestruns+=("$item")', workflow)

        matrix = json.loads(
            (ROOT / "tool/test/platform_capability_matrix.json").read_text(
                encoding="utf-8"
            )
        )
        gates = {
            contract.get("scenario"): contract.get("gate", "required")
            for contract in matrix["contracts"]
            if contract.get("platform") in {"ios", "macos"}
        }
        for scenario in (
            "ios_document_picker_cancel_1",
            "ios_document_picker_cancel_2",
            "ios_document_picker_cancel_3",
            "ios_media_business_round_trip",
            "macos_open_panel_cancel",
            "macos_file_result_adapter",
        ):
            self.assertEqual(gates[scenario], "required")
        for scenario in (
            "ios_document_picker_select",
            "ios_document_picker_export",
            "ios_document_picker_export_cancel",
            "ios_document_picker_export_termination",
            "macos_open_panel_select",
        ):
            self.assertEqual(gates[scenario], "observation")
        ios_media_contract = next(
            contract
            for contract in matrix["contracts"]
            if contract.get("scenario") == "ios_media_business_round_trip"
        )
        self.assertEqual(ios_media_contract["framework"], "integration_test")

        ios_media_test = (
            ROOT / "lddc/integration_test/ios_media_business_round_trip_test.dart"
        ).read_text(encoding="utf-8")
        self.assertIn("expect(Platform.isIOS, isTrue", ios_media_test)
        self.assertIn("FD 所有权和幂等关闭由 RunnerTests", ios_media_test)
        component_runner = (
            ROOT / "tool/test/run_apple_component_contracts.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("if (-not $IsMacOS)", component_runner)
        self.assertIn('"-d", $Device', component_runner)
        self.assertIn("--raw-report-type dart-jsonl", component_runner)
        self.assertIn('executionPlatform = if ($Platform -eq "ios")', component_runner)
        self.assertIn("Ensure-IosSimulatorVisibleToFlutter", component_runner)
        self.assertIn("simctl bootstatus", component_runner)
        self.assertIn("flutter devices --machine", component_runner)
        apple_component_test = (
            ROOT / "lddc/test/platform/files/app_file_picker_test.dart"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "debugDefaultTargetPlatformOverride = TargetPlatform.macOS",
            apple_component_test,
        )

    def test_apple_platform_schemes_include_native_and_ui_test_targets(self) -> None:
        for platform in ("ios", "macos"):
            scheme = ET.parse(
                ROOT
                / f"lddc/{platform}/Runner.xcodeproj/xcshareddata/xcschemes/RunnerPlatformTests.xcscheme"
            )
            testables = scheme.getroot().findall(".//TestableReference")
            testable_names = [
                reference.get("BuildableName")
                for testable in testables
                for reference in testable.findall("BuildableReference")
            ]
            build_names = [
                reference.get("BuildableName")
                for reference in scheme.getroot().findall(
                    ".//BuildActionEntry/BuildableReference"
                )
            ]
            self.assertCountEqual(
                testable_names,
                ["RunnerTests.xctest", "RunnerUITests.xctest"],
            )
            self.assertEqual(testable_names.count("RunnerTests.xctest"), 1)
            self.assertEqual(testable_names.count("RunnerUITests.xctest"), 1)
            self.assertEqual(build_names.count("RunnerTests.xctest"), 1)
            self.assertEqual(build_names.count("RunnerUITests.xctest"), 1)
            self.assertTrue(testables)
            self.assertTrue(
                all(testable.get("parallelizable") == "NO" for testable in testables)
            )

    def test_ios_simulator_creator_supports_local_and_ci_ownership(self) -> None:
        creator = (ROOT / "tool/test/create_ios_simulator.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn('if [[ -n "${GITHUB_ENV:-}" ]]', creator)
        self.assertIn("run_ios_platform_tests.ps1 -Device", creator)
        self.assertNotIn('xcrun simctl boot "$udid"', creator)
        self.assertIn("platform runner owns boot and cleanup", creator)
        # ERR trap 必须覆盖报告和环境交接；成功后才能把清理责任交给调用方。
        self.assertGreater(creator.rfind("trap - ERR"), creator.find('>"$report_path"'))
        self.assertGreater(creator.rfind("trap - ERR"), creator.find('>>"$GITHUB_ENV"'))

    def test_ios_build_is_decoupled_from_dynamic_destination(self) -> None:
        runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        workflow = (
            ROOT / ".github/workflows/platform-stabilization.yml"
        ).read_text(encoding="utf-8")
        build_match = re.search(
            r'Phase "ios-xcuitest-build-for-testing"[\s\S]{0,1200}?if \(\$buildExitCode -ne 0\)',
            runner,
        )
        self.assertIsNotNone(build_match)
        build_source = build_match.group(0)
        self.assertIn('"-destination", "generic/platform=iOS Simulator"', build_source)
        self.assertNotIn("id=$Device", build_source)
        for marker in (
            "Invoke-XcodeDestinationProbe",
            "Wait-XcodeDestinationReady",
            '@("xcdevice", "list", "--timeout", "5")',
            '"-showdestinations"',
            "Restart-SimulatorForDestinationRegistration",
            '"destination_registration_failure"',
            "Set-DestinationProbeMetadata -Probe $destinationProbe",
        ):
            self.assertIn(marker, runner)
        self.assertLess(
            runner.find('Wait-XcodeDestinationReady -Stage "initial"'),
            runner.find(
                "foreach ($entry in $selectedScenarioEntries)",
                runner.find('Wait-XcodeDestinationReady -Stage "initial"'),
            ),
        )
        for marker in (
            "runs-on: macos-26",
            "LDDC_XCODE_VERSION: '26.6'",
            "LDDC_IOS_RUNTIME_VERSION: '26.5'",
            "ios-required:",
            "ios-files-observation:",
        ):
            self.assertIn(marker, workflow)

    def test_ios_dynamic_destination_mutations_are_rejected(self) -> None:
        checker = _load_native_isolation_checker()
        source = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        self.assertEqual(checker.ios_destination_contract_failures(source), [])
        mutations = (
            source.replace(
                '"-destination", "generic/platform=iOS Simulator"',
                '"-destination", "platform=iOS Simulator,id=$Device,arch=$hostArchitecture"',
                1,
            ),
            source.replace("Wait-XcodeDestinationReady", "Wait-SimctlOnlyReady"),
            source.replace('"destination_registration_failure"', '"build_failure"', 1),
        )
        for mutation in mutations:
            self.assertNotEqual(checker.ios_destination_contract_failures(mutation), [])

    def test_ios_element_type_gate_rejects_collection_property_mutation(self) -> None:
        checker = _load_native_isolation_checker()
        self.assertEqual(
            checker.invalid_descendant_element_types(
                "preview.descendants(matching: .otherElements)"
            ),
            ["otherElements"],
        )
        self.assertEqual(
            checker.invalid_descendant_element_types(
                "preview.descendants(matching: .other)"
            ),
            [],
        )

    def test_local_match_driver_keeps_real_keyed_tile_contract(self) -> None:
        source = (
            ROOT / "lddc/integration_test/support/integration_drivers.dart"
        ).read_text(encoding="utf-8")
        match = re.search(
            r"Future<void> toggleSkipExisting\(\) async \{(?P<body>.*?)\n  \}",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(match)
        body = match.group("body")
        self.assertIn("tile.evaluate().length != 1", body)
        self.assertIn("tileWidget is! CheckboxListTile", body)
        self.assertIn("tileWidget.onChanged == null", body)
        self.assertIn("await tapVisible(tester, tile", body)
        self.assertNotIn("find.descendant(", body)
        self.assertNotIn("find.byType(Checkbox)", body)
        self.assertNotIn(".title", body)
        self.assertNotIn("find.byWidget(", body)

    def test_l10n_structure_distinguishes_template_tokens_from_html(self) -> None:
        checker = _load_l10n_checker()
        structure = checker._message_structure(
            "Title: %<title> <strong>{count, plural, other{files}}</strong>"
        )

        self.assertEqual(structure[0], {("count", "plural")})
        self.assertEqual(structure[1], [("", "strong"), ("/", "strong")])
        self.assertEqual(structure[2], ["title"])

    def test_l10n_structure_rejects_translated_template_token(self) -> None:
        checker = _load_l10n_checker()

        self.assertNotEqual(
            checker._message_structure("Album: %<album>"),
            checker._message_structure("アルバム: %<アルバム>"),
        )

    def test_coverage_checker_accepts_line_branch_and_changed_thresholds(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            lcov = root / "lcov.info"
            diff = root / "changed.diff"
            lcov.write_text(
                "SF:lib/example.dart\nDA:1,1\nDA:2,0\nBRDA:1,0,0,1\nBRDA:2,0,0,0\nend_of_record\n",
                encoding="utf-8",
            )
            diff.write_text(
                "+++ b/app/lib/example.dart\n@@ -0,0 +1,1 @@\n+return true;\n",
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool/check_coverage.py"),
                    "--input",
                    f"{lcov}=app",
                    "--minimum-line",
                    "50",
                    "--minimum-branch",
                    "50",
                    "--diff",
                    str(diff),
                ],
                check=False,
            )
            self.assertEqual(result.returncode, 0)

    def test_integration_report_verifier_rejects_skipped_report(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scenario.json").write_text(
                json.dumps(
                    {
                        "profile": "offline",
                        "device": "windows",
                        "steps": [],
                        "status": "skipped",
                        "coverageStatus": "skipped",
                        "success": False,
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool/test/verify_integration_reports.py"),
                    "--directory",
                    str(root),
                    "--profile",
                    "offline",
                    "--platform",
                    "windows",
                    "--run-id",
                    "quality-test-run",
                ],
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)

    def test_integration_report_verifier_rejects_ui_report_without_viewport(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scenario.json").write_text(
                json.dumps(
                    {
                        "scenario": "open_lyrics_flow",
                        "profile": "offline",
                        "device": "windows",
                        "steps": [{"step": "opened", "success": True}],
                        "status": "passed",
                        "coverageStatus": "executed",
                        "success": True,
                        "extra": {},
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool/test/verify_integration_reports.py"),
                    "--directory",
                    str(root),
                    "--profile",
                    "offline",
                    "--platform",
                    "windows",
                    "--run-id",
                    "quality-test-run",
                ],
                check=False,
            )

            self.assertNotEqual(result.returncode, 0)

    def test_integration_report_verifier_accepts_complete_offline_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "scenario.json").write_text(
                json.dumps(
                    _complete_scenario_report(
                        profile="offline",
                        platform="windows",
                        scenario="contract_only",
                    )
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool/test/verify_integration_reports.py"),
                    "--directory",
                    str(root),
                    "--profile",
                    "offline",
                    "--platform",
                    "windows",
                    "--run-id",
                    "quality-test-run",
                ],
                check=False,
            )

            self.assertEqual(result.returncode, 0)

    def test_integration_report_verifier_rejects_platform_fake_and_zero_actions(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = _complete_scenario_report(
                profile="platform",
                platform="windows",
                scenario="platform_capability_smoke",
            )
            capabilities = payload["capabilities"]
            assert isinstance(capabilities, dict)
            file_picker = capabilities["filePicker"]
            assert isinstance(file_picker, dict)
            file_picker.update(
                {
                    "mode": "scripted",
                    "applicable": True,
                    "reason": "错误降级",
                }
            )
            (root / "scenario.json").write_text(
                json.dumps(payload),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool/test/verify_integration_reports.py"),
                    "--directory",
                    str(root),
                    "--profile",
                    "platform",
                    "--platform",
                    "windows",
                    "--run-id",
                    "quality-test-run",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("filePicker", result.stderr)
            self.assertIn("没有能力证据", result.stderr)

    def test_integration_report_verifier_requires_component_verified_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payload = _complete_scenario_report(
                profile="platform",
                platform="ios",
                scenario="ios_media_business_round_trip",
                framework="integration_test",
            )
            (root / "scenario.json").write_text(
                json.dumps(payload),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool/test/verify_integration_reports.py"),
                    "--directory",
                    str(root),
                    "--profile",
                    "platform",
                    "--platform",
                    "ios",
                    "--run-id",
                    "quality-test-run",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("filePicker=componentVerified", result.stderr)
            self.assertIn("没有能力证据", result.stderr)

    def test_platform_capability_matrix_is_platform_and_scenario_specific(self) -> None:
        android = _resolved_capabilities(
            profile="platform",
            platform="android",
            scenario="platform_capability_smoke",
        )
        windows = _resolved_capabilities(
            profile="platform",
            platform="windows",
            scenario="platform_capability_smoke",
        )
        live_collection = _resolved_capabilities(
            profile="live",
            platform="linux",
            scenario="search_collection_flow",
        )
        media = _resolved_capabilities(
            profile="platform",
            platform="windows",
            scenario="platform_media_resource",
            framework="dart-native-assets",
        )
        android_media = _resolved_capabilities(
            profile="platform",
            platform="android",
            scenario="android_documentsui_select",
            framework="uiautomator",
        )
        ios_media = _resolved_capabilities(
            profile="platform",
            platform="ios",
            scenario="ios_document_picker_select",
            framework="xcuitest",
        )

        self.assertEqual(android["windowHost"]["mode"], "notApplicable")
        self.assertFalse(android["windowHost"]["applicable"])
        self.assertEqual(windows["windowHost"]["mode"], "real")
        self.assertTrue(windows["windowHost"]["required"])
        self.assertEqual(live_collection["network"]["mode"], "real")
        self.assertEqual(live_collection["translation"]["mode"], "notApplicable")
        self.assertEqual(media["media"]["mode"], "real")
        self.assertTrue(media["media"]["required"])
        self.assertEqual(media["resourceCleanup"]["mode"], "real")
        self.assertEqual(media["desktopProcess"]["mode"], "notApplicable")
        self.assertEqual(android_media["media"]["mode"], "real")
        self.assertTrue(android_media["media"]["required"])
        self.assertEqual(ios_media["media"]["mode"], "real")
        self.assertTrue(ios_media["media"]["required"])

    def test_platform_fixture_verifier_rejects_hash_drift(self) -> None:
        source = ROOT / "lddc/integration_test/fixtures/media"
        verifier = ROOT / "tool/test/verify_platform_fixtures.py"
        with tempfile.TemporaryDirectory() as temp:
            copied = Path(temp) / "media"
            shutil.copytree(source, copied)
            accepted = subprocess.run(
                [
                    sys.executable,
                    str(verifier),
                    "--manifest",
                    str(copied / "manifest.json"),
                ],
                check=False,
                capture_output=True,
            )
            (copied / "audio_sample.wav").write_bytes(b"changed")
            rejected = subprocess.run(
                [
                    sys.executable,
                    str(verifier),
                    "--manifest",
                    str(copied / "manifest.json"),
                ],
                check=False,
                capture_output=True,
            )

            self.assertEqual(accepted.returncode, 0)
            self.assertNotEqual(rejected.returncode, 0)

    def test_native_normalizer_and_verifier_reject_missing_cleanup_evidence(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        verifier = ROOT / "tool/test/verify_integration_reports.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario_dir = root / "scenarios"
            scenario_dir.mkdir()
            raw = root / "android.xml"
            evidence = root / "evidence.json"
            scenario = scenario_dir / "scenario.json"
            raw.write_text(
                '<testsuite name="android" tests="1" failures="0" errors="0" skipped="0">'
                '<testcase classname="DocumentsUi" name="cancel" />'
                "</testsuite>",
                encoding="utf-8",
            )
            payload = {
                "runId": "native-quality-run",
                "scenario": "android_documentsui_cancel",
                "profile": "platform",
                "platform": "android",
                "framework": "uiautomator",
                "steps": [{"step": "cancel", "success": True}],
                "capabilityEvidence": {
                    "filePicker": [{"action": "documentsui_cancel"}],
                    "nativeChannels": [{"action": "flutter_cancel_round_trip"}],
                    "resourceCleanup": [{"action": "resources_at_baseline"}],
                },
                "resources": {
                    "baseline": {"openFdCount": 0, "pendingPickerCount": 0},
                    "final": {"openFdCount": 0, "pendingPickerCount": 0},
                    "thresholds": {"openFdCount": 0, "pendingPickerCount": 0},
                },
                "artifacts": [],
                "extra": {},
            }
            evidence.write_text(json.dumps(payload), encoding="utf-8")
            normalized = subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "android-junit-xml",
                    "--framework",
                    "uiautomator",
                    "--exit-code",
                    "0",
                    "--evidence",
                    str(evidence),
                ],
                check=False,
            )
            accepted = subprocess.run(
                [
                    sys.executable,
                    str(verifier),
                    "--directory",
                    str(scenario_dir),
                    "--profile",
                    "platform",
                    "--platform",
                    "android",
                    "--run-id",
                    "native-quality-run",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            report = json.loads(scenario.read_text(encoding="utf-8"))
            resource_mutation = json.loads(json.dumps(report))
            resource_mutation["resources"]["final"]["pendingPickerCount"] = 1
            scenario.write_text(json.dumps(resource_mutation), encoding="utf-8")
            rejected_resources = subprocess.run(
                [
                    sys.executable,
                    str(verifier),
                    "--directory",
                    str(scenario_dir),
                    "--profile",
                    "platform",
                    "--platform",
                    "android",
                    "--run-id",
                    "native-quality-run",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            scenario.write_text(json.dumps(report), encoding="utf-8")
            report["capabilities"]["resourceCleanup"]["evidence"] = []
            report["runner"]["nativeActionCount"] = 2
            scenario.write_text(json.dumps(report), encoding="utf-8")
            rejected = subprocess.run(
                [
                    sys.executable,
                    str(verifier),
                    "--directory",
                    str(scenario_dir),
                    "--profile",
                    "platform",
                    "--platform",
                    "android",
                    "--run-id",
                    "native-quality-run",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(normalized.returncode, 0)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("resourceCleanup", rejected.stderr)
            self.assertNotEqual(rejected_resources.returncode, 0)
            self.assertIn("超过阈值", rejected_resources.stderr)

    def test_native_normalizer_marks_unstarted_xcresult_as_not_exercised(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario = root / "scenario.json"
            raw = root / "scenario.summary.json"
            evidence = root / "evidence.json"
            raw.write_text(
                json.dumps(
                    {
                        "totalTestCount": 0,
                        "passedTests": 0,
                        "failedTests": 1,
                        "skippedTests": 0,
                    }
                ),
                encoding="utf-8",
            )
            evidence.write_text(
                json.dumps(
                    {
                        "runId": "ios-build-failure",
                        "scenario": "ios_document_picker_select",
                        "profile": "platform",
                        "platform": "ios",
                        "framework": "xcuitest",
                        "steps": [
                            {
                                "step": "build",
                                "success": False,
                                "error": "build failure",
                            }
                        ],
                        "capabilityEvidence": {},
                        "resources": {
                            "baseline": {},
                            "final": {},
                            "thresholds": {},
                        },
                        "artifacts": [],
                        "extra": {
                            "failureClass": "build_failure",
                            "resourceMeasurementStatus": (
                                "not_exercised_before_test_start"
                            ),
                        },
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "xcresult-summary",
                    "--framework",
                    "xcuitest",
                    "--exit-code",
                    "1",
                    "--evidence",
                    str(evidence),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(scenario.read_text(encoding="utf-8"))
            self.assertFalse(report["runner"]["testStarted"])
            self.assertEqual(report["coverageStatus"], "notExercised")
            self.assertEqual(report["resources"]["baseline"], {})

    def test_flutter_normalizer_writes_failure_reports_for_invalid_mobile_json(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario = root / "batch_convert_flow.json"
            raw = root / "batch_convert_flow.jsonl"
            junit = root / "batch_convert_flow.xml"
            scenario.write_text(
                "run-as: unknown package: com.cmzj.lddc\n", encoding="utf-8"
            )
            raw.write_text("", encoding="utf-8")

            result = subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "flutter-jsonl",
                    "--framework",
                    "integration_test",
                    "--exit-code",
                    "1",
                    "--run-id",
                    "offline-android-test",
                    "--scenario",
                    "batch_convert_flow",
                    "--profile",
                    "offline",
                    "--platform",
                    "android",
                    "--failure-junit",
                    str(junit),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            report = json.loads(scenario.read_text(encoding="utf-8"))
            self.assertFalse(report["success"])
            self.assertEqual(report["status"], "failed")
            self.assertIn("规范化失败", report["extra"]["infrastructureFailure"])
            suite = ET.parse(junit).getroot()
            self.assertEqual(suite.get("failures"), "1")

    def test_flutter_normalizer_overrides_passing_junit_when_runner_failed(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario = root / "platform_capability_smoke.json"
            raw = root / "platform_capability_smoke.jsonl"
            junit = root / "platform_capability_smoke.xml"
            payload = _complete_scenario_report(
                profile="platform",
                platform="android",
                scenario="platform_capability_smoke",
            )
            scenario.write_text(json.dumps(payload), encoding="utf-8")
            raw.write_text(
                json.dumps({"type": "testStart", "test": {"id": 1}}) + "\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "flutter-jsonl",
                    "--framework",
                    "integration_test",
                    "--exit-code",
                    "1",
                    "--failure-junit",
                    str(junit),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            normalized = json.loads(scenario.read_text(encoding="utf-8"))
            self.assertFalse(normalized["success"])
            self.assertEqual(ET.parse(junit).getroot().get("failures"), "1")

    def test_flutter_normalizer_preserves_native_failure_when_scenario_is_missing(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        framework = "integration_test+xcuitest"
        scenario_name = "macos_open_panel_select"
        native_error = "NSOpenPanel 的精确 fixture 候选数量不是一个可命中目标"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario = root / "scenario.json"
            raw = root / "flutter.jsonl"
            evidence = root / "evidence.json"
            junit = root / "scenario.xml"
            raw.write_text(
                json.dumps({"type": "testStart", "test": {"id": 1}}) + "\n",
                encoding="utf-8",
            )
            evidence.write_text(
                json.dumps(
                    {
                        "runId": "macos-hybrid-failure",
                        "scenario": scenario_name,
                        "profile": "platform",
                        "platform": "macos",
                        "framework": framework,
                        "steps": [
                            {
                                "step": "xcuitest_native_panel_action",
                                "success": False,
                                "error": native_error,
                            }
                        ],
                        "capabilityEvidence": {
                            "resourceCleanup": [
                                {"action": "flutter_and_xcuitest_processes_closed"}
                            ]
                        },
                        "resources": {
                            "baseline": {"childProcessCount": 0},
                            "final": {"childProcessCount": 0},
                            "thresholds": {"childProcessCount": 0},
                        },
                        "artifacts": [],
                        "extra": {"xctestExitCode": 65},
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "flutter-jsonl",
                    "--framework",
                    framework,
                    "--exit-code",
                    "1",
                    "--evidence",
                    str(evidence),
                    "--run-id",
                    "macos-hybrid-failure",
                    "--scenario",
                    scenario_name,
                    "--profile",
                    "platform",
                    "--platform",
                    "macos",
                    "--failure-junit",
                    str(junit),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(scenario.read_text(encoding="utf-8"))
            self.assertFalse(report["success"])
            self.assertEqual(report["coverageStatus"], "executed")
            self.assertEqual(report["steps"][0]["error"], native_error)
            self.assertIn(
                "场景报告不存在",
                report["extra"]["flutterScenarioReportFailure"],
            )
            failure = ET.parse(junit).getroot().find(".//failure")
            self.assertIsNotNone(failure)
            self.assertEqual(failure.get("message"), native_error)

    def test_flutter_normalizer_missing_scenario_cannot_pass_with_success_evidence(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        framework = "integration_test+xcuitest"
        scenario_name = "macos_open_panel_cancel"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario = root / "scenario.json"
            raw = root / "flutter.jsonl"
            evidence = root / "evidence.json"
            raw.write_text(
                json.dumps({"type": "testStart", "test": {"id": 1}}) + "\n",
                encoding="utf-8",
            )
            evidence.write_text(
                json.dumps(
                    {
                        "runId": "macos-hybrid-missing",
                        "scenario": scenario_name,
                        "profile": "platform",
                        "platform": "macos",
                        "framework": framework,
                        "steps": [{"step": "xcuitest_cancel", "success": True}],
                        "capabilityEvidence": {
                            "filePicker": [{"action": "cancel"}],
                            "windowHost": [{"action": "native_panel"}],
                            "resourceCleanup": [{"action": "closed"}],
                        },
                        "resources": {
                            "baseline": {},
                            "final": {},
                            "thresholds": {},
                        },
                        "artifacts": [],
                        "extra": {},
                    }
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "flutter-jsonl",
                    "--framework",
                    framework,
                    "--exit-code",
                    "0",
                    "--evidence",
                    str(evidence),
                    "--run-id",
                    "macos-hybrid-missing",
                    "--scenario",
                    scenario_name,
                    "--profile",
                    "platform",
                    "--platform",
                    "macos",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(scenario.read_text(encoding="utf-8"))
            self.assertFalse(report["success"])
            self.assertEqual(report["status"], "failed")
            self.assertFalse(report["steps"][-1]["success"])
            self.assertIn("场景报告不存在", report["steps"][-1]["error"])

    def test_flutter_normalizer_merges_flaui_evidence_and_rejects_mismatch(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        framework = "integration_test+flaui-uia3"
        scenario_name = "windows_file_dialog_cancel"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario = root / "scenario.json"
            raw = root / "flutter.jsonl"
            evidence = root / "evidence.json"
            capabilities = _resolved_capabilities(
                profile="platform",
                platform="windows",
                scenario=scenario_name,
                framework=framework,
            )
            capabilities["nativeChannels"]["evidence"] = [
                {"action": "returned_to_flutter"}
            ]
            capabilities["desktopProcess"]["evidence"] = [
                {"action": "real_app"}
            ]
            scenario.write_text(
                json.dumps(
                    {
                        "schemaVersion": 2,
                        "runId": "hybrid-run",
                        "scenario": scenario_name,
                        "profile": "platform",
                        "platform": "windows",
                        "framework": framework,
                        "capabilities": capabilities,
                        "resources": {"baseline": {}, "final": {}, "thresholds": {}},
                        "runner": {},
                        "artifacts": [],
                        "steps": [{"step": "flutter", "success": True}],
                        "status": "passed",
                        "coverageStatus": "executed",
                        "success": True,
                        "extra": {},
                    }
                ),
                encoding="utf-8",
            )
            raw.write_text(
                json.dumps({"type": "testStart", "test": {"id": 1}}) + "\n",
                encoding="utf-8",
            )
            native_payload = {
                "runId": "hybrid-run",
                "scenario": scenario_name,
                "profile": "platform",
                "platform": "windows",
                "framework": framework,
                "steps": [{"step": "flaui", "success": True}],
                "capabilityEvidence": {
                    "filePicker": [{"action": "cancel"}],
                    "windowHost": [{"action": "dialog"}],
                    "resourceCleanup": [{"action": "closed"}],
                },
                "resources": {
                    "baseline": {"childProcessCount": 0},
                    "final": {"childProcessCount": 0},
                    "thresholds": {"childProcessCount": 0},
                },
                "artifacts": [],
                "extra": {"nativeFramework": "flaui-uia3"},
            }
            evidence.write_text(json.dumps(native_payload), encoding="utf-8")
            command = [
                sys.executable,
                str(normalizer),
                "--scenario-report",
                str(scenario),
                "--raw-report",
                str(raw),
                "--raw-report-type",
                "flutter-jsonl",
                "--framework",
                framework,
                "--exit-code",
                "0",
                "--evidence",
                str(evidence),
            ]
            merged = subprocess.run(command, check=False, capture_output=True, text=True)
            self.assertEqual(merged.returncode, 0, merged.stderr)
            result = json.loads(scenario.read_text(encoding="utf-8"))
            self.assertTrue(result["success"])
            self.assertEqual(result["runner"]["nativeActionCount"], 5)
            self.assertEqual(len(result["steps"]), 2)
            self.assertEqual(result["resources"]["final"]["childProcessCount"], 0)

            native_payload["scenario"] = "windows_file_dialog_select"
            evidence.write_text(json.dumps(native_payload), encoding="utf-8")
            rejected = subprocess.run(command, check=False, capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)

    def test_trx_converter_preserves_failure_and_skip_outcomes(self) -> None:
        converter = ROOT / "tool/test/trx_to_junit.py"
        namespace = "http://microsoft.com/schemas/VisualStudio/TeamTest/2010"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "result.trx"
            target = root / "result.xml"
            source.write_text(
                f'''<?xml version="1.0" encoding="utf-8"?>
<TestRun xmlns="{namespace}">
  <Results>
    <UnitTestResult testName="passed" outcome="Passed" duration="00:00:01.250" />
    <UnitTestResult testName="failed" outcome="Failed" duration="00:00:00.500">
      <Output><ErrorInfo><Message>expected failure</Message><StackTrace>stack</StackTrace></ErrorInfo></Output>
    </UnitTestResult>
    <UnitTestResult testName="skipped" outcome="NotExecuted" />
  </Results>
</TestRun>''',
                encoding="utf-8",
            )
            converted = subprocess.run(
                [
                    sys.executable,
                    str(converter),
                    "--input",
                    str(source),
                    "--output",
                    str(target),
                    "--scenario",
                    "windows_file_dialog_select",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(converted.returncode, 0, converted.stderr)
            suite = ET.parse(target).getroot()
            self.assertEqual(suite.get("tests"), "3")
            self.assertEqual(suite.get("failures"), "1")
            self.assertEqual(suite.get("errors"), "0")
            self.assertEqual(suite.get("skipped"), "1")
            self.assertIsNone(suite.find("./testcase[@name='passed']/failure"))
            failure = suite.find("./testcase[@name='failed']/failure")
            self.assertIsNotNone(failure)
            self.assertEqual(failure.get("message"), "expected failure")

    def test_dart_process_jsonl_rejects_skipped_execution(self) -> None:
        normalizer = ROOT / "tool/test/normalize_integration_report.py"
        verifier = ROOT / "tool/test/verify_integration_reports.py"
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            scenario_dir = root / "scenarios"
            scenario_dir.mkdir()
            raw = root / "process.jsonl"
            evidence = root / "evidence.json"
            scenario = scenario_dir / "desktop_real_process.json"
            start = {
                "type": "testStart",
                "test": {"id": 1, "name": "desktop process"},
            }
            done = {
                "type": "testDone",
                "testID": 1,
                "result": "success",
                "skipped": False,
            }
            raw.write_text(
                "\n".join((json.dumps(start), json.dumps(done))) + "\n",
                encoding="utf-8",
            )
            evidence.write_text(
                json.dumps(
                    {
                        "runId": "desktop-process-quality",
                        "scenario": "desktop_real_process",
                        "profile": "platform",
                        "platform": "windows",
                        "framework": "dart-process-e2e",
                        "steps": [
                            {"step": "desktop_real_process", "success": True}
                        ],
                        "capabilityEvidence": {
                            "nativeChannels": [{"action": "loopback_hello"}],
                            "desktopProcess": [{"action": "primary_started"}],
                            "resourceCleanup": [{"action": "resources_released"}],
                        },
                        "resources": {
                            "baseline": {"childProcessCount": 0},
                            "final": {"childProcessCount": 0},
                            "thresholds": {"childProcessCount": 0},
                        },
                        "artifacts": [],
                        "extra": {},
                    }
                ),
                encoding="utf-8",
            )

            normalized = subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "dart-jsonl",
                    "--framework",
                    "dart-process-e2e",
                    "--exit-code",
                    "0",
                    "--evidence",
                    str(evidence),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            accepted = subprocess.run(
                [
                    sys.executable,
                    str(verifier),
                    "--directory",
                    str(scenario_dir),
                    "--profile",
                    "platform",
                    "--platform",
                    "windows",
                    "--run-id",
                    "desktop-process-quality",
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            done["result"] = "skipped"
            done["skipped"] = True
            raw.write_text(
                "\n".join((json.dumps(start), json.dumps(done))) + "\n",
                encoding="utf-8",
            )
            subprocess.run(
                [
                    sys.executable,
                    str(normalizer),
                    "--scenario-report",
                    str(scenario),
                    "--raw-report",
                    str(raw),
                    "--raw-report-type",
                    "dart-jsonl",
                    "--framework",
                    "dart-process-e2e",
                    "--exit-code",
                    "0",
                    "--evidence",
                    str(evidence),
                ],
                check=False,
            )
            rejected = subprocess.run(
                [
                    sys.executable,
                    str(verifier),
                    "--directory",
                    str(scenario_dir),
                    "--profile",
                    "platform",
                    "--platform",
                    "windows",
                    "--run-id",
                    "desktop-process-quality",
                ],
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(normalized.returncode, 0, normalized.stderr)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("跳过", rejected.stderr)


if __name__ == "__main__":
    unittest.main()
