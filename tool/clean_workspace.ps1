param(
    [switch]$DryRun,
    [string]$PluginRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$flutterRepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$lddcRoot = Join-Path $flutterRepoRoot 'lddc'

if ([string]::IsNullOrWhiteSpace($PluginRoot)) {
    $PluginRoot = Join-Path $flutterRepoRoot '..\..\LDDC_Plugins\foobar2000\foo_lddc'
}
$pluginRootPath = [System.IO.Path]::GetFullPath($PluginRoot)

function Test-InsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar

    # 清理脚本只允许删除根目录内部的 allowlist 目标，避免路径拼错时删到仓库外。
    return $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Add-CleanupTarget {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-InsideRoot -Path $fullPath -Root $Root)) {
        throw "拒绝清理根目录外路径：$fullPath"
    }

    $Targets.Add([pscustomobject]@{
        Path = $fullPath
        Root = [System.IO.Path]::GetFullPath($Root)
        Kind = $Kind
    }) | Out-Null
}

function Add-RecursiveGlobCleanupTargets {
    param(
        [System.Collections.Generic.List[object]]$Targets,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    Get-ChildItem -LiteralPath $Root -Filter $Pattern -Recurse -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Add-CleanupTarget -Targets $Targets -Path $_.FullName -Root $Root -Kind $Kind
        }
}

function Remove-CleanupTarget {
    param(
        [Parameter(Mandatory = $true)]$Target
    )

    if (-not (Test-InsideRoot -Path $Target.Path -Root $Target.Root)) {
        throw "删除前二次校验失败：$($Target.Path)"
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] $($Target.Kind): $($Target.Path)"
        return $true
    }

    Write-Host "[REMOVE] $($Target.Kind): $($Target.Path)"
    try {
        Remove-Item -LiteralPath $Target.Path -Recurse -Force
        return $true
    } catch {
        Write-Warning "清理失败：$($Target.Path)；原因：$($_.Exception.Message)"
        return $false
    }
}

if (-not (Test-Path -LiteralPath $lddcRoot)) {
    throw "找不到 Flutter 主工程目录：$lddcRoot"
}
if (-not (Test-Path -LiteralPath $pluginRootPath)) {
    throw "找不到 foo_lddc 插件目录：$pluginRootPath"
}

$targets = [System.Collections.Generic.List[object]]::new()

# Flutter/Dart/Gradle/IDE 产物会被工具自动重建，保留它们只会拖慢全仓搜索和人工审查。
Add-CleanupTarget -Targets $targets -Path (Join-Path $lddcRoot '.dart_tool') -Root $lddcRoot -Kind 'flutter-cache'
Add-CleanupTarget -Targets $targets -Path (Join-Path $lddcRoot 'build') -Root $lddcRoot -Kind 'flutter-build'
Add-CleanupTarget -Targets $targets -Path (Join-Path $lddcRoot 'android\.gradle') -Root $lddcRoot -Kind 'android-gradle-cache'
Add-CleanupTarget -Targets $targets -Path (Join-Path $lddcRoot 'android\.kotlin\errors') -Root $lddcRoot -Kind 'android-kotlin-errors'
Add-CleanupTarget -Targets $targets -Path (Join-Path $lddcRoot '.idea') -Root $lddcRoot -Kind 'ide-cache'
Add-CleanupTarget -Targets $targets -Path (Join-Path $lddcRoot '.flutter-plugins-dependencies') -Root $lddcRoot -Kind 'flutter-plugin-snapshot'
Add-RecursiveGlobCleanupTargets -Targets $targets -Root $lddcRoot -Pattern '*.iml' -Kind 'ide-project-file'

# 插件根目录中的 VS 缓存和输出目录不属于源码；可交付组件应由 release artifact 管理。
Add-CleanupTarget -Targets $targets -Path (Join-Path $pluginRootPath '.vs') -Root $pluginRootPath -Kind 'vs-cache'
Add-CleanupTarget -Targets $targets -Path (Join-Path $pluginRootPath 'foo_lddc') -Root $pluginRootPath -Kind 'plugin-intermediate'
Add-CleanupTarget -Targets $targets -Path (Join-Path $pluginRootPath 'Release') -Root $pluginRootPath -Kind 'plugin-build'
Add-CleanupTarget -Targets $targets -Path (Join-Path $pluginRootPath 'Release FB2K') -Root $pluginRootPath -Kind 'plugin-build'
Add-CleanupTarget -Targets $targets -Path (Join-Path $pluginRootPath 'x64') -Root $pluginRootPath -Kind 'plugin-build'
Add-CleanupTarget -Targets $targets -Path (Join-Path $pluginRootPath 'foo_lddc.vcxproj.user') -Root $pluginRootPath -Kind 'vs-user-file'

$sdkRoot = Join-Path $pluginRootPath 'SDK'
if (Test-Path -LiteralPath $sdkRoot) {
    $sdkBuildDirNames = @('x64', 'x86', 'Win32', 'ARM', 'ARM64', 'Debug', 'Release', 'obj', 'bin')
    Get-ChildItem -LiteralPath $sdkRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $sdkBuildDirNames -contains $_.Name } |
        Sort-Object FullName -Descending |
        ForEach-Object {
            Add-CleanupTarget -Targets $targets -Path $_.FullName -Root $pluginRootPath -Kind 'sdk-build'
        }
}

$uniqueTargets = @($targets |
    Sort-Object Path -Unique |
    Sort-Object @{ Expression = { $_.Path.Length }; Descending = $true })

if ($uniqueTargets.Count -eq 0) {
    Write-Host '没有发现需要清理的 allowlist 目标。'
    exit 0
}

Write-Host "清理目标数量：$($uniqueTargets.Count)"
$failedTargets = [System.Collections.Generic.List[string]]::new()
foreach ($target in $uniqueTargets) {
    $ok = Remove-CleanupTarget -Target $target
    if (-not $ok) {
        $failedTargets.Add($target.Path) | Out-Null
    }
}

if ($DryRun) {
    Write-Host 'DryRun 完成：未删除任何文件。'
} else {
    if ($failedTargets.Count -gt 0) {
        Write-Warning "清理完成，但有 $($failedTargets.Count) 个目标失败，通常是仍被 Dart/Flutter/IDE 进程占用。"
        foreach ($failedPath in $failedTargets) {
            Write-Warning "未清理：$failedPath"
        }
        exit 1
    }

    Write-Host '清理完成。'
}
