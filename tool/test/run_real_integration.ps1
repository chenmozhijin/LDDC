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
  [ValidateRange(60, 600)]
  [int]$StartupTimeoutSeconds = 300,
  [ValidateRange(300, 1800)]
  [int]$TargetTimeoutSeconds = 1200,
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
    # Dart VM 在 Android 应用进程中把 Directory.systemTemp 映射到 code_cache，
    # 不是普通 cache。旧路径会在应用明确打印 report written 后仍稳定拉取失败，
    # 使业务成功被错误归类为基础设施失败。
    $relativePath = "code_cache/$ContainerReportDir/$Scenario.json" -replace '\\', '/'
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
    # NSTemporaryDirectory 位于应用容器的 Data/tmp，而不是宿主进程的 /tmp；
    # 直接使用 GetTempPath 会稳定漏掉已经生成的报告并制造假基础设施失败。
    $source = Join-Path ([Environment]::GetFolderPath("UserProfile")) `
      "Library/Containers/com.cmzj.lddc/Data/tmp"
    foreach ($segment in ($ContainerReportDir -split '[/\\]+')) {
      if (-not [string]::IsNullOrWhiteSpace($segment)) {
        $source = Join-Path $source $segment
      }
    }
    $source = Join-Path $source "$Scenario.json"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      [IO.File]::WriteAllText(
        $DiagnosticPath,
        "expected macOS sandbox report: $source",
        [Text.UTF8Encoding]::new($false)
      )
      throw "macOS 应用容器没有生成 $Scenario.json"
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

function Test-ScenarioExecutionStarted {
  param([Parameter(Mandatory = $true)][string]$EventReportPath)

  if (-not (Test-Path -LiteralPath $EventReportPath -PathType Leaf)) {
    return $false
  }
  foreach ($line in Get-Content -LiteralPath $EventReportPath -ErrorAction SilentlyContinue) {
    try {
      $event = $line | ConvertFrom-Json
    } catch {
      continue
    }
    if ($event.type -ne "testStart") {
      continue
    }
    $testName = [string]$event.test.name
    # Flutter 会先写入隐藏的 `loading <target>` 用例。它只能证明 runner
    # 启动过，不能证明应用已建立 debug 连接或业务场景实际开始执行。
    if (-not [string]::IsNullOrWhiteSpace($testName) -and
        -not $testName.StartsWith("loading ")) {
      return $true
    }
  }
  return $false
}

function Test-IosSimulatorReady {
  param([Parameter(Mandatory = $true)][string]$Stage)

  if ($Platform -ne "ios") {
    return $true
  }
  $deviceLines = & xcrun simctl list devices --json 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "iOS Simulator 在 $Stage 无法读取设备状态: $($deviceLines -join ' ')"
    return $false
  }
  try {
    $devices = (($deviceLines) -join [Environment]::NewLine) | ConvertFrom-Json
    $deviceInfo = $null
    foreach ($runtime in $devices.devices.PSObject.Properties) {
      foreach ($candidate in @($runtime.Value)) {
        if ($candidate.udid -eq $Device) {
          $deviceInfo = $candidate
          break
        }
      }
      if ($null -ne $deviceInfo) {
        break
      }
    }
  } catch {
    Write-Warning "iOS Simulator 在 $Stage 返回了损坏的设备清单: $($_.Exception.Message)"
    return $false
  }
  if ($null -eq $deviceInfo) {
    Write-Warning "iOS Simulator 在 $Stage 找不到指定 UDID=$Device"
    return $false
  }
  if ($deviceInfo.state -eq "Shutdown") {
    & xcrun simctl boot $Device 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "iOS Simulator 在 $Stage 无法启动"
      return $false
    }
  } elseif ($deviceInfo.state -notin @("Booted", "Booting")) {
    Write-Warning "iOS Simulator 在 $Stage 状态不可恢复: $($deviceInfo.state)"
    return $false
  }
  & xcrun simctl bootstatus $Device -b 2>&1 | Write-Host
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "iOS Simulator 在 $Stage 等待 Booted 失败"
    return $false
  }
  return $true
}

function Invoke-BoundedFlutterTest {
  param(
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$EventReportPath
  )

  $flutterCommand = (Get-Command flutter).Source
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.UseShellExecute = $false
  $startInfo.WorkingDirectory = $appRoot
  if ($IsWindows -and $flutterCommand.EndsWith(".bat")) {
    $startInfo.FileName = "cmd.exe"
    foreach ($argument in @("/d", "/c", $flutterCommand) + $Arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  } else {
    $startInfo.FileName = $flutterCommand
    foreach ($argument in $Arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  $stopwatch = [Diagnostics.Stopwatch]::StartNew()
  try {
    while (-not $process.WaitForExit(1000)) {
      if ($stopwatch.Elapsed.TotalSeconds -ge $TargetTimeoutSeconds) {
        # Flutter tool、设备桥或原生 runner 可能在场景执行期间挂住。
        # 必须终止完整进程树并返回明确超时码，后续 normalizer 才能生成失败 JUnit。
        $process.Kill($true)
        $process.WaitForExit()
        return 124
      }
      if ($stopwatch.Elapsed.TotalSeconds -ge $StartupTimeoutSeconds -and
          -not (Test-ScenarioExecutionStarted -EventReportPath $EventReportPath)) {
        # 设备只写出隐藏 loading 用例时，应用尚未真正开始场景。及时回收并
        # 返回独立基础设施码，允许 runner 执行唯一一次启动重试。
        $process.Kill($true)
        $process.WaitForExit()
        return 125
      }
    }
    if (-not (Test-ScenarioExecutionStarted -EventReportPath $EventReportPath)) {
      return 125
    }
    return $process.ExitCode
  } finally {
    $stopwatch.Stop()
    $process.Dispose()
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
      $simulatorReady = Test-IosSimulatorReady `
        -Stage "$scenarioName-attempt-$($infrastructureAttempt + 1)"
      if ($simulatorReady) {
        $testExitCode = Invoke-BoundedFlutterTest `
          -Arguments $flutterArguments `
          -EventReportPath $jsonPath
      } else {
        # 126 明确表示设备基础设施未就绪；后续 normalizer 仍会生成失败
        # scenario/JUnit，且只允许按既有规则重试一次。
        $testExitCode = 126
      }
      if ($testExitCode -eq 0) {
        break
      }

      $testStarted = Test-ScenarioExecutionStarted -EventReportPath $jsonPath
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

    $convertExitCode = 0
    if (Test-Path -LiteralPath $jsonPath -PathType Leaf) {
      & python $converter --input $jsonPath --output $junitPath
      $convertExitCode = $LASTEXITCODE
    } else {
      $convertExitCode = 1
    }
    # 原始 JSONL 先转换；normalizer 最后根据应用退出码与报告回收状态写入
    # 联合结果，必要时用失败 JUnit 覆盖原始成功，保持三类结果一致。
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
