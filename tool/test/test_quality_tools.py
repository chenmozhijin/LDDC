from __future__ import annotations

import importlib.util
import json
import os
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
            '"flutter_failed_xcresult_drain"',
            '"xctest_failed_flutter_terminated"',
            '"runner_scenario_deadline"',
            '"macOS xcresult summary 缺失或损坏"',
            '"macOS xcresult attachment 导出失败',
            '"runnerClassification"',
        ):
            self.assertIn(marker, runner)
        # 结果包错误只能写诊断字段，不能覆盖 Flutter/XCTest 原始失败原因。
        self.assertNotIn(
            '$runnerFailureMessage = "macOS xcresult attachment 导出失败',
            runner,
        )

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


if __name__ == "__main__":
    unittest.main()
