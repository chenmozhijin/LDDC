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
    *, profile: str, platform: str, scenario: str
) -> dict[str, object]:
    return {
        "schemaVersion": 2,
        "runId": "quality-test-run",
        "scenario": scenario,
        "profile": profile,
        "platform": platform,
        "framework": "integration_test",
        "steps": [{"step": "opened", "success": True}],
        "status": "passed",
        "coverageStatus": "executed",
        "success": True,
        "capabilities": _resolved_capabilities(
            profile=profile,
            platform=platform,
            scenario=scenario,
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

    def test_ios_simulator_creator_supports_local_and_ci_ownership(self) -> None:
        creator = (ROOT / "tool/test/create_ios_simulator.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn('if [[ -n "${GITHUB_ENV:-}" ]]', creator)
        self.assertIn("run_ios_platform_tests.ps1 -Device", creator)
        # ERR trap 必须覆盖报告和环境交接；成功后才能把清理责任交给调用方。
        self.assertGreater(creator.rfind("trap - ERR"), creator.find('>"$report_path"'))
        self.assertGreater(creator.rfind("trap - ERR"), creator.find('>>"$GITHUB_ENV"'))

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

    def test_local_match_driver_keeps_checkbox_descendant_contract(self) -> None:
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
        self.assertIn("find.descendant(", body)
        self.assertIn("find.byType(Checkbox)", body)
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
            self.assertIn("没有真实调用证据", result.stderr)

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


    def test_ios_cancellation_round_contract_rejects_regressions(self) -> None:
        checker = _load_native_isolation_checker()
        source = (ROOT / "lddc/ios/RunnerUITests/RunnerUITests.swift").read_text(
            encoding="utf-8"
        )
        runner = (ROOT / "tool/test/run_ios_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        workflow = (
            ROOT / ".github/workflows/cross-platform-validation.yml"
        ).read_text(encoding="utf-8")
        matrix = json.loads(
            (ROOT / "tool/test/platform_capability_matrix.json").read_text(
                encoding="utf-8"
            )
        )

        self.assertEqual(checker.ios_picker_cancellation_failures(source), [])
        self.assertEqual(
            checker.ios_cancellation_split_contract_failures(
                runner,
                workflow,
                matrix,
            ),
            [],
        )

        source_mutations = (
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
            source.replace("for _ in 0..<2", "for _ in 0..<4", 1),
            source.replace(
                "query.element(boundBy: index)",
                "query.allElementsBoundByIndex[index]",
                1,
            ),
            source.replace(
                "actionBudgetSeconds: cancellationRoundActionBudgetSeconds",
                "actionBudgetSeconds: 120",
                1,
            ),
            source.replace("executionTimeAllowance = 120", "executionTimeAllowance = 180", 1),
            source.replace(
                '    cleanupDiagnostics["pickerCleanupStrategy"] = '
                '"terminate_app_without_repeating_picker_navigation"',
                "    try? cancelSystemPicker(app: app)\n"
                '    cleanupDiagnostics["pickerCleanupStrategy"] = '
                '"terminate_app_without_repeating_picker_navigation"',
                1,
            ),
            source.replace(
                "    let picker = try normalizePickerToBrowseRoot(\n"
                "      app: app,\n"
                "      cancellationContext: cancellationContext\n"
                "    )",
                "    let picker = try waitForSystemPicker(app: app, timeout: 5)",
                1,
            ),
        )
        for index, mutation in enumerate(source_mutations):
            with self.subTest(kind="swift", index=index):
                self.assertNotEqual(mutation, source)
                self.assertNotEqual(
                    checker.ios_picker_cancellation_failures(mutation),
                    [],
                )

        wrong_mapping = runner.replace(
            'Method = "testDocumentPickerCancellationRound2ReturnsToFlutter"',
            'Method = "testDocumentPickerCancellationRound1ReturnsToFlutter"',
            1,
        )
        wrong_observation_mapping = runner.replace(
            'Name = "ios_document_picker_select"\n    Method = '
            '"testDocumentPickerSelectsSeededAudio"',
            'Name = "ios_document_picker_select"\n    Method = '
            '"testDocumentPickerCancellationRound1ReturnsToFlutter"',
            1,
        )
        old_workflow = workflow.replace(
            "-Scenarios " + chr(36) + "cancelScenarios",
            "-Scenarios ios_document_picker_cancel",
            1,
        )
        missing_observation_declaration = workflow.replace(
            "-ObservationScenarios " + chr(36) + "filesObservationScenarios",
            "",
            1,
        )
        observation_in_required_summary = workflow.replace(
            "--phase 'picker_cancel_required|Document Picker cancellation XCUITest|"
            "${{ steps.picker_cancel_required.outcome }}' `",
            "--phase 'picker_cancel_required|Document Picker cancellation XCUITest|"
            "${{ steps.picker_cancel_required.outcome }}' `\n"
            "            --phase 'files_observation|Files observation|"
            "${{ steps.files_observation.outcome }}' `",
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
        required_observation = json.loads(json.dumps(matrix))
        for contract in required_observation["contracts"]:
            if contract.get("scenario") == "ios_document_picker_select":
                contract["gate"] = "required"
        missing_observation = json.loads(json.dumps(matrix))
        missing_observation["contracts"] = [
            contract
            for contract in missing_observation["contracts"]
            if contract.get("scenario") != "ios_document_picker_export_termination"
        ]
        increased_timeout = runner.replace(
            "[int]" + chr(36) + "ScenarioTimeoutSeconds = 120",
            "[int]" + chr(36) + "ScenarioTimeoutSeconds = 180",
            1,
        )
        implicit_observation = runner.replace(
            "if (" + chr(36) + "expectedObservation -ne " + chr(36) + "declaredObservation)",
            "if ($false)",
            1,
        )

        cross_file_mutations = (
            (wrong_mapping, workflow, matrix),
            (wrong_observation_mapping, workflow, matrix),
            (runner, old_workflow, matrix),
            (runner, missing_observation_declaration, matrix),
            (runner, observation_in_required_summary, matrix),
            (runner, workflow, missing_round),
            (runner, workflow, observation_round),
            (runner, workflow, required_observation),
            (runner, workflow, missing_observation),
            (increased_timeout, workflow, matrix),
            (implicit_observation, workflow, matrix),
        )
        for index, (mutated_runner, mutated_workflow, mutated_matrix) in enumerate(
            cross_file_mutations
        ):
            with self.subTest(kind="cross_file", index=index):
                self.assertNotEqual(
                    checker.ios_cancellation_split_contract_failures(
                        mutated_runner,
                        mutated_workflow,
                        mutated_matrix,
                    ),
                    [],
                )

    def test_ios_files_observation_activation_contract_rejects_regressions(self) -> None:
        # 完整 Files 导航属于 observation，但它的测试契约仍必须拒绝回退：单击在
        # iOS 26.5 上随机只选中不激活，精确相等比较歌词又会漏掉规范化后的时间
        # 标签。两者都会把真实结果误判成失败，只能靠修正断言解决，不能靠放宽
        # 超时、改写证据或跳过场景掩盖，因此这里逐条锁定。
        checker = _load_native_isolation_checker()
        source = (ROOT / "lddc/ios/RunnerUITests/RunnerUITests.swift").read_text(
            encoding="utf-8"
        )

        self.assertEqual(checker.ios_ui_test_failures(source), [])

        mutations = (
            source.replace(
                'action: "document_picker_fixture_cell_double_tapped"',
                'action: "document_picker_fixture_cell_tapped"',
                1,
            ),
            source.replace(
                "      retainedFixture.doubleTap()",
                "      retainedFixture.tap()",
                1,
            ),
            source.replace(
                "    if !waitForPickerDismissal(\n"
                "      app: app,\n"
                "      staleRootReturnControlProvider: { app.buttons[self.openSongIdentifier] },\n"
                "      timeout: 3\n"
                "    ), let retainedPicker = systemPickerContext(app: app) {",
                "    if false, let retainedPicker = systemPickerContext(app: app) {",
                1,
            ),
            source.replace(
                "private func waitForPreviewLyricsValue(",
                "private func waitForPreviewLyricsText(",
                1,
            ),
            source.replace(
                '"value MATCHES %@ OR label MATCHES %@"',
                '"label == %@ OR value == %@"',
                1,
            ),
            source.replace(
                "    let lyricsPredicate = NSPredicate(",
                '    _ = NSPredicate(format: "label == %@ OR value == %@", '
                '"Hello LDDC", "Hello LDDC")\n'
                "    let lyricsPredicate = NSPredicate(",
                1,
            ),
            source.replace(
                "      if preview.exists {",
                "      _ = preview.staticTexts.firstMatch\n      if preview.exists {",
                1,
            ),
            source.replace(
                r'  private let fixtureLyricsAccessibilityPattern ='
                r' #"^\[00:00\.\d{2,3}\]Hello LDDC$"#' + "\n",
                "",
                1,
            ),
            source.replace("for attempt in 1...2", "for attempt in 1...3", 1),
            source.replace("for attempt in 1...2", "for attempt in 1...1", 1),
        )
        for index, mutation in enumerate(mutations):
            with self.subTest(kind="ios_ui_test", index=index):
                self.assertNotEqual(mutation, source)
                self.assertNotEqual(checker.ios_ui_test_failures(mutation), [])

    def test_platform_observation_gate_contract_rejects_regressions(self) -> None:
        checker = _load_native_isolation_checker()
        macos_runner = (ROOT / "tool/test/run_macos_platform_tests.ps1").read_text(
            encoding="utf-8"
        )
        workflow = (
            ROOT / ".github/workflows/cross-platform-validation.yml"
        ).read_text(encoding="utf-8")
        matrix = json.loads(
            (ROOT / "tool/test/platform_capability_matrix.json").read_text(
                encoding="utf-8"
            )
        )
        finalizer = (
            ROOT / "tool/test/finalize_macos_system_ui_reports.py"
        ).read_text(encoding="utf-8")

        self.assertEqual(
            checker.macos_observation_contract_failures(
                macos_runner,
                workflow,
                matrix,
                finalizer,
            ),
            [],
        )

        required_select = json.loads(json.dumps(matrix))
        for contract in required_select["contracts"]:
            if contract.get("scenario") == "macos_open_panel_select":
                contract["gate"] = "required"
        missing_observation_parameter = workflow.replace(
            "-ObservationScenarios macos_open_panel_select",
            "",
            1,
        )
        observation_in_required_summary = workflow.replace(
            "--phase 'required_report_finalize|Required report finalization|"
            "${{ steps.required_report_finalize.outcome }}'",
            "--phase 'required_report_finalize|Required report finalization|"
            "${{ steps.required_report_finalize.outcome }}' `\n"
            "            --phase 'finder_observation|Finder observation|"
            "${{ steps.finder_observation.outcome }}'",
            1,
        )
        missing_runner_observation = macos_runner.replace(
            "[string[]]" + chr(36) + "ObservationScenarios = @()",
            "[string[]]" + chr(36) + "ObservationScenarios = @('macos_open_panel_cancel')",
            1,
        )
        scalar_selection_count = macos_runner.replace(
            chr(36) + "selectedScenarioCount = @(" + chr(36) + "selectedScenarioEntries).Count",
            chr(36) + "selectedScenarioCount = " + chr(36) + "selectedScenarioEntries.Count",
            1,
        )
        default_selection_guard = macos_runner.replace(
            "if (" + chr(36) + "scenarioFilter.Count -gt 0 -and "
            + chr(36) + "selectedScenarioCount -ne " + chr(36) + "scenarioFilter.Count)",
            "if (" + chr(36) + "selectedScenarioCount -ne " + chr(36) + "scenarioFilter.Count)",
            1,
        )
        missing_finalizer_scope = finalizer.replace(
            "for scenario in args.scenarios:",
            "for scenario in VALID_SCENARIOS:",
            1,
        )
        missing_observation_evidence = finalizer.replace(
            'extra["experimentalObservation"] = True',
            "extra.clear()",
            1,
        )

        mutations = (
            (macos_runner, workflow, required_select, finalizer),
            (macos_runner, missing_observation_parameter, matrix, finalizer),
            (macos_runner, observation_in_required_summary, matrix, finalizer),
            (missing_runner_observation, workflow, matrix, finalizer),
            (scalar_selection_count, workflow, matrix, finalizer),
            (default_selection_guard, workflow, matrix, finalizer),
            (macos_runner, workflow, matrix, missing_finalizer_scope),
            (macos_runner, workflow, matrix, missing_observation_evidence),
        )
        for index, (mutated_runner, mutated_workflow, mutated_matrix, mutated_finalizer) in enumerate(
            mutations
        ):
            with self.subTest(index=index):
                self.assertNotEqual(
                    checker.macos_observation_contract_failures(
                        mutated_runner,
                        mutated_workflow,
                        mutated_matrix,
                        mutated_finalizer,
                    ),
                    [],
                )

    def test_capability_matrix_resolves_required_and_observation_gates(self) -> None:
        path = ROOT / "tool/test/capability_matrix.py"
        spec = importlib.util.spec_from_file_location("capability_matrix_gate", path)
        if spec is None or spec.loader is None:
            self.fail(f"无法加载能力矩阵解析器: {path}")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        matrix = module.load_matrix()

        expected_gates = {
            ("ios", "ios_document_picker_cancel_1", "xcuitest"): "required",
            ("ios", "ios_document_picker_cancel_2", "xcuitest"): "required",
            ("ios", "ios_document_picker_cancel_3", "xcuitest"): "required",
            ("ios", "ios_document_picker_select", "xcuitest"): "observation",
            ("ios", "ios_document_picker_export", "xcuitest"): "observation",
            ("ios", "ios_document_picker_export_cancel", "xcuitest"): "observation",
            ("ios", "ios_document_picker_export_termination", "xcuitest"): "observation",
            ("macos", "macos_open_panel_cancel", "integration_test+xcuitest"): "required",
            ("macos", "macos_open_panel_select", "integration_test+xcuitest"): "observation",
        }
        for (platform, scenario, framework), gate in expected_gates.items():
            with self.subTest(scenario=scenario):
                self.assertEqual(
                    module.resolve_gate(
                        matrix,
                        profile="platform",
                        platform=platform,
                        scenario=scenario,
                        framework=framework,
                    ),
                    gate,
                )

        with self.assertRaises(module.CapabilityMatrixError):
            module.resolve_gate(
                matrix,
                profile="platform",
                platform="ios",
                scenario="ios_document_picker_missing",
                framework="xcuitest",
            )

        invalid_matrix = json.loads(json.dumps(matrix))
        invalid_matrix["contracts"][0]["gate"] = "soft-required"
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "invalid-capability-matrix.json"
            path.write_text(json.dumps(invalid_matrix), encoding="utf-8")
            with self.assertRaises(module.CapabilityMatrixError):
                module.load_matrix(path)


if __name__ == "__main__":
    unittest.main()
