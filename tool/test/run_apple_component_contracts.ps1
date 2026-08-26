param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("ios", "macos")]
  [string]$Platform,
  [string]$Device = "",
  [string]$ReportDir = "build/integration_reports/apple-component"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$junitConverter = Join-Path $repoRoot "tool/test/json_report_to_junit.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$testTarget = if ($Platform -eq "ios") {
  "integration_test/ios_media_business_round_trip_test.dart"
} else {
  "test/platform/files/app_file_picker_test.dart"
}
$testName = if ($Platform -eq "ios") {
  "iOS 确定性文件句柄通过生产媒体链路完成往返"
} else {
  "Apple 分层文件组件通过真实 TagLib 完成读取、转换、写回和重新打开"
}
$framework = if ($Platform -eq "ios") { "integration_test" } else { "flutter_test" }
$scenario = if ($Platform -eq "ios") {
  "ios_media_business_round_trip"
} else {
  "macos_file_result_adapter"
}
$runId = "platform-$Platform-component-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))

if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}
$runRoot = Join-Path $ReportDir $runId
$rawDir = Join-Path $runRoot "raw"
$scenarioDir = Join-Path $runRoot "scenarios"
$junitDir = Join-Path $runRoot "junit"
foreach ($directory in @($rawDir, $scenarioDir, $junitDir)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$rawReport = Join-Path $rawDir "$scenario.jsonl"
$evidencePath = Join-Path $rawDir "$scenario.evidence.json"
$scenarioPath = Join-Path $scenarioDir "$scenario.json"
$junitPath = Join-Path $junitDir "$scenario.xml"
$fixture = Join-Path $appRoot "integration_test/fixtures/media/audio_sample.mp3"
$fixtureInfo = Get-Item -LiteralPath $fixture
$fixtureHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
$fixtureBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fixture))

if (-not $IsMacOS) {
  throw "Apple 文件和媒体 required 场景只能在 macOS hosted runner 执行"
}
if ($Platform -eq "ios" -and [string]::IsNullOrWhiteSpace($Device)) {
  throw "iOS 文件和媒体 required 场景必须显式指定 Simulator device"
}

$testExitCode = 1
$testError = $null
Push-Location $appRoot
try {
  try {
    $arguments = @("test", $testTarget)
    if ($Platform -eq "ios") {
      $arguments += @(
        "-d", $Device,
        "--dart-define=LDDC_APPLE_COMPONENT_FIXTURE_BASE64=$fixtureBase64",
        "--dart-define=LDDC_APPLE_COMPONENT_FIXTURE_SHA256=$fixtureHash",
        "--dart-define=LDDC_APPLE_COMPONENT_FIXTURE_SIZE=$($fixtureInfo.Length)"
      )
    } else {
      $arguments += @("--plain-name", $testName)
    }
    $arguments += @(
      "--reporter", "expanded",
      "--file-reporter", "json:$rawReport",
      "--no-pub"
    )
    & flutter @arguments
    $testExitCode = $LASTEXITCODE
  } catch {
    # 启动器错误也必须继续生成失败报告，不能让缺失 JSONL 覆盖原始阶段。
    $testError = $_.Exception.GetType().Name
    $testExitCode = 1
  }
} finally {
  Pop-Location
}

$success = $testExitCode -eq 0
$filePickerEvidence = if ($success) {
  @([ordered]@{ action = "deterministic_file_handle_component_verified" })
} else {
  @()
}
$mediaEvidence = if ($success) {
  @([ordered]@{ action = "production_taglib_read_convert_write_reopen" })
} else {
  @()
}
$evidence = [ordered]@{
  runId = $runId
  scenario = $scenario
  profile = "platform"
  platform = $Platform
  framework = $framework
  capabilityEvidence = [ordered]@{
    filePicker = $filePickerEvidence
    media = $mediaEvidence
  }
  resources = [ordered]@{
    baseline = @{}
    final = @{}
    thresholds = @{}
  }
  artifacts = @(
    [ordered]@{
      name = "audio_sample.mp3"
      size = [int64]$fixtureInfo.Length
      sha256 = $fixtureHash
    }
  )
  steps = @(
    [ordered]@{
      name = "file_adapter_media_round_trip"
      success = $success
      error = if ($success) {
        $null
      } elseif ($null -ne $testError) {
        "Flutter 组件契约测试启动失败: $testError"
      } else {
        "Flutter 组件契约测试失败"
      }
    }
  )
  extra = [ordered]@{
    pickerBoundary = "componentVerified"
    executionPlatform = if ($Platform -eq "ios") { "ios_simulator" } else { "macos_host" }
    nativePickerCoveredBy = if ($Platform -eq "ios") {
      "ios_picker_open_cancel_ui+ios_picker_delegate_contract"
    } else {
      "macos_open_panel_cancel"
    }
  }
}
[IO.File]::WriteAllText(
  $evidencePath,
  ($evidence | ConvertTo-Json -Depth 12),
  [Text.UTF8Encoding]::new($false)
)

# flutter test --file-reporter 输出的是 Dart test JSON 事件流，不是已经生成的
# LDDC schemaVersion=2 场景报告；必须走 dart-jsonl 分支，由 evidence 和矩阵
# 构造统一场景报告，否则 required 组件测试会在规范化前必然失败。
& python $normalizer `
  --scenario-report $scenarioPath `
  --raw-report $rawReport `
  --raw-report-type dart-jsonl `
  --framework $framework `
  --exit-code $testExitCode `
  --evidence $evidencePath `
  --matrix $matrix `
  --run-id $runId `
  --scenario $scenario `
  --profile platform `
  --platform $Platform `
  --failure-junit $junitPath
$normalizeExitCode = $LASTEXITCODE

& python $junitConverter --input $rawReport --output $junitPath
$junitExitCode = $LASTEXITCODE

& python $verifier `
  --directory $scenarioDir `
  --junit-directory $junitDir `
  --profile platform `
  --platform $Platform `
  --run-id $runId `
  --matrix $matrix
$verifyExitCode = $LASTEXITCODE

$fixtureHashAfter = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash.ToLowerInvariant()
if ($fixtureHashAfter -ne $fixtureHash) {
  Write-Error "Apple 组件测试修改了 tracked fixture" -ErrorAction Continue
  $verifyExitCode = 1
}

Write-Host "Apple component contract reports: $runRoot"
if ($testExitCode -ne 0 -or $normalizeExitCode -ne 0 `
    -or $junitExitCode -ne 0 -or $verifyExitCode -ne 0) {
  exit 1
}
