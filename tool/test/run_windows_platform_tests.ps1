param(
  [string]$ReportDir = "build/integration_reports/windows-native",
  [ValidateSet("all", "select", "cancel")]
  [string]$ScenarioFilter = "all",
  [ValidateRange(120, 600)]
  [int]$ScenarioTimeoutSeconds = 420
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$testProject = Join-Path $appRoot "windows/RunnerPlatformTests/RunnerPlatformTests.csproj"
$flutterTarget = "integration_test/windows_file_dialog_platform_test.dart"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$junitConverter = Join-Path $repoRoot "tool/test/json_report_to_junit.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$matrixResolver = Join-Path $repoRoot "tool/test/capability_matrix.py"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
$fixtureSource = (Resolve-Path (Join-Path $appRoot "integration_test/fixtures/media/lyrics_sample.lrc")).Path
$framework = "integration_test+flaui-uia3"
$flutterCommand = (Get-Command flutter -ErrorAction Stop).Source
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

$existingLddc = @(Get-Process -Name "lddc" -ErrorAction SilentlyContinue)
if ($existingLddc.Count -gt 0) {
  throw "Windows 平台测试要求启动前不存在 LDDC 进程，当前 PID: $($existingLddc.Id -join ', ')"
}

$runId = "platform-windows-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Join-Path $ReportDir $runId
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$evidenceDir = Join-Path $runRoot "evidence"
$diagnosticsDir = Join-Path $runRoot "diagnostics"
$sandboxParent = [IO.Path]::GetFullPath((Join-Path $appRoot "build/native_test_sandboxes"))
$sandboxRoot = [IO.Path]::GetFullPath((Join-Path $sandboxParent $runId))
$syncDir = Join-Path $sandboxRoot "native-sync"
if (-not $sandboxRoot.StartsWith($sandboxParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw "Windows 平台测试 sandbox 超出允许目录"
}
foreach ($directory in @($scenarioDir, $rawDir, $junitDir, $evidenceDir, $diagnosticsDir, $sandboxRoot, $syncDir)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
$fixtureDirectory = Join-Path $sandboxRoot "fixtures"
New-Item -ItemType Directory -Force -Path $fixtureDirectory | Out-Null
$fixture = Join-Path $fixtureDirectory (Split-Path -Leaf $fixtureSource)
Copy-Item -LiteralPath $fixtureSource -Destination $fixture -Force

$environmentNames = @(
  "LDDC_IT_RUN_ID",
  "LDDC_FIXTURE_PATH",
  "LDDC_NATIVE_EVIDENCE_DIR",
  "LDDC_NATIVE_SYNC_DIR"
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$scenarios = @(
  @{
    Name = "windows_file_dialog_select"
    Action = "select"
    Target = "integration_test/windows_file_dialog_platform_test.dart"
    Method = "RunnerPlatformTests.FileDialogPlatformTests.SelectsFixtureFromDialogOpenedByFlutterIntegrationTest"
  },
  @{
    Name = "windows_file_dialog_cancel"
    Action = "cancel"
    Target = "integration_test/windows_file_dialog_platform_test.dart"
    Method = "RunnerPlatformTests.FileDialogPlatformTests.CancelsAndReopensDialogOpenedByFlutterIntegrationTest"
  }
)
if ($ScenarioFilter -ne "all") {
  $scenarios = @($scenarios | Where-Object { $_.Action -eq $ScenarioFilter })
}

function Resolve-CapabilityContract {
  param([Parameter(Mandatory = $true)][string]$Scenario)

  $encoded = & python $matrixResolver `
    --matrix $matrix `
    --profile platform `
    --platform windows `
    --scenario $Scenario `
    --framework $framework `
    --base64
  if ($LASTEXITCODE -ne 0) {
    throw "无法解析 Windows 联合场景 $Scenario 的能力契约"
  }
  return (($encoded -join "").Trim())
}

function Stop-TestProcessTree {
  param([Diagnostics.Process]$Process)

  if ($null -eq $Process) {
    return
  }
  $Process.Refresh()
  if (-not $Process.HasExited) {
    & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
    $Process.Refresh()
    if (-not $Process.HasExited) {
      $Process.WaitForExit()
    }
  }
}

function Wait-CoordinatedProcesses {
  param(
    [Parameter(Mandatory = $true)][Diagnostics.Process]$FlutterProcess,
    [Parameter(Mandatory = $true)][Diagnostics.Process]$DotnetProcess
  )

  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($ScenarioTimeoutSeconds)
  $timedOut = $false
  $failureDeadline = $null
  while ($true) {
    $FlutterProcess.Refresh()
    $DotnetProcess.Refresh()
    if ($FlutterProcess.HasExited -and $DotnetProcess.HasExited) {
      break
    }
    if ($FlutterProcess.HasExited -and $FlutterProcess.ExitCode -ne 0 -and $null -eq $failureDeadline) {
      $failureDeadline = [DateTimeOffset]::UtcNow.AddSeconds(70)
    }
    if ($DotnetProcess.HasExited -and $DotnetProcess.ExitCode -ne 0 -and $null -eq $failureDeadline) {
      $failureDeadline = [DateTimeOffset]::UtcNow.AddSeconds(70)
    }
    if ($null -ne $failureDeadline -and [DateTimeOffset]::UtcNow -ge $failureDeadline) {
      Stop-TestProcessTree -Process $FlutterProcess
      Stop-TestProcessTree -Process $DotnetProcess
      break
    }
    if ([DateTimeOffset]::UtcNow -ge $deadline) {
      $timedOut = $true
      Stop-TestProcessTree -Process $FlutterProcess
      Stop-TestProcessTree -Process $DotnetProcess
      break
    }
    Start-Sleep -Milliseconds 200
  }
  $FlutterProcess.WaitForExit()
  $DotnetProcess.WaitForExit()
  return @{
    Flutter = $(if ($timedOut) { 124 } else { $FlutterProcess.ExitCode })
    Dotnet = $(if ($timedOut) { 124 } else { $DotnetProcess.ExitCode })
  }
}

function Assert-PassingTrx {
  param([Parameter(Mandatory = $true)][string]$Path)

  [xml]$document = Get-Content -LiteralPath $Path
  $results = @($document.SelectNodes("//*[local-name()='UnitTestResult']"))
  if ($results.Count -ne 1 -or $results[0].outcome -ne "Passed") {
    throw "FlaUI TRX 必须且只能包含一个 Passed 测试"
  }
}

function Add-RunnerCleanupEvidence {
  param([Parameter(Mandatory = $true)][string]$Path)

  $payload = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -AsHashtable
  if (-not $payload.capabilityEvidence.ContainsKey("resourceCleanup")) {
    $payload.capabilityEvidence["resourceCleanup"] = @()
  }
  $payload.capabilityEvidence["resourceCleanup"] += @{
    action = "flutter_test_process_and_native_automation_closed"
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

try {
  & dotnet restore $testProject --locked-mode
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
  & dotnet build $testProject --configuration Release --no-restore
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  $env:LDDC_IT_RUN_ID = $runId
  $env:LDDC_FIXTURE_PATH = $fixture
  $env:LDDC_NATIVE_EVIDENCE_DIR = $evidenceDir
  $env:LDDC_NATIVE_SYNC_DIR = $syncDir

  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $action = $entry.Action
    $flutterTarget = $entry.Target
    $method = $entry.Method
    $capabilitiesB64 = Resolve-CapabilityContract -Scenario $scenario
    $flutterJsonl = Join-Path $rawDir "$scenario.jsonl"
    $trxPath = Join-Path $rawDir "$scenario.trx"
    $evidencePath = Join-Path $evidenceDir "$scenario.json"
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    $junitPath = Join-Path $junitDir "$scenario.xml"

    foreach ($path in @($flutterJsonl, $trxPath, $evidencePath, $scenarioPath, $junitPath)) {
      Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }

    $dotnetArguments = @(
      "test", $testProject,
      "--configuration", "Release",
      "--no-build",
      "--no-restore",
      "--filter", "FullyQualifiedName=$method",
      "--results-directory", $rawDir,
      "--logger", "trx;LogFileName=$scenario.trx"
    )
    $flutterArguments = @(
      "test", $flutterTarget,
      "-d", "windows",
      "-r", "expanded",
      "--file-reporter", "json:$flutterJsonl",
      "--dart-define=LDDC_IT_PROFILE=platform",
      "--dart-define=LDDC_IT_DEVICE=windows",
      "--dart-define=LDDC_IT_RUN_ID=$runId",
      "--dart-define=LDDC_IT_FRAMEWORK=$framework",
      "--dart-define=LDDC_IT_CAPABILITIES_B64=$capabilitiesB64",
      "--dart-define=LDDC_IT_REPORT_DIR=$scenarioDir",
      "--dart-define=LDDC_IT_WORKSPACE_ROOT=$sandboxRoot",
      "--dart-define=LDDC_WINDOWS_NATIVE_SYNC_DIR=$syncDir",
      "--dart-define=LDDC_IT_STEP_TIMEOUT_MS=60000",
      "--dart-define=LDDC_WINDOWS_DIALOG_ACTION=$action"
    )

    Write-Host "Running hybrid Windows scenario: $scenario"
    $dotnetProcess = Start-Process `
      -FilePath "dotnet" `
      -ArgumentList $dotnetArguments `
      -WorkingDirectory $repoRoot `
      -PassThru `
      -NoNewWindow
    $flutterProcess = $null
    try {
      $flutterProcess = Start-Process `
        -FilePath $flutterCommand `
        -ArgumentList $flutterArguments `
        -WorkingDirectory $appRoot `
        -PassThru `
        -NoNewWindow
      $exitCodes = Wait-CoordinatedProcesses `
        -FlutterProcess $flutterProcess `
        -DotnetProcess $dotnetProcess
    } finally {
      Stop-TestProcessTree -Process $flutterProcess
      Stop-TestProcessTree -Process $dotnetProcess
      if ($null -ne $flutterProcess) {
        $flutterProcess.Dispose()
      }
      $dotnetProcess.Dispose()
    }

    if (-not (Test-Path -LiteralPath $flutterJsonl -PathType Leaf)) {
      throw "$scenario 没有生成 Flutter JSONL"
    }
    if (-not (Test-Path -LiteralPath $trxPath -PathType Leaf)) {
      throw "$scenario 没有生成 FlaUI TRX"
    }
    if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
      throw "$scenario 没有生成 FlaUI evidence JSON"
    }
    if (-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)) {
      throw "$scenario 没有生成 Flutter 场景 JSON"
    }
    Assert-PassingTrx -Path $trxPath

    $remainingLddc = @(Get-Process -Name "lddc" -ErrorAction SilentlyContinue)
    if ($remainingLddc.Count -gt 0) {
      throw "$scenario 结束后残留 LDDC 进程: $($remainingLddc.Id -join ', ')"
    }
    Add-RunnerCleanupEvidence -Path $evidencePath

    $combinedExitCode = if ($exitCodes.Flutter -eq 0 -and $exitCodes.Dotnet -eq 0) { 0 } else { 1 }
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $flutterJsonl `
      --raw-report-type flutter-jsonl `
      --framework $framework `
      --exit-code $combinedExitCode `
      --evidence $evidencePath `
      --matrix $matrix
    $normalizeExitCode = $LASTEXITCODE
    & python $junitConverter --input $flutterJsonl --output $junitPath
    $junitExitCode = $LASTEXITCODE
    if ($normalizeExitCode -ne 0) {
      exit $normalizeExitCode
    }
    if ($junitExitCode -ne 0) {
      exit $junitExitCode
    }
    if ($combinedExitCode -ne 0) {
      exit $combinedExitCode
    }
  }

  & python $verifier `
    --directory $scenarioDir `
    --junit-directory $junitDir `
    --profile platform `
    --platform windows `
    --run-id $runId `
    --matrix $matrix
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} finally {
  $remainingLddc = @(Get-Process -Name "lddc" -ErrorAction SilentlyContinue)
  foreach ($process in $remainingLddc) {
    & taskkill.exe /PID $process.Id /T /F | Out-Null
  }
  if (Test-Path -LiteralPath $sandboxRoot -PathType Container) {
    if (-not $sandboxRoot.StartsWith($sandboxParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "拒绝清理允许目录之外的 Windows 平台测试 sandbox"
    }
    Remove-Item -LiteralPath $sandboxRoot -Recurse -Force
  }
  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
  }
}

Write-Host "Windows hybrid platform reports: $runRoot"
