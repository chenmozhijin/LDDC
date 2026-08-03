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
$gradle = if ($IsWindows) { ".\gradlew.bat" } else { "./gradlew" }

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

Push-Location $androidRoot
try {
  foreach ($entry in $scenarios) {
    $scenario = $entry.Name
    $method = $entry.Method
    & $adb -s $Device logcat -c
    $rawResult = $null
    $testExitCode = 1
    $testStarted = $false
    for ($attempt = 0; $attempt -lt 2 -and -not $testStarted; $attempt += 1) {
      $startedAt = [DateTime]::UtcNow
      $testExitCode = Invoke-BoundedInstrumentation -Method $method
      $rawResult = Find-NewAndroidTestResult -StartedAt $startedAt
      $testStarted = $null -ne $rawResult -and (Test-AndroidReportStarted -Report $rawResult)
      if (-not $testStarted -and $attempt -eq 0) {
        # UTP 可能在 onBeforeAll 连接设备失败后仍生成 tests=0 的 XML。它与完全
        # 缺报告一样都没有执行测试，允许重试一次；一旦测试数大于零，无论
        # 成败都必须保留真实结果，不能通过重跑掩盖。
        Start-Sleep -Seconds 5
      }
    }
    if ($null -eq $rawResult) {
      throw "Android instrumentation 两次启动均未生成 JUnit XML；最后退出码为 $testExitCode"
    }
    $rawPath = Join-Path $rawDir "$scenario.xml"
    $junitPath = Join-Path $junitDir "$scenario.xml"
    Copy-Item -LiteralPath $rawResult.FullName -Destination $rawPath -Force
    Copy-Item -LiteralPath $rawResult.FullName -Destination $junitPath -Force

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
    $scenarioPath = Join-Path $scenarioDir "$scenario.json"
    & python $normalizer `
      --scenario-report $scenarioPath `
      --raw-report $rawPath `
      --raw-report-type android-junit-xml `
      --framework uiautomator `
      --exit-code $effectiveExitCode `
      --evidence $evidencePath `
      --matrix $matrix
    $normalizeExitCode = $LASTEXITCODE

    if ($effectiveExitCode -ne 0 -or $normalizeExitCode -ne 0) {
      & $adb -s $Device logcat -d | Out-File `
        -LiteralPath (Join-Path $diagnosticsDir "$scenario-logcat.txt") `
        -Encoding utf8
      & $adb -s $Device shell uiautomator dump /sdcard/lddc-window.xml
      & $adb -s $Device pull /sdcard/lddc-window.xml `
        (Join-Path $diagnosticsDir "$scenario-window.xml") | Out-Null
      if ($normalizeExitCode -ne 0) {
        exit $normalizeExitCode
      }
      exit $effectiveExitCode
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
  exit $LASTEXITCODE
}

Write-Host "Android platform reports: $runRoot"
