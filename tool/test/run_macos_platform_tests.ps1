param(
  [string]$ReportDir = "build/integration_reports/macos-native",
  [ValidateRange(30, 600)]
  [int]$ScenarioTimeoutSeconds = 120,
  [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$junitConverter = Join-Path $repoRoot "tool/test/xcresult_summary_to_junit.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
$fixture = (Resolve-Path (Join-Path $appRoot "integration_test/fixtures/media/audio_sample.mp3")).Path
$fixtureSize = (Get-Item -LiteralPath $fixture).Length
$fixtureSha256 = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

$runId = "platform-macos-{0}-{1}" -f `
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
      "-destination", "platform=macOS",
      "-only-testing:RunnerUITests/RunnerUITests/$Method",
      "-resultBundlePath", $ResultBundle
    )) {
    [void]$startInfo.ArgumentList.Add($argument)
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  try {
    if (-not $process.WaitForExit($ScenarioTimeoutSeconds * 1000)) {
      # XCUITest runner 无响应时终止整个进程树，避免 xcodebuild 与 testmanagerd 客户端留在 runner。
      $process.Kill($true)
      $process.WaitForExit()
      return 124
    }
    return $process.ExitCode
  } finally {
    $process.Dispose()
  }
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
    platform = "macos"
    framework = "xcuitest"
    steps = @([ordered]@{ step = $Scenario; success = $false; error = $Message })
    capabilityEvidence = @{}
    resources = [ordered]@{
      baseline = @{ nativeWindowCount = 0 }
      final = @{ nativeWindowCount = 1 }
      thresholds = @{ nativeWindowCount = 0 }
    }
    artifacts = @()
    extra = @{}
  }
  [IO.File]::WriteAllText($Path, ($payload | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}

Push-Location $appRoot
try {
  # flutter test 会把临时 listener.dart 写入 Debug 构建设置；Xcode 若复用该产物，
  # listener 清理后 kernel_snapshot 会失败。先重建正常 main.dart Debug 应用，
  # 再让 XCUITest build-for-testing 使用稳定入口。
  & flutter build macos --debug
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  & xcodebuild build-for-testing `
    -workspace macos/Runner.xcworkspace `
    -scheme RunnerPlatformTests `
    -configuration Debug `
    -destination "platform=macOS" `
    -derivedDataPath $derivedData `
    "LDDC_IT_RUN_ID=$runId" `
    "LDDC_FIXTURE_PATH=$fixture" `
    "LDDC_FIXTURE_SIZE=$fixtureSize" `
    "LDDC_FIXTURE_SHA256=$fixtureSha256"
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  $xctestrun = Get-ChildItem -Path (Join-Path $derivedData "Build/Products") `
    -Recurse -File -Filter "*.xctestrun" | Select-Object -First 1
  if ($null -eq $xctestrun) {
    throw "macOS build-for-testing 没有生成 xctestrun"
  }
  if ($BuildOnly) {
    # GitHub-hosted macOS 没有可由仓库非交互授予的 Xcode Helper 辅助功能权限，
    # XCUIApplication 会在系统 accessibility 握手阶段失败。CI 仍编译完整 UI
    # test bundle 和 xctestrun，防止 Swift、scheme 或链接配置回归；真实 NSOpenPanel
    # 场景继续由默认运行模式在已授权实体 Mac 上执行，不能由此模式生成通过报告。
    Write-Host "macOS XCUITest build-only validation passed: $($xctestrun.FullName)"
    return
  }

  $scenarios = @(
    @{ Name = "macos_open_panel_select"; Method = "testOpenPanelSelectsFixture" },
    @{ Name = "macos_open_panel_cancel"; Method = "testOpenPanelCancellationReturnsToFlutter" }
  )
  $overallExitCode = 0
  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $method = $entry.Method
    $resultBundle = Join-Path $rawDir "$scenario.xcresult"
    $testExitCode = Invoke-BoundedXcodeTest `
      -XcTestRun $xctestrun.FullName `
      -Method $method `
      -ResultBundle $resultBundle

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
      # 文件面板选择和取消是独立场景。旧 runner 在首个失败后立即退出，
      # hosted CI 只能得到半份证据并需要再次提交才能发现后续问题。
      # 继续执行剩余场景，但最终仍返回非零，不能把失败降级为成功。
      $overallExitCode = 1
      Write-Warning "macOS XCUITest 场景 $scenario 失败，继续收集其余独立场景"
    }
  }
} finally {
  Pop-Location
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

Write-Host "macOS platform reports: $runRoot"
exit $overallExitCode
