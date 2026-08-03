param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("windows", "macos", "linux")]
  [string]$Platform,
  [string]$AppExe = "",
  [string]$ReportDir = "build/integration_reports/desktop-process",
  [ValidateRange(60, 300)]
  [int]$ScenarioTimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$testRoot = Join-Path $repoRoot "packages/lddc_desktop_protocol"
if ([string]::IsNullOrWhiteSpace($AppExe)) {
  $AppExe = switch ($Platform) {
    # Flutter 会在不同 target 之间复用桌面构建目录，Debug 和 Release 都可能
    # 被测试入口覆盖。真实进程 E2E 只接受 Release 构建后立即保存的生产快照，
    # 避免把 resident/performance 测试程序误判为正式应用。
    "windows" { "lddc/build/production_e2e/windows/lddc.exe" }
    "macos" { "lddc/build/production_e2e/macos/LDDC.app/Contents/MacOS/LDDC" }
    "linux" { "lddc/build/production_e2e/linux/lddc" }
  }
}
if (-not [IO.Path]::IsPathRooted($AppExe)) {
  $AppExe = Join-Path $repoRoot $AppExe
}
if (-not (Test-Path -LiteralPath $AppExe -PathType Leaf)) {
  throw "桌面进程 E2E 应用不存在: $AppExe"
}
$appExeFullPath = (Resolve-Path -LiteralPath $AppExe).Path
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

if ($Platform -eq "windows") {
  $processName = [IO.Path]::GetFileNameWithoutExtension($AppExe)
  if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
    # 全局 mutex 无法按临时目录隔离；必须在创建任何 runId 目录前拒绝运行，
    # 否则一次正常的前置条件失败也会留下误导性的测试 sandbox。
    throw "Windows 全局单实例测试要求运行前没有同名 LDDC 进程"
  }
}

$runId = "platform-$Platform-process-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Join-Path $ReportDir $runId
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$evidenceDir = Join-Path $runRoot "evidence"
$diagnosticsDir = Join-Path $runRoot "diagnostics"
$sandboxParent = [IO.Path]::GetFullPath((Join-Path $appRoot "build/native_test_sandboxes"))
$sandboxRoot = [IO.Path]::GetFullPath((Join-Path $sandboxParent $runId))
if (-not $sandboxRoot.StartsWith($sandboxParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw "桌面进程 E2E sandbox 超出允许目录"
}
foreach ($directory in @($scenarioDir, $rawDir, $junitDir, $evidenceDir, $diagnosticsDir, $sandboxRoot)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$environmentNames = @(
  "LDDC_IT_RUN_ID", "LDDC_IT_PLATFORM",
  "LDDC_PROCESS_E2E_APP_EXE", "LDDC_NATIVE_EVIDENCE_DIR",
  "LDDC_NATIVE_LOG_DIR", "LDDC_PROCESS_E2E_PID_FILE",
  "LDDC_PROCESS_E2E_INFO_FILE",
  "LDDC_PROCESS_E2E_APPDATA", "LDDC_PROCESS_E2E_LOCALAPPDATA",
  "LDDC_PROCESS_E2E_HOME", "LDDC_PROCESS_E2E_XDG_CONFIG_HOME",
  "LDDC_PROCESS_E2E_XDG_CACHE_HOME", "LDDC_PROCESS_E2E_XDG_DATA_HOME",
  "LDDC_PROCESS_E2E_TMPDIR"
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$env:LDDC_PROCESS_E2E_APPDATA = Join-Path $sandboxRoot "Roaming"
$env:LDDC_PROCESS_E2E_LOCALAPPDATA = Join-Path $sandboxRoot "Local"
$env:LDDC_PROCESS_E2E_HOME = Join-Path $sandboxRoot "Home"
$env:LDDC_PROCESS_E2E_XDG_CONFIG_HOME = Join-Path $sandboxRoot "Config"
$env:LDDC_PROCESS_E2E_XDG_CACHE_HOME = Join-Path $sandboxRoot "Cache"
$env:LDDC_PROCESS_E2E_XDG_DATA_HOME = Join-Path $sandboxRoot "Data"
$env:LDDC_PROCESS_E2E_TMPDIR = Join-Path $sandboxRoot "Temp"
foreach ($directory in @(
    $env:LDDC_PROCESS_E2E_APPDATA, $env:LDDC_PROCESS_E2E_LOCALAPPDATA,
    $env:LDDC_PROCESS_E2E_HOME, $env:LDDC_PROCESS_E2E_XDG_CONFIG_HOME,
    $env:LDDC_PROCESS_E2E_XDG_CACHE_HOME, $env:LDDC_PROCESS_E2E_XDG_DATA_HOME,
    $env:LDDC_PROCESS_E2E_TMPDIR
  )) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
$env:LDDC_IT_RUN_ID = $runId
$env:LDDC_IT_PLATFORM = $Platform
$env:LDDC_PROCESS_E2E_APP_EXE = (Resolve-Path -LiteralPath $AppExe).Path
$env:LDDC_NATIVE_EVIDENCE_DIR = $evidenceDir
$env:LDDC_NATIVE_LOG_DIR = $diagnosticsDir
$env:LDDC_PROCESS_E2E_PID_FILE = Join-Path $runRoot "primary.pid"
$env:LDDC_PROCESS_E2E_INFO_FILE = switch ($Platform) {
  "windows" { Join-Path $env:LDDC_PROCESS_E2E_LOCALAPPDATA "LDDC/info.json" }
  "linux" { Join-Path $env:LDDC_PROCESS_E2E_XDG_DATA_HOME "LDDC/info.json" }
  "macos" { Join-Path $env:LDDC_PROCESS_E2E_HOME "Library/Application Support/LDDC/info.json" }
}
$runStartedAt = Get-Date

$rawPath = Join-Path $rawDir "desktop_real_process.jsonl"
$evidencePath = Join-Path $evidenceDir "desktop_real_process.json"
$scenarioPath = Join-Path $scenarioDir "desktop_real_process.json"
$junitPath = Join-Path $junitDir "desktop_real_process.xml"

function Invoke-BoundedDartTest {
  $dartCommand = (Get-Command dart).Source
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.UseShellExecute = $false
  $startInfo.WorkingDirectory = $testRoot
  $arguments = @(
    "test",
    "platform_test/desktop_real_process_e2e_test.dart",
    "--file-reporter=json:$rawPath"
  )
  if ($IsWindows -and $dartCommand.EndsWith(".bat")) {
    $startInfo.FileName = "cmd.exe"
    foreach ($argument in @("/d", "/c", $dartCommand) + $arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  } else {
    $startInfo.FileName = $dartCommand
    foreach ($argument in $arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  try {
    if (-not $process.WaitForExit($ScenarioTimeoutSeconds * 1000)) {
      # 测试框架失去响应时终止 Dart test 与其子进程，PID 文件用于补充清理已脱离的服务进程。
      $process.Kill($true)
      $process.WaitForExit()
      return 124
    }
    return $process.ExitCode
  } finally {
    $process.Dispose()
  }
}

try {
  $testExitCode = Invoke-BoundedDartTest
  if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
    throw "桌面进程 E2E 没有生成 Dart JSONL"
  }
  if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
    throw "桌面进程 E2E 没有生成 evidence JSON"
  }

  & python (Join-Path $repoRoot "tool/test/normalize_integration_report.py") `
    --scenario-report $scenarioPath `
    --raw-report $rawPath `
    --raw-report-type dart-jsonl `
    --framework dart-process-e2e `
    --exit-code $testExitCode `
    --evidence $evidencePath `
    --matrix (Join-Path $repoRoot "tool/test/platform_capability_matrix.json")
  $normalizeExitCode = $LASTEXITCODE
  & python (Join-Path $repoRoot "tool/test/json_report_to_junit.py") `
    --input $rawPath `
    --output $junitPath
  $junitExitCode = $LASTEXITCODE

  if ($testExitCode -ne 0) { exit $testExitCode }
  if ($normalizeExitCode -ne 0) { exit $normalizeExitCode }
  if ($junitExitCode -ne 0) { exit $junitExitCode }

  & python (Join-Path $repoRoot "tool/test/verify_integration_reports.py") `
    --directory $scenarioDir `
    --junit-directory $junitDir `
    --profile platform `
    --platform $Platform `
    --run-id $runId `
    --matrix (Join-Path $repoRoot "tool/test/platform_capability_matrix.json")
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  if (Test-Path -LiteralPath $env:LDDC_PROCESS_E2E_PID_FILE -PathType Leaf) {
    $primaryPid = [int](Get-Content -LiteralPath $env:LDDC_PROCESS_E2E_PID_FILE -Raw)
    $primaryProcess = Get-Process -Id $primaryPid -ErrorAction SilentlyContinue
    if ($null -ne $primaryProcess) {
      $primaryProcess.Kill($true)
      $primaryProcess.WaitForExit(5000) | Out-Null
    }
  }
  if ($Platform -eq "windows") {
    # 端口 CLI 可能在 primary 声明完成前拉起替代服务。运行前已确认同名进程为零，
    # 因此这里只回收本次开始后且可执行路径完全一致的进程，避免留下服务或误伤用户实例。
    $processName = [IO.Path]::GetFileNameWithoutExtension($appExeFullPath)
    foreach ($ownedProcess in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
      try {
        if ($ownedProcess.Path -eq $appExeFullPath -and $ownedProcess.StartTime -ge $runStartedAt) {
          $ownedProcess.Kill($true)
          $ownedProcess.WaitForExit(5000) | Out-Null
        }
      } catch {
        # 进程已经退出或路径在退出竞态中不可读时，下一轮资源核验会给出明确失败。
      }
    }
  }
  if (Test-Path -LiteralPath $sandboxRoot -PathType Container) {
    # 应用 bootstrap 日志位于隔离的 APPDATA/XDG/HOME 目录。必须在删除 sandbox
    # 前复制到失败 artifact，否则服务端口超时只剩引擎 stderr，无法判断生产状态机。
    foreach ($applicationLog in @(Get-ChildItem -LiteralPath $sandboxRoot -Recurse -File -Filter "*.log" -ErrorAction SilentlyContinue)) {
      $relativeLogPath = [IO.Path]::GetRelativePath($sandboxRoot, $applicationLog.FullName)
      $safeLogName = ($relativeLogPath -replace '[:/\\]+', '_')
      Copy-Item -LiteralPath $applicationLog.FullName -Destination (Join-Path $diagnosticsDir $safeLogName) -Force
    }
  }
  if (Test-Path -LiteralPath $sandboxRoot -PathType Container) {
    # 递归删除前重新校验绝对父目录，避免异常路径影响工作区其他文件。
    if (-not $sandboxRoot.StartsWith($sandboxParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "拒绝清理允许目录之外的桌面进程 E2E sandbox"
    }
    Remove-Item -LiteralPath $sandboxRoot -Recurse -Force
  }
  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
  }
}

Write-Host "Desktop process E2E reports: $runRoot"
