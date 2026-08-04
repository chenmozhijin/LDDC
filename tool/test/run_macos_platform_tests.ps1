param(
  [string]$ReportDir = "build/integration_reports/macos-native",
  [ValidateRange(120, 600)]
  [int]$ScenarioTimeoutSeconds = 300
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
$fixtureSource = (Resolve-Path (Join-Path $appRoot "integration_test/fixtures/media/audio_sample.mp3")).Path
$fixtureSize = (Get-Item -LiteralPath $fixtureSource).Length
$fixtureSha256 = (Get-FileHash -LiteralPath $fixtureSource -Algorithm SHA256).Hash.ToLowerInvariant()
$framework = "integration_test+xcuitest"
$flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
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
$attachmentsDir = Join-Path $runRoot "attachments"
$diagnosticsDir = Join-Path $runRoot "diagnostics"
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
foreach ($directory in @($scenarioDir, $rawDir, $junitDir, $attachmentsDir, $diagnosticsDir)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$scenarios = @(
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

function Stop-ProcessTree {
  param([Diagnostics.Process]$Process)

  if ($null -eq $Process) {
    return
  }
  $Process.Refresh()
  if (-not $Process.HasExited) {
    # .NET 8 在 macOS 会递归终止当前测试进程的后代，避免 flutter_tester 和
    # xcodebuild 客户端在失败后继续持有应用、socket 或结果目录。
    $Process.Kill($true)
    $Process.WaitForExit()
  }
}

function Wait-ForPickerMarker {
  param(
    [Parameter(Mandatory = $true)][Diagnostics.Process]$FlutterProcess,
    [Parameter(Mandatory = $true)][string]$MarkerPath,
    [Parameter(Mandatory = $true)][string]$Scenario
  )

  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($ScenarioTimeoutSeconds)
  while (-not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
    $FlutterProcess.Refresh()
    if ($FlutterProcess.HasExited) {
      throw "Flutter integration_test 在打开 NSOpenPanel 前退出，exit=$($FlutterProcess.ExitCode)"
    }
    if ([DateTimeOffset]::UtcNow -ge $deadline) {
      throw "Flutter integration_test 未在超时内请求 NSOpenPanel"
    }
    Start-Sleep -Milliseconds 200
  }

  try {
    $marker = Get-Content -LiteralPath $MarkerPath -Raw | ConvertFrom-Json
  } catch {
    throw "Flutter integration_test 写入了损坏的 NSOpenPanel marker: $($_.Exception.Message)"
  }
  [long]$applicationPid = 0
  $hasValidPid = [long]::TryParse([string]$marker.pid, [ref]$applicationPid)
  if ($marker.runId -ne $runId `
      -or $marker.scenario -ne $Scenario `
      -or $marker.state -ne "picker_requested" `
      -or -not $hasValidPid `
      -or $applicationPid -le 0) {
    throw "NSOpenPanel marker 与当前 runId/scenario/state/PID 不匹配"
  }
  $applicationProcess = Get-Process -Id ([int]$applicationPid) -ErrorAction SilentlyContinue
  if ($null -eq $applicationProcess -or $applicationProcess.ProcessName -ne "LDDC") {
    throw "NSOpenPanel marker 指向的 LDDC 应用进程不存在"
  }
  return $marker
}

function Wait-ForBoundedExit {
  param(
    [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
    Stop-ProcessTree -Process $Process
    return 124
  }
  return $Process.ExitCode
}

function Invoke-BoundedXcodeTest {
  param(
    [Parameter(Mandatory = $true)][string]$XcTestRun,
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$ResultBundle
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = "xcodebuild"
  $startInfo.UseShellExecute = $false
  foreach ($argument in @(
      "test-without-building",
      "-xctestrun", $XcTestRun,
      "-destination", "platform=macOS",
      "-parallel-testing-enabled", "NO",
      "-only-testing:RunnerUITests/RunnerUITests/$Method",
      "-resultBundlePath", $ResultBundle
    )) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  try {
    return Wait-ForBoundedExit -Process $process -TimeoutSeconds $ScenarioTimeoutSeconds
  } finally {
    Stop-ProcessTree -Process $process
    $process.Dispose()
  }
}

function Read-XcresultSummary {
  param(
    [Parameter(Mandatory = $true)][string]$ResultBundle,
    [Parameter(Mandatory = $true)][string]$SummaryPath
  )

  if (-not (Test-Path -LiteralPath $ResultBundle)) {
    return $false
  }
  $summary = & xcrun xcresulttool get test-results summary `
    --path $ResultBundle --format json 2>$null
  if ($LASTEXITCODE -ne 0 -or $summary.Count -eq 0) {
    return $false
  }
  [IO.File]::WriteAllText(
    $SummaryPath,
    ($summary -join [Environment]::NewLine),
    [Text.UTF8Encoding]::new($false)
  )
  return $true
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
  param([Parameter(Mandatory = $true)][string]$Path)

  $payload = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
  if (-not $payload.capabilityEvidence.ContainsKey("resourceCleanup")) {
    $payload.capabilityEvidence["resourceCleanup"] = @()
  }
  $payload.capabilityEvidence["resourceCleanup"] += @{
    action = "flutter_and_xcuitest_processes_closed"
  }
  foreach ($section in @("baseline", "final", "thresholds")) {
    if (-not $payload.resources.ContainsKey($section)) {
      $payload.resources[$section] = @{}
    }
    $payload.resources[$section]["childProcessCount"] = 0
  }
  [IO.File]::WriteAllText(
    $Path,
    ($payload | ConvertTo-Json -Depth 20),
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
$activeFlutterProcess = $null
Push-Location $appRoot
try {
  $existingLddc = @(Get-Process -Name "LDDC" -ErrorAction SilentlyContinue)
  if ($existingLddc.Count -gt 0) {
    throw "macOS hybrid 测试要求启动前不存在 LDDC 进程，当前 PID: $($existingLddc.Id -join ', ')"
  }
  # 先构建稳定 main.dart 与 UI test bundle；随后 flutter test 可以使用临时 listener，
  # XCUITest 只附着其已运行的 bundle id，不启动 build-for-testing 产物。
  & flutter build macos --debug
  if ($LASTEXITCODE -ne 0) {
    throw "macOS Debug build 失败，exit=$LASTEXITCODE"
  }
  New-Item -ItemType Directory -Force `
    -Path $syncDir, (Split-Path -Parent $fixture), $containerReportDir | Out-Null
  Copy-Item -LiteralPath $fixtureSource -Destination $fixture -Force
  & xcodebuild build-for-testing `
    -workspace $testProject `
    -scheme RunnerPlatformTests `
    -configuration Debug `
    -destination "platform=macOS" `
    -parallel-testing-enabled NO `
    -derivedDataPath $derivedData `
    "LDDC_IT_RUN_ID=$runId" `
    "LDDC_FIXTURE_PATH=$fixture"
  if ($LASTEXITCODE -ne 0) {
    throw "macOS XCUITest build-for-testing 失败，exit=$LASTEXITCODE"
  }
  $xctestrun = Get-ChildItem -Path (Join-Path $derivedData "Build/Products") `
    -Recurse -File -Filter "*.xctestrun" | Select-Object -First 1
  if ($null -eq $xctestrun) {
    throw "macOS build-for-testing 没有生成 xctestrun"
  }

  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $action = $entry.Action
    $method = $entry.Method
    $capabilitiesB64 = Resolve-CapabilityContract -Scenario $scenario
    $markerPath = Join-Path $syncDir "$scenario.picker.json"
    $flutterJsonl = Join-Path $rawDir "$scenario.flutter.jsonl"
    $resultBundle = Join-Path $rawDir "$scenario.xcresult"
    $summaryPath = Join-Path $rawDir "$scenario.xcresult.summary.json"
    $scenarioAttachments = Join-Path $attachmentsDir $scenario
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    $containerScenarioPath = Join-Path $containerReportDir "$scenario.json"
    $junitPath = Join-Path $junitDir "$scenario.xml"
    New-Item -ItemType Directory -Force -Path $scenarioAttachments | Out-Null
    foreach ($path in @($markerPath, $flutterJsonl, $summaryPath, $scenarioPath, $containerScenarioPath, $junitPath)) {
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
      "--dart-define=LDDC_IT_STEP_TIMEOUT_MS=90000"
    )

    $flutterExitCode = 1
    $xcodeExitCode = 1
    $nativeSummaryPassed = $false
    try {
      Write-Host "Running macOS hybrid scenario: $scenario"
      $activeFlutterProcess = Start-Process `
        -FilePath $flutterCommand `
        -ArgumentList $flutterArguments `
        -WorkingDirectory $appRoot `
        -PassThru `
        -NoNewWindow
      $pickerMarker = Wait-ForPickerMarker `
        -FlutterProcess $activeFlutterProcess `
        -MarkerPath $markerPath `
        -Scenario $scenario
      $xcodeExitCode = Invoke-BoundedXcodeTest `
        -XcTestRun $xctestrun.FullName `
        -Method $method `
        -ResultBundle $resultBundle
      $flutterExitCode = Wait-ForBoundedExit `
        -Process $activeFlutterProcess `
        -TimeoutSeconds $(if ($xcodeExitCode -eq 0) { 90 } else { 10 })
      $summaryReady = Read-XcresultSummary `
        -ResultBundle $resultBundle `
        -SummaryPath $summaryPath
      $nativeSummaryPassed = $summaryReady -and (Test-PassingXcresultSummary -SummaryPath $summaryPath)
      if (Test-Path -LiteralPath $resultBundle) {
        & xcrun xcresulttool export attachments `
          --path $resultBundle `
          --output-path $scenarioAttachments
      }
    } catch {
      Write-Warning "$scenario hybrid runner 失败: $($_.Exception.Message)"
    } finally {
      Stop-ProcessTree -Process $activeFlutterProcess
      if ($null -ne $activeFlutterProcess) {
        $activeFlutterProcess.Dispose()
        $activeFlutterProcess = $null
      }
    }

    $remainingLddc = @(Get-Process -Name "LDDC" -ErrorAction SilentlyContinue)
    foreach ($process in $remainingLddc) {
      $process.Kill($true)
      $process.WaitForExit()
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
      Write-FallbackEvidence `
        -Path $fallbackEvidence `
        -Scenario $scenario `
        -Message "XCUITest 未导出 hybrid evidence attachment"
      $evidencePath = Get-Item -LiteralPath $fallbackEvidence
    }
    Add-RunnerCleanupEvidence -Path $evidencePath.FullName

    if (Test-Path -LiteralPath $containerScenarioPath -PathType Leaf) {
      Copy-Item -LiteralPath $containerScenarioPath -Destination $scenarioPath -Force
    }
    $combinedExitCode = if (
      $flutterExitCode -eq 0 `
        -and $xcodeExitCode -eq 0 `
        -and $nativeSummaryPassed `
        -and $remainingLddc.Count -eq 0
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
    if ($combinedExitCode -ne 0 -or $normalizeExitCode -ne 0 -or $junitExitCode -ne 0) {
      $overallExitCode = 1
    }
  }
} catch {
  $overallExitCode = 1
  $message = "macOS hybrid infrastructure failure: $($_.Exception.Message)"
  Write-Error $message -ErrorAction Continue
  Write-InfrastructureFailureReports -Message $message
} finally {
  Stop-ProcessTree -Process $activeFlutterProcess
  Pop-Location
  try {
    if (Test-Path -LiteralPath $hybridRoot -PathType Container) {
      Remove-Item -LiteralPath $hybridRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $derivedData -PathType Container) {
      Remove-Item -LiteralPath $derivedData -Recurse -Force
    }
  } catch {
    $overallExitCode = 1
    $message = "macOS hybrid cleanup failure: $($_.Exception.Message)"
    Write-Error $message -ErrorAction Continue
    Write-InfrastructureFailureReports -Message $message -Overwrite
  }
}

& python $verifier `
  --directory $scenarioDir `
  --junit-directory $junitDir `
  --profile platform `
  --platform macos `
  --run-id $runId `
  --matrix $matrix
if ($LASTEXITCODE -ne 0) {
  $overallExitCode = 1
}

Write-Host "macOS hybrid platform reports: $runRoot"
exit $overallExitCode
