from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET


class FinalizeMacosSystemUiReportsTest(unittest.TestCase):
    def test_watchdog_failure_creates_two_parseable_failure_reports(self) -> None:
        root = Path(__file__).resolve().parents[2]
        script = root / "tool/test/finalize_macos_system_ui_reports.py"
        with tempfile.TemporaryDirectory() as temporary:
            report_root = Path(temporary) / "reports"
            completed = subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--report-root",
                    str(report_root),
                    "--step-outcome",
                    "failure",
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )

            self.assertEqual(completed.returncode, 0, completed.stderr)
            run_roots = list(report_root.glob("platform-macos-*"))
            self.assertEqual(len(run_roots), 1)
            run_root = run_roots[0]
            for scenario in ("macos_open_panel_select", "macos_open_panel_cancel"):
                scenario_report = run_root / "scenarios" / f"{scenario}.json"
                junit_report = run_root / "junit" / f"{scenario}.xml"
                payload = json.loads(scenario_report.read_text(encoding="utf-8"))
                self.assertEqual(payload["scenario"], scenario)
                self.assertFalse(payload["success"])
                self.assertIsNotNone(ET.parse(junit_report).getroot())

    def test_existing_failed_reports_are_a_successful_finalization(self) -> None:
        root = Path(__file__).resolve().parents[2]
        script = root / "tool/test/finalize_macos_system_ui_reports.py"
        with tempfile.TemporaryDirectory() as temporary:
            report_root = Path(temporary) / "reports"
            run_root = report_root / "platform-macos-existing"
            for scenario in ("macos_open_panel_select", "macos_open_panel_cancel"):
                scenario_dir = run_root / "scenarios"
                junit_dir = run_root / "junit"
                scenario_dir.mkdir(parents=True, exist_ok=True)
                junit_dir.mkdir(parents=True, exist_ok=True)
                (scenario_dir / f"{scenario}.json").write_text(
                    json.dumps(
                        {
                            "schemaVersion": 2,
                            "runId": run_root.name,
                            "scenario": scenario,
                            "profile": "platform",
                            "platform": "macos",
                            "framework": "integration_test+xcuitest",
                            "success": False,
                        }
                    ),
                    encoding="utf-8",
                )
                (junit_dir / f"{scenario}.xml").write_text(
                    f'<testsuite name="{scenario}" tests="1" failures="1" />',
                    encoding="utf-8",
                )

            completed = subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--report-root",
                    str(report_root),
                    "--step-outcome",
                    "failure",
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_corrupt_or_mismatched_reports_fail_finalization(self) -> None:
        root = Path(__file__).resolve().parents[2]
        script = root / "tool/test/finalize_macos_system_ui_reports.py"
        for mutation in ("json", "xml", "identity"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as temporary:
                report_root = Path(temporary) / "reports"
                run_root = report_root / "platform-macos-corrupt"
                scenario_dir = run_root / "scenarios"
                junit_dir = run_root / "junit"
                scenario_dir.mkdir(parents=True)
                junit_dir.mkdir(parents=True)
                for scenario in ("macos_open_panel_select", "macos_open_panel_cancel"):
                    payload = {
                        "schemaVersion": 2,
                        "runId": run_root.name,
                        "scenario": scenario,
                        "profile": "platform",
                        "platform": "macos",
                        "framework": "integration_test+xcuitest",
                    }
                    (scenario_dir / f"{scenario}.json").write_text(
                        json.dumps(payload),
                        encoding="utf-8",
                    )
                    (junit_dir / f"{scenario}.xml").write_text(
                        f'<testsuite name="{scenario}" tests="1" />',
                        encoding="utf-8",
                    )
                target_scenario = "macos_open_panel_select"
                if mutation == "json":
                    (scenario_dir / f"{target_scenario}.json").write_text(
                        "{broken",
                        encoding="utf-8",
                    )
                elif mutation == "xml":
                    (junit_dir / f"{target_scenario}.xml").write_text(
                        "<testsuite",
                        encoding="utf-8",
                    )
                else:
                    payload = json.loads(
                        (scenario_dir / f"{target_scenario}.json").read_text(
                            encoding="utf-8"
                        )
                    )
                    payload["scenario"] = "wrong-scenario"
                    (scenario_dir / f"{target_scenario}.json").write_text(
                        json.dumps(payload),
                        encoding="utf-8",
                    )

                completed = subprocess.run(
                    [
                        sys.executable,
                        str(script),
                        "--report-root",
                        str(report_root),
                        "--step-outcome",
                        "failure",
                    ],
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=30,
                )
                self.assertEqual(completed.returncode, 1)


if __name__ == "__main__":
    unittest.main()
