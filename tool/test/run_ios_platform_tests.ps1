param(
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [string]$ReportDir = "build/integration_reports/ios-native",
  [ValidateRange(30, 600)]
  [int]$ScenarioTimeoutSeconds = 120
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
$derivedData = Join-Path $appRoot "build/native_test_derived_data/$runId"
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$attachmentsDir = Join-Path $runRoot "attachments"
foreach ($directory in @($scenarioDir, $rawDir, $junitDir, $attachmentsDir)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
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
    [Parameter(Mandatory = $true)][string]$Message
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
      baseline = @{ nativeWindowCount = 0 }
      final = @{ nativeWindowCount = 1 }
      thresholds = @{ nativeWindowCount = 0 }
    }
    artifacts = @()
    extra = @{ simulator = $simulatorMetadata }
  }
  [IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

function Write-InfrastructureFailureReports {
  param([Parameter(Mandatory = $true)][string]$Message)

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
    Write-FallbackEvidence -Path $fallbackEvidence -Scenario $scenario -Message $Message
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
  Ensure-SimulatorBooted -Stage "runner-entry"
  $simulatorMetadata = Get-SimulatorMetadata
  $expectedRuntimeVersion = [string]$env:LDDC_IOS_RUNTIME_VERSION
  if (-not [string]::IsNullOrWhiteSpace($expectedRuntimeVersion) `
      -and $simulatorMetadata.runtimeVersion -ne $expectedRuntimeVersion) {
    throw "iOS Simulator runtime 漂移：actual=$($simulatorMetadata.runtimeVersion) expected=$expectedRuntimeVersion"
  }
  Invoke-RequiredSimctl `
    -Stage "locale/languages" `
    -CommandArguments @("spawn", $Device, "defaults", "write", "NSGlobalDomain", "AppleLanguages", "-array", "en") | Out-Null
  Invoke-RequiredSimctl `
    -Stage "locale/region" `
    -CommandArguments @("spawn", $Device, "defaults", "write", "NSGlobalDomain", "AppleLocale", "en_US") | Out-Null
  $simulatorMetadata.configuredLanguage = "en"
  $simulatorMetadata.configuredLocale = "en_US"
  $buildExitCode = Invoke-BoundedNativeCommand `
    -Phase "ios-xcuitest-build-for-testing" `
    -FilePath "xcodebuild" `
    -Arguments @(
      "build-for-testing",
      "-workspace", "ios/Runner.xcworkspace",
      "-scheme", "RunnerPlatformTests",
      "-configuration", "PlatformTest",
      "-destination", "platform=iOS Simulator,id=$Device,arch=$hostArchitecture",
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

  $appBundle = Get-ChildItem -Path (Join-Path $derivedData "Build/Products") `
    -Recurse -Directory -Filter "LDDC.app" | Select-Object -First 1
  $xctestrun = Get-ChildItem -Path (Join-Path $derivedData "Build/Products") `
    -Recurse -File -Filter "*.xctestrun" | Select-Object -First 1
  if ($null -eq $appBundle -or $null -eq $xctestrun) {
    throw "iOS build-for-testing 没有生成 app 或 xctestrun"
  }
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
    $evidencePath = Get-ChildItem -Path $scenarioAttachments -Recurse -File `
      | Where-Object {
          try {
            $payload = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            $payload.scenario -eq $scenario
          } catch {
            $false
          }
        } `
      | Select-Object -First 1
    if ($null -eq $evidencePath) {
      $reportingErrors += "XCUITest 未导出 evidence attachment"
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
          $exportedFiles = @(
            Get-ChildItem -LiteralPath $postTestDocuments -File `
              | Where-Object { $_.Extension.Equals(".lrc", [StringComparison]::OrdinalIgnoreCase) }
          )
          if ($exportedFiles.Count -ne 1) {
            $message = "iOS 导出场景应生成且只生成一个 LRC，实际为 $($exportedFiles.Count)"
            Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
            $effectiveExitCode = 1
            $postconditionStatus = "failed"
          } else {
            $exportedFile = $exportedFiles[0]
            if ($exportedFile.Name -match '^[0-9a-fA-F-]{36}-') {
              $message = "iOS 导出文件名泄露了内部临时 UUID"
              Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
              $effectiveExitCode = 1
              $postconditionStatus = "failed"
            }
            $exportedText = Get-Content -LiteralPath $exportedFile.FullName -Raw
            if (-not $exportedText.Contains("Hello LDDC", [StringComparison]::Ordinal)) {
              $message = "iOS 导出文件缺少预期歌词正文"
              Add-PostconditionFailure -EvidencePath $evidencePath.FullName -SummaryPath $summaryPath -Message $message
              $effectiveExitCode = 1
              $postconditionStatus = "failed"
            }
            $evidencePayload = Get-Content -LiteralPath $evidencePath.FullName -Raw | ConvertFrom-Json
            $evidencePayload.artifacts = @(
              [ordered]@{
                name = $exportedFile.Name
                size = $exportedFile.Length
                sha256 = (Get-FileHash -LiteralPath $exportedFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
              }
            )
            [IO.File]::WriteAllText(
              $evidencePath.FullName,
              ($evidencePayload | ConvertTo-Json -Depth 20),
              [Text.UTF8Encoding]::new($false)
            )
            # 导出产物已完成正文与摘要验证，删除测试容器副本，防止影响后续取消场景。
            Remove-Item -LiteralPath $exportedFile.FullName -Force
          }
        } elseif ($scenario -in @("ios_document_picker_export_cancel", "ios_document_picker_export_termination")) {
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
      # 不能阻断后续证据收集，但最终退出码仍必须失败，避免 CI 假绿。
      $overallExitCode = 1
      Write-Warning "iOS XCUITest 场景 $scenario 失败，继续收集其余独立场景"
    }
  }
} catch {
  $overallExitCode = 1
  $message = "iOS platform infrastructure failure: $($_.Exception.Message)"
  Write-Error $message -ErrorAction Continue
  Write-InfrastructureFailureReports -Message $message
} finally {
  & xcrun simctl terminate $Device com.cmzj.lddc.platformtests 2>$null
  & xcrun simctl terminate $Device com.apple.DocumentsApp 2>$null
  & xcrun simctl uninstall $Device com.cmzj.lddc.platformtests 2>$null
  foreach ($environmentName in $previousTestRunnerEnvironment.Keys) {
    [Environment]::SetEnvironmentVariable(
      $environmentName,
      $previousTestRunnerEnvironment[$environmentName],
      "Process"
    )
  }
  Pop-Location
}

& python $verifier `
  --directory $scenarioDir `
  --junit-directory $junitDir `
  --profile platform `
  --platform ios `
  --run-id $runId `
  --matrix $matrix
if ($LASTEXITCODE -ne 0) {
  $overallExitCode = 1
}

Write-Host "iOS platform reports: $runRoot"
exit $overallExitCode
