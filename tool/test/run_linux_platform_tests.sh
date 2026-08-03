#!/usr/bin/env bash
set -euo pipefail

app_exe="${1:-lddc/build/linux/x64/debug/bundle/lddc}"
report_dir="${2:-lddc/build/integration_reports/linux-native}"
python_bin="${LDDC_PLATFORM_PYTHON:-python3}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ "$app_exe" = /* ]] || app_exe="$repo_root/$app_exe"
[[ "$report_dir" = /* ]] || report_dir="$repo_root/$report_dir"
[[ -x "$app_exe" ]] || { echo "Linux 平台测试应用不可执行: $app_exe" >&2; exit 2; }
[[ -n "${DISPLAY:-}" ]] || { echo "Linux 平台测试缺少 DISPLAY" >&2; exit 2; }
[[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || { echo "Linux 平台测试缺少 DBus session" >&2; exit 2; }

version="$($python_bin -c 'import importlib.metadata; print(importlib.metadata.version("dogtail"))')"
[[ "$version" == "2.0.4" ]] || { echo "Dogtail 版本必须为 2.0.4，实际为 $version" >&2; exit 2; }

run_id="platform-linux-$(date +%s%3N)-$(printf '%08x' "$RANDOM")"
run_root="$report_dir/$run_id"
scenario_dir="$run_root/scenarios"
raw_dir="$run_root/raw"
junit_dir="$run_root/junit"
evidence_dir="$run_root/evidence"
diagnostics_dir="$run_root/diagnostics"
sandbox_root="$repo_root/lddc/build/native_test_sandboxes/$run_id"
mkdir -p "$scenario_dir" "$raw_dir" "$junit_dir" "$evidence_dir" "$diagnostics_dir" \
  "$sandbox_root/home" "$sandbox_root/config" "$sandbox_root/cache" "$sandbox_root/data" "$sandbox_root/tmp"

export HOME="$sandbox_root/home"
export XDG_CONFIG_HOME="$sandbox_root/config"
export XDG_CACHE_HOME="$sandbox_root/cache"
export XDG_DATA_HOME="$sandbox_root/data"
export TMPDIR="$sandbox_root/tmp"
export XDG_RUNTIME_DIR="$sandbox_root/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
export LANG="C.UTF-8"
export LC_ALL="C.UTF-8"
export NO_AT_BRIDGE=0
export LDDC_IT_RUN_ID="$run_id"
export LDDC_LINUX_APP_EXE="$app_exe"
export LDDC_LINUX_ACCESSIBLE_APP_NAME="lddc"
export LDDC_FIXTURE_PATH="$repo_root/lddc/integration_test/fixtures/media/audio_sample.mp3"
export LDDC_NATIVE_EVIDENCE_DIR="$evidence_dir"
export LDDC_NATIVE_LOG_DIR="$diagnostics_dir"
export LDDC_NATIVE_PID_FILE="$run_root/lddc.pid"

cleanup() {
  if [[ -f "$LDDC_NATIVE_PID_FILE" ]]; then
    pid="$(cat "$LDDC_NATIVE_PID_FILE")"
    # pytest 被 timeout 终止时 Python finally 可能来不及执行，只清理本场景记录的独立进程组。
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  case "$sandbox_root" in
    "$repo_root/lddc/build/native_test_sandboxes/"*)
      rm -rf -- "$sandbox_root"
      ;;
    *)
      echo "拒绝删除越界 Linux 测试 sandbox: $sandbox_root" >&2
      ;;
  esac
}
trap cleanup EXIT

declare -A methods=(
  [linux_gtk_file_chooser_select]=test_gtk_file_chooser_selects_fixture
  [linux_gtk_file_chooser_cancel]=test_gtk_file_chooser_cancellation_returns_to_flutter
)

for scenario in linux_gtk_file_chooser_select linux_gtk_file_chooser_cancel; do
  method="${methods[$scenario]}"
  raw_path="$raw_dir/$scenario.xml"
  set +e
  timeout --signal=TERM --kill-after=10s 90s \
    "$python_bin" -m pytest "$repo_root/lddc/linux/platform_tests/test_file_dialog.py::$method" \
    --junitxml="$raw_path"
  test_exit_code=$?
  set -e
  [[ -f "$raw_path" ]] || { echo "Linux Dogtail 场景 $scenario 没有生成 pytest JUnit" >&2; exit 1; }
  evidence_path="$evidence_dir/$scenario.json"
  [[ -f "$evidence_path" ]] || { echo "Linux Dogtail 场景 $scenario 没有生成 evidence JSON" >&2; exit 1; }

  cp "$raw_path" "$junit_dir/$scenario.xml"
  set +e
  "$python_bin" "$repo_root/tool/test/normalize_integration_report.py" \
    --scenario-report "$scenario_dir/$scenario.json" \
    --raw-report "$raw_path" \
    --raw-report-type pytest-junit \
    --framework dogtail-atspi \
    --exit-code "$test_exit_code" \
    --evidence "$evidence_path" \
    --matrix "$repo_root/tool/test/platform_capability_matrix.json"
  normalize_exit_code=$?
  set -e
  if (( test_exit_code != 0 || normalize_exit_code != 0 )); then
    ps -ef > "$diagnostics_dir/$scenario-processes.txt"
    (( normalize_exit_code == 0 )) || exit "$normalize_exit_code"
    exit "$test_exit_code"
  fi
done

"$python_bin" "$repo_root/tool/test/verify_integration_reports.py" \
  --directory "$scenario_dir" \
  --junit-directory "$junit_dir" \
  --profile platform \
  --platform linux \
  --run-id "$run_id" \
  --matrix "$repo_root/tool/test/platform_capability_matrix.json"

echo "Linux platform reports: $run_root"
