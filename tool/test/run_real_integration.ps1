param(
  [string[]]$Targets = @(),
  [Parameter(Mandatory = $true)]
  [ValidateSet("offline", "platform", "live")]
  [string]$Profile,
  [Parameter(Mandatory = $true)]
  [string]$Device,
  [Parameter(Mandatory = $true)]
  [ValidateSet("windows", "macos", "linux", "android", "ios")]
  [string]$Platform,
  [string]$ReportDir = "build/integration_reports",
  [int]$RequestTimeoutMs = 10000,
  [ValidateRange(0, 1)]
  [int]$RequestRetryCount = 0,
  [ValidateRange(0, 1)]
  [int]$InfrastructureRetryCount = 1,
  [int]$StepTimeoutMs = 20000,
  [switch]$ValidateOnly
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$converter = Join-Path $repoRoot "tool/test/json_report_to_junit.py"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$matrixResolver = Join-Path $repoRoot "tool/test/capability_matrix.py"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

$allowedTargets = switch ($Profile) {
  "offline" {
    $offlineTargets = @(
      "integration_test/batch_convert_flow_test.dart",
      "integration_test/local_match_flow_test.dart",
      "integration_test/open_lyrics_flow_test.dart",
      "integration_test/screenshot_capability_test.dart",
      "integration_test/search_collection_flow_test.dart",
      "integration_test/search_song_flow_test.dart",
      "integration_test/settings_about_flow_test.dart"
    )
    if ($Platform -in @("windows", "macos", "linux")) {
      $offlineTargets += "integration_test/desktop_lyrics_protocol_test.dart"
    }
    $offlineTargets
  }
  "platform" { @("integration_test/platform_capability_smoke_test.dart") }
  "live" {
    @(
      "integration_test/search_collection_flow_test.dart",
      "integration_test/search_song_flow_test.dart"
    )
  }
}
if ($Targets.Count -eq 0) {
  $Targets = $allowedTargets
}
$unexpectedTargets = @($Targets | Where-Object { $_ -notin $allowedTargets })
if ($unexpectedTargets.Count -gt 0) {
  throw "profile '$Profile' 不允许执行 target: $($unexpectedTargets -join ', ')"
}

function Resolve-CapabilityContract {
  param([Parameter(Mandatory = $true)][string]$Scenario)

  $encoded = & python $matrixResolver `
    --matrix $matrix `
    --profile $Profile `
    --platform $Platform `
    --scenario $Scenario `
    --framework integration_test `
    --base64
  if ($LASTEXITCODE -ne 0) {
    throw "无法解析 $Profile/$Platform/$Scenario 的能力契约"
  }
  return (($encoded -join "").Trim())
}

function Copy-MobileScenarioReport {
  param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [Parameter(Mandatory = $true)][string]$ContainerReportDir,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if ($Platform -eq "android") {
    $relativePath = "cache/$ContainerReportDir/$Scenario.json" -replace '\\', '/'
    $jsonLines = & adb -s $Device exec-out run-as com.cmzj.lddc cat $relativePath
    if ($LASTEXITCODE -ne 0) {
      throw "无法从 Android 应用沙箱拉回 $Scenario.json"
    }
    [IO.File]::WriteAllText(
      $Destination,
      ($jsonLines -join [Environment]::NewLine),
      [Text.UTF8Encoding]::new($false)
    )
    return
  }

  if ($Platform -eq "ios") {
    $container = ((& xcrun simctl get_app_container $Device com.cmzj.lddc data) -join "").Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($container)) {
      throw "无法解析 iOS Simulator 应用数据容器"
    }
    $source = Join-Path $container "tmp"
    foreach ($segment in ($ContainerReportDir -split '[/\\]+')) {
      if (-not [string]::IsNullOrWhiteSpace($segment)) {
        $source = Join-Path $source $segment
      }
    }
    $source = Join-Path $source "$Scenario.json"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "iOS 应用沙箱没有生成 $Scenario.json"
    }
    Copy-Item -LiteralPath $source -Destination $Destination -Force
  }
}

# ValidateOnly 也解析每个目标的矩阵项，防止 workflow 通过语法检查却在真实设备上
# 才发现 profile、平台或场景没有契约。该路径不创建目录、不启动 Flutter。
foreach ($target in $Targets) {
  $scenarioName = [IO.Path]::GetFileNameWithoutExtension($target) -replace '[^a-zA-Z0-9._-]', '_'
  $scenarioName = $scenarioName -replace '_test$', ''
  [void](Resolve-CapabilityContract -Scenario $scenarioName)
}
if ($ValidateOnly) {
  Write-Host "Integration runner contract passed: $Profile/$Platform"
  exit 0
}

$runId = "{0}-{1}-{2}-{3}" -f `
  $Profile, `
  $Platform, `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Join-Path $ReportDir $runId
$scenarioReportDir = Join-Path $runRoot "scenarios"
$eventReportDir = Join-Path $runRoot "test-events"
$junitReportDir = Join-Path $runRoot "junit"
$containerReportDir = "lddc_integration_reports/$runId/scenarios"

New-Item -ItemType Directory -Force -Path $scenarioReportDir | Out-Null
New-Item -ItemType Directory -Force -Path $eventReportDir | Out-Null
New-Item -ItemType Directory -Force -Path $junitReportDir | Out-Null

Write-Host "Integration profile: $Profile"
Write-Host "Integration device: $Device ($Platform)"
Write-Host "Integration run id: $runId"
Write-Host "Integration report directory: $runRoot"
Write-Host "Integration targets: $($Targets -join ', ')"

Push-Location $appRoot
try {
  foreach ($target in $Targets) {
    $scenarioName = [IO.Path]::GetFileNameWithoutExtension($target) -replace '[^a-zA-Z0-9._-]', '_'
    $scenarioName = $scenarioName -replace '_test$', ''
    $capabilitiesB64 = Resolve-CapabilityContract -Scenario $scenarioName
    $jsonPath = Join-Path $eventReportDir "$scenarioName.jsonl"
    $junitPath = Join-Path $junitReportDir "$scenarioName.xml"
    $scenarioPath = Join-Path $scenarioReportDir "$scenarioName.json"
    $processReportDir = if ($Platform -in @("android", "ios")) {
      $containerReportDir
    } else {
      $scenarioReportDir
    }
    $flutterArguments = @(
      "test",
      $target,
      "-d", $Device,
      "-r", "expanded",
      "--file-reporter", "json:$jsonPath",
      "--dart-define=LDDC_IT_PROFILE=$Profile",
      "--dart-define=LDDC_IT_DEVICE=$Platform",
      "--dart-define=LDDC_IT_RUN_ID=$runId",
      "--dart-define=LDDC_IT_FRAMEWORK=integration_test",
      "--dart-define=LDDC_IT_CAPABILITIES_B64=$capabilitiesB64",
      "--dart-define=LDDC_IT_REPORT_DIR=$processReportDir",
      "--dart-define=LDDC_IT_REQUEST_TIMEOUT_MS=$RequestTimeoutMs",
      "--dart-define=LDDC_IT_REQUEST_RETRY_COUNT=$RequestRetryCount",
      "--dart-define=LDDC_IT_STEP_TIMEOUT_MS=$StepTimeoutMs"
    )

    Write-Host "Running '$target' with profile '$Profile' on device '$Device' ($Platform)"
    $infrastructureAttempt = 0
    do {
      if (Test-Path -LiteralPath $jsonPath) {
        Remove-Item -LiteralPath $jsonPath -Force
      }
      & flutter @flutterArguments
      $testExitCode = $LASTEXITCODE
      if ($testExitCode -eq 0) {
        break
      }

      $testStarted = (Test-Path -LiteralPath $jsonPath) -and
        (Select-String -LiteralPath $jsonPath -Pattern '"type"\s*:\s*"testStart"' -Quiet)
      if ($testStarted -or $infrastructureAttempt -ge $InfrastructureRetryCount) {
        break
      }
      $infrastructureAttempt += 1
      Write-Warning "Target '$target' 在 testStart 前失败，执行唯一一次基础设施重试"
    } while ($true)

    if ($Platform -in @("android", "ios")) {
      Copy-MobileScenarioReport `
        -Scenario $scenarioName `
        -ContainerReportDir $containerReportDir `
        -Destination $scenarioPath
    }
    if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)) {
      throw "Target '$target' 没有生成场景 JSON 报告"
    }

    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $jsonPath `
      --raw-report-type flutter-jsonl `
      --framework integration_test `
      --exit-code $testExitCode
    $normalizeExitCode = $LASTEXITCODE
    & python $converter --input $jsonPath --output $junitPath
    $convertExitCode = $LASTEXITCODE
    if ($normalizeExitCode -ne 0) {
      exit $normalizeExitCode
    }
    if ($convertExitCode -ne 0) {
      exit $convertExitCode
    }
    if ($testExitCode -ne 0) {
      exit $testExitCode
    }
  }

  & python $verifier `
    --directory $scenarioReportDir `
    --junit-directory $junitReportDir `
    --profile $Profile `
    --platform $Platform `
    --run-id $runId `
    --matrix $matrix
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  Pop-Location
}

Write-Host "Integration reports: $runRoot"
