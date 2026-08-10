from __future__ import annotations

import json
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from unittest import mock
import unittest


@unittest.skipUnless(os.name == "posix", "进程组 mutation 只在 POSIX 质量 runner 执行")
class ProcessGroupSupervisorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(__file__).resolve().parents[2]
        self.supervisor = self.root / "tool/test/process_group_supervisor.py"
        self.temporary = tempfile.TemporaryDirectory()
        self.output_root = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _run(self, *, timeout: float, grace: float, code: str) -> tuple[subprocess.CompletedProcess[str], dict]:
        status = self.output_root / "status.json"
        completed = subprocess.run(
            [
                sys.executable,
                str(self.supervisor),
                "--phase",
                "mutation",
                "--timeout",
                str(timeout),
                "--grace",
                str(grace),
                "--cwd",
                str(self.output_root),
                "--status",
                str(status),
                "--",
                sys.executable,
                "-c",
                code,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        return completed, json.loads(status.read_text(encoding="utf-8"))

    def test_preserves_normal_nonzero_exit_and_writes_zero_resource_final(self) -> None:
        completed, status = self._run(timeout=3, grace=0.2, code="raise SystemExit(7)")

        self.assertEqual(completed.returncode, 7)
        self.assertEqual(status["exitCode"], 7)
        self.assertFalse(status["timedOut"])
        self.assertEqual(status["finalProcessCount"], 0)
        self.assertEqual(status["command"], Path(sys.executable).name)

    def test_timeout_escalates_to_sigkill_when_child_ignores_sigterm(self) -> None:
        completed, status = self._run(
            timeout=0.3,
            grace=0.2,
            code=(
                "import signal,time;"
                "signal.signal(signal.SIGTERM, signal.SIG_IGN);"
                "time.sleep(30)"
            ),
        )

        self.assertEqual(completed.returncode, 124)
        self.assertEqual(status["exitCode"], 124)
        self.assertTrue(status["timedOut"])
        self.assertTrue(status["terminateSent"])
        self.assertTrue(status["killSent"])
        self.assertEqual(status["finalProcessCount"], 0)
        self.assertEqual(status["resourceMeasurementStatus"], "available")

    def test_unavailable_snapshot_does_not_turn_success_into_residual_failure(self) -> None:
        spec = importlib.util.spec_from_file_location("process_group_supervisor", self.supervisor)
        self.assertIsNotNone(spec)
        self.assertIsNotNone(spec.loader)
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        status_path = self.output_root / "unavailable-status.json"
        args = SimpleNamespace(
            phase="snapshot-unavailable",
            timeout=3.0,
            grace=0.2,
            cwd=str(self.output_root),
            status=str(status_path),
            stdout=None,
            stderr=None,
            command=[sys.executable, "-c", "raise SystemExit(0)"],
        )
        unavailable = module._GroupSnapshot(
            process_count=None,
            rss_bytes=None,
            error="forced snapshot failure",
        )
        with mock.patch.object(module, "_group_snapshot", return_value=unavailable):
            exit_code = module.run_supervised(args)

        status = json.loads(status_path.read_text(encoding="utf-8"))
        self.assertEqual(exit_code, 0)
        self.assertEqual(status["exitCode"], 0)
        self.assertEqual(status["resourceMeasurementStatus"], "unavailable")
        self.assertIsNone(status["finalProcessCount"])
        self.assertIsNone(status["error"])


if __name__ == "__main__":
    unittest.main()
