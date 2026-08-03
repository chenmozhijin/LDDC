param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("windows", "macos", "linux")]
  [string]$Platform,
  [ValidateSet(3, 20)]
  [int]$LoopCount = 3,
  [string]$ReportDir = "build/integration_reports/platform-media-resource",
  [ValidateRange(90, 900)]
  [int]$ScenarioTimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$appRoot = Join-Path $repoRoot "lddc"
$testRoot = Join-Path $repoRoot "packages/lddc_lyrics_runtime"
$fixtureRoot = (Resolve-Path (Join-Path $appRoot "integration_test/fixtures/media")).Path
if (-not [IO.Path]::IsPathRooted($ReportDir)) {
  $ReportDir = Join-Path $appRoot $ReportDir
}

$runId = "platform-$Platform-media-{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), `
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$runRoot = Join-Path $ReportDir $runId
$scenarioDir = Join-Path $runRoot "scenarios"
$rawDir = Join-Path $runRoot "raw"
$junitDir = Join-Path $runRoot "junit"
$evidenceDir = Join-Path $runRoot "evidence"
$sandboxParent = [IO.Path]::GetFullPath((Join-Path $appRoot "build/native_test_sandboxes"))
$sandboxRoot = [IO.Path]::GetFullPath((Join-Path $sandboxParent $runId))
if (-not $sandboxRoot.StartsWith($sandboxParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw "媒体测试 sandbox 超出允许目录"
}
foreach ($directory in @($scenarioDir, $rawDir, $junitDir, $evidenceDir)) {
  New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$environmentNames = @(
  "LDDC_IT_RUN_ID", "LDDC_IT_PLATFORM", "LDDC_NATIVE_EVIDENCE_DIR",
  "LDDC_MEDIA_FIXTURE_DIR", "LDDC_MEDIA_WORK_DIR", "LDDC_MEDIA_LOOP_COUNT"
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
  $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

$env:LDDC_IT_RUN_ID = $runId
$env:LDDC_IT_PLATFORM = $Platform
$env:LDDC_NATIVE_EVIDENCE_DIR = $evidenceDir
$env:LDDC_MEDIA_FIXTURE_DIR = $fixtureRoot
$env:LDDC_MEDIA_WORK_DIR = Join-Path $sandboxRoot "media"
$env:LDDC_MEDIA_LOOP_COUNT = $LoopCount.ToString([Globalization.CultureInfo]::InvariantCulture)

$rawPath = Join-Path $rawDir "platform_media_resource.jsonl"
$evidencePath = Join-Path $evidenceDir "platform_media_resource.json"
$scenarioPath = Join-Path $scenarioDir "platform_media_resource.json"
$junitPath = Join-Path $junitDir "platform_media_resource.xml"

function Invoke-BoundedDartTest {
  $dartCommand = (Get-Command dart).Source
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.UseShellExecute = $false
  $startInfo.WorkingDirectory = $testRoot
  $arguments = @(
    "test",
    "platform_test/platform_media_resource_test.dart",
    "--file-reporter=json:$rawPath"
  )
  if ($IsWindows -and $dartCommand.EndsWith(".bat")) {
    $startInfo.FileName = "cmd.exe"
    foreach ($argument in @("/d", "/c", $dartCommand) + $arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  } else {
    $startInfo.FileName = $dartCommand
    foreach ($argument in $arguments) {
      [void]$startInfo.ArgumentList.Add($argument)
    }
  }
  $process = [Diagnostics.Process]::Start($startInfo)
  try {
    if (-not $process.WaitForExit($ScenarioTimeoutSeconds * 1000)) {
      # native asset 或测试框架失去响应时必须回收完整进程树，不能把超时伪装成跳过。
      $process.Kill($true)
      $process.WaitForExit()
      return 124
    }
    return $process.ExitCode
  } finally {
    $process.Dispose()
  }
}

try {
  $testExitCode = Invoke-BoundedDartTest
  if (-not (Test-Path -LiteralPath $rawPath -PathType Leaf)) {
    # 首次 native-assets build hook 也受场景硬超时约束。即使它在测试开始前
    # 超时，也必须生成可上传的失败 scenario/JUnit，不能只留下空 artifact。
    & python (Join-Path $repoRoot "tool/test/normalize_integration_report.py") `
      --scenario-report $scenarioPath `
      --raw-report $rawPath `
      --raw-report-type dart-jsonl `
      --framework dart-native-assets `
      --exit-code $testExitCode `
      --evidence $evidencePath `
      --matrix (Join-Path $repoRoot "tool/test/platform_capability_matrix.json") `
      --run-id $runId `
      --scenario platform_media_resource `
      --profile platform `
      --platform $Platform `
      --failure-junit $junitPath
    throw "媒体资源测试没有生成 Dart JSONL"
  }
  if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
    throw "媒体资源测试没有生成 evidence JSON"
  }

  & python (Join-Path $repoRoot "tool/test/normalize_integration_report.py") `
    --scenario-report $scenarioPath `
    --raw-report $rawPath `
    --raw-report-type dart-jsonl `
    --framework dart-native-assets `
    --exit-code $testExitCode `
    --evidence $evidencePath `
    --matrix (Join-Path $repoRoot "tool/test/platform_capability_matrix.json")
  $normalizeExitCode = $LASTEXITCODE
  & python (Join-Path $repoRoot "tool/test/json_report_to_junit.py") `
    --input $rawPath `
    --output $junitPath
  $junitExitCode = $LASTEXITCODE

  if ($testExitCode -ne 0) { exit $testExitCode }
  if ($normalizeExitCode -ne 0) { exit $normalizeExitCode }
  if ($junitExitCode -ne 0) { exit $junitExitCode }

  & python (Join-Path $repoRoot "tool/test/verify_integration_reports.py") `
    --directory $scenarioDir `
    --junit-directory $junitDir `
    --profile platform `
    --platform $Platform `
    --run-id $runId `
    --matrix (Join-Path $repoRoot "tool/test/platform_capability_matrix.json")
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  if (Test-Path -LiteralPath $sandboxRoot -PathType Container) {
    # 递归删除前再次核对绝对路径，避免异常 runId 或路径解析误删工作区其他内容。
    if (-not $sandboxRoot.StartsWith($sandboxParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
      throw "拒绝清理允许目录之外的媒体测试 sandbox"
    }
    Remove-Item -LiteralPath $sandboxRoot -Recurse -Force
  }
  foreach ($name in $environmentNames) {
    [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
  }
}

Write-Host "Platform media resource reports: $runRoot"
