param(
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [string]$ReportDir = "build/integration_reports/ios-native",
  [ValidateRange(30, 600)]
  [int]$ScenarioTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$junitConverter = Join-Path $repoRoot "tool/test/xcresult_summary_to_junit.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
$fixture = Join-Path $appRoot "integration_test/fixtures/media/audio_sample.mp3"
$fixtureSize = (Get-Item -LiteralPath $fixture).Length
$fixtureSha256 = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
$simulatorMetadata = [ordered]@{
  udid = $Device
  runtime = "unknown"
  model = "unknown"
  deviceTypeIdentifier = "unknown"
  state = "unknown"
}
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

$runId = "platform-ios-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Join-Path $ReportDir $runId
$derivedData = Join-Path $appRoot "build/native_test_derived_data/$runId"
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$attachmentsDir = Join-Path $runRoot "attachments"
foreach ($directory in @($scenarioDir, $rawDir, $junitDir, $attachmentsDir)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

function Invoke-BoundedXcodeTest {
  param(
    [Parameter(Mandatory = $true)]
    [string]$XcTestRun,
    [Parameter(Mandatory = $true)]
    [string]$Method,
    [Parameter(Mandatory = $true)]
    [string]$ResultBundle
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = "xcodebuild"
  $startInfo.UseShellExecute = $false
  foreach ($argument in @(
      "test-without-building",
      "-xctestrun", $XcTestRun,
      "-destination", "platform=iOS Simulator,id=$Device",
      "-parallel-testing-enabled", "NO",
      "-only-testing:RunnerUITests/RunnerUITests/$Method",
      "-resultBundlePath", $ResultBundle
    )) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  try {
    if (-not $process.WaitForExit($ScenarioTimeoutSeconds * 1000)) {
      # XCUITest runner 无响应时终止其整个进程树，随后由外层 finally 清理 Simulator 应用。
      $process.Kill($true)
      $process.WaitForExit()
      return 124
    }
    return $process.ExitCode
  } finally {
    $process.Dispose()
  }
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
  foreach ($runtime in $payload.devices.PSObject.Properties) {
    foreach ($deviceInfo in @($runtime.Value)) {
      if ($deviceInfo.udid -eq $Device) {
        return [ordered]@{
          udid = [string]$deviceInfo.udid
          runtime = [string]$runtime.Name
          model = [string]$deviceInfo.name
          deviceTypeIdentifier = [string]$deviceInfo.deviceTypeIdentifier
          state = [string]$deviceInfo.state
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
  param([Parameter(Mandatory = $true)][string]$ResultBundle)

  if (-not (Test-Path -LiteralPath $ResultBundle)) {
    return $null
  }
  $summary = & xcrun xcresulttool get test-results summary `
    --path $ResultBundle --format json 2>$null
  if ($LASTEXITCODE -ne 0 -or $summary.Count -eq 0) {
    return $null
  }
  try {
    $payload = ($summary -join [Environment]::NewLine) | ConvertFrom-Json
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
  Ensure-SimulatorBooted -Stage "runner-entry"
  $simulatorMetadata = Get-SimulatorMetadata
  Invoke-RequiredSimctl `
    -Stage "locale/languages" `
    -CommandArguments @("spawn", $Device, "defaults", "write", "NSGlobalDomain", "AppleLanguages", "-array", "en") | Out-Null
  Invoke-RequiredSimctl `
    -Stage "locale/region" `
    -CommandArguments @("spawn", $Device, "defaults", "write", "NSGlobalDomain", "AppleLocale", "en_US") | Out-Null
  & xcodebuild build-for-testing `
    -workspace ios/Runner.xcworkspace `
    -scheme RunnerPlatformTests `
    -configuration PlatformTest `
    -destination "platform=iOS Simulator,id=$Device" `
    -parallel-testing-enabled NO `
    -derivedDataPath $derivedData `
    CODE_SIGNING_ALLOWED=NO `
    "LDDC_IT_RUN_ID=$runId" `
    "LDDC_FIXTURE_SIZE=$fixtureSize" `
    "LDDC_FIXTURE_SHA256=$fixtureSha256"
  if ($LASTEXITCODE -ne 0) {
    throw "iOS build-for-testing 失败，exit=$LASTEXITCODE"
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
  $containerOutput = Invoke-RequiredSimctl `
    -Stage "resolve-app-container" `
    -CommandArguments @("get_app_container", $Device, "com.cmzj.lddc.platformtests", "data")
  $container = (($containerOutput) -join "").Trim()
  if ([string]::IsNullOrWhiteSpace($container)) {
    throw "无法取得 iOS 平台测试应用容器"
  }
  $documents = Join-Path $container "Documents"
  New-Item -ItemType Directory -Force -Path $documents | Out-Null
  Copy-Item -LiteralPath $fixture -Destination (Join-Path $documents "audio_sample.mp3") -Force

  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $method = $entry.Method
    $resultBundle = Join-Path $rawDir "$scenario.xcresult"
    Ensure-SimulatorBooted -Stage "before-$scenario"
    $testExitCode = Invoke-BoundedXcodeTest `
      -XcTestRun $xctestrun.FullName `
      -Method $method `
      -ResultBundle $resultBundle
    if ($testExitCode -ne 0) {
      $startedTestCount = Get-XcresultStartedTestCount -ResultBundle $resultBundle
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
          -ResultBundle $resultBundle
      }
    }

    $summaryPath = Join-Path $rawDir "$scenario.summary.json"
    $summaryReady = $false
    if (Test-Path -LiteralPath $resultBundle) {
      $summaryLines = & xcrun xcresulttool get test-results summary `
        --path $resultBundle --format json
      if ($LASTEXITCODE -eq 0 -and $summaryLines.Count -gt 0) {
        [IO.File]::WriteAllText(
          $summaryPath,
          ($summaryLines -join [Environment]::NewLine),
          [Text.UTF8Encoding]::new($false)
        )
        $summaryReady = $true
      }
    }
    if (-not $summaryReady) {
      Write-FallbackSummary -Path $summaryPath -Message "XCUITest 未生成可读取的 xcresult summary"
    }
    $scenarioAttachments = Join-Path $attachmentsDir $scenario
    New-Item -ItemType Directory -Force -Path $scenarioAttachments | Out-Null
    if (Test-Path -LiteralPath $resultBundle) {
      & xcrun xcresulttool export attachments `
        --path $resultBundle `
        --output-path $scenarioAttachments
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
      $fallbackEvidence = Join-Path $scenarioAttachments "lddc-evidence-$scenario.json"
      Write-FallbackEvidence -Path $fallbackEvidence -Scenario $scenario -Message "XCUITest 未导出 evidence attachment"
      $evidencePath = Get-Item -LiteralPath $fallbackEvidence
    }
    Add-SimulatorEvidence -EvidencePath $evidencePath.FullName
    if ($scenario -eq "ios_document_picker_select") {
      # XCUITest 写入的是测试 app Documents 中的真实文件。测试返回后由宿主计算
      # 最终摘要并写入结构化 evidence，避免把 Simulator 绝对路径带入报告。
      $selectedFixture = Join-Path $documents "audio_sample.mp3"
      if (-not (Test-Path -LiteralPath $selectedFixture -PathType Leaf)) {
        throw "iOS 写入后 fixture 不存在"
      }
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
    } elseif ($scenario -eq "ios_document_picker_export") {
      $exportedFiles = @(
        Get-ChildItem -LiteralPath $documents -File `
          | Where-Object { $_.Extension.Equals(".lrc", [StringComparison]::OrdinalIgnoreCase) }
      )
      if ($exportedFiles.Count -ne 1) {
        Add-EvidenceFailure `
          -EvidencePath $evidencePath.FullName `
          -Message "iOS 导出场景应生成且只生成一个 LRC，实际为 $($exportedFiles.Count)"
      } else {
        $exportedFile = $exportedFiles[0]
        if ($exportedFile.Name -match '^[0-9a-fA-F-]{36}-') {
          Add-EvidenceFailure `
            -EvidencePath $evidencePath.FullName `
            -Message "iOS 导出文件名泄露了内部临时 UUID"
        }
        $exportedText = Get-Content -LiteralPath $exportedFile.FullName -Raw
        if (-not $exportedText.Contains("Hello LDDC", [StringComparison]::Ordinal)) {
          Add-EvidenceFailure `
            -EvidencePath $evidencePath.FullName `
            -Message "iOS 导出文件缺少预期歌词正文"
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
        Get-ChildItem -LiteralPath $documents -File `
          | Where-Object { $_.Extension.Equals(".lrc", [StringComparison]::OrdinalIgnoreCase) }
      )
      if ($unexpectedExports.Count -ne 0) {
        Add-EvidenceFailure `
          -EvidencePath $evidencePath.FullName `
          -Message "iOS 取消或终止导出后残留了用户输出文件"
      }
    }
    $temporaryExportRoot = Join-Path $container "tmp/lddc_search_exports"
    if (Test-Path -LiteralPath $temporaryExportRoot) {
      $temporaryExportEntries = @(Get-ChildItem -LiteralPath $temporaryExportRoot -Force)
      if ($temporaryExportEntries.Count -ne 0) {
        Add-EvidenceFailure `
          -EvidencePath $evidencePath.FullName `
          -Message "iOS 场景 $scenario 结束后仍残留临时导出资源"
      }
    }
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $summaryPath `
      --raw-report-type xcresult-summary `
      --framework xcuitest `
      --exit-code $testExitCode `
      --evidence $evidencePath.FullName `
      --matrix $matrix
    $normalizeExitCode = $LASTEXITCODE
    $junitPath = Join-Path $junitDir "$scenario.xml"
    & python $junitConverter --input $summaryPath --output $junitPath --scenario $scenario
    $junitExitCode = $LASTEXITCODE
    if ($testExitCode -ne 0 -or $normalizeExitCode -ne 0 -or $junitExitCode -ne 0) {
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
