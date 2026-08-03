param(
  [int]$Cycles = 100,
  [int]$SettleSeconds = 10,
  [string]$ReportPath = "build/windows_multi_window_smoke/report.json",
  [ValidateSet("both", "floating", "selector")]
  [string]$WindowMode = "both",
  [ValidateSet("resident", "rebuild")]
  [string]$Scenario = "resident",
  [ValidateSet("Debug", "Release")]
  [string]$Configuration = "Release",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$reportFullPath = [System.IO.Path]::GetFullPath(
  (Join-Path (Get-Location) $ReportPath)
)
$reportDirectory = Split-Path -Parent $reportFullPath
$traceFullPath = Join-Path $reportDirectory "trace.log"
$crashTraceFullPath = Join-Path $reportDirectory "native-crash.log"
$runnerDiagnosticPath = Join-Path $reportDirectory "runner-diagnostic.json"
New-Item -ItemType Directory -Force $reportDirectory | Out-Null
Remove-Item -LiteralPath $reportFullPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $traceFullPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $crashTraceFullPath -Force -ErrorAction SilentlyContinue

if (-not $SkipBuild) {
  # Flutter 3.47 已包含 Windows empty-frame resize 的上游修复，因此这里固定使用
  # 当前 channel 下载的标准 engine。禁止传入 --local-engine，避免 smoke 结果再次依赖
  # 开发机上的本地 engine 产物。执行后仍需重建 main.dart，避免测试入口进入交付包。
  $buildMode = "--$($Configuration.ToLowerInvariant())"
  flutter build windows $buildMode `
    -t integration_test\standalone\windows_multi_window_smoke_main.dart
  if ($LASTEXITCODE -ne 0) {
    # PowerShell 不会默认把原生命令的非零退出码转换成异常。必须在解析旧 exe
    # 之前立即失败，否则编译错误后可能继续执行上一次构建并生成假绿报告。
    [ordered]@{
      schema = "lddc.windows_resource_runner"
      phase = "build"
      exitCode = $LASTEXITCODE
      reportExists = Test-Path -LiteralPath $reportFullPath
    } | ConvertTo-Json -Depth 4 | Set-Content `
      -LiteralPath $runnerDiagnosticPath -Encoding utf8
    throw "Windows multi-window smoke build failed with exit code $LASTEXITCODE. Diagnostic: $runnerDiagnosticPath"
  }
}

$exe = Resolve-Path "build\windows\x64\runner\$Configuration\lddc.exe"
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $exe.Path
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.Environment["LDDC_CRASH_TRACE"] = $crashTraceFullPath
[void]$startInfo.ArgumentList.Add("--cycles=$Cycles")
[void]$startInfo.ArgumentList.Add("--settle-seconds=$SettleSeconds")
[void]$startInfo.ArgumentList.Add("--report=$reportFullPath")
[void]$startInfo.ArgumentList.Add("--trace=$traceFullPath")
[void]$startInfo.ArgumentList.Add("--window-mode=$WindowMode")
[void]$startInfo.ArgumentList.Add("--scenario=$Scenario")
$startedAt = [DateTimeOffset]::UtcNow
$exitCode = $null
$launchError = $null
try {
  # lddc.exe 使用 Windows GUI 子系统。PowerShell 的调用运算符不会等待这类
  # 进程，CI 会在报告落盘前进入 artifact 上传；直接使用 Process 并等待退出。
  $smokeProcess = [System.Diagnostics.Process]::Start($startInfo)
  $smokeProcess.WaitForExit()
  $exitCode = $smokeProcess.ExitCode
} catch {
  $launchError = $_.Exception.ToString()
} finally {
  $diagnostic = [ordered]@{
    schema = "lddc.windows_resource_runner"
    startedAt = $startedAt.ToString("O")
    finishedAt = [DateTimeOffset]::UtcNow.ToString("O")
    exitCode = $exitCode
    reportExists = Test-Path -LiteralPath $reportFullPath
    traceExists = Test-Path -LiteralPath $traceFullPath
    crashTraceExists = Test-Path -LiteralPath $crashTraceFullPath
    launchError = $launchError
  }
  $diagnostic | ConvertTo-Json -Depth 4 | Set-Content `
    -LiteralPath $runnerDiagnosticPath -Encoding utf8
}

if ($null -ne $launchError) {
  throw "Windows multi-window smoke could not start. Diagnostic: $runnerDiagnosticPath"
}
if ($exitCode -ne 0) {
  throw "Windows multi-window smoke failed with exit code $exitCode. Report: $reportFullPath"
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
