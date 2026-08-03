param(
  [int]$Cycles = 100,
  [int]$SettleSeconds = 10,
  [string]$ReportPath = "build/windows_multi_window_smoke/report.json",
  [ValidateSet("both", "floating", "selector")]
  [string]$WindowMode = "both",
  [ValidateSet("resident", "rebuild")]
  [string]$Scenario = "resident",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$reportFullPath = [System.IO.Path]::GetFullPath(
  (Join-Path (Get-Location) $ReportPath)
)

if (-not $SkipBuild) {
  # Flutter 3.47 已包含 Windows empty-frame resize 的上游修复，因此这里固定使用
  # 当前 channel 下载的标准 engine。禁止传入 --local-engine，避免 smoke 结果再次依赖
  # 开发机上的本地 engine 产物。执行后仍需重建 main.dart，避免测试入口进入交付包。
  flutter build windows --release `
    -t integration_test\standalone\windows_multi_window_smoke_main.dart
}

$exe = Resolve-Path "build\windows\x64\runner\Release\lddc.exe"
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $exe.Path
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
[void]$startInfo.ArgumentList.Add("--cycles=$Cycles")
[void]$startInfo.ArgumentList.Add("--settle-seconds=$SettleSeconds")
[void]$startInfo.ArgumentList.Add("--report=$reportFullPath")
[void]$startInfo.ArgumentList.Add("--window-mode=$WindowMode")
[void]$startInfo.ArgumentList.Add("--scenario=$Scenario")
$smokeProcess = [System.Diagnostics.Process]::Start($startInfo)
$smokeProcess.WaitForExit()
if ($smokeProcess.ExitCode -ne 0) {
  throw "Windows multi-window smoke failed. Report: $reportFullPath"
}

if (-not (Test-Path -LiteralPath $reportFullPath)) {
  throw "Windows multi-window smoke did not write a report: $reportFullPath"
}
$report = Get-Content -LiteralPath $reportFullPath -Raw | ConvertFrom-Json
if ($report.success -ne $true) {
  if ($Scenario -eq "resident") {
    throw "Windows resident multi-window smoke assertions failed. Report: $reportFullPath"
  }
  # 完整重建用于追踪 Flutter engine 上游残余；崩溃仍由进程退出码阻断，
  # 但资源阈值单独失败只记录报告，不替代长驻显隐场景的发布判定。
  Write-Warning "Windows rebuild stress metrics exceeded thresholds. Report: $reportFullPath"
}
$report | ConvertTo-Json -Depth 8
