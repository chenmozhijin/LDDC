param(
  [string]$Device = "",
  [string]$ReportDir = "build/integration_reports/android-native",
  [ValidateRange(60, 900)]
  [int]$ScenarioTimeoutSeconds = 240,
  [string]$GradleInitScript = "",
  [ValidateSet(
    "android_documentsui_select",
    "android_documentsui_cancel",
    "android_documentsui_save",
    "android_documentsui_tree",
    "android_documentsui_lifecycle"
  )]
  [string[]]$ScenarioName = @(),
  [switch]$ValidateReportParser
)

$ErrorActionPreference = "Stop"

function Get-AndroidReportTestCount {
  param(
    [Parameter(Mandatory = $true)]
    [xml]$Document
  )

  $root = $Document.DocumentElement
  if ($null -eq $root) {
    throw "Android JUnit XML 没有根节点"
  }
  # XML 中普遍存在 name 属性，PowerShell XML 适配器会让 $root.Name 返回该属性
  # 而不是元素名。LocalName 来自 DOM 节点本身，可稳定区分两种合法 JUnit 根结构。
  $suites = if ($root.LocalName -eq "testsuite") {
    @($root)
  } elseif ($root.LocalName -eq "testsuites") {
    @($root.SelectNodes("./testsuite"))
  } else {
    throw "Android JUnit XML 根节点必须是 testsuite 或 testsuites"
  }

  $testCount = 0
  foreach ($suite in $suites) {
    # PowerShell 的 XML 属性适配器在不同根结构下可能返回字符串、节点集合或
    # 空值。直接读取 XmlElement 属性可避免真实 tests=1 失败被误判为未启动，
    # 从而违反“只有零测试基础设施失败允许重试一次”的契约。
    $testsText = $suite.GetAttribute("tests")
    $suiteTestCount = 0
    if (-not [int]::TryParse($testsText, [ref]$suiteTestCount) -or $suiteTestCount -lt 0) {
      throw "Android JUnit tests 属性无效：'$testsText'"
    }
    $testCount += $suiteTestCount
  }
  return $testCount
}

function Test-AndroidReportStarted {
  param(
    [Parameter(Mandatory = $true)]
    [IO.FileInfo]$Report
  )

  try {
    [xml]$document = Get-Content -LiteralPath $Report.FullName -Raw
    return (Get-AndroidReportTestCount -Document $document) -gt 0
  } catch {
    return $false
  }
}

function Test-ShouldRetryAndroidScenario {
  param(
    [Parameter(Mandatory = $true)][int]$Attempt,
    [Parameter(Mandatory = $true)][bool]$TestStarted,
    [string]$FailureCategory = "",
    [int]$NativeActionCount = 0
  )

  if ($Attempt -ne 0) {
    return $false
  }
  if (-not $TestStarted) {
    return $true
  }
  return $FailureCategory -eq "hosted_system_anr" -and $NativeActionCount -eq 0
}

if ($ValidateReportParser) {
  $cases = @(
    @{
      Name = "零测试允许基础设施重试"
      Xml = '<testsuite name="zero" tests="0" failures="0" errors="0" skipped="0" />'
      Started = $false
    },
    @{
      Name = "真实失败禁止重试"
      Xml = '<testsuite name="failed" tests="1" failures="1" errors="0" skipped="0" />'
      Started = $true
    },
    @{
      Name = "真实成功禁止重试"
      Xml = '<testsuites><testsuite name="passed" tests="1" failures="0" errors="0" skipped="0" /></testsuites>'
      Started = $true
    }
  )
  foreach ($case in $cases) {
    [xml]$document = $case.Xml
    $started = (Get-AndroidReportTestCount -Document $document) -gt 0
    if ($started -ne $case.Started) {
      throw "Android JUnit parser 自检失败：$($case.Name)"
    }
  }
  $retryCases = @(
    @{ Name = "零测试基础设施失败"; Started = $false; Category = ""; Actions = 0; Retry = $true },
    @{ Name = "零动作系统 ANR"; Started = $true; Category = "hosted_system_anr"; Actions = 0; Retry = $true },
    @{ Name = "已有动作系统 ANR"; Started = $true; Category = "hosted_system_anr"; Actions = 1; Retry = $false },
    @{ Name = "DocumentsUI 确定性失败"; Started = $true; Category = "documents_ui_failure"; Actions = 0; Retry = $false },
    @{ Name = "资源清理失败"; Started = $true; Category = "resource_cleanup_failure"; Actions = 0; Retry = $false },
    @{ Name = "业务失败"; Started = $true; Category = "application_failure"; Actions = 0; Retry = $false },
    @{ Name = "第二次失败"; Started = $true; Category = "hosted_system_anr"; Actions = 0; Retry = $false; Attempt = 1 }
  )
  foreach ($case in $retryCases) {
    $attempt = if ($case.ContainsKey("Attempt")) { [int]$case.Attempt } else { 0 }
    $actual = Test-ShouldRetryAndroidScenario `
      -Attempt $attempt `
      -TestStarted $case.Started `
      -FailureCategory $case.Category `
      -NativeActionCount $case.Actions
    if ($actual -ne $case.Retry) {
      throw "Android 重试契约自检失败：$($case.Name)"
    }
  }
  Write-Output "Android JUnit parser 自检通过：tests=0 可重试，tests=1 成功或失败均不重试。"
  exit 0
}

if ([string]::IsNullOrWhiteSpace($Device)) {
  throw "必须显式指定 Android device"
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$androidRoot = Join-Path $appRoot "android"
$normalizer = Join-Path $repoRoot "tool/test/normalize_integration_report.py"
$verifier = Join-Path $repoRoot "tool/test/verify_integration_reports.py"
$matrix = Join-Path $repoRoot "tool/test/platform_capability_matrix.json"
$gradle = Join-Path $androidRoot $(if ($IsWindows) { "gradlew.bat" } else { "gradlew" })

# CI 通常会把 adb 放入 PATH，但本地提权或非交互 shell 可能不会继承该 PATH。
# 这里复用 Android 标准的 SDK 环境变量和 local.properties，只解析运行时路径，
# 不在脚本或测试报告中固化开发机的绝对 SDK 目录。
$adbCommand = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue
$adb = if ($null -ne $adbCommand) { $adbCommand.Source } else { $null }
$sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME) | Where-Object {
  -not [string]::IsNullOrWhiteSpace($_)
}
$localProperties = Join-Path $androidRoot "local.properties"
if (Test-Path -LiteralPath $localProperties -PathType Leaf) {
  $sdkProperty = Get-Content -LiteralPath $localProperties | Where-Object {
    $_ -match '^sdk\.dir='
  } | Select-Object -First 1
  if ($null -ne $sdkProperty) {
    $sdkRoot = ($sdkProperty -split '=', 2)[1].Replace('\\', '\').Replace('\:', ':')
    $sdkRoots += $sdkRoot
  }
}
if ([string]::IsNullOrWhiteSpace($adb)) {
  $adbFileName = if ($IsWindows) { "adb.exe" } else { "adb" }
  foreach ($sdkRoot in $sdkRoots) {
    $candidate = Join-Path $sdkRoot "platform-tools/$adbFileName"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      $adb = (Resolve-Path -LiteralPath $candidate).Path
      break
    }
  }
}
if ([string]::IsNullOrWhiteSpace($adb)) {
  throw "找不到 adb；请配置 PATH、ANDROID_SDK_ROOT、ANDROID_HOME 或 android/local.properties"
}
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}
if (-not [string]::IsNullOrWhiteSpace($GradleInitScript)) {
  if (-not [IO.Path]::IsPathRooted($GradleInitScript)) {
    $GradleInitScript = Join-Path $repoRoot $GradleInitScript
  }
  $GradleInitScript = (Resolve-Path -LiteralPath $GradleInitScript).Path
}

$runId = "platform-android-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Join-Path $ReportDir $runId
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$diagnosticsDir = Join-Path $runRoot "diagnostics"
foreach ($directory in @($scenarioDir, $rawDir, $junitDir, $diagnosticsDir)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$state = ((& $adb -s $Device get-state) -join "").Trim()
if ($LASTEXITCODE -ne 0 -or $state -ne "device") {
  throw "Android device '$Device' 不可用"
}

$scenarios = @(
  @{
    Name = "android_documentsui_select"
    Method = "semanticsIdentifierCanOpenDocumentsUiAndSelectRealAudio"
  },
  @{
    Name = "android_documentsui_cancel"
    Method = "documentsUiCancellationReturnsToSameFlutterAction"
  },
  @{
    Name = "android_documentsui_save"
    Method = "documentsUiSavesLyricsAndReadsBackRealOutput"
  },
  @{
    Name = "android_documentsui_tree"
    Method = "documentsUiPersistsAndReleasesTreePermission"
  },
  @{
    Name = "android_documentsui_lifecycle"
    Method = "pendingPickerIsReleasedWhenActivityIsDestroyed"
  }
)
if ($ScenarioName.Count -gt 0) {
  $scenarios = @($scenarios | Where-Object { $_.Name -in $ScenarioName })
}
$overallStatus = 0

function Invoke-BoundedInstrumentation {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Method
  )

  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.UseShellExecute = $false
  $startInfo.WorkingDirectory = $androidRoot
  $arguments = @(
    ":app:connectedDebugAndroidTest",
    "-Pandroid.testInstrumentationRunnerArguments.class=com.cmzj.lddc.DocumentsUiPlatformPocTest#$Method",
    "-Pandroid.testInstrumentationRunnerArguments.lddcRunId=$runId"
  )
  if (-not [string]::IsNullOrWhiteSpace($GradleInitScript)) {
    $arguments += @("--init-script", $GradleInitScript)
  }
  if ($IsWindows) {
    $startInfo.FileName = "cmd.exe"
    foreach ($argument in @("/d", "/c", $gradle) + $arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  } else {
    $startInfo.FileName = $gradle
    foreach ($argument in $arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  try {
    if (-not $process.WaitForExit($ScenarioTimeoutSeconds * 1000)) {
      # 设备通信或 instrumentation 无响应时，必须终止 Gradle/test runner 整棵进程树。
      $process.Kill($true)
      $process.WaitForExit()
      return 124
    }
    return $process.ExitCode
  } finally {
    $process.Dispose()
  }
}

function Find-NewAndroidTestResult {
  param(
    [Parameter(Mandatory = $true)]
    [DateTime]$StartedAt
  )

  $resultRoot = Join-Path $appRoot "build/app/outputs/androidTest-results/connected/debug"
  if (-not (Test-Path -LiteralPath $resultRoot -PathType Container)) {
    return $null
  }
  return Get-ChildItem -LiteralPath $resultRoot -Recurse -File -Filter "TEST-*.xml" `
    | Where-Object { $_.LastWriteTimeUtc -ge $StartedAt.AddSeconds(-2) } `
    | Sort-Object LastWriteTimeUtc -Descending `
    | Select-Object -First 1
}

function Read-LoggedAndroidEvidence {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Scenario
  )

  $logLines = & $adb -s $Device logcat -d -s "LDDC_NATIVE_EVIDENCE:I" "*:S"
  if ($LASTEXITCODE -ne 0) {
    return $null
  }
  $pattern = "LDDC_EVIDENCE\|{0}\|{1}\|(\d+)\|(\d+)\|([A-Za-z0-9+/=]+)" -f `
    [regex]::Escape($runId), `
    [regex]::Escape($Scenario)
  $chunks = @{}
  $expectedCount = $null
  foreach ($line in $logLines) {
    $match = [regex]::Match($line, $pattern)
    if (-not $match.Success) {
      continue
    }
    $index = [int]$match.Groups[1].Value
    $count = [int]$match.Groups[2].Value
    if ($null -ne $expectedCount -and $expectedCount -ne $count) {
      return $null
    }
    $expectedCount = $count
    $chunks[$index] = $match.Groups[3].Value
  }
  if ($null -eq $expectedCount -or $expectedCount -le 0 -or $chunks.Count -ne $expectedCount) {
    return $null
  }
  $encoded = [Text.StringBuilder]::new()
  for ($index = 0; $index -lt $expectedCount; $index += 1) {
    if (-not $chunks.ContainsKey($index)) {
      return $null
    }
    [void]$encoded.Append($chunks[$index])
  }
  try {
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded.ToString()))
  } catch {
    return $null
  }
}

function Get-AndroidEvidenceMetadata {
  param([Parameter(Mandatory = $true)][string]$Scenario)

  $text = Read-LoggedAndroidEvidence -Scenario $Scenario
  if ([string]::IsNullOrWhiteSpace($text)) {
    return $null
  }
  try {
    $payload = $text | ConvertFrom-Json -ErrorAction Stop
    return [pscustomobject]@{
      FailureCategory = [string]$payload.extra.failureCategory
      NativeActionCount = [int]$payload.extra.nativeActionCount
    }
  } catch {
    return $null
  }
}

function Restart-HostedAndroidEmulator {
  # Quickstep ANR 是 hosted emulator 的系统进程故障。仅在 evidence 证明资源
  # 已回基线且原生动作数为零时重启一次本次 emulator；不清空应用数据、不改
  # fixture，也不重试已经执行过业务动作或资源清理失败的场景。
  & $adb -s $Device reboot
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Android hosted emulator 重启命令失败"
    return $false
  }

  $deadline = [DateTimeOffset]::UtcNow.AddSeconds(120)
  while ([DateTimeOffset]::UtcNow -lt $deadline) {
    $deviceState = ((& $adb -s $Device get-state 2>$null) -join "").Trim()
    if ($LASTEXITCODE -eq 0 -and $deviceState -eq "device") {
      $bootCompleted = ((& $adb -s $Device shell getprop sys.boot_completed 2>$null) -join "").Trim()
      if ($LASTEXITCODE -eq 0 -and $bootCompleted -eq "1") {
        & $adb -s $Device shell input keyevent 3 | Out-Null
        Start-Sleep -Seconds 3
        return $true
      }
    }
    Start-Sleep -Seconds 2
  }
  Write-Warning "Android hosted emulator 未在 120 秒内完成重启"
  return $false
}

Push-Location $androidRoot
try {
  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $method = $entry.Method
    & $adb -s $Device logcat -c
    $rawResult = $null
    $testExitCode = 1
    $testStarted = $false
    $infrastructureRetryPerformed = $false
    for ($attempt = 0; $attempt -lt 2; $attempt += 1) {
      $startedAt = [DateTime]::UtcNow
      $testExitCode = Invoke-BoundedInstrumentation -Method $method
      $rawResult = Find-NewAndroidTestResult -StartedAt $startedAt
      $testStarted = $null -ne $rawResult -and (Test-AndroidReportStarted -Report $rawResult)
      $evidenceMetadata = if ($testStarted) {
        Get-AndroidEvidenceMetadata -Scenario $scenario
      } else {
        $null
      }
      $hostedSystemAnr = $null -ne $evidenceMetadata `
        -and $evidenceMetadata.FailureCategory -eq "hosted_system_anr" `
        -and $evidenceMetadata.NativeActionCount -eq 0
      $shouldRetry = Test-ShouldRetryAndroidScenario `
        -Attempt $attempt `
        -TestStarted $testStarted `
        -FailureCategory $(if ($hostedSystemAnr) { "hosted_system_anr" } else { "" }) `
        -NativeActionCount $(if ($null -ne $evidenceMetadata) { $evidenceMetadata.NativeActionCount } else { 0 })
      if ($shouldRetry) {
        # UTP 可能在 onBeforeAll 连接设备失败后仍生成 tests=0 的 XML。它与完全
        # 缺报告一样都没有执行测试，允许重试一次；一旦测试数大于零，无论
        # 成败都必须保留真实结果。唯一例外是 evidence 明确证明 Quickstep
        # system ANR 且资源已回基线、原生动作数为零，此时重启一次 emulator。
        if ($hostedSystemAnr) {
          $infrastructureRetryPerformed = Restart-HostedAndroidEmulator
          if (-not $infrastructureRetryPerformed) {
            break
          }
        } else {
          Start-Sleep -Seconds 5
        }
        & $adb -s $Device logcat -c
        continue
      }
      break
    }
    $rawPath = Join-Path $rawDir "$scenario.xml"
    $junitPath = Join-Path $junitDir "$scenario.xml"
    if ($null -eq $rawResult) {
      # 两次启动都没有原始 XML 时仍要为当前场景留下 tests=0 的诚实证据，
      # 让 normalizer 明确记录 testStarted=false。不能直接 throw，否则后续互相
      # 独立的 DocumentsUI 场景会被短路，也不能构造伪测试用例冒充已执行。
      [xml]$missingReport = '<testsuite name="android-instrumentation-missing" tests="0" failures="0" errors="0" skipped="0" />'
      $missingReport.Save($rawPath)
      $testStarted = $false
      if ($testExitCode -eq 0) {
        $testExitCode = 1
      }
    } else {
      Copy-Item -LiteralPath $rawResult.FullName -Destination $rawPath -Force
    }
    Copy-Item -LiteralPath $rawPath -Destination $junitPath -Force

    $relativeEvidence = "cache/lddc_native_evidence/$runId/$scenario.json"
    $evidenceLines = & $adb -s $Device exec-out run-as com.cmzj.lddc cat $relativeEvidence
    $evidencePullExitCode = $LASTEXITCODE
    $evidencePath = Join-Path $rawDir "$scenario.evidence.json"
    $evidenceText = ($evidenceLines -join [Environment]::NewLine)

    $hasValidEvidence = $false
    if ($evidencePullExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($evidenceText)) {
      try {
        $parsedEvidence = $evidenceText | ConvertFrom-Json -ErrorAction Stop
        $hasValidEvidence = $null -ne $parsedEvidence -and $parsedEvidence -is [PSCustomObject]
      } catch {
        $hasValidEvidence = $false
      }
    }
    if (-not $hasValidEvidence) {
      $loggedEvidenceText = Read-LoggedAndroidEvidence -Scenario $scenario
      if (-not [string]::IsNullOrWhiteSpace($loggedEvidenceText)) {
        try {
          $parsedEvidence = $loggedEvidenceText | ConvertFrom-Json -ErrorAction Stop
          $hasValidEvidence = $null -ne $parsedEvidence -and $parsedEvidence -is [PSCustomObject]
          if ($hasValidEvidence) {
            $evidenceText = $loggedEvidenceText
          }
        } catch {
          $hasValidEvidence = $false
        }
      }
    }

    [IO.File]::WriteAllText(
      $evidencePath,
      $evidenceText,
      [Text.UTF8Encoding]::new($false)
    )

    $effectiveExitCode = $testExitCode
    if (-not $hasValidEvidence) {
      # @Before 等原生准备阶段可能早于测试自身的 reporter 失败。此时 JUnit 已证明
      # 测试实际启动，runner 生成最小失败 evidence 以保留根因和诊断链；它绝不能
      # 提供真实能力证据，也不能让失败被重试或误判为成功。
      $fallbackEvidence = [ordered]@{
        runId = $runId
        scenario = $scenario
        profile = "platform"
        platform = "android"
        framework = "uiautomator"
        steps = @(
          [ordered]@{
            name = "instrumentation_failed_before_evidence"
            success = $false
            error = "原生测试未生成有效 evidence；请查看 JUnit 与 logcat"
          }
        )
        capabilityEvidence = @{}
        resources = [ordered]@{
          baseline = @{}
          final = @{}
          thresholds = @{}
        }
        artifacts = @()
        extra = [ordered]@{
          evidencePullExitCode = $evidencePullExitCode
        }
      }
      $fallbackJson = $fallbackEvidence | ConvertTo-Json -Depth 8
      [IO.File]::WriteAllText(
        $evidencePath,
        $fallbackJson,
        [Text.UTF8Encoding]::new($false)
      )
      if ($effectiveExitCode -eq 0) {
        $effectiveExitCode = 1
      }
    }
    if ($infrastructureRetryPerformed -and $hasValidEvidence) {
      try {
        $evidencePayload = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
        if ($null -eq $evidencePayload.extra) {
          $evidencePayload | Add-Member -NotePropertyName extra -NotePropertyValue ([pscustomobject]@{})
        }
        $evidencePayload.extra | Add-Member `
          -NotePropertyName infrastructureRetry `
          -NotePropertyValue "hosted_system_anr_recovery" `
          -Force
        [IO.File]::WriteAllText(
          $evidencePath,
          ($evidencePayload | ConvertTo-Json -Depth 20),
          [Text.UTF8Encoding]::new($false)
        )
      } catch {
        Write-Warning "无法记录 Android system ANR 恢复证据: $($_.Exception.Message)"
        $effectiveExitCode = 1
      }
    }
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $rawPath `
      --raw-report-type android-junit-xml `
      --framework uiautomator `
      --exit-code $effectiveExitCode `
      --evidence $evidencePath `
      --failure-junit $junitPath `
      --matrix $matrix
    $normalizeExitCode = $LASTEXITCODE

    if ($effectiveExitCode -ne 0 -or $normalizeExitCode -ne 0) {
      & $adb -s $Device logcat -d | Out-File `
        -LiteralPath (Join-Path $diagnosticsDir "$scenario-logcat.txt") `
        -Encoding utf8
      & $adb -s $Device shell uiautomator dump /sdcard/lddc-window.xml
      & $adb -s $Device pull /sdcard/lddc-window.xml `
        (Join-Path $diagnosticsDir "$scenario-window.xml") | Out-Null
      $overallStatus = 1
      Write-Warning "Android DocumentsUI 场景 $scenario 失败，继续收集其余独立场景"
    }
  }
} finally {
  & $adb -s $Device shell am force-stop com.cmzj.lddc | Out-Null
  Pop-Location
}

& python $verifier `
  --directory $scenarioDir `
  --junit-directory $junitDir `
  --profile platform `
  --platform android `
  --run-id $runId `
  --matrix $matrix
if ($LASTEXITCODE -ne 0) {
  $overallStatus = 1
}

Write-Host "Android platform reports: $runRoot"
exit $overallStatus
