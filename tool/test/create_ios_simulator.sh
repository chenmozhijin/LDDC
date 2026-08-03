#!/usr/bin/env bash
set -euo pipefail

report_path="${1:-lddc/build/integration_reports/ios-simulator.json}"
mkdir -p "$(dirname "$report_path")"

runtime_json="$(xcrun simctl list runtimes available -j)"
runtime="$(jq -r '
  [.runtimes[] | select(.isAvailable == true and .platform == "iOS")]
  | sort_by(.version | split(".") | map(tonumber))
  | last | .identifier // empty
' <<<"$runtime_json")"
runtime_version="$(jq -r --arg id "$runtime" '
  .runtimes[] | select(.identifier == $id) | .version
' <<<"$runtime_json")"
if [[ -z "$runtime" || -z "$runtime_version" ]]; then
  echo "ERROR: hosted runner 没有可用 iOS runtime" >&2
  exit 1
fi

device_json="$(xcrun simctl list devicetypes -j)"
udid=""
model=""
while IFS=$'\t' read -r name identifier; do
  [[ -n "$identifier" ]] || continue
  # 不固定具体 iPhone 型号。某些旧 device type 不能搭配最新 runtime，
  # simctl create 的返回码就是当前 Xcode 最可靠的兼容性判据。
  if candidate="$(xcrun simctl create "LDDC CI ${GITHUB_RUN_ID:-local}-${RANDOM}" "$identifier" "$runtime" 2>/dev/null)"; then
    udid="$candidate"
    model="$name"
    break
  fi
done < <(jq -r '.devicetypes[] | select(.name | startswith("iPhone")) | [.name, .identifier] | @tsv' <<<"$device_json")

if [[ -z "$udid" ]]; then
  echo "ERROR: 没有与 $runtime 兼容的 iPhone device type" >&2
  exit 1
fi

cleanup_failed_device() {
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" >/dev/null 2>&1 || true
}
trap cleanup_failed_device ERR
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
trap - ERR

jq -n \
  --arg udid "$udid" \
  --arg runtime "$runtime" \
  --arg runtimeVersion "$runtime_version" \
  --arg model "$model" \
  '{udid: $udid, runtime: $runtime, runtimeVersion: $runtimeVersion, model: $model}' \
  >"$report_path"

echo "DEVICE_ID=$udid" >>"$GITHUB_ENV"
echo "IOS_SIMULATOR_RUNTIME=$runtime" >>"$GITHUB_ENV"
echo "IOS_SIMULATOR_MODEL=$model" >>"$GITHUB_ENV"
echo "Created iOS simulator: $model $runtimeVersion ($udid)"
