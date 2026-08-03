#!/usr/bin/env bash
set -euo pipefail

report_root="lddc/build/integration_reports"
phase_events="$report_root/android-phases.jsonl"
mkdir -p "$report_root"
: >"$phase_events"

run_phase() {
  local name="$1"
  local limit="$2"
  shift 2
  local started_at ended_at phase_exit
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "::group::Android phase $name (timeout=$limit)"
  set +e
  timeout --signal=TERM --kill-after=30s "$limit" "$@"
  phase_exit=$?
  set -e
  ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -cn \
    --arg phase "$name" \
    --arg startedAt "$started_at" \
    --arg endedAt "$ended_at" \
    --argjson exitCode "$phase_exit" \
    '{phase: $phase, startedAt: $startedAt, endedAt: $endedAt, exitCode: $exitCode}' \
    >>"$phase_events"
  echo "Android phase $name exit=$phase_exit started=$started_at ended=$ended_at"
  echo '::endgroup::'
  return "$phase_exit"
}

# android-emulator-runner 的 script 字段可能逐行启动 shell。将状态、函数和聚合
# 固定在一个脚本进程内，确保任一阶段失败后其余独立证据仍会继续生成。
status=0
run_phase android-jvm 25m bash -lc \
  'cd lddc/android && chmod +x gradlew && ./gradlew :app:testDebugUnitTest' || status=1
run_phase android-offline 35m pwsh -NoProfile -File \
  tool/test/run_real_integration.ps1 -Profile offline \
  -Device emulator-5554 -Platform android || status=1
run_phase android-platform 35m pwsh -NoProfile -File \
  tool/test/run_real_integration.ps1 -Profile platform \
  -Device emulator-5554 -Platform android || status=1
run_phase android-uiautomator 30m pwsh -NoProfile -File \
  tool/test/run_android_platform_tests.ps1 -Device emulator-5554 || status=1
jq -s '.' "$phase_events" >"$report_root/android-phases.json"
exit "$status"
