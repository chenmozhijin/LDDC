param(
  [string]$ReportDir = "build/integration_reports/macos-native",
  [ValidateRange(120, 180)]
  [int]$ScenarioTimeoutSeconds = 120,
  [ValidateRange(120, 300)]
  [int]$FlutterStartupTimeoutSeconds = 180,
  [ValidateSet("macos_open_panel_select", "macos_open_panel_cancel")]
  [string[]]$Scenarios = @(),
  [ValidateSet("macos_open_panel_select", "macos_open_panel_cancel")]
  [string[]]$ObservationScenarios = @(),
  [switch]$PreserveBuildProducts
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$testProject = Join-Path $appRoot "macos/Runner.xcworkspace"
$flutterTarget = "integration_test/macos_file_dialog_platform_test.dart"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$junitConverter = Join-Path $repoRoot "tool/test/json_report_to_junit.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$matrixResolver = Join-Path $repoRoot "tool/test/capability_matrix.py"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
$processSupervisor = Join-Path $repoRoot "tool/test/process_group_supervisor.py"
$fixtureSource = (Resolve-Path (Join-Path $appRoot "integration_test/fixtures/media/audio_sample.mp3")).Path
$fixtureSize = (Get-Item -LiteralPath $fixtureSource).Length
$fixtureSha256 = (Get-FileHash -LiteralPath $fixtureSource -Algorithm SHA256).Hash.ToLowerInvariant()
$framework = "integration_test+xcuitest"
$hybridNativeActionTimeoutSeconds = 90
$flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
$hostArchitecture = (& /usr/bin/uname -m).Trim()
if ($hostArchitecture -notin @("arm64", "x86_64")) {
  throw "不支持的 macOS hosted runner 架构: $hostArchitecture"
}
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

$runId = "platform-macos-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Join-Path $ReportDir $runId
$derivedDataParent = [IO.Path]::GetFullPath(
  (Join-Path $appRoot "build/native_test_derived_data")
)
$derivedData = [IO.Path]::GetFullPath((Join-Path $derivedDataParent $runId))
if (-not $derivedData.StartsWith(
    $derivedDataParent + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::Ordinal
  )) {
  throw "macOS Xcode DerivedData 超出测试构建根"
}
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$requiredScenarioDir = Join-Path $runRoot "required-scenarios"
$requiredJunitDir = Join-Path $runRoot "required-junit"
$attachmentsDir = Join-Path $runRoot "attachments"
$diagnosticsDir = Join-Path $runRoot "diagnostics"
$processStatusDir = Join-Path $diagnosticsDir "process-status"
$containerData = [IO.Path]::GetFullPath(
  (Join-Path $HOME "Library/Containers/com.cmzj.lddc/Data")
)
$containerTempRoot = [IO.Path]::GetFullPath((Join-Path $containerData "tmp"))
$hybridRelativeRoot = "lddc_hybrid/$runId"
$hybridRoot = [IO.Path]::GetFullPath(
  (Join-Path $containerTempRoot $hybridRelativeRoot)
)
if (-not $hybridRoot.StartsWith(
    $containerTempRoot + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::Ordinal
  )) {
  throw "macOS hybrid 临时目录超出 App Sandbox 容器 tmp 根"
}
$syncDir = Join-Path $hybridRoot "sync"
$workspaceRoot = Join-Path $hybridRoot "workspace"
$fixture = Join-Path $workspaceRoot "fixtures/audio_sample.mp3"
$containerReportDir = Join-Path $hybridRoot "reports"
foreach ($directory in @(
    $scenarioDir, $rawDir, $junitDir, $requiredScenarioDir, $requiredJunitDir,
    $attachmentsDir, $diagnosticsDir, $processStatusDir
  )) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

function Resolve-UniqueBuildArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Filter,
    [Parameter(Mandatory = $true)][string]$Description
  )

  $matches = @(
    Get-ChildItem -Path $Root -Recurse -File -Filter $Filter | Sort-Object FullName
  )
  if ($matches.Count -ne 1) {
    $relativeMatches = @($matches | ForEach-Object {
        [IO.Path]::GetRelativePath($Root, $_.FullName).Replace("\", "/")
      })
    throw "$Description 必须且只能生成一个，实际为 $($matches.Count)：$($relativeMatches -join ', ')"
  }
  return $matches[0]
}

$allScenarios = @(
  @{
    Name = "macos_open_panel_select"
    Action = "select"
    Method = "testOpenPanelSelectsFixture"
  },
  @{
    Name = "macos_open_panel_cancel"
    Action = "cancel"
    Method = "testOpenPanelCancellationReturnsToFlutter"
  }
)
$scenarioFilter = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($scenario in $Scenarios) { $scenarioFilter.Add($scenario) | Out-Null }
$observationFilter = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($scenario in $ObservationScenarios) { $observationFilter.Add($scenario) | Out-Null }
$scenarios = if ($scenarioFilter.Count -eq 0) {
  @($allScenarios)
} else {
  @($allScenarios | Where-Object { $scenarioFilter.Contains($_.Name) })
}
if ($scenarios.Count -eq 0) { throw "没有选择任何 macOS OpenPanel 场景" }
foreach ($entry in $scenarios) {
  $gateOutput = @(& python $matrixResolver `
      --matrix $matrix `
      --profile platform `
      --platform macos `
      --scenario $entry.Name `
      --framework integration_test+xcuitest `
      --gate)
  $gateExitCode = $LASTEXITCODE
  $expectedGate = ($gateOutput -join "`n").Trim()
  if ($gateExitCode -ne 0 -or $expectedGate -notin @("required", "observation")) {
    throw "无法解析 macOS 场景 $($entry.Name) 的 gate"
  }
  $declaredObservation = $observationFilter.Contains($entry.Name)
  if ($ObservationScenarios.Count -gt 0 `
      -and (($expectedGate -eq "observation") -ne $declaredObservation)) {
    throw "macOS 场景 $($entry.Name) 的 runner gate 与能力矩阵不一致"
  }
  if ($expectedGate -eq "observation") {
    $observationFilter.Add($entry.Name) | Out-Null
  }
}
# XCTest 结果包的收尾是独立的诊断阶段。它不能延长 Flutter 业务预算，
# 但 Flutter 先失败时需要给 xcodebuild 一个固定窗口写出原始结果。
$xcodeReportDrainSeconds = 30
$testRunnerEnvironment = [ordered]@{
  TEST_RUNNER_LDDC_IT_RUN_ID = $runId
  TEST_RUNNER_LDDC_FIXTURE_PATH = $fixture
  TEST_RUNNER_LDDC_MACOS_HYBRID_SYNC_DIR = $syncDir
}
$previousTestRunnerEnvironment = @{}

function Start-SupervisedProcess {
  param(
    [Parameter(Mandatory = $true)][string]$Phase,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)][string]$StdoutPath,
    [Parameter(Mandatory = $true)][string]$StderrPath
  )

  foreach ($path in @($StdoutPath, $StderrPath)) {
    $parent = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  }

  $safePhase = $Phase -replace '[^A-Za-z0-9_.-]', '-'
  $statusPath = Join-Path $processStatusDir (
    "{0}-{1}.json" -f $safePhase, ([Guid]::NewGuid().ToString("N").Substring(0, 8))
  )
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = "python"
  $startInfo.WorkingDirectory = $WorkingDirectory
  $startInfo.UseShellExecute = $false
  foreach ($argument in @(
      $processSupervisor,
      "--phase", $Phase,
      "--timeout", [string]$TimeoutSeconds,
      "--grace", "2",
      "--cwd", $WorkingDirectory,
      "--status", $statusPath,
      "--stdout", $StdoutPath,
      "--stderr", $StderrPath,
      "--", $FilePath
    )) {
    [void]$startInfo.ArgumentList.Add([string]$argument)
  }
  foreach ($argument in $ArgumentList) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) {
    $process.Dispose()
    throw "无法启动进程组监督器: $Phase"
  }
  return [pscustomobject]@{
    Phase = $Phase
    Process = $process
    StatusPath = $statusPath
    TimeoutSeconds = $TimeoutSeconds
    StdoutPath = $StdoutPath
    StderrPath = $StderrPath
    StartedAt = [DateTimeOffset]::UtcNow
  }
}

function Stop-SupervisedProcess {
  param([Parameter(Mandatory = $true)]$Handle)

  $process = $Handle.Process
  $process.Refresh()
  if ($process.HasExited) {
    return $true
  }
  # 监督器收到 TERM 后会先回收独立 child process group；若监督器自身失去响应，
  # 最多再等待 7 秒后强制结束。两个等待都必须有上限。
  & /bin/kill -TERM $process.Id 2>$null
  if ($process.WaitForExit(7000)) {
    return $true
  }
  & /bin/kill -KILL $process.Id 2>$null
  return $process.WaitForExit(5000)
}

function Read-SupervisorStatus {
  param([Parameter(Mandatory = $true)]$Handle)

  if (-not (Test-Path -LiteralPath $Handle.StatusPath -PathType Leaf)) {
    return [pscustomobject]@{
      ExitCode = 125
      TimedOut = $false
      DurationSeconds = [Math]::Round(
        ([DateTimeOffset]::UtcNow - $Handle.StartedAt).TotalSeconds,
        3
      )
      PeakWorkingSetBytes = $null
      FinalProcessCount = $null
      Error = "进程组监督器没有写入状态文件"
      StdoutPath = $Handle.StdoutPath
      StderrPath = $Handle.StderrPath
    }
  }
  try {
    $status = Get-Content -LiteralPath $Handle.StatusPath -Raw | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      ExitCode = 125
      TimedOut = $false
      DurationSeconds = [Math]::Round(
        ([DateTimeOffset]::UtcNow - $Handle.StartedAt).TotalSeconds,
        3
      )
      PeakWorkingSetBytes = $null
      FinalProcessCount = $null
      Error = "进程组监督器状态文件损坏: $($_.Exception.Message)"
      StdoutPath = $Handle.StdoutPath
      StderrPath = $Handle.StderrPath
    }
  }
  return [pscustomobject]@{
    ExitCode = [int]$status.exitCode
    TimedOut = [bool]$status.timedOut
    DurationSeconds = [double]$status.durationSeconds
    PeakWorkingSetBytes = $status.peakRssBytes
    FinalProcessCount = $status.finalProcessCount
    Error = $status.error
    StdoutPath = $Handle.StdoutPath
    StderrPath = $Handle.StderrPath
  }
}

function Wait-SupervisedProcess {
  param(
    [Parameter(Mandatory = $true)]$Handle,
    [int]$AdditionalSeconds = 15
  )

  $deadline = $Handle.StartedAt.AddSeconds($Handle.TimeoutSeconds + $AdditionalSeconds)
  while (-not $Handle.Process.WaitForExit(1000)) {
    if ([DateTimeOffset]::UtcNow -ge $deadline) {
      if (-not (Stop-SupervisedProcess -Handle $Handle)) {
        Write-Error "进程组监督器无法在有界时间内结束: $($Handle.Phase)" -ErrorAction Continue
      }
      break
    }
  }
  return Read-SupervisorStatus -Handle $Handle
}

function Invoke-BoundedProcess {
  param(
    [Parameter(Mandatory = $true)][string]$Phase,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)][string]$StdoutPath,
    [Parameter(Mandatory = $true)][string]$StderrPath
  )

  $handle = Start-SupervisedProcess `
    -Phase $Phase `
    -FilePath $FilePath `
    -ArgumentList $ArgumentList `
    -WorkingDirectory $WorkingDirectory `
    -TimeoutSeconds $TimeoutSeconds `
    -StdoutPath $StdoutPath `
    -StderrPath $StderrPath
  try {
    return Wait-SupervisedProcess -Handle $handle
  } finally {
    if (-not $handle.Process.HasExited) {
      [void](Stop-SupervisedProcess -Handle $handle)
    }
    $handle.Process.Dispose()
  }
}

function Resolve-CapabilityContract {
  param([Parameter(Mandatory = $true)][string]$Scenario)

  $encoded = & python $matrixResolver `
    --matrix $matrix `
    --profile platform `
    --platform macos `
    --scenario $Scenario `
    --framework $framework `
    --base64
  if ($LASTEXITCODE -ne 0) {
    throw "无法解析 macOS hybrid 场景 $Scenario 的能力契约"
  }
  return (($encoded -join "").Trim())
}

function Stop-RawProcessBounded {
  param([Diagnostics.Process]$Process)

  if ($null -eq $Process) {
    return
  }
  $Process.Refresh()
  if (-not $Process.HasExited) {
    & /bin/kill -TERM $Process.Id 2>$null
    if (-not $Process.WaitForExit(5000)) {
      & /bin/kill -KILL $Process.Id 2>$null
      if (-not $Process.WaitForExit(5000)) {
        Write-Error "进程 PID $($Process.Id) 无法在有界时间内结束" -ErrorAction Continue
      }
    }
  }
}

function Wait-ForLddcProcessBaseline {
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
  $stableSamples = 0
  $count = 0
  do {
    $count = @(Get-Process -Name "LDDC" -ErrorAction SilentlyContinue).Count
    if ($count -eq 0) {
      $stableSamples += 1
      if ($stableSamples -ge 3) {
        return 0
      }
    } else {
      $stableSamples = 0
    }
    Start-Sleep -Milliseconds 100
  } while ([DateTimeOffset]::UtcNow -lt $deadline)
  return $count
}

function Get-SupervisorResidualCount {
  param([object[]]$Statuses)

  $count = 0
  foreach ($status in $Statuses) {
    if ($null -eq $status) {
      continue
    }
    if ($null -eq $status.FinalProcessCount) {
      # 已启动的监督器若缺少最终进程计数，资源状态不可证明，必须失败。
      $count += 1
      continue
    }
    $count += [Math]::Max(0, [int]$status.FinalProcessCount)
  }
  return $count
}

function Wait-ForHybridState {
  param(
    [Parameter(Mandatory = $true)]$FlutterHandle,
    [Parameter(Mandatory = $true)][string]$StatePath,
    [Parameter(Mandatory = $true)][string]$Scenario,
    [Parameter(Mandatory = $true)][string]$ExpectedState,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
  while ($true) {
    if ([DateTimeOffset]::UtcNow -ge $deadline) {
      throw "Flutter integration_test 未在超时内写入状态 $ExpectedState"
    }
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
      $FlutterHandle.Process.Refresh()
      if ($FlutterHandle.Process.HasExited) {
        $status = Read-SupervisorStatus -Handle $FlutterHandle
        throw "Flutter integration_test 在状态 $ExpectedState 前退出，exit=$($status.ExitCode)"
      }
      Start-Sleep -Milliseconds 100
      continue
    }
    try {
      $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    } catch {
      throw "Flutter integration_test 写入了损坏的 hybrid 状态: $($_.Exception.Message)"
    }
    if ($state.schemaVersion -ne 1 `
        -or $state.runId -ne $runId `
        -or $state.scenario -ne $Scenario) {
      throw "macOS hybrid 状态与当前 schema/runId/scenario 不匹配"
    }
    if ($state.state -eq "flutter_failed") {
      $diagnosticText = if ($null -eq $state.diagnostics) {
        "unavailable"
      } else {
        ($state.diagnostics | ConvertTo-Json -Compress -Depth 3)
      }
      throw "Flutter hybrid 状态失败: $($state.error); diagnostics=$diagnosticText"
    }
    if ($state.state -eq $ExpectedState) {
      break
    }
    $FlutterHandle.Process.Refresh()
    if ($FlutterHandle.Process.HasExited) {
      $status = Read-SupervisorStatus -Handle $FlutterHandle
      throw "Flutter integration_test 在状态 $ExpectedState 前退出，exit=$($status.ExitCode)"
    }
    Start-Sleep -Milliseconds 100
  }

  if ($ExpectedState -ne "picker_requested") {
    return $state
  }

  [long]$applicationPid = 0
  $hasValidPid = [long]::TryParse([string]$state.appPid, [ref]$applicationPid)
  if (-not $hasValidPid `
      -or $applicationPid -le 0) {
    throw "macOS hybrid 状态中的应用 PID 无效"
  }
  $applicationProcess = Get-Process -Id ([int]$applicationPid) -ErrorAction SilentlyContinue
  if ($null -eq $applicationProcess -or $applicationProcess.ProcessName -ne "LDDC") {
    throw "macOS hybrid 状态指向的 LDDC 应用进程不存在"
  }
  try {
    $bundlePath = [string]$state.appBundlePath
    if ([string]::IsNullOrWhiteSpace($bundlePath) `
        -or -not [IO.Path]::IsPathRooted($bundlePath) `
        -or [IO.Path]::GetExtension($bundlePath) -ne ".app" `
        -or -not (Test-Path -LiteralPath $bundlePath -PathType Container)) {
      throw "macOS hybrid 状态中的 app bundle 路径无效"
    }
    $infoPlist = Join-Path $bundlePath "Contents/Info.plist"
    if (-not (Test-Path -LiteralPath $infoPlist -PathType Leaf)) {
      throw "macOS hybrid app bundle 缺少 Info.plist"
    }
    [string]$bundleIdentifier = (& /usr/bin/plutil -extract CFBundleIdentifier raw -o - $infoPlist 2>$null) -join ""
    if ($LASTEXITCODE -ne 0 -or $bundleIdentifier.Trim() -ne "com.cmzj.lddc") {
      throw "macOS hybrid app bundle identifier 不匹配"
    }
  } finally {
    $applicationProcess.Dispose()
  }
  return $state
}

function Assert-FlutterCompletionState {
  param(
    [Parameter(Mandatory = $true)]$State,
    [Parameter(Mandatory = $true)][string]$Action
  )

  $diagnostics = $State.diagnostics
  if ($null -eq $diagnostics) {
    throw "Flutter completion marker 缺少结果 diagnostics"
  }
  if ($Action -eq "select") {
    if ([string]$diagnostics.inputType -ne "songFile") {
      throw "Flutter completion marker 的 inputType 不是 songFile"
    }
    if ([string]$diagnostics.inputName -ne "audio_sample.mp3") {
      throw "Flutter completion marker 的 inputName 不匹配 fixture"
    }
    if ([string]$diagnostics.inputPathPresent -ne "True") {
      throw "Flutter completion marker 缺少选中文件路径"
    }
    if ([string]$diagnostics.rawTextContainsFixture -ne "True") {
      throw "Flutter completion marker 缺少 fixture 歌词正文证据"
    }
  } else {
    if ([string]$diagnostics.inputType -ne "null" `
        -or [string]$diagnostics.inputName -ne "" `
        -or [string]$diagnostics.inputPathPresent -ne "False") {
      throw "Flutter cancel completion marker 包含非空文件结果"
    }
  }
}

function Write-SanitizedHybridStateDiagnostic {
  param(
    [Parameter(Mandatory = $true)][string]$StatePath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Scenario
  )

  if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
    return
  }
  try {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    $payload = [ordered]@{
      schemaVersion = $state.schemaVersion
      runId = $state.runId
      scenario = $state.scenario
      state = $state.state
      timestamp = $state.timestamp
      appPidPresent = ([int64]$state.appPid -gt 0)
      appBundleName = [IO.Path]::GetFileName([string]$state.appBundlePath)
      action = $state.action
      success = $state.success
      error = $state.error
      diagnostics = $state.diagnostics
    }
    [IO.File]::WriteAllText(
      $OutputPath,
      ($payload | ConvertTo-Json -Depth 5),
      [Text.UTF8Encoding]::new($false)
    )
  } catch {
    [IO.File]::WriteAllText(
      $OutputPath,
      (@{
          scenario = $Scenario
          state = "diagnostic_parse_failed"
          error = $_.Exception.Message
        } | ConvertTo-Json),
      [Text.UTF8Encoding]::new($false)
    )
  }
}

function Start-SupervisedXcodeTest {
  param(
    [Parameter(Mandatory = $true)][string]$XcTestRun,
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$ResultBundle,
    [Parameter(Mandatory = $true)][string]$LogPrefix,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  return Start-SupervisedProcess `
    -Phase "xcuitest/$Method" `
    -FilePath "xcodebuild" `
    -ArgumentList @(
      "test-without-building",
      "-xctestrun", $XcTestRun,
      "-destination", "platform=macOS,arch=$hostArchitecture",
      "-parallel-testing-enabled", "NO",
      "-test-timeouts-enabled", "YES",
      "-maximum-test-execution-time-allowance", "$hybridNativeActionTimeoutSeconds",
      "-only-testing:RunnerUITests/RunnerUITests/$Method",
      "-resultBundlePath", $ResultBundle
    ) `
    -WorkingDirectory $appRoot `
    -TimeoutSeconds $TimeoutSeconds `
    -StdoutPath "$LogPrefix.stdout.log" `
    -StderrPath "$LogPrefix.stderr.log"
}

function Read-XcresultSummary {
  param(
    [Parameter(Mandatory = $true)][string]$ResultBundle,
    [Parameter(Mandatory = $true)][string]$SummaryPath
  )

  if (-not (Test-Path -LiteralPath $ResultBundle)) {
    return $false
  }
  $result = Invoke-BoundedProcess `
    -Phase "xcresult-summary" `
    -FilePath "xcrun" `
    -ArgumentList @("xcresulttool", "get", "test-results", "summary", "--path", $ResultBundle, "--format", "json") `
    -WorkingDirectory $appRoot `
    -TimeoutSeconds 120 `
    -StdoutPath $SummaryPath `
    -StderrPath "$SummaryPath.stderr.log"
  if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    return $false
  }
  return (Get-Item -LiteralPath $SummaryPath).Length -gt 0
}

function Test-PassingXcresultSummary {
  param([Parameter(Mandatory = $true)][string]$SummaryPath)

  if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    return $false
  }
  try {
    $summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json
    return $summary.totalTestCount -eq 1 `
      -and $summary.failedTests -eq 0 `
      -and $summary.skippedTests -eq 0
  } catch {
    return $false
  }
}

function ConvertTo-SanitizedFailureMessage {
  param([string]$Message)

  if ([string]::IsNullOrWhiteSpace($Message)) {
    return $null
  }
  $sanitized = $Message.Trim()
  foreach ($replacement in @(
      @($fixture, "<fixture>"),
      @($hybridRoot, "<hybrid-root>"),
      @($appRoot, "<app-root>"),
      @($repoRoot, "<workspace>")
    )) {
    $source = [string]$replacement[0]
    if (-not [string]::IsNullOrWhiteSpace($source)) {
      $sanitized = $sanitized.Replace(
        $source,
        [string]$replacement[1],
        [StringComparison]::OrdinalIgnoreCase
      )
    }
  }
  return $sanitized
}

function Get-XcresultFailureMessage {
  param([Parameter(Mandatory = $true)][string]$SummaryPath)

  if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) {
    return $null
  }
  try {
    $summary = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json
    foreach ($failure in @($summary.testFailures)) {
      $failureText = [string]$failure.failureText
      if (-not [string]::IsNullOrWhiteSpace($failureText)) {
        return ConvertTo-SanitizedFailureMessage -Message $failureText
      }
    }
  } catch {
    return $null
  }
  return $null
}

function Get-FlutterScenarioFailureMessage {
  param([Parameter(Mandatory = $true)][string]$ScenarioPath)

  if (-not (Test-Path -LiteralPath $ScenarioPath -PathType Leaf)) {
    return $null
  }
  try {
    $scenarioPayload = Get-Content -LiteralPath $ScenarioPath -Raw | ConvertFrom-Json
    foreach ($step in @($scenarioPayload.steps)) {
      if ($step.success -ne $true -and -not [string]::IsNullOrWhiteSpace([string]$step.error)) {
        return ConvertTo-SanitizedFailureMessage -Message ([string]$step.error)
      }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$scenarioPayload.extra.error)) {
      return ConvertTo-SanitizedFailureMessage -Message ([string]$scenarioPayload.extra.error)
    }
  } catch {
    return $null
  }
  return $null
}

function Resolve-FallbackFailureMessage {
  param(
    [string]$RunnerFailureMessage,
    [string]$XcresultFailureMessage,
    [string]$FlutterFailureMessage,
    [Parameter(Mandatory = $true)][int]$EvidenceCount
  )

  foreach ($candidate in @(
      $RunnerFailureMessage,
      $XcresultFailureMessage,
      $FlutterFailureMessage
    )) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
      return ConvertTo-SanitizedFailureMessage -Message $candidate
    }
  }
  return "XCUITest hybrid evidence attachment 必须且只能有一个，实际为 $EvidenceCount"
}

function Write-FallbackEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Scenario,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $payload = [ordered]@{
    runId = $runId
    scenario = $Scenario
    profile = "platform"
    platform = "macos"
    framework = $framework
    steps = @([ordered]@{ step = "xcuitest_native_panel_action"; success = $false; error = $Message })
    capabilityEvidence = @{}
    resources = [ordered]@{
      baseline = @{}
      final = @{}
      thresholds = @{}
    }
    artifacts = @()
    extra = @{ infrastructureFailure = $Message }
  }
  [IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

function Add-RunnerCleanupEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][int]$FinalChildProcessCount
  )

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
  if (-not $payload.capabilityEvidence.ContainsKey("resourceCleanup")) {
    $payload.capabilityEvidence["resourceCleanup"] = @()
  }
  if ($FinalChildProcessCount -eq 0) {
    $payload.capabilityEvidence["resourceCleanup"] += @{
      action = "flutter_and_xcuitest_processes_closed"
    }
  } else {
    $payload.steps += @{
      step = "runner_process_cleanup"
      success = $false
      error = "测试拥有的子进程仍有 $FinalChildProcessCount 个存活"
    }
  }
  foreach ($section in @("baseline", "final", "thresholds")) {
    if (-not $payload.resources.ContainsKey($section)) {
      $payload.resources[$section] = @{}
    }
  }
  $payload.resources["baseline"]["childProcessCount"] = 0
  $payload.resources["final"]["childProcessCount"] = $FinalChildProcessCount
  $payload.resources["thresholds"]["childProcessCount"] = 0
  [IO.File]::WriteAllText(
    $Path,
    ($payload | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
  )
}

function Add-RunnerDiagnosticEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$RunnerTerminationReason,
    [string]$XcresultReportError,
    [bool]$ReportDrainAttempted,
    [int]$FlutterExitCode,
    [int]$XcodeExitCode
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return
  }
  try {
    $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
  } catch {
    return
  }
  if (-not $payload.ContainsKey("extra") -or $payload.extra -isnot [hashtable]) {
    $payload.extra = @{}
  }
  $payload.extra["runnerClassification"] = [ordered]@{
    flutterExitCode = $FlutterExitCode
    xctestExitCode = $XcodeExitCode
    runnerTerminated = -not [string]::IsNullOrWhiteSpace($RunnerTerminationReason)
    runnerTerminationReason = $RunnerTerminationReason
    reportDrainAttempted = $ReportDrainAttempted
    xcresultReportCorrupt = -not [string]::IsNullOrWhiteSpace($XcresultReportError)
    xcresultReportError = $XcresultReportError
  }
  [IO.File]::WriteAllText(
    $Path,
    ($payload | ConvertTo-Json -Depth 30),
    [Text.UTF8Encoding]::new($false)
  )
}

function Write-InfrastructureFailureReports {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [switch]$Overwrite
  )

  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    $junitPath = Join-Path $junitDir "$scenario.xml"
    if (-not $Overwrite `
        -and (Test-Path -LiteralPath $scenarioPath -PathType Leaf) `
        -and (Test-Path -LiteralPath $junitPath -PathType Leaf)) {
      continue
    }

    $flutterJsonl = Join-Path $rawDir "$scenario.flutter.jsonl"
    $fallbackEvidence = Join-Path $attachmentsDir "lddc-evidence-$scenario.json"
    Write-FallbackEvidence -Path $fallbackEvidence -Scenario $scenario -Message $Message
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $flutterJsonl `
      --raw-report-type flutter-jsonl `
      --framework $framework `
      --exit-code 1 `
      --evidence $fallbackEvidence `
      --matrix $matrix `
      --run-id $runId `
      --scenario $scenario `
      --profile platform `
      --platform macos `
      --failure-junit $junitPath
  }
}

$overallExitCode = 0
$observationFailureDetected = $false
$activeFlutterHandle = $null
Push-Location $appRoot
try {
  foreach ($entry in $testRunnerEnvironment.GetEnumerator()) {
    $environmentName = [string]$entry.Key
    $previousTestRunnerEnvironment[$environmentName] =
      [Environment]::GetEnvironmentVariable($environmentName, "Process")
    # xcodebuild test-without-building 只保证把 TEST_RUNNER_ 前缀变量传给
    # 测试进程。scheme 中的 $(...) build setting 在 hosted runner 没有进入
    # RunnerUITests，曾导致 runId 与同步目录同时缺失。
    [Environment]::SetEnvironmentVariable(
      $environmentName,
      [string]$entry.Value,
      "Process"
    )
  }
  $existingLddc = @(Get-Process -Name "LDDC" -ErrorAction SilentlyContinue)
  if ($existingLddc.Count -gt 0) {
    throw "macOS hybrid 测试要求启动前不存在 LDDC 进程，当前 PID: $($existingLddc.Id -join ', ')"
  }
  # xcodebuild 会自行编译 Runner 与 UI test bundle，但仍依赖 Flutter 生成的
  # Generated.xcconfig 和 ephemeral/*.xcfilelist。config-only 只生成这些 Xcode
  # 输入，不提前完整编译应用，因此既满足原生构建前置条件，也避免重复构建。
  $flutterConfigResult = Invoke-BoundedProcess `
    -Phase "flutter-macos-config" `
    -FilePath $flutterCommand `
    -ArgumentList @("build", "macos", "--debug", "--config-only") `
    -WorkingDirectory $appRoot `
    -TimeoutSeconds 180 `
    -StdoutPath (Join-Path $diagnosticsDir "flutter-macos-config.stdout.log") `
    -StderrPath (Join-Path $diagnosticsDir "flutter-macos-config.stderr.log")
  if ($flutterConfigResult.ExitCode -ne 0) {
    throw "macOS Flutter Xcode 配置生成失败，exit=$($flutterConfigResult.ExitCode)"
  }
  $podInstallResult = Invoke-BoundedProcess `
    -Phase "pod-install" `
    -FilePath "pod" `
    -ArgumentList @("install", "--project-directory=macos") `
    -WorkingDirectory $appRoot `
    -TimeoutSeconds 180 `
    -StdoutPath (Join-Path $diagnosticsDir "pod-install.stdout.log") `
    -StderrPath (Join-Path $diagnosticsDir "pod-install.stderr.log")
  if ($podInstallResult.ExitCode -ne 0) {
    throw "macOS CocoaPods 解析失败，exit=$($podInstallResult.ExitCode)"
  }
  New-Item -ItemType Directory -Force `
    -Path $syncDir, (Split-Path -Parent $fixture), $containerReportDir | Out-Null
  Copy-Item -LiteralPath $fixtureSource -Destination $fixture -Force
  $uiBuildResult = Invoke-BoundedProcess `
    -Phase "xcuitest-build-for-testing" `
    -FilePath "xcodebuild" `
    -ArgumentList @(
      "build-for-testing",
      "-workspace", $testProject,
      "-scheme", "RunnerPlatformTests",
      "-configuration", "Debug",
      "-destination", "platform=macOS,arch=$hostArchitecture",
      "-parallel-testing-enabled", "NO",
      "-derivedDataPath", $derivedData
    ) `
    -WorkingDirectory $appRoot `
    -TimeoutSeconds 600 `
    -StdoutPath (Join-Path $diagnosticsDir "xcuitest-build.stdout.log") `
    -StderrPath (Join-Path $diagnosticsDir "xcuitest-build.stderr.log")
  if ($uiBuildResult.ExitCode -ne 0) {
    throw "macOS XCUITest build-for-testing 失败，exit=$($uiBuildResult.ExitCode)"
  }
  $xctestrun = Resolve-UniqueBuildArtifact `
    -Root (Join-Path $derivedData "Build/Products") `
    -Filter "*.xctestrun" `
    -Description "macOS RunnerPlatformTests xctestrun"

  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $action = $entry.Action
    $method = $entry.Method
    $capabilitiesB64 = Resolve-CapabilityContract -Scenario $scenario
    $statePath = Join-Path $syncDir "$scenario.state.json"
    $flutterJsonl = Join-Path $rawDir "$scenario.flutter.jsonl"
    $resultBundle = Join-Path $rawDir "$scenario.xcresult"
    $summaryPath = Join-Path $rawDir "$scenario.xcresult.summary.json"
    $scenarioAttachments = Join-Path $attachmentsDir $scenario
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    $containerScenarioPath = Join-Path $containerReportDir "$scenario.json"
    $junitPath = Join-Path $junitDir "$scenario.xml"
    New-Item -ItemType Directory -Force -Path $scenarioAttachments | Out-Null
    foreach ($path in @($statePath, $flutterJsonl, $summaryPath, $scenarioPath, $containerScenarioPath, $junitPath)) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }

    $flutterArguments = @(
      "test", $flutterTarget,
      "-d", "macos",
      "-r", "expanded",
      "--file-reporter", "json:$flutterJsonl",
      "--dart-define=LDDC_IT_PROFILE=platform",
      "--dart-define=LDDC_IT_DEVICE=macos",
      "--dart-define=LDDC_IT_RUN_ID=$runId",
      "--dart-define=LDDC_IT_FRAMEWORK=$framework",
      "--dart-define=LDDC_IT_CAPABILITIES_B64=$capabilitiesB64",
      "--dart-define=LDDC_IT_REPORT_DIR=$hybridRelativeRoot/reports",
      "--dart-define=LDDC_IT_WORKSPACE_ROOT=$workspaceRoot",
      "--dart-define=LDDC_MACOS_HYBRID_SYNC_DIR=$syncDir",
      "--dart-define=LDDC_MACOS_DIALOG_ACTION=$action",
      "--dart-define=LDDC_FIXTURE_SIZE=$fixtureSize",
      "--dart-define=LDDC_FIXTURE_SHA256=$fixtureSha256",
      "--dart-define=LDDC_IT_STEP_TIMEOUT_MS=$($hybridNativeActionTimeoutSeconds * 1000)"
    )

    $flutterExitCode = 1
    $xcodeExitCode = 1
    $nativeSummaryPassed = $false
    $xcodeHandle = $null
    $xcodeStatus = $null
    $flutterStatus = $null
    $runnerFailureMessage = $null
    $runnerTerminationReason = $null
    $xcresultReportError = $null
    $reportDrainAttempted = $false
    $scenarioStartedAt = [DateTimeOffset]::UtcNow
    $scenarioDeadline = $null
    try {
      Write-Host "Running macOS hybrid scenario: $scenario"
      # 外层监督器只额外保留进程退出和状态文件落盘余量；实际 Flutter
      # 冷启动与业务场景仍分别由 180/120 秒边界控制，不能用这里掩盖超时。
      $activeFlutterHandle = Start-SupervisedProcess `
        -Phase "flutter-integration/$scenario" `
        -FilePath $flutterCommand `
        -ArgumentList $flutterArguments `
        -WorkingDirectory $appRoot `
        -TimeoutSeconds ($FlutterStartupTimeoutSeconds + $ScenarioTimeoutSeconds + 15) `
        -StdoutPath (Join-Path $diagnosticsDir "$scenario.flutter.stdout.log") `
        -StderrPath (Join-Path $diagnosticsDir "$scenario.flutter.stderr.log")

      # testStart 只表示 Dart 测试进程创建了测试事件，不能证明 Flutter 应用已经
      # 完成冷编译、启动并准备调用 NSOpenPanel。这里只等待 Flutter 单写的
      # picker_requested marker；冷编译消耗独立启动预算，避免在应用仍处于
      # Building macOS application 时误杀进程。marker 出现后才开始业务总预算。
      $null = Wait-ForHybridState `
        -FlutterHandle $activeFlutterHandle `
        -StatePath $statePath `
        -Scenario $scenario `
        -ExpectedState "picker_requested" `
        -TimeoutSeconds $FlutterStartupTimeoutSeconds
      $scenarioDeadline = [DateTimeOffset]::UtcNow.AddSeconds($ScenarioTimeoutSeconds)

      $remainingScenarioSeconds = [int][Math]::Floor(
        ($scenarioDeadline - [DateTimeOffset]::UtcNow).TotalSeconds
      )
      if ($remainingScenarioSeconds -le 0) {
        throw "macOS hybrid 在启动 XCUITest 前已耗尽场景总预算"
      }
      # XCTest 内部仍以 90 秒终止原生业务动作；xcodebuild 进程额外获得固定
      # 30 秒写完 xcresult。该监督预算不延长测试动作，只防止报告在落盘时被截断。
      $xcodeHandle = Start-SupervisedXcodeTest `
        -XcTestRun $xctestrun.FullName `
        -Method $method `
        -ResultBundle $resultBundle `
        -LogPrefix (Join-Path $diagnosticsDir "$scenario.xcodebuild") `
        -TimeoutSeconds ([Math]::Min(
          $hybridNativeActionTimeoutSeconds + $xcodeReportDrainSeconds,
          $remainingScenarioSeconds
        ))

      while ([DateTimeOffset]::UtcNow -lt $scenarioDeadline) {
        $activeFlutterHandle.Process.Refresh()
        $xcodeHandle.Process.Refresh()

        if ($xcodeHandle.Process.HasExited -and $null -eq $xcodeStatus) {
          $xcodeStatus = Wait-SupervisedProcess -Handle $xcodeHandle -AdditionalSeconds 5
          $xcodeExitCode = $xcodeStatus.ExitCode
          if ($xcodeExitCode -ne 0) {
            # 原生 runner 已经失败时，Flutter 仍会阻塞在系统面板。
            # 立即结束所有的进程组，不等待完整场景 deadline。
            $runnerTerminationReason = "xctest_failed_flutter_terminated"
            if (-not $activeFlutterHandle.Process.HasExited) {
              [void](Stop-SupervisedProcess -Handle $activeFlutterHandle)
            }
            break
          }
          $remainingCompletionSeconds = [int][Math]::Floor(
            ($scenarioDeadline - [DateTimeOffset]::UtcNow).TotalSeconds
          )
          $flutterCompletionState = Wait-ForHybridState `
            -FlutterHandle $activeFlutterHandle `
            -StatePath $statePath `
            -Scenario $scenario `
            -ExpectedState "flutter_completed" `
            -TimeoutSeconds ([Math]::Max(1, $remainingCompletionSeconds))
          if ($flutterCompletionState.success -ne $true) {
            throw "Flutter hybrid 完成状态缺少成功标记"
          }
          Assert-FlutterCompletionState `
            -State $flutterCompletionState `
            -Action $action
        }

        if ($activeFlutterHandle.Process.HasExited -and $null -eq $flutterStatus) {
          $flutterStatus = Wait-SupervisedProcess -Handle $activeFlutterHandle -AdditionalSeconds 5
          $flutterExitCode = $flutterStatus.ExitCode
          if ($flutterExitCode -ne 0 -and -not $xcodeHandle.Process.HasExited) {
            # Flutter 业务先失败时，原生测试可能仍在写附件。只保留固定的
            # 报告收尾窗口，窗口结束后再结束 XCTest；这不是业务重试或超时放宽。
            $reportDrainAttempted = $true
            $drainDeadline = [DateTimeOffset]::UtcNow.AddSeconds($xcodeReportDrainSeconds)
            while (-not $xcodeHandle.Process.HasExited -and [DateTimeOffset]::UtcNow -lt $drainDeadline) {
              Start-Sleep -Milliseconds 200
              $xcodeHandle.Process.Refresh()
            }
            if (-not $xcodeHandle.Process.HasExited) {
              $runnerTerminationReason = "flutter_failed_xcresult_drain_expired"
              [void](Stop-SupervisedProcess -Handle $xcodeHandle)
            } else {
              # 原生测试在独立收尾窗口内自然退出时，保留其真实退出码，不能把
              # runner 主动终止或 143 伪造成原始 XCTest 结果。
              $xcodeStatus = Wait-SupervisedProcess -Handle $xcodeHandle -AdditionalSeconds 5
              $xcodeExitCode = $xcodeStatus.ExitCode
            }
            break
          }
        }
        if ($null -ne $flutterStatus -and $null -ne $xcodeStatus) {
          break
        }
        Start-Sleep -Milliseconds 200
      }
      if (-not $activeFlutterHandle.Process.HasExited) {
        [void](Stop-SupervisedProcess -Handle $activeFlutterHandle)
      }
      if (-not $xcodeHandle.Process.HasExited) {
        $runnerTerminationReason = $runnerTerminationReason ?? "runner_scenario_deadline"
        [void](Stop-SupervisedProcess -Handle $xcodeHandle)
      }
      if ($null -eq $flutterStatus) {
        $runnerTerminationReason = $runnerTerminationReason ?? "runner_scenario_deadline"
        $flutterStatus = Wait-SupervisedProcess -Handle $activeFlutterHandle -AdditionalSeconds 5
      }
      if ($null -eq $xcodeStatus) {
        $runnerTerminationReason = $runnerTerminationReason ?? "runner_scenario_deadline"
        $xcodeStatus = Wait-SupervisedProcess -Handle $xcodeHandle -AdditionalSeconds 5
      }
      $flutterExitCode = $flutterStatus.ExitCode
      $xcodeExitCode = $xcodeStatus.ExitCode
    } catch {
      $runnerFailureMessage = $_.Exception.Message
      Write-Warning "$scenario hybrid runner 失败: $runnerFailureMessage"
    } finally {
      if ($null -ne $xcodeHandle) {
        if (-not $xcodeHandle.Process.HasExited) {
          [void](Stop-SupervisedProcess -Handle $xcodeHandle)
        }
        if ($null -eq $xcodeStatus) {
          $xcodeStatus = Wait-SupervisedProcess -Handle $xcodeHandle -AdditionalSeconds 5
        }
        $xcodeHandle.Process.Dispose()
        $xcodeHandle = $null
      }
      if ($null -ne $activeFlutterHandle) {
        if (-not $activeFlutterHandle.Process.HasExited) {
          [void](Stop-SupervisedProcess -Handle $activeFlutterHandle)
        }
        if ($null -eq $flutterStatus) {
          $flutterStatus = Wait-SupervisedProcess -Handle $activeFlutterHandle -AdditionalSeconds 5
        }
        $activeFlutterHandle.Process.Dispose()
        $activeFlutterHandle = $null
      }
    }
    if ($null -ne $flutterStatus) {
      $flutterExitCode = $flutterStatus.ExitCode
    }
    if ($null -ne $xcodeStatus) {
      $xcodeExitCode = $xcodeStatus.ExitCode
    }
    if (Test-Path -LiteralPath $resultBundle) {
      $summaryReady = Read-XcresultSummary `
        -ResultBundle $resultBundle `
        -SummaryPath $summaryPath
      if (-not $summaryReady -and [string]::IsNullOrWhiteSpace($xcresultReportError)) {
        $xcresultReportError = "macOS xcresult summary 缺失或损坏"
      }
      $nativeSummaryPassed = $summaryReady -and (Test-PassingXcresultSummary -SummaryPath $summaryPath)
      $attachmentResult = Invoke-BoundedProcess `
        -Phase "xcresult-attachments/$scenario" `
        -FilePath "xcrun" `
        -ArgumentList @("xcresulttool", "export", "attachments", "--path", $resultBundle, "--output-path", $scenarioAttachments) `
        -WorkingDirectory $appRoot `
        -TimeoutSeconds 120 `
        -StdoutPath (Join-Path $diagnosticsDir "$scenario.attachments.stdout.log") `
        -StderrPath (Join-Path $diagnosticsDir "$scenario.attachments.stderr.log")
      if ($attachmentResult.ExitCode -ne 0) {
        $xcresultReportError = "macOS xcresult attachment 导出失败，exit=$($attachmentResult.ExitCode)"
        Write-Warning "$scenario $xcresultReportError"
      }
    } elseif ([string]::IsNullOrWhiteSpace($xcresultReportError)) {
      $xcresultReportError = "macOS xcresult 结果包缺失"
    }
    Write-SanitizedHybridStateDiagnostic `
      -StatePath $statePath `
      -OutputPath (Join-Path $diagnosticsDir "$scenario.hybrid-state.json") `
      -Scenario $scenario

    foreach ($process in @(Get-Process -Name "LDDC" -ErrorAction SilentlyContinue)) {
      Stop-RawProcessBounded -Process $process
      $process.Dispose()
    }
    $finalLddcCount = Wait-ForLddcProcessBaseline
    $evidenceCandidates = @(
      Get-ChildItem -Path $scenarioAttachments -Recurse -File `
        | Where-Object {
            try {
              $payload = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
              $payload.scenario -eq $scenario
            } catch {
              $false
            }
          }
    )
    $evidencePath = if ($evidenceCandidates.Count -eq 1) {
      $evidenceCandidates[0]
    } else {
      $null
    }
    if ($null -eq $evidencePath) {
      $fallbackEvidence = Join-Path $scenarioAttachments "lddc-evidence-$scenario.json"
      $xcresultFailureMessage = Get-XcresultFailureMessage -SummaryPath $summaryPath
      $flutterScenarioFailureMessage = Get-FlutterScenarioFailureMessage `
        -ScenarioPath $containerScenarioPath
      Write-FallbackEvidence `
        -Path $fallbackEvidence `
        -Scenario $scenario `
        -Message (Resolve-FallbackFailureMessage `
          -RunnerFailureMessage $runnerFailureMessage `
          -XcresultFailureMessage $xcresultFailureMessage `
          -FlutterFailureMessage $flutterScenarioFailureMessage `
          -EvidenceCount $evidenceCandidates.Count)
      $evidencePath = Get-Item -LiteralPath $fallbackEvidence
    }
    # 每个受监督命令的 process group 才是 runner 真正拥有的进程边界。
    # 旧实现按瞬时父子关系永久登记 PID，会把 Xcode 启动后转交给系统管理的
    # 持久服务误报为 LDDC 泄漏。这里同时核对监督器最终计数与 LDDC 进程名，
    # 两者任一残留仍会以同一个零阈值阻断。
    $ownedFinalCount = $finalLddcCount + (Get-SupervisorResidualCount -Statuses @(
      $flutterStatus,
      $xcodeStatus
    ))
    Add-RunnerCleanupEvidence `
      -Path $evidencePath.FullName `
      -FinalChildProcessCount $ownedFinalCount
    Add-RunnerDiagnosticEvidence `
      -Path $evidencePath.FullName `
      -RunnerTerminationReason $runnerTerminationReason `
      -XcresultReportError $xcresultReportError `
      -ReportDrainAttempted $reportDrainAttempted `
      -FlutterExitCode $flutterExitCode `
      -XcodeExitCode $xcodeExitCode

    if (Test-Path -LiteralPath $containerScenarioPath -PathType Leaf) {
      Copy-Item -LiteralPath $containerScenarioPath -Destination $scenarioPath -Force
    }
    $combinedExitCode = if (
      $flutterExitCode -eq 0 `
        -and $xcodeExitCode -eq 0 `
        -and $nativeSummaryPassed `
        -and [string]::IsNullOrWhiteSpace($runnerFailureMessage) `
        -and [string]::IsNullOrWhiteSpace($xcresultReportError) `
        -and $evidenceCandidates.Count -eq 1 `
        -and $finalLddcCount -eq 0 `
        -and $ownedFinalCount -eq 0
    ) { 0 } else { 1 }
    # Flutter JSONL 先生成自身 JUnit；随后 normalizer 在报告损坏时可以写入
    # 更准确的基础设施失败 JUnit，不能再被原始转换结果覆盖。
    if (Test-Path -LiteralPath $flutterJsonl -PathType Leaf) {
      & python $junitConverter --input $flutterJsonl --output $junitPath
      $junitExitCode = $LASTEXITCODE
    } else {
      $junitExitCode = 1
    }
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $flutterJsonl `
      --raw-report-type flutter-jsonl `
      --framework $framework `
      --exit-code $combinedExitCode `
      --evidence $evidencePath.FullName `
      --matrix $matrix `
      --run-id $runId `
      --scenario $scenario `
      --profile platform `
      --platform macos `
      --failure-junit $junitPath
    $normalizeExitCode = $LASTEXITCODE
    if ($observationFilter.Contains($scenario)) {
      if ($normalizeExitCode -ne 0 -or $junitExitCode -ne 0) {
        $overallExitCode = 1
      } elseif ($combinedExitCode -ne 0) {
        $observationFailureDetected = $true
        Write-Warning "macOS observation 场景 $scenario 失败，保留真实报告且不阻断 required"
      }
    } elseif ($combinedExitCode -ne 0 -or $normalizeExitCode -ne 0 -or $junitExitCode -ne 0) {
      $overallExitCode = 1
    }
  }
} catch {
  $overallExitCode = 1
  $message = "macOS hybrid infrastructure failure: $($_.Exception.Message)"
  Write-Error $message -ErrorAction Continue
  Write-InfrastructureFailureReports -Message $message
} finally {
  if ($null -ne $activeFlutterHandle) {
    if (-not $activeFlutterHandle.Process.HasExited) {
      [void](Stop-SupervisedProcess -Handle $activeFlutterHandle)
    }
    $activeFlutterHandle.Process.Dispose()
    $activeFlutterHandle = $null
  }
  Pop-Location
  try {
    if (Test-Path -LiteralPath $hybridRoot -PathType Container) {
      Remove-Item -LiteralPath $hybridRoot -Recurse -Force
    }
    if (-not $PreserveBuildProducts -and (Test-Path -LiteralPath $derivedData -PathType Container)) {
      Remove-Item -LiteralPath $derivedData -Recurse -Force
    }
  } catch {
    $overallExitCode = 1
    $message = "macOS hybrid cleanup failure: $($_.Exception.Message)"
    Write-Error $message -ErrorAction Continue
    Write-InfrastructureFailureReports -Message $message -Overwrite
  }
  foreach ($environmentName in $previousTestRunnerEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable(
      $environmentName,
      $previousTestRunnerEnvironment[$environmentName],
      "Process"
    )
  }
}

foreach ($entry in $scenarios) {
  if ($observationFilter.Contains($entry.Name)) { continue }
  $scenarioPath = Join-Path $scenarioDir "$($entry.Name).json"
  $junitPath = Join-Path $junitDir "$($entry.Name).xml"
  if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf) `
      -or -not (Test-Path -LiteralPath $junitPath -PathType Leaf)) {
    $overallExitCode = 1
    Write-Error "macOS required 场景 $($entry.Name) 缺少报告" -ErrorAction Continue
    continue
  }
  Copy-Item -LiteralPath $scenarioPath -Destination $requiredScenarioDir -Force
  Copy-Item -LiteralPath $junitPath -Destination $requiredJunitDir -Force
}
$requiredReports = @(Get-ChildItem -LiteralPath $requiredScenarioDir -File -ErrorAction SilentlyContinue)
if ($requiredReports.Count -gt 0) {
  & python $verifier `
    --directory $requiredScenarioDir `
    --junit-directory $requiredJunitDir `
    --profile platform `
    --platform macos `
    --run-id $runId `
    --matrix $matrix
  if ($LASTEXITCODE -ne 0) { $overallExitCode = 1 }
}
if ($requiredReports.Count -eq 0 -and $observationFailureDetected) {
  # 独立 observation job 返回真实失败，再由 workflow 的 job 级
  # continue-on-error 取消阻断；不能在 runner 内部伪装成成功。
  $overallExitCode = 1
}

Write-Host "macOS hybrid platform reports: $runRoot"
exit $overallExitCode
