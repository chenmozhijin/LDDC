#!/usr/bin/env bash
set -euo pipefail

report_path="${1:-lddc/build/integration_reports/ios-simulator.json}"
mkdir -p "$(dirname "$report_path")"
host_arch="$(uname -m)"
if [[ "$host_arch" != "arm64" && "$host_arch" != "x86_64" ]]; then
  echo "ERROR: 不支持的 macOS hosted 架构: $host_arch" >&2
  exit 1
fi

expected_runtime_version="${LDDC_IOS_RUNTIME_VERSION:-26.5}"
expected_runtime_major="${expected_runtime_version%%.*}"
expected_xcode_version="${LDDC_XCODE_VERSION:-26.6}"
xcode_version_number="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
xcode_major="${xcode_version_number%%.*}"
if [[ -z "$xcode_version_number" || "$xcode_version_number" != "$expected_xcode_version" ]]; then
  echo "ERROR: 当前 Xcode $xcode_version_number 与固定版本 $expected_xcode_version 不一致" >&2
  exit 1
fi
if [[ "$xcode_major" != "$expected_runtime_major" ]]; then
  echo "ERROR: 固定 Xcode $xcode_version_number 与 iOS runtime $expected_runtime_version 主版本不一致" >&2
  exit 1
fi
xcode_version="$(xcodebuild -version | tr '\n' ' ' | sed 's/[[:space:]]*$//')"

runtime_json="$(xcrun simctl list runtimes available -j)"
runtime="$(jq -r --arg expectedVersion "$expected_runtime_version" '
  [.runtimes[]
    | select(.isAvailable == true and .platform == "iOS")
    | select(.version == $expectedVersion)]
  | sort_by(.version | split(".") | map(tonumber))
  | last | .identifier // empty
' <<<"$runtime_json")"
runtime_version="$(jq -r --arg id "$runtime" '
  .runtimes[] | select(.identifier == $id) | .version
' <<<"$runtime_json")"
if [[ -z "$runtime" || -z "$runtime_version" ]]; then
  echo "ERROR: hosted runner 没有可用的 iOS $expected_runtime_version runtime" >&2
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

jq -n \
  --arg udid "$udid" \
  --arg runtime "$runtime" \
  --arg runtimeVersion "$runtime_version" \
  --arg model "$model" \
  --arg hostArchitecture "$host_arch" \
  --arg expectedRuntimeMajor "$expected_runtime_major" \
  --arg expectedRuntimeVersion "$expected_runtime_version" \
  --arg expectedXcodeVersion "$expected_xcode_version" \
  --arg xcodeVersion "$xcode_version" \
  '{udid: $udid, runtime: $runtime, runtimeVersion: $runtimeVersion, expectedRuntimeMajor: $expectedRuntimeMajor, expectedRuntimeVersion: $expectedRuntimeVersion, expectedXcodeVersion: $expectedXcodeVersion, model: $model, hostArchitecture: $hostArchitecture, xcodeVersion: $xcodeVersion}' \
  >"$report_path"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "DEVICE_ID=$udid" >>"$GITHUB_ENV"
  echo "IOS_SIMULATOR_RUNTIME=$runtime" >>"$GITHUB_ENV"
  echo "IOS_SIMULATOR_MODEL=$model" >>"$GITHUB_ENV"
  echo "IOS_HOST_ARCH=$host_arch" >>"$GITHUB_ENV"
else
  # 本地开发不会提供 GitHub Actions 环境文件。将同样的显式设备契约
  # 输出到终端，调用者可直接传给 run_ios_platform_tests.ps1 -Device。
  echo "DEVICE_ID=$udid"
  echo "IOS_SIMULATOR_RUNTIME=$runtime"
  echo "IOS_SIMULATOR_MODEL=$model"
  echo "IOS_HOST_ARCH=$host_arch"
fi
# 设备元数据和调用方交接全部成功后，才把清理所有权交给 workflow 或本地开发者。
# 此前任一步骤失败都会由 ERR trap 删除本次创建的唯一模拟器。
trap - ERR
echo "Created iOS simulator: $model $runtime_version ($udid)"
