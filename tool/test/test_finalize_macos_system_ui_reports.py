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

            self.assertEqual(completed.returncode, 1)
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


if __name__ == "__main__":
    unittest.main()
