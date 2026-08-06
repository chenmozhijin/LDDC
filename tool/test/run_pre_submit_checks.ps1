[CmdletBinding()]
param(
  [string]$ReportRoot = ".internal_docs/pre-submit",
  [switch]$SkipWindowsIntegration
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$runId = "{0}-{1}" -f `
  [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(),
  ([Guid]::NewGuid().ToString("N").Substring(0, 8))
$absoluteReportRoot = if ([IO.Path]::IsPathRooted($ReportRoot)) {
  [IO.Path]::GetFullPath($ReportRoot)
} else {
  [IO.Path]::GetFullPath((Join-Path $repoRoot $ReportRoot))
}
$runRoot = Join-Path $absoluteReportRoot $runId
$outputRoot = Join-Path $runRoot "output"
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
# 把 compileall 的字节码写入被忽略的临时根，避免触碰仓库内可能被测试进程
# 占用的 __pycache__，也不会把本地 Python 产物带入候选文件。
$env:PYTHONPYCACHEPREFIX = Join-Path $repoRoot ".tmp/pre-submit-pycache"
New-Item -ItemType Directory -Force -Path $env:PYTHONPYCACHEPREFIX | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$overallExitCode = 0

function Invoke-PreSubmitCheck {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [string]$WorkingDirectory = $repoRoot,
    [bool]$Required = $true
  )

  $safeName = $Name -replace "[^A-Za-z0-9_.-]", "-"
  $stdoutPath = Join-Path $outputRoot "$safeName.stdout.log"
  $stderrPath = Join-Path $outputRoot "$safeName.stderr.log"
  $startedAt = [DateTimeOffset]::UtcNow
  $exitCode = 125
  $status = "failed"
  $errorMessage = $null
  try {
    $command = Get-Command $FilePath -ErrorAction SilentlyContinue
    if ($null -eq $command -and -not [IO.File]::Exists($FilePath)) {
      throw "找不到命令: $FilePath"
    }
    # 使用 PowerShell 原生调用而不是 Start-Process。Dart/Flutter 在 Windows
    # 通常解析为 .bat，Start-Process 交给 cmd /c 后可能留下不会结束的包装进程；
    # 调用运算符能正确等待 bat 的真实退出码，并保留独立 stdout/stderr。
    Push-Location $WorkingDirectory
    try {
      & $FilePath @ArgumentList 1> $stdoutPath 2> $stderrPath
      $exitCode = $LASTEXITCODE
    } finally {
      Pop-Location
    }
    if ($exitCode -eq 0) {
      $status = "passed"
    } else {
      $errorMessage = "命令退出码为 $exitCode"
    }
  } catch {
    $errorMessage = $_.Exception.Message
  }
  $endedAt = [DateTimeOffset]::UtcNow
  $entry = [ordered]@{
    name = $Name
    command = @($FilePath) + $ArgumentList
    required = $Required
    status = $status
    exitCode = $exitCode
    startedAt = $startedAt.ToString("o")
    endedAt = $endedAt.ToString("o")
    durationSeconds = [Math]::Round(($endedAt - $startedAt).TotalSeconds, 3)
    stdout = [IO.Path]::GetRelativePath($repoRoot, $stdoutPath).Replace("\", "/")
    stderr = [IO.Path]::GetRelativePath($repoRoot, $stderrPath).Replace("\", "/")
    error = $errorMessage
  }
  $results.Add($entry)
  if ($Required -and $status -ne "passed") {
    $script:overallExitCode = 1
  }
}

function Add-HostedOnlyCheck {
  param([Parameter(Mandatory = $true)][string]$Name, [string]$Reason)
  $results.Add([ordered]@{
      name = $Name
      command = @()
      required = $false
      status = "hosted-only"
      exitCode = $null
      startedAt = $null
      endedAt = $null
      durationSeconds = 0
      stdout = $null
      stderr = $null
      error = $Reason
    })
}

Push-Location $repoRoot
try {
  Invoke-PreSubmitCheck -Name "dart-format" -FilePath "dart" -ArgumentList @(
    "format", "--output=none", "--set-exit-if-changed",
    "lddc/lib", "lddc/test", "lddc/integration_test", "packages"
  )
  Invoke-PreSubmitCheck -Name "dart-analyze" -FilePath "dart" -ArgumentList @("analyze")
  Invoke-PreSubmitCheck -Name "search-workspace-tests" -FilePath "flutter" -ArgumentList @(
    "test", "packages/lddc_lyrics_flutter/test/search/search_workspace_test.dart"
  )
  Invoke-PreSubmitCheck -Name "desktop-launch-argument-tests" -FilePath "flutter" -ArgumentList @(
    "test", "lddc/test/platform/desktop/service_host/desktop_service_launch_arguments_test.dart"
  )
  Invoke-PreSubmitCheck -Name "integration-driver-tests" -FilePath "flutter" -ArgumentList @(
    "test", "lddc/test/integration_support/integration_drivers_test.dart"
  )
  Invoke-PreSubmitCheck -Name "python-quality-tests" -FilePath "python" -ArgumentList @(
    "-m", "unittest", "discover", "-s", "tool/test", "-p", "test_*.py"
  )
  Invoke-PreSubmitCheck -Name "python-compileall" -FilePath "python" -ArgumentList @(
    "-m", "compileall", "-q", "tool"
  )
  Invoke-PreSubmitCheck -Name "native-test-isolation" -FilePath "python" -ArgumentList @(
    "tool/test/check_native_test_isolation.py"
  )
  $astScript = @"
`$errors = `$null
`$files = @(git ls-files '*.ps1') + @('tool/test/run_pre_submit_checks.ps1')
foreach (`$relative in `$files | Select-Object -Unique) {
  `$path = Join-Path '$repoRoot' `$relative
  if (-not (Test-Path -LiteralPath `$path -PathType Leaf)) { throw "PowerShell 文件不存在: `$relative" }
  [System.Management.Automation.Language.Parser]::ParseFile(`$path, [ref]`$null, [ref]`$errors) | Out-Null
  if (`$errors.Count -gt 0) { throw "PowerShell AST error in `$path" }
}
"@
  Invoke-PreSubmitCheck -Name "powershell-ast" -FilePath "pwsh" -ArgumentList @(
    "-NoProfile", "-Command", $astScript
  )
  $yamlScript = "import pathlib, yaml; [yaml.safe_load(path.read_text(encoding='utf-8')) for path in pathlib.Path('.github/workflows').glob('*.yml')]"
  Invoke-PreSubmitCheck -Name "workflow-yaml" -FilePath "python" -ArgumentList @(
    "-c", $yamlScript
  )
  Invoke-PreSubmitCheck -Name "git-diff-check" -FilePath "git" -ArgumentList @(
    "diff", "--check", "HEAD", "--"
  )
  Invoke-PreSubmitCheck -Name "git-hygiene" -FilePath "python" -ArgumentList @(
    "tool/check_git_hygiene.py"
  )
  if ($SkipWindowsIntegration) {
    Add-HostedOnlyCheck -Name "windows-local-match-integration" `
      -Reason "调用方显式跳过；该项未运行不能作为本地门禁通过证据"
    $overallExitCode = 1
  } else {
    Invoke-PreSubmitCheck -Name "windows-local-match-integration" -FilePath "pwsh" -ArgumentList @(
      "-NoProfile", "-File", (Join-Path $repoRoot "tool/test/run_real_integration.ps1"),
      "-Profile", "offline", "-Device", "windows", "-Platform", "windows",
      "-Targets", "integration_test/local_match_flow_test.dart"
    )
  }
  Add-HostedOnlyCheck -Name "apple-native-ui" `
    -Reason "Windows 无法证明 macOS/iOS 系统 accessibility tree；必须由 hosted XCUITest 验证"
  Add-HostedOnlyCheck -Name "linux-dogtail-ui" `
    -Reason "Windows 无法连接 Linux AT-SPI；必须由 hosted Linux 环境验证"
} finally {
  Pop-Location
  $manifest = [ordered]@{
    schemaVersion = 1
    runId = $runId
    root = [IO.Path]::GetRelativePath($repoRoot, $runRoot).Replace("\", "/")
    completedAt = [DateTimeOffset]::UtcNow.ToString("o")
    status = if ($overallExitCode -eq 0) { "passed_with_hosted_only" } else { "failed" }
    exitCode = $overallExitCode
    checks = @($results)
  }
  [IO.File]::WriteAllText(
    (Join-Path $runRoot "manifest.json"),
    ($manifest | ConvertTo-Json -Depth 30),
    [Text.UTF8Encoding]::new($false)
  )
}

Write-Host "Pre-submit manifest: $runRoot/manifest.json"
exit $overallExitCode
