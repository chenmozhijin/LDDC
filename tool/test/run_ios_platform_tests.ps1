param(
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [string]$ReportDir = "build/integration_reports/ios-native",
  [ValidateRange(30, 600)]
  [int]$ScenarioTimeoutSeconds = 120,
  [ValidateSet("ios_document_picker_export_cancel")]
  [string[]]$ExperimentalScenarios = @()
)

$ErrorActionPreference = "Stop"

# XCTest 内部仍使用 ScenarioTimeoutSeconds 作为真实测试动作的硬上限。
# xcodebuild 在测试已结束后还需要有界写入 xcresult 的 Info.plist、
# attachments 和 summary。外层多留 90 秒只用于报告收尾，不延长
# Document Picker 操作、断言或业务等待；超过该边界仍会回收整个进程组。
$xcodeResultFinalizationTimeoutSeconds = $ScenarioTimeoutSeconds + 90

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$junitConverter = Join-Path $repoRoot "tool/test/xcresult_summary_to_junit.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
$processSupervisor = Join-Path $repoRoot "tool/test/process_group_supervisor.py"
$fixture = Join-Path $appRoot "integration_test/fixtures/media/audio_sample.mp3"
$fixtureSize = (Get-Item -LiteralPath $fixture).Length
$fixtureSha256 = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
$fixtureBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture))
$exportWitnessFileName = ".lddc_platform_export_witness.json"
$hostArchitecture = ((& uname -m 2>$null) -join "").Trim()
if ($LASTEXITCODE -ne 0 -or $hostArchitecture -notin @("arm64", "x86_64")) {
  throw "无法确定 iOS hosted 宿主架构: $hostArchitecture"
}
$xcodeVersion = ((& xcodebuild -version 2>$null) -join " ").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($xcodeVersion)) {
  throw "无法确定 iOS hosted Xcode 版本"
}
$expectedXcodeVersion = [string]$env:LDDC_XCODE_VERSION
if (-not [string]::IsNullOrWhiteSpace($expectedXcodeVersion) `
    -and -not $xcodeVersion.StartsWith("Xcode $expectedXcodeVersion ", [StringComparison]::Ordinal)) {
  throw "iOS hosted Xcode 漂移：actual=$xcodeVersion expected=$expectedXcodeVersion"
}
$simulatorMetadata = [ordered]@{
  udid = $Device
  runtime = "unknown"
  runtimeVersion = "unknown"
  model = "unknown"
  deviceTypeIdentifier = "unknown"
  state = "unknown"
  hostArchitecture = $hostArchitecture
  xcodeVersion = $xcodeVersion
  configuredLanguage = "unknown"
  configuredLocale = "unknown"
  destinationDiscovery = [ordered]@{
    ready = $false
    stage = "not_started"
    attempt = 0
    xcdeviceVisible = $false
    showDestinationsVisible = $false
  }
}
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

$runId = "platform-ios-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$testRunnerEnvironment = [ordered]@{
  TEST_RUNNER_LDDC_IT_RUN_ID = $runId
  TEST_RUNNER_LDDC_FIXTURE_SIZE = [string]$fixtureSize
  TEST_RUNNER_LDDC_FIXTURE_SHA256 = $fixtureSha256
  TEST_RUNNER_LDDC_FIXTURE_BASE64 = $fixtureBase64
}
$previousTestRunnerEnvironment = @{}
$runRoot = Join-Path $ReportDir $runId
$derivedDataParent = [IO.Path]::GetFullPath(
  (Join-Path $appRoot "build/native_test_derived_data")
)
$derivedData = [IO.Path]::GetFullPath((Join-Path $derivedDataParent $runId))
if (-not $derivedData.StartsWith(
    $derivedDataParent + [IO.Path]::DirectorySeparatorChar,
    [StringComparison]::Ordinal
  )) {
  throw "iOS Xcode DerivedData 超出测试构建根"
}
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$attachmentsDir = Join-Path $runRoot "attachments"
$requiredScenarioDir = Join-Path $runRoot "required-scenarios"
$requiredJunitDir = Join-Path $runRoot "required-junit"
foreach ($directory in @(
    $scenarioDir,
    $rawDir,
    $junitDir,
    $attachmentsDir,
    $requiredScenarioDir,
    $requiredJunitDir
  )) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

function Resolve-UniqueBuildArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Filter,
    [Parameter(Mandatory = $true)][string]$Description,
    [switch]$Directory
  )

  $matches = if ($Directory) {
    @(Get-ChildItem -Path $Root -Recurse -Directory -Filter $Filter | Sort-Object FullName)
  } else {
    @(Get-ChildItem -Path $Root -Recurse -File -Filter $Filter | Sort-Object FullName)
  }
  if ($matches.Count -ne 1) {
    $relativeMatches = @($matches | ForEach-Object {
        [IO.Path]::GetRelativePath($Root, $_.FullName).Replace("\", "/")
      })
    throw "$Description 必须且只能生成一个，实际为 $($matches.Count)：$($relativeMatches -join ', ')"
  }
  return $matches[0]
}

function Invoke-BoundedNativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Phase,
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [Parameter(Mandatory = $true)]
    [int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)]
    [string]$StdoutPath,
    [Parameter(Mandatory = $true)]
    [string]$StderrPath
  )

  $safePhase = $Phase -replace '[^A-Za-z0-9._-]', '-'
  $statusPath = Join-Path $rawDir "$safePhase.supervisor.json"
  foreach ($path in @($statusPath, $StdoutPath, $StderrPath)) {
    Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
  }
  # Xcode 与 xcresulttool 都可能派生辅助进程。统一交给 POSIX 进程组监督器，
  # 超时后同时回收 leader 和后代，避免报告提取卡住并污染后续独立场景。
  & python $processSupervisor `
    --phase $Phase `
    --timeout $TimeoutSeconds `
    --grace 5 `
    --cwd $appRoot `
    --status $statusPath `
    --stdout $StdoutPath `
    --stderr $StderrPath `
    -- $FilePath @Arguments `
    | ForEach-Object { Write-Host $_ }
  $exitCode = $LASTEXITCODE
  return $exitCode
}

function Read-BoundedCommandStatus {
  param([Parameter(Mandatory = $true)][string]$Phase)

  $safePhase = $Phase -replace '[^A-Za-z0-9._-]', '-'
  $statusPath = Join-Path $rawDir "$safePhase.supervisor.json"
  if (-not (Test-Path -LiteralPath $statusPath -PathType Leaf)) {
    return $null
  }
  try {
    return Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Format-BoundedCommandFailure {
  param(
    [Parameter(Mandatory = $true)][string]$Phase,
    [Parameter(Mandatory = $true)][int]$ExitCode
  )

  $status = Read-BoundedCommandStatus -Phase $Phase
  if ($null -eq $status) {
    return "$Phase 监督器没有可解析的状态，exit=$ExitCode"
  }
  $measurementStatus = [string]$status.resourceMeasurementStatus
  $measurementErrors = if ($null -ne $status.resourceMeasurementErrors) {
    (@($status.resourceMeasurementErrors) -join " | ")
  } else {
    ""
  }
  $commandError = [string]$status.error
  $details = @(
    "exit=$([int]$status.exitCode)",
    "measurement=$measurementStatus"
  )
  if (-not [string]::IsNullOrWhiteSpace($commandError)) {
    $details += "error=$commandError"
  }
  if (-not [string]::IsNullOrWhiteSpace($measurementErrors)) {
    $details += "measurementErrors=$measurementErrors"
  }
  return "$Phase 失败: $($details -join ', ')"
}

function Invoke-BoundedXcodeTest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$XcTestRun,
    [Parameter(Mandatory = $true)]
    [string]$Method,
    [Parameter(Mandatory = $true)]
    [string]$ResultBundle,
    [string]$Attempt = "attempt1"
  )

  $arguments = @(
      "test-without-building",
      "-xctestrun", $XcTestRun,
      "-destination", "platform=iOS Simulator,id=$Device,arch=$hostArchitecture",
      "-parallel-testing-enabled", "NO",
      "-test-timeouts-enabled", "YES",
      "-maximum-test-execution-time-allowance", "$ScenarioTimeoutSeconds",
      "-only-testing:RunnerUITests/RunnerUITests/$Method",
      "-resultBundlePath", $ResultBundle
  )
  return Invoke-BoundedNativeCommand `
    -Phase "ios-xcuitest-$Method-$Attempt" `
    -FilePath "xcodebuild" `
    -Arguments $arguments `
    -TimeoutSeconds $xcodeResultFinalizationTimeoutSeconds `
    -StdoutPath (Join-Path $rawDir "$Method.$Attempt.xcodebuild.stdout.log") `
    -StderrPath (Join-Path $rawDir "$Method.$Attempt.xcodebuild.stderr.log")
}

function Get-SimulatorState {
  $output = & xcrun simctl list devices --json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "无法查询 iOS Simulator 状态: $($output -join ' ')"
  }
  $payload = ($output -join [Environment]::NewLine) | ConvertFrom-Json
  foreach ($runtime in $payload.devices.PSObject.Properties) {
    foreach ($deviceInfo in @($runtime.Value)) {
      if ($deviceInfo.udid -eq $Device) {
        return [string]$deviceInfo.state
      }
    }
  }
  throw "Simulator $Device 不存在于 simctl 设备清单"
}

function Get-SimulatorMetadata {
  $output = & xcrun simctl list devices --json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "无法查询 iOS Simulator 元数据: $($output -join ' ')"
  }
  $payload = ($output -join [Environment]::NewLine) | ConvertFrom-Json
  $runtimeOutput = & xcrun simctl list runtimes --json 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "无法查询 iOS Simulator runtime 元数据: $($runtimeOutput -join ' ')"
  }
  $runtimePayload = ($runtimeOutput -join [Environment]::NewLine) | ConvertFrom-Json
  foreach ($runtime in $payload.devices.PSObject.Properties) {
    foreach ($deviceInfo in @($runtime.Value)) {
      if ($deviceInfo.udid -eq $Device) {
        $runtimeInfo = @($runtimePayload.runtimes | Where-Object {
            $_.identifier -eq $runtime.Name
          }) | Select-Object -First 1
        if ($null -eq $runtimeInfo -or [string]::IsNullOrWhiteSpace([string]$runtimeInfo.version)) {
          throw "Simulator $Device 的 runtime $($runtime.Name) 缺少版本元数据"
        }
        return [ordered]@{
          udid = [string]$deviceInfo.udid
          runtime = [string]$runtime.Name
          runtimeVersion = [string]$runtimeInfo.version
          model = [string]$deviceInfo.name
          deviceTypeIdentifier = [string]$deviceInfo.deviceTypeIdentifier
          state = [string]$deviceInfo.state
          hostArchitecture = $hostArchitecture
          xcodeVersion = $xcodeVersion
          destinationDiscovery = [ordered]@{
            ready = $false
            stage = "not_started"
            attempt = 0
            xcdeviceVisible = $false
            showDestinationsVisible = $false
          }
        }
      }
    }
  }
  throw "Simulator $Device 不存在于 simctl 设备清单"
}

function Invoke-RequiredSimctl {
  param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][string[]]$CommandArguments
  )
  $output = & xcrun simctl @CommandArguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "iOS Simulator 阶段 $Stage 失败: $($output -join ' ')"
  }
  return $output
}

function Get-PlatformTestContainer {
  $containerOutput = Invoke-RequiredSimctl `
    -Stage "resolve-app-container" `
    -CommandArguments @("get_app_container", $Device, "com.cmzj.lddc.platformtests", "data")
  $resolvedContainer = (($containerOutput) -join "").Trim()
  if ([string]::IsNullOrWhiteSpace($resolvedContainer)) {
    throw "无法取得 iOS 平台测试应用容器"
  }
  return $resolvedContainer
}

function Ensure-SimulatorBooted {
  param([Parameter(Mandatory = $true)][string]$Stage)

  $state = Get-SimulatorState
  if ($state -eq "Shutdown") {
    Invoke-RequiredSimctl -Stage "$Stage/boot" -CommandArguments @("boot", $Device) | Out-Null
  } elseif ($state -notin @("Booted", "Booting")) {
    throw "iOS Simulator 在 $Stage 处于不可恢复状态: $state"
  }
  Invoke-RequiredSimctl -Stage "$Stage/bootstatus" -CommandArguments @("bootstatus", $Device, "-b") | Out-Null
  $finalState = Get-SimulatorState
  if ($finalState -ne "Booted") {
    throw "iOS Simulator 在 $Stage 等待后仍不是 Booted: $finalState"
  }
}

function Test-TextContainsDeviceId {
  param(
    [AllowEmptyString()]
    [string]$Text
  )

  return -not [string]::IsNullOrWhiteSpace($Text) `
    -and $Text.Contains($Device, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-XcodeDestinationProbe {
  param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][int]$Attempt
  )

  $safeStage = $Stage -replace '[^A-Za-z0-9._-]', '-'
  $prefix = "destination-$safeStage-attempt-$Attempt"
  $xcdeviceStdout = Join-Path $rawDir "$prefix.xcdevice.stdout.json"
  $xcdeviceStderr = Join-Path $rawDir "$prefix.xcdevice.stderr.log"
  $destinationsStdout = Join-Path $rawDir "$prefix.showdestinations.stdout.log"
  $destinationsStderr = Join-Path $rawDir "$prefix.showdestinations.stderr.log"
  $probePath = Join-Path $rawDir "$prefix.json"

  # simctl 的 Booted 只代表 CoreSimulator 已完成启动，不代表 Xcode 的
  # destination discovery 已经注册该设备。xcdevice 与当前 scheme 的
  # showdestinations 必须同时看见相同 UDID，才允许启动真实 XCTest。
  $xcdeviceExitCode = Invoke-BoundedNativeCommand `
    -Phase "ios-xcdevice-$safeStage-$Attempt" `
    -FilePath "xcrun" `
    -Arguments @("xcdevice", "list", "--timeout", "5") `
    -TimeoutSeconds 20 `
    -StdoutPath $xcdeviceStdout `
    -StderrPath $xcdeviceStderr
  $destinationsExitCode = Invoke-BoundedNativeCommand `
    -Phase "ios-showdestinations-$safeStage-$Attempt" `
    -FilePath "xcodebuild" `
    -Arguments @(
      "-workspace", "ios/Runner.xcworkspace",
      "-scheme", "RunnerPlatformTests",
      "-configuration", "PlatformTest",
      "-showdestinations"
    ) `
    -TimeoutSeconds 30 `
    -StdoutPath $destinationsStdout `
    -StderrPath $destinationsStderr

  $xcdeviceText = if (Test-Path -LiteralPath $xcdeviceStdout -PathType Leaf) {
    Get-Content -LiteralPath $xcdeviceStdout -Raw
  } else {
    ""
  }
  if (Test-Path -LiteralPath $xcdeviceStderr -PathType Leaf) {
    $xcdeviceText += Get-Content -LiteralPath $xcdeviceStderr -Raw
  }
  $destinationsText = if (Test-Path -LiteralPath $destinationsStdout -PathType Leaf) {
    Get-Content -LiteralPath $destinationsStdout -Raw
  } else {
    ""
  }
  if (Test-Path -LiteralPath $destinationsStderr -PathType Leaf) {
    $destinationsText += Get-Content -LiteralPath $destinationsStderr -Raw
  }
  $state = Get-SimulatorState
  $probe = [ordered]@{
    stage = $Stage
    attempt = $Attempt
    checkedAt = [DateTimeOffset]::UtcNow.ToString("O")
    deviceId = $Device
    simctlState = $state
    xcdeviceExitCode = $xcdeviceExitCode
    xcdeviceVisible = Test-TextContainsDeviceId -Text $xcdeviceText
    showDestinationsExitCode = $destinationsExitCode
    showDestinationsVisible = Test-TextContainsDeviceId -Text $destinationsText
  }
  $probe["ready"] = $probe.simctlState -eq "Booted" `
    -and $probe.xcdeviceExitCode -eq 0 `
    -and $probe.xcdeviceVisible `
    -and $probe.showDestinationsExitCode -eq 0 `
    -and $probe.showDestinationsVisible
  [IO.File]::WriteAllText(
    $probePath,
    ($probe | ConvertTo-Json -Depth 10),
    [Text.UTF8Encoding]::new($false)
  )
  return $probe
}

function Wait-XcodeDestinationReady {
  param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [ValidateRange(1, 12)][int]$MaxAttempts = 6,
    [ValidateRange(1, 10)][int]$DelaySeconds = 2
  )

  $lastProbe = $null
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt += 1) {
    $lastProbe = Invoke-XcodeDestinationProbe -Stage $Stage -Attempt $attempt
    if ($lastProbe.ready) {
      return $lastProbe
    }
    if ($attempt -lt $MaxAttempts) {
      Start-Sleep -Seconds $DelaySeconds
    }
  }
  return $lastProbe
}

function Set-DestinationProbeMetadata {
  param($Probe)

  if ($null -eq $Probe) {
    return
  }
  $simulatorMetadata["destinationDiscovery"] = [ordered]@{
    ready = [bool]$Probe.ready
    stage = [string]$Probe.stage
    attempt = [int]$Probe.attempt
    xcdeviceVisible = [bool]$Probe.xcdeviceVisible
    showDestinationsVisible = [bool]$Probe.showDestinationsVisible
  }
}

function Restart-SimulatorForDestinationRegistration {
  param([Parameter(Mandatory = $true)][string]$Stage)

  # 只重启调用方明确传入并负责清理的同一个设备。禁止在 runner 内新建第二个
  # UDID，否则 workflow 仍会清理旧设备并泄漏新设备。该恢复只发生在任何
  # XCTest 尚未开始之前，且全程只允许一次。
  $state = Get-SimulatorState
  if ($state -in @("Booted", "Booting")) {
    Invoke-RequiredSimctl -Stage "$Stage/shutdown" -CommandArguments @("shutdown", $Device) | Out-Null
  } elseif ($state -ne "Shutdown") {
    throw "iOS Simulator 在 destination 恢复前处于不可恢复状态: $state"
  }
  Invoke-RequiredSimctl -Stage "$Stage/boot" -CommandArguments @("boot", $Device) | Out-Null
  Invoke-RequiredSimctl -Stage "$Stage/bootstatus" -CommandArguments @("bootstatus", $Device, "-b") | Out-Null
  if ((Get-SimulatorState) -ne "Booted") {
    throw "iOS Simulator destination 恢复后仍未完成启动"
  }
}

function Get-XcresultStartedTestCount {
  param(
    [Parameter(Mandatory = $true)][string]$ResultBundle,
    [Parameter(Mandatory = $true)][string]$Scenario
  )

  if (-not (Test-Path -LiteralPath $ResultBundle)) {
    return $null
  }
  $summaryPath = Join-Path $rawDir "$Scenario.retry-check.summary.json"
  $stderrPath = Join-Path $rawDir "$Scenario.retry-check.stderr.log"
  $exitCode = Invoke-BoundedNativeCommand `
    -Phase "ios-xcresult-retry-check-$Scenario" `
    -FilePath "xcrun" `
    -Arguments @(
      "xcresulttool", "get", "test-results", "summary",
      "--path", $ResultBundle, "--format", "json"
    ) `
    -TimeoutSeconds 120 `
    -StdoutPath $summaryPath `
    -StderrPath $stderrPath
  if ($exitCode -ne 0 `
      -or -not (Test-Path -LiteralPath $summaryPath -PathType Leaf) `
      -or (Get-Item -LiteralPath $summaryPath).Length -eq 0) {
    return $null
  }
  try {
    $payload = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    return [int]$payload.totalTestCount
  } catch {
    return $null
  }
}

function Add-EvidenceFailure {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EvidencePath,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $payload = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json
  if ($null -eq $payload.steps -or $payload.steps.Count -eq 0) {
    throw "iOS evidence 缺少可写入失败状态的步骤"
  }
  $existing = [string]$payload.steps[0].error
  $payload.steps[0].success = $false
  $payload.steps[0].error = if ([string]::IsNullOrWhiteSpace($existing)) {
    $Message
  } else {
    "$existing; $Message"
  }
  [IO.File]::WriteAllText(
    $EvidencePath,
    ($payload | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
  )
}

function Add-SummaryFailure {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  $payload = Get-Content -LiteralPath $SummaryPath -Raw | ConvertFrom-Json
  $existing = if ($payload.PSObject.Properties.Name -contains "error") {
    [string]$payload.error
  } else {
    ""
  }
  $payload.totalTestCount = [Math]::Max(1, [int]$payload.totalTestCount)
  $payload.passedTests = 0
  $payload.failedTests = [Math]::Max(1, [int]$payload.failedTests)
  $errorMessage = if ([string]::IsNullOrWhiteSpace($existing)) {
    $Message
  } else {
    "$existing; $Message"
  }
  if ($payload.PSObject.Properties.Name -contains "error") {
    $payload.error = $errorMessage
  } else {
    $payload | Add-Member -NotePropertyName error -NotePropertyValue $errorMessage
  }
  [IO.File]::WriteAllText(
    $SummaryPath,
    ($payload | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
  )
}

function Add-PostconditionFailure {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EvidencePath,
    [Parameter(Mandatory = $true)]
    [string]$SummaryPath,
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  # 文件正文、hash 和临时资源属于 XCTest 之外的宿主后验条件。它们失败时必须
  # 同时更新 evidence 与 summary，使统一报告、JUnit 和退出码保持一致。
  Add-EvidenceFailure -EvidencePath $EvidencePath -Message $Message
  Add-SummaryFailure -SummaryPath $SummaryPath -Message $Message
}

function Add-SimulatorEvidence {
  param([Parameter(Mandatory = $true)][string]$EvidencePath)

  $payload = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json -AsHashtable
  if (-not $payload.ContainsKey("extra") -or $null -eq $payload.extra) {
    $payload["extra"] = @{}
  }
  $payload.extra["simulator"] = $simulatorMetadata
  [IO.File]::WriteAllText(
    $EvidencePath,
    ($payload | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
  )
}

function Add-RunnerEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][DateTimeOffset]$StartedAt,
    [Parameter(Mandatory = $true)][DateTimeOffset]$EndedAt,
    [Parameter(Mandatory = $true)][int]$XcTestExitCode,
    [Parameter(Mandatory = $true)][int]$EffectiveExitCode,
    [Parameter(Mandatory = $true)][bool]$TestStarted,
    [Parameter(Mandatory = $true)][string]$PostconditionStatus
  )

  $payload = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json -AsHashtable
  if (-not $payload.ContainsKey("extra") -or $null -eq $payload.extra) {
    $payload["extra"] = @{}
  }
  $payload.extra["runner"] = [ordered]@{
    startedAt = $StartedAt.ToString("O")
    endedAt = $EndedAt.ToString("O")
    durationMilliseconds = [Math]::Max(
      0,
      [int64]($EndedAt - $StartedAt).TotalMilliseconds
    )
    testStarted = $TestStarted
    xctestExitCode = $XcTestExitCode
    effectiveExitCode = $EffectiveExitCode
    postconditionStatus = $PostconditionStatus
  }
  [IO.File]::WriteAllText(
    $EvidencePath,
    ($payload | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
  )
}

function Add-ExperimentalObservationEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][string]$Reason
  )

  $payload = Get-Content -LiteralPath $EvidencePath -Raw | ConvertFrom-Json -AsHashtable
  if (-not $payload.ContainsKey("extra") -or $null -eq $payload.extra) {
    $payload["extra"] = [ordered]@{}
  }
  $payload.extra["experimentalObservation"] = $true
  $payload.extra["experimentalReason"] = $Reason
  [IO.File]::WriteAllText(
    $EvidencePath,
    ($payload | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
  )
}

function Write-FallbackSummary {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Message
  )
  $payload = [ordered]@{
    totalTestCount = 0
    passedTests = 0
    failedTests = 1
    skippedTests = 0
    error = $Message
  }
  [IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
}

function Write-FallbackEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Scenario,
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$FailureClass = "infrastructure_failure"
  )
  $payload = [ordered]@{
    runId = $runId
    scenario = $Scenario
    profile = "platform"
    platform = "ios"
    framework = "xcuitest"
    steps = @([ordered]@{ step = $Scenario; success = $false; error = $Message })
    capabilityEvidence = @{}
    resources = [ordered]@{
      baseline = @{}
      final = @{}
      thresholds = @{}
    }
    artifacts = @()
    extra = [ordered]@{
      simulator = $simulatorMetadata
      failureClass = $FailureClass
      resourceMeasurementStatus = "not_exercised_before_test_start"
    }
  }
  [IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

function Write-InfrastructureFailureReports {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$FailureClass = "infrastructure_failure"
  )

  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    $junitPath = Join-Path $junitDir "$scenario.xml"
    if ((Test-Path -LiteralPath $scenarioPath) -and (Test-Path -LiteralPath $junitPath)) {
      continue
    }
    $summaryPath = Join-Path $rawDir "$scenario.summary.json"
    $fallbackEvidence = Join-Path $attachmentsDir "lddc-evidence-$scenario.json"
    Write-FallbackSummary -Path $summaryPath -Message $Message
    Write-FallbackEvidence `
      -Path $fallbackEvidence `
      -Scenario $scenario `
      -Message $Message `
      -FailureClass $FailureClass
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $summaryPath `
      --raw-report-type xcresult-summary `
      --framework xcuitest `
      --exit-code 1 `
      --evidence $fallbackEvidence `
      --matrix $matrix
    & python $junitConverter --input $summaryPath --output $junitPath --scenario $scenario
  }
}

$scenarios = @(
  @{
    Name = "ios_document_picker_select"
    Method = "testDocumentPickerSelectsSeededAudio"
  },
  @{
    Name = "ios_document_picker_cancel"
    Method = "testDocumentPickerCancellationReturnsToFlutter"
  },
  @{
    Name = "ios_document_picker_export"
    Method = "testDocumentPickerExportsLyricsFile"
  },
  @{
    Name = "ios_document_picker_export_cancel"
    Method = "testDocumentPickerExportCancellationCleansTemporaryFile"
  },
  @{
    Name = "ios_document_picker_export_termination"
    Method = "testTerminatedExportIsCleanedOnNextLaunch"
  }
)
$overallExitCode = 0
$experimentalScenarioAllowlist = [Collections.Generic.HashSet[string]]::new(
  [StringComparer]::Ordinal
)
foreach ($scenario in $ExperimentalScenarios) {
  $experimentalScenarioAllowlist.Add($scenario) | Out-Null
}
$observedExperimentalScenarios = [Collections.Generic.HashSet[string]]::new(
  [StringComparer]::Ordinal
)
$infrastructureFailureMessage = $null
$infrastructureFailureClass = "infrastructure_failure"
$activeInfrastructureFailureClass = "infrastructure_failure"

Push-Location $appRoot
try {
  foreach ($entry in $testRunnerEnvironment.GetEnumerator()) {
    $environmentName = [string]$entry.Key
    $previousTestRunnerEnvironment[$environmentName] =
      [Environment]::GetEnvironmentVariable($environmentName, "Process")
    # test-without-building 使用 Apple 约定的 TEST_RUNNER_ 前缀向 XCTest
    # 进程传值，避免依赖 scheme 中不会在 hosted runner 展开的 $(...) 宏。
    [Environment]::SetEnvironmentVariable(
      $environmentName,
      [string]$entry.Value,
      "Process"
    )
  }
  # 编译测试产物只依赖固定的 iOS Simulator SDK，不绑定刚创建的临时
  # UDID。这样 CoreSimulator 已 Booted、但 Xcode destination discovery
  # 尚未注册设备时，不会在 build-for-testing 阶段产生误导性的 exit 70。
  $simulatorMetadata = Get-SimulatorMetadata
  $expectedRuntimeVersion = [string]$env:LDDC_IOS_RUNTIME_VERSION
  if (-not [string]::IsNullOrWhiteSpace($expectedRuntimeVersion) `
      -and $simulatorMetadata.runtimeVersion -ne $expectedRuntimeVersion) {
    throw "iOS Simulator runtime 漂移：actual=$($simulatorMetadata.runtimeVersion) expected=$expectedRuntimeVersion"
  }
  $activeInfrastructureFailureClass = "build_failure"
  # Document Picker 已被前移到其它完整 Flutter 构建之前。首次 checkout 中
  # 只有 pub 依赖，尚无 Generated.xcconfig 与 Pods；先执行 config-only 和
  # 有界 pod install，避免依赖后续 release/debug 阶段隐式准备工作区。
  $flutterConfigExitCode = Invoke-BoundedNativeCommand `
    -Phase "ios-flutter-config" `
    -FilePath "flutter" `
    -Arguments @("build", "ios", "--debug", "--simulator", "--config-only") `
    -TimeoutSeconds 300 `
    -StdoutPath (Join-Path $rawDir "flutter-config.stdout.log") `
    -StderrPath (Join-Path $rawDir "flutter-config.stderr.log")
  if ($flutterConfigExitCode -ne 0) {
    throw "iOS Flutter Xcode 配置生成失败，exit=$flutterConfigExitCode"
  }
  $podInstallExitCode = Invoke-BoundedNativeCommand `
    -Phase "ios-pod-install" `
    -FilePath "pod" `
    -Arguments @("install", "--project-directory=ios") `
    -TimeoutSeconds 300 `
    -StdoutPath (Join-Path $rawDir "pod-install.stdout.log") `
    -StderrPath (Join-Path $rawDir "pod-install.stderr.log")
  if ($podInstallExitCode -ne 0) {
    throw (Format-BoundedCommandFailure -Phase "iOS CocoaPods" -ExitCode $podInstallExitCode)
  }
  $buildExitCode = Invoke-BoundedNativeCommand `
    -Phase "ios-xcuitest-build-for-testing" `
    -FilePath "xcodebuild" `
    -Arguments @(
      "build-for-testing",
      "-workspace", "ios/Runner.xcworkspace",
      "-scheme", "RunnerPlatformTests",
      "-configuration", "PlatformTest",
      "-destination", "generic/platform=iOS Simulator",
      "-parallel-testing-enabled", "NO",
      "-derivedDataPath", $derivedData,
      "CODE_SIGNING_ALLOWED=NO"
    ) `
    -TimeoutSeconds 900 `
    -StdoutPath (Join-Path $rawDir "build-for-testing.stdout.log") `
    -StderrPath (Join-Path $rawDir "build-for-testing.stderr.log")
  if ($buildExitCode -ne 0) {
    throw "iOS build-for-testing 失败，exit=$buildExitCode"
  }
  $activeInfrastructureFailureClass = "destination_registration_failure"

  Ensure-SimulatorBooted -Stage "before-destination-discovery"
  $simulatorMetadata.state = Get-SimulatorState
  Invoke-RequiredSimctl `
    -Stage "locale/languages" `
    -CommandArguments @("spawn", $Device, "defaults", "write", "NSGlobalDomain", "AppleLanguages", "-array", "en") | Out-Null
  Invoke-RequiredSimctl `
    -Stage "locale/region" `
    -CommandArguments @("spawn", $Device, "defaults", "write", "NSGlobalDomain", "AppleLocale", "en_US") | Out-Null
  $simulatorMetadata.configuredLanguage = "en"
  $simulatorMetadata.configuredLocale = "en_US"
  $destinationProbe = Wait-XcodeDestinationReady -Stage "initial"
  Set-DestinationProbeMetadata -Probe $destinationProbe
  if ($null -eq $destinationProbe -or -not $destinationProbe.ready) {
    Restart-SimulatorForDestinationRegistration -Stage "destination-registration-recovery"
    $simulatorMetadata.state = Get-SimulatorState
    $destinationProbe = Wait-XcodeDestinationReady -Stage "recovery"
    Set-DestinationProbeMetadata -Probe $destinationProbe
  }
  if ($null -eq $destinationProbe -or -not $destinationProbe.ready) {
    throw (
      "iOS Simulator 已由 simctl 启动，但 xcdevice 或 RunnerPlatformTests " +
      "showdestinations 在一次有界重启后仍未发现设备 $Device"
    )
  }
  $activeInfrastructureFailureClass = "test_infrastructure_failure"

  $buildProducts = Join-Path $derivedData "Build/Products"
  $appBundle = Resolve-UniqueBuildArtifact `
    -Root $buildProducts `
    -Filter "LDDC.app" `
    -Description "iOS PlatformTest app" `
    -Directory
  $xctestrun = Resolve-UniqueBuildArtifact `
    -Root $buildProducts `
    -Filter "*.xctestrun" `
    -Description "iOS RunnerPlatformTests xctestrun"
  Ensure-SimulatorBooted -Stage "before-install"
  Invoke-RequiredSimctl `
    -Stage "install-platform-test-app" `
    -CommandArguments @("install", $Device, $appBundle.FullName) | Out-Null
  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $method = $entry.Method
    $scenarioStartedAt = [DateTimeOffset]::UtcNow
    $resultBundle = Join-Path $rawDir "$scenario.xcresult"
    $retryCheckSummaryPath = Join-Path $rawDir "$scenario.retry-check.summary.json"
    $retryPerformed = $false
    Ensure-SimulatorBooted -Stage "before-$scenario"
    # 每个场景启动前删除旧 witness，避免上一轮异常中断留下的成功摘要被当前
    # 场景误用。测试 app 启动时仍会再次重置容器，两层清理共同覆盖 Xcode
    # 复用既有容器和重新安装应用这两种行为。
    $preScenarioContainer = Get-PlatformTestContainer
    $preScenarioWitness = Join-Path `
      (Join-Path $preScenarioContainer "Documents") `
      $exportWitnessFileName
    Remove-Item -LiteralPath $preScenarioWitness -Force -ErrorAction SilentlyContinue
    $testExitCode = Invoke-BoundedXcodeTest `
      -XcTestRun $xctestrun.FullName `
      -Method $method `
      -ResultBundle $resultBundle
    if ($testExitCode -ne 0) {
      $startedTestCount = Get-XcresultStartedTestCount `
        -ResultBundle $resultBundle `
        -Scenario $scenario
      $simulatorState = Get-SimulatorState
      if ($startedTestCount -eq 0 -and $simulatorState -eq "Shutdown") {
        # 只允许在 XCTest 尚未开始且设备意外关机时恢复一次。真实用例失败、
        # assertion 失败和已经启动的测试绝不能通过自动重试被掩盖。
        $firstAttemptBundle = Join-Path $rawDir "$scenario.attempt1.xcresult"
        Move-Item -LiteralPath $resultBundle -Destination $firstAttemptBundle
        Ensure-SimulatorBooted -Stage "retry-$scenario"
        $testExitCode = Invoke-BoundedXcodeTest `
          -XcTestRun $xctestrun.FullName `
          -Method $method `
          -ResultBundle $resultBundle `
          -Attempt "attempt2"
        $retryPerformed = $true
      }
    }

    $summaryPath = Join-Path $rawDir "$scenario.summary.json"
    $summaryReady = $false
    $reportingErrors = @()
    $summaryRecordedErrorCount = 0
    if (-not $retryPerformed `
        -and $testExitCode -ne 0 `
        -and (Test-Path -LiteralPath $retryCheckSummaryPath -PathType Leaf)) {
      try {
        $retrySummary = Get-Content -LiteralPath $retryCheckSummaryPath -Raw `
          | ConvertFrom-Json
        if ($null -ne $retrySummary.totalTestCount) {
          Copy-Item -LiteralPath $retryCheckSummaryPath -Destination $summaryPath -Force
          $summaryReady = $true
        }
      } catch {
        $summaryReady = $false
      }
    }
    if (-not $summaryReady -and (Test-Path -LiteralPath $resultBundle)) {
      $summaryStderr = Join-Path $rawDir "$scenario.summary.stderr.log"
      $summaryExitCode = Invoke-BoundedNativeCommand `
        -Phase "ios-xcresult-summary-$scenario" `
        -FilePath "xcrun" `
        -Arguments @(
          "xcresulttool", "get", "test-results", "summary",
          "--path", $resultBundle, "--format", "json"
        ) `
        -TimeoutSeconds 120 `
        -StdoutPath $summaryPath `
        -StderrPath $summaryStderr
      if ($summaryExitCode -eq 0 `
          -and (Test-Path -LiteralPath $summaryPath -PathType Leaf) `
          -and (Get-Item -LiteralPath $summaryPath).Length -gt 0) {
        try {
          $summaryPayload = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
          $summaryReady = $null -ne $summaryPayload.totalTestCount
        } catch {
          $summaryReady = $false
        }
      }
      if (-not $summaryReady) {
        $reportingErrors += "xcresult summary 无法读取，exit=$summaryExitCode，诊断=$([IO.Path]::GetFileName($summaryStderr))"
      }
    } elseif (-not $summaryReady) {
      $reportingErrors += "XCUITest 未生成 xcresult bundle"
    }
    if (-not $summaryReady) {
      $summaryMessage = if ($reportingErrors.Count -gt 0) {
        $reportingErrors -join "; "
      } else {
        "XCUITest 未生成可读取的 xcresult summary"
      }
      Write-FallbackSummary -Path $summaryPath -Message $summaryMessage
      $summaryRecordedErrorCount = $reportingErrors.Count
    }
    $testActuallyStarted = $false
    try {
      $startedSummary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
      $testActuallyStarted = [int]$startedSummary.totalTestCount -gt 0
    } catch {
      $testActuallyStarted = $false
    }
    $scenarioAttachments = Join-Path $attachmentsDir $scenario
    Remove-Item -LiteralPath $scenarioAttachments -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $scenarioAttachments | Out-Null
    if (Test-Path -LiteralPath $resultBundle) {
      $attachmentStdout = Join-Path $rawDir "$scenario.attachments.stdout.log"
      $attachmentStderr = Join-Path $rawDir "$scenario.attachments.stderr.log"
      $attachmentExitCode = Invoke-BoundedNativeCommand `
        -Phase "ios-xcresult-attachments-$scenario" `
        -FilePath "xcrun" `
        -Arguments @(
          "xcresulttool", "export", "attachments",
          "--path", $resultBundle,
          "--output-path", $scenarioAttachments
        ) `
        -TimeoutSeconds 120 `
        -StdoutPath $attachmentStdout `
        -StderrPath $attachmentStderr
      if ($attachmentExitCode -ne 0) {
        $reportingErrors += "xcresult attachment 导出失败，exit=$attachmentExitCode，诊断=$([IO.Path]::GetFileName($attachmentStderr))"
      }
    }
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
      $reportingErrors += "XCUITest evidence attachment 必须且只能有一个，实际为 $($evidenceCandidates.Count)"
      $fallbackEvidence = Join-Path $scenarioAttachments "lddc-evidence-$scenario.json"
      Write-FallbackEvidence `
        -Path $fallbackEvidence `
        -Scenario $scenario `
        -Message ($reportingErrors -join "; ")
      $evidencePath = Get-Item -LiteralPath $fallbackEvidence
    } elseif ($reportingErrors.Count -gt 0) {
      Add-EvidenceFailure `
        -EvidencePath $evidencePath.FullName `
        -Message ($reportingErrors -join "; ")
    }
    try {
      Add-SimulatorEvidence -EvidencePath $evidencePath.FullName
    } catch {
      # 单个场景的 attachment 损坏不能阻断后续四个独立场景。改用受控失败
      # evidence，并保留原始 XCTest summary 作为该场景的第一手错误证据。
      $message = "iOS 场景 $scenario 无法增补 Simulator evidence: $($_.Exception.Message)"
      $reportingErrors += $message
      $fallbackEvidence = Join-Path $scenarioAttachments "lddc-evidence-$scenario.runner-fallback.json"
      Write-FallbackEvidence -Path $fallbackEvidence -Scenario $scenario -Message $message
      $evidencePath = Get-Item -LiteralPath $fallbackEvidence
    }
    if ($reportingErrors.Count -gt $summaryRecordedErrorCount) {
      $newSummaryErrors = $reportingErrors[
        $summaryRecordedErrorCount..($reportingErrors.Count - 1)
      ] -join "; "
      Add-SummaryFailure `
        -SummaryPath $summaryPath `
        -Message $newSummaryErrors
    }
    $effectiveExitCode = $testExitCode
    $postconditionStatus = if ($testExitCode -eq 0) { "passed" } else { "not_run" }
    if ($reportingErrors.Count -gt 0) {
      $effectiveExitCode = 1
    }
    if ($testExitCode -eq 0) {
      try {
        # Xcode 可能在 UI 测试安装阶段更换 Simulator data container。后验检查必须
        # 重新解析当前容器，不能继续使用测试前缓存的绝对路径。
        $postTestContainer = Get-PlatformTestContainer
        $postTestDocuments = Join-Path $postTestContainer "Documents"
        if ($scenario -eq "ios_document_picker_select") {
          # XCUITest 写入的是测试 app Documents 中的真实文件。测试返回后由宿主计算
          # 最终摘要并写入结构化 evidence，避免把 Simulator 绝对路径带入报告。
          $selectedFixture = Join-Path $postTestDocuments "audio_sample.mp3"
          if (-not (Test-Path -LiteralPath $selectedFixture -PathType Leaf)) {
            $message = "iOS 写入后 fixture 不存在"
            Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
            $effectiveExitCode = 1
            $postconditionStatus = "failed"
          } else {
            $evidencePayload = Get-Content -LiteralPath $evidencePath.FullName -Raw | ConvertFrom-Json
            $evidencePayload.artifacts = @(
              [ordered]@{
                name = "audio_sample.mp3"
                size = (Get-Item -LiteralPath $selectedFixture).Length
                sha256 = (Get-FileHash -LiteralPath $selectedFixture -Algorithm SHA256).Hash.ToLowerInvariant()
              }
            )
            [IO.File]::WriteAllText(
              $evidencePath.FullName,
              ($evidencePayload | ConvertTo-Json -Depth 20),
              [Text.UTF8Encoding]::new($false)
            )
          }
        } elseif ($scenario -eq "ios_document_picker_export") {
          $exportWitness = Join-Path $postTestDocuments $exportWitnessFileName
          try {
            if (-not (Test-Path -LiteralPath $exportWitness -PathType Leaf)) {
              throw "iOS 导出成功后没有生成 PlatformTest witness"
            }
            $witness = Get-Content -LiteralPath $exportWitness -Raw | ConvertFrom-Json
            foreach ($forbiddenWitnessField in @("path", "url", "identifier")) {
              if ($null -ne $witness.PSObject.Properties[$forbiddenWitnessField]) {
                throw "iOS 导出 witness 含有禁止字段: $forbiddenWitnessField"
              }
            }
            if ([int]$witness.schemaVersion -ne 1) {
              throw "iOS 导出 witness schemaVersion 无效"
            }
            if ($witness.success -ne $true) {
              throw "iOS 导出 witness 未能读取最终用户文件，errorClass=$($witness.errorClass)"
            }
            if ($witness.cleanupSucceeded -ne $true) {
              throw "iOS 导出 witness 未能清理匿名测试输出，errorClass=$($witness.cleanupErrorClass)"
            }
            if ([string]$witness.fileName -cne "lddc_export.lrc") {
              throw "iOS 导出最终文件名错误: $($witness.fileName)"
            }
            $exportedBytes = [Convert]::FromBase64String([string]$witness.utf8Base64)
            if ([int64]$witness.size -ne $exportedBytes.LongLength) {
              throw "iOS 导出 witness 大小与实际字节不一致"
            }
            $computedSha256 = [Convert]::ToHexString(
              [Security.Cryptography.SHA256]::HashData($exportedBytes)
            ).ToLowerInvariant()
            if ([string]$witness.sha256 -cne $computedSha256) {
              throw "iOS 导出 witness SHA-256 与实际字节不一致"
            }
            $exportedText = [Text.Encoding]::UTF8.GetString($exportedBytes)
            if (-not [regex]::IsMatch(
                $exportedText,
                '^\[00:00\.\d{2,3}\]Hello LDDC(?:\r?\n)?$',
                [Text.RegularExpressions.RegexOptions]::CultureInvariant
              )) {
              throw "iOS 导出文件正文不符合匿名单行 LRC 契约"
            }
            $evidencePayload = Get-Content -LiteralPath $evidencePath.FullName -Raw | ConvertFrom-Json
            $evidencePayload.artifacts = @(
              [ordered]@{
                name = [string]$witness.fileName
                size = [int64]$witness.size
                sha256 = $computedSha256
              }
            )
            [IO.File]::WriteAllText(
              $evidencePath.FullName,
              ($evidencePayload | ConvertTo-Json -Depth 20),
              [Text.UTF8Encoding]::new($false)
            )
          } catch {
            # witness 属于导出业务后验。解析、摘要或正文不一致必须保留为当前
            # 场景失败，不能落入外层 runner-metadata catch 后伪装成报告设施错误。
            $message = $_.Exception.Message
            Add-PostconditionFailure `
              -EvidencePath $evidencePath.FullName `
              -SummaryPath $summaryPath `
              -Message $message
            $effectiveExitCode = 1
            $postconditionStatus = "failed"
          } finally {
            Remove-Item -LiteralPath $exportWitness -Force -ErrorAction SilentlyContinue
          }
        } elseif ($scenario -in @("ios_document_picker_export_cancel", "ios_document_picker_export_termination")) {
          $unexpectedWitness = Join-Path $postTestDocuments $exportWitnessFileName
          if (Test-Path -LiteralPath $unexpectedWitness -PathType Leaf) {
            $message = "iOS 取消或终止导出后残留了成功导出 witness"
            Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
            $effectiveExitCode = 1
            $postconditionStatus = "failed"
            Remove-Item -LiteralPath $unexpectedWitness -Force -ErrorAction SilentlyContinue
          }
          $unexpectedExports = @(
            Get-ChildItem -LiteralPath $postTestDocuments -File `
              | Where-Object { $_.Extension.Equals(".lrc", [StringComparison]::OrdinalIgnoreCase) }
          )
          if ($unexpectedExports.Count -ne 0) {
            $message = "iOS 取消或终止导出后残留了用户输出文件"
            Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
            $effectiveExitCode = 1
            $postconditionStatus = "failed"
          }
        }
        $temporaryExportRoot = Join-Path $postTestContainer "tmp/lddc_search_exports"
        if (Test-Path -LiteralPath $temporaryExportRoot) {
          $temporaryExportEntries = @(Get-ChildItem -LiteralPath $temporaryExportRoot -Force)
          if ($temporaryExportEntries.Count -ne 0) {
            $message = "iOS 场景 $scenario 结束后仍残留临时导出资源"
            Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
            $effectiveExitCode = 1
            $postconditionStatus = "failed"
          }
        }
      } catch {
        # 宿主后验检查失败不能覆盖已完成的 XCTest 结果，也不能中断后续独立场景。
        $message = "iOS 场景 $scenario 后验检查失败: $($_.Exception.Message)"
        Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
        $effectiveExitCode = 1
        $postconditionStatus = "failed"
      }
    }
    try {
      Add-RunnerEvidence `
        -EvidencePath $evidencePath.FullName `
        -StartedAt $scenarioStartedAt `
        -EndedAt ([DateTimeOffset]::UtcNow) `
        -XcTestExitCode $testExitCode `
        -EffectiveExitCode $effectiveExitCode `
        -TestStarted $testActuallyStarted `
        -PostconditionStatus $postconditionStatus
    } catch {
      # runner 元数据失败属于当前场景的报告失败，不能覆盖 XCTest 结论，
      # 更不能跳出 foreach 让后续系统 Picker 场景失去诊断。
      $message = "iOS 场景 $scenario 无法写入 runner evidence: $($_.Exception.Message)"
      Add-SummaryFailure -SummaryPath $summaryPath -Message $message
      $effectiveExitCode = 1
      $fallbackEvidence = Join-Path $scenarioAttachments "lddc-evidence-$scenario.runner-fallback.json"
      Write-FallbackEvidence -Path $fallbackEvidence -Scenario $scenario -Message $message
      Add-RunnerEvidence `
        -EvidencePath $fallbackEvidence `
        -StartedAt $scenarioStartedAt `
        -EndedAt ([DateTimeOffset]::UtcNow) `
        -XcTestExitCode $testExitCode `
        -EffectiveExitCode $effectiveExitCode `
        -TestStarted $testActuallyStarted `
        -PostconditionStatus $postconditionStatus
      $evidencePath = Get-Item -LiteralPath $fallbackEvidence
    }
    $experimentalObservation = $false
    if ($experimentalScenarioAllowlist.Contains($scenario) `
        -and $scenario -eq "ios_document_picker_export_cancel" `
        -and $testExitCode -ne 0 `
        -and $reportingErrors.Count -eq 0) {
      $summaryText = Get-Content -LiteralPath $summaryPath -Raw
      if ($summaryText.Contains(
          "experimental_ax_cancel_unavailable",
          [StringComparison]::Ordinal
        )) {
        $experimentalObservation = $true
        Add-ExperimentalObservationEvidence `
          -EvidencePath $evidencePath.FullName `
          -Reason "iOS 26.5 保存型 Picker 返回根层后未暴露可命中的 typed Cancel Button"
      }
    }
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $summaryPath `
      --raw-report-type xcresult-summary `
      --framework xcuitest `
      --exit-code $effectiveExitCode `
      --evidence $evidencePath.FullName `
      --matrix $matrix
    $normalizeExitCode = $LASTEXITCODE
    $junitPath = Join-Path $junitDir "$scenario.xml"
    & python $junitConverter --input $summaryPath --output $junitPath --scenario $scenario
    $junitExitCode = $LASTEXITCODE
    if ($effectiveExitCode -ne 0 -or $normalizeExitCode -ne 0 -or $junitExitCode -ne 0) {
      # Document Picker 的选择、取消、导出和生命周期场景彼此独立。单个失败
      # 不能阻断后续证据收集。只有保存型 Picker 明确返回专用 AX 限制标记、
      # 且统一报告均完整时，实验 workflow 才将该场景排除于 required outcome；
      # 编译、runner、报告或其他断言失败仍然必须使 job 失败。
      if ($experimentalObservation `
          -and $normalizeExitCode -eq 0 `
          -and $junitExitCode -eq 0) {
        $observedExperimentalScenarios.Add($scenario) | Out-Null
        Write-Warning "iOS XCUITest 场景 $scenario 保留失败证据并标记为实验观察"
      } else {
        $overallExitCode = 1
        Write-Warning "iOS XCUITest 场景 $scenario 失败，继续收集其余独立场景"
      }
    }
  }
} catch {
  $overallExitCode = 1
  $infrastructureFailureMessage = "iOS platform infrastructure failure: $($_.Exception.Message)"
  $infrastructureFailureClass = $activeInfrastructureFailureClass
  Write-Error $infrastructureFailureMessage -ErrorAction Continue
} finally {
  & xcrun simctl terminate $Device com.cmzj.lddc.platformtests 2>$null
  & xcrun simctl terminate $Device com.apple.DocumentsApp 2>$null
  & xcrun simctl uninstall $Device com.cmzj.lddc.platformtests 2>$null
  try {
    if (Test-Path -LiteralPath $derivedData -PathType Container) {
      Remove-Item -LiteralPath $derivedData -Recurse -Force
    }
  } catch {
    $overallExitCode = 1
    Write-Error "iOS Xcode DerivedData 清理失败: $($_.Exception.Message)" -ErrorAction Continue
  }
  foreach ($environmentName in $previousTestRunnerEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable(
      $environmentName,
      $previousTestRunnerEnvironment[$environmentName],
      "Process"
    )
  }
  Pop-Location
}

if (-not [string]::IsNullOrWhiteSpace($infrastructureFailureMessage)) {
  # 基础设施失败报告必须在应用、系统 Picker 和 DerivedData 清理完成后生成。
  # 这样 testStarted=false 的报告只表达“未执行”，不会把清理前的临时状态
  # 误写成资源泄漏或伪造 resourceCleanup 成功证据。
  Write-InfrastructureFailureReports `
    -Message $infrastructureFailureMessage `
    -FailureClass $infrastructureFailureClass
}

foreach ($entry in $scenarios) {
  $scenario = $entry.Name
  if ($observedExperimentalScenarios.Contains($scenario)) {
    continue
  }
  $scenarioPath = Join-Path $scenarioDir "$scenario.json"
  $junitPath = Join-Path $junitDir "$scenario.xml"
  if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf) `
      -or -not (Test-Path -LiteralPath $junitPath -PathType Leaf)) {
    $overallExitCode = 1
    Write-Error "iOS required 场景 $scenario 缺少 scenario JSON 或 JUnit" -ErrorAction Continue
    continue
  }
  Copy-Item -LiteralPath $scenarioPath -Destination $requiredScenarioDir -Force
  Copy-Item -LiteralPath $junitPath -Destination $requiredJunitDir -Force
}

& python $verifier `
  --directory $requiredScenarioDir `
  --junit-directory $requiredJunitDir `
  --profile platform `
  --platform ios `
  --run-id $runId `
  --matrix $matrix
if ($LASTEXITCODE -ne 0) {
  $overallExitCode = 1
}

Write-Host "iOS platform reports: $runRoot"
exit $overallExitCode
