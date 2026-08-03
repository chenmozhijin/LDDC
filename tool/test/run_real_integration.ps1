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

function Copy-ContainerScenarioReport {
  param(
    [Parameter(Mandatory = $true)][string]$Scenario,
    [Parameter(Mandatory = $true)][string]$ContainerReportDir,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$DiagnosticPath
  )

  if ($Platform -eq "android") {
    $relativePath = "cache/$ContainerReportDir/$Scenario.json" -replace '\\', '/'
    $jsonLines = & adb -s $Device exec-out run-as com.cmzj.lddc cat $relativePath 2>&1
    $pullExitCode = $LASTEXITCODE
    $content = ($jsonLines -join [Environment]::NewLine).Trim()
    if ($pullExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($content)) {
      [IO.File]::WriteAllText($DiagnosticPath, $content, [Text.UTF8Encoding]::new($false))
      throw "无法从 Android 应用沙箱拉回 $Scenario.json，adb exit=$pullExitCode"
    }
  } elseif ($Platform -eq "ios") {
    $containerOutput = & xcrun simctl get_app_container $Device com.cmzj.lddc data 2>&1
    $containerExitCode = $LASTEXITCODE
    $container = (($containerOutput) -join "").Trim()
    if ($containerExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($container)) {
      [IO.File]::WriteAllText($DiagnosticPath, ($containerOutput -join [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
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
    $content = [IO.File]::ReadAllText($source)
  } elseif ($Platform -eq "macos") {
    # 开启 App Sandbox 的 macOS 测试应用不能写 runner 的仓库绝对路径。
    # 应用把相对目录解析到 NSTemporaryDirectory，测试结束后再由宿主回收。
    $source = [IO.Path]::GetTempPath()
    foreach ($segment in ($ContainerReportDir -split '[/\\]+')) {
      if (-not [string]::IsNullOrWhiteSpace($segment)) {
        $source = Join-Path $source $segment
      }
    }
    $source = Join-Path $source "$Scenario.json"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "macOS 应用临时目录没有生成 $Scenario.json"
    }
    $content = [IO.File]::ReadAllText($source)
  }

  try {
    $payload = $content | ConvertFrom-Json -AsHashtable
  } catch {
    [IO.File]::WriteAllText($DiagnosticPath, $content, [Text.UTF8Encoding]::new($false))
    throw "移动端 $Scenario 场景报告不是有效 JSON"
  }
  if ($payload.schemaVersion -ne 2 -or
      $payload.runId -ne $runId -or
      $payload.scenario -ne $Scenario -or
      $payload.platform -ne $Platform) {
    [IO.File]::WriteAllText($DiagnosticPath, $content, [Text.UTF8Encoding]::new($false))
    throw "移动端 $Scenario 场景报告身份或 schema 不匹配"
  }
  [IO.File]::WriteAllText($Destination, $content, [Text.UTF8Encoding]::new($false))
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

$overallExitCode = 0
Push-Location $appRoot
try {
  foreach ($target in $Targets) {
    $scenarioName = [IO.Path]::GetFileNameWithoutExtension($target) -replace '[^a-zA-Z0-9._-]', '_'
    $scenarioName = $scenarioName -replace '_test$', ''
    $capabilitiesB64 = Resolve-CapabilityContract -Scenario $scenarioName
    $jsonPath = Join-Path $eventReportDir "$scenarioName.jsonl"
    $junitPath = Join-Path $junitReportDir "$scenarioName.xml"
    $scenarioPath = Join-Path $scenarioReportDir "$scenarioName.json"
    $diagnosticPath = Join-Path $scenarioReportDir "$scenarioName.report-pull.txt"
    $processReportDir = if ($Platform -in @("android", "ios", "macos")) {
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
    if ($Platform -in @("android", "ios")) {
      # Flutter 默认在测试结束时卸载移动端应用；报告位于应用沙箱，必须先回收
      # 并完成校验，再由本 runner 的 finally 显式卸载。
      $flutterArguments += "--no-uninstall"
    }

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

    $collectionExitCode = 0
    if ($Platform -in @("android", "ios", "macos")) {
      try {
        Copy-ContainerScenarioReport `
          -Scenario $scenarioName `
          -ContainerReportDir $containerReportDir `
          -Destination $scenarioPath `
          -DiagnosticPath $diagnosticPath
      } catch {
        $collectionExitCode = 1
        Write-Error -ErrorAction Continue $_
      }
    }

    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $jsonPath `
      --raw-report-type flutter-jsonl `
      --framework integration_test `
      --exit-code $(if ($collectionExitCode -ne 0 -and $testExitCode -eq 0) { 1 } else { $testExitCode }) `
      --run-id $runId `
      --scenario $scenarioName `
      --profile $Profile `
      --platform $Platform `
      --failure-junit $junitPath
    $normalizeExitCode = $LASTEXITCODE
    $convertExitCode = 0
    if ($normalizeExitCode -eq 0) {
      & python $converter --input $jsonPath --output $junitPath
      $convertExitCode = $LASTEXITCODE
    }
    if ($testExitCode -ne 0 -or $collectionExitCode -ne 0 -or
        $normalizeExitCode -ne 0 -or $convertExitCode -ne 0) {
      $overallExitCode = 1
      Write-Warning "Target '$target' 失败；继续执行其余独立场景以收集完整证据"
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
    $overallExitCode = 1
  }
} finally {
  Pop-Location
  if ($Platform -eq "android") {
    & adb -s $Device uninstall com.cmzj.lddc 2>&1 | Write-Host
  } elseif ($Platform -eq "ios") {
    & xcrun simctl uninstall $Device com.cmzj.lddc 2>&1 | Write-Host
  }
}

Write-Host "Integration reports: $runRoot"
exit $overallExitCode
