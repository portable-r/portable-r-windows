# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  make.ps1 - Task runner behind the Makefile                             ║
# ║                                                                         ║
# ║  The Makefile's recipes are one-line calls into this script, which      ║
# ║  reads ARCH/VERSION/RTVERSION from the environment when they are not    ║
# ║  passed as parameters. Versions come from versions.json.                ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Usage: .\make.ps1 <target> [-Arch x64|aarch64|arm64] [-Version x.y.z] [-RtVersion NN]
#        make <target> [ARCH=...] [VERSION=...] [RTVERSION=...]

param(
    [Parameter(Position = 0)]
    [string]$Target = "help",

    [string]$Arch = $(if ($env:ARCH) { $env:ARCH } else { "x64" }),

    [string]$Version = $env:VERSION,

    [string]$RtVersion = $env:RTVERSION
)

$ErrorActionPreference = "Stop"

if ($Arch -eq "arm64") { $Arch = "aarch64" }
if ($Arch -notin @("x64", "aarch64")) {
    Write-Host "x Unknown ARCH '$Arch' (use x64, aarch64 or arm64)" -ForegroundColor Red
    exit 1
}

$build = Join-Path $PSScriptRoot "build.ps1"
$versionsJson = Get-Content (Join-Path $PSScriptRoot "versions.json") -Raw | ConvertFrom-Json
$RVersions = @($versionsJson.r.$Arch)
$RtVersions = @($versionsJson.rtools.PSObject.Properties |
    Where-Object { $_.Name -ne "r_series" -and $_.Value.$Arch.file } |
    ForEach-Object { $_.Name })

function Require($Value, $Name, $Example) {
    if (-not $Value) {
        Write-Host "x $Name is required. Usage: make $Target $Name=$Example" -ForegroundColor Red
        exit 1
    }
}

# Runs build.ps1 once per item; build.ps1 reports failure through its exit
# code (or by throwing), and any failure makes the target fail
function Invoke-Batch($Items, $Label, [scriptblock]$BuildArgs) {
    Write-Host "Building $($Items.Count) $Label ($Arch)" -ForegroundColor White
    $pass = 0; $fail = 0
    foreach ($item in $Items) {
        Write-Host "`n-- $item --" -ForegroundColor White
        $splat = & $BuildArgs $item
        try {
            & $build @splat
            if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
            $pass++
        } catch {
            Write-Host "x $item failed ($_)" -ForegroundColor Red
            $fail++
        }
    }
    Write-Host "`nResults: $pass succeeded, $fail failed" -ForegroundColor White
    if ($fail -gt 0) { exit 1 }
}

# Runs a script and exits with its exit code. Pass a hashtable for named
# parameters (an array would bind "-RVersion" etc. as positional values).
function Invoke-Script($Path, $Arguments) {
    & $Path @Arguments
    exit $LASTEXITCODE
}

function Remove-Artifacts($Patterns) {
    foreach ($p in $Patterns) {
        Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue
    }
}

$rDir = "portable-r-$Version-win-$Arch"
$rtDir = "portable-rtools$RtVersion-win-$Arch"

switch ($Target) {
    "help" {
        Write-Host ""
        Write-Host "  Portable R + Rtools for Windows - Build Targets" -ForegroundColor White
        Write-Host ""
        Write-Host "  R only:" -ForegroundColor DarkGray
        Write-Host "  build VERSION=x.y.z         Build portable R" -ForegroundColor Cyan
        Write-Host "  test VERSION=x.y.z          Test a portable R build" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  R + Rtools:" -ForegroundColor DarkGray
        Write-Host "  build-full VERSION=x.y.z    Build portable R + Rtools" -ForegroundColor Cyan
        Write-Host "  test-full VERSION=x.y.z     Test an R + Rtools build" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Rtools standalone:" -ForegroundColor DarkGray
        Write-Host "  build-rtools RTVERSION=45   Build standalone Rtools" -ForegroundColor Cyan
        Write-Host "  test-rtools RTVERSION=45    Test a standalone Rtools build" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Batch (versions from versions.json):" -ForegroundColor DarkGray
        Write-Host "  build-all                   Build all R versions (R only)" -ForegroundColor Cyan
        Write-Host "  build-all-full              Build all R versions (R + Rtools)" -ForegroundColor Cyan
        Write-Host "  build-all-rtools            Build all Rtools versions" -ForegroundColor Cyan
        Write-Host "  list                        List supported versions" -ForegroundColor Cyan
        Write-Host "  verify VERSION=x.y.z        Quick check of an existing build" -ForegroundColor Cyan
        Write-Host "  clean VERSION=x.y.z         Remove build artifacts for a version" -ForegroundColor Cyan
        Write-Host "  clean-all                   Remove all build artifacts" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  All targets take ARCH=x64 (default), aarch64 or arm64."
        Write-Host ""
        Write-Host "  Examples:"
        Write-Host "    make build VERSION=4.6.1"
        Write-Host "    make build-full VERSION=4.6.1 ARCH=aarch64"
        Write-Host "    make build-rtools RTVERSION=45"
        Write-Host "    make build-all"
        Write-Host ""
    }

    "build" {
        Require $Version "VERSION" "4.6.1"
        Invoke-Script $build @{ RVersion = $Version; Architecture = $Arch }
    }
    "build-full" {
        Require $Version "VERSION" "4.6.1"
        Invoke-Script $build @{ RVersion = $Version; Architecture = $Arch; IncludeRtools = $true }
    }
    "build-rtools" {
        Require $RtVersion "RTVERSION" "45"
        Invoke-Script $build @{ RtoolsOnly = $true; RtoolsVersion = $RtVersion; Architecture = $Arch }
    }

    "build-all" {
        Invoke-Batch $RVersions "R versions" { param($v) @{ RVersion = $v; Architecture = $Arch } }
    }
    "build-all-full" {
        Invoke-Batch $RVersions "R versions (R + Rtools)" { param($v) @{ RVersion = $v; Architecture = $Arch; IncludeRtools = $true } }
    }
    "build-all-rtools" {
        Invoke-Batch $RtVersions "Rtools versions" { param($v) @{ RtoolsOnly = $true; RtoolsVersion = $v; Architecture = $Arch } }
    }

    "test" {
        Require $Version "VERSION" "4.6.1"
        Invoke-Script (Join-Path $PSScriptRoot "tests/run-tests.ps1") @($rDir)
    }
    "test-full" {
        Require $Version "VERSION" "4.6.1"
        Invoke-Script (Join-Path $PSScriptRoot "tests/run-tests.ps1") @("$rDir-full")
    }
    "test-rtools" {
        Require $RtVersion "RTVERSION" "45"
        Invoke-Script (Join-Path $PSScriptRoot "tests/run-rtools-tests.ps1") @($rtDir)
    }

    "verify" {
        Require $Version "VERSION" "4.6.1"
        if (-not (Test-Path $rDir)) { Write-Host "x $rDir not found" -ForegroundColor Red; exit 1 }
        $r = Join-Path $rDir "bin" "Rscript.exe"
        Write-Host "Verifying $rDir" -ForegroundColor White
        & $r --version 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
        & $r -e "cat(R.version.string, '\n')" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor Green }
        if ($LASTEXITCODE -ne 0) { Write-Host "x Rscript failed" -ForegroundColor Red; exit 1 }
        Write-Host "$([char]0x2713) All checks passed" -ForegroundColor Green
    }

    # Archives are .zip (R only) or .7z (R + Rtools, Rtools), or .zip for
    # those too when build.ps1 had no 7z on PATH
    "clean" {
        Require $Version "VERSION" "4.6.1"
        Remove-Artifacts @($rDir, "$rDir.zip*", "$rDir-full", "$rDir-full.zip*", "$rDir-full.7z*")
    }
    "clean-all" {
        Remove-Artifacts @("portable-r-*-win-*", "portable-rtools*-win-*", "R-*-win.exe", "R-*-aarch64.exe", "rtools4*-*.exe")
    }

    "list" {
        Write-Host "R versions ($Arch):"
        foreach ($v in $RVersions) {
            $dir = "portable-r-$v-win-$Arch"
            $hasR = Test-Path "$dir.zip"
            $hasFull = (Test-Path "$dir-full.7z") -or (Test-Path "$dir-full.zip")
            if ($hasR -and $hasFull) { Write-Host "  * $v  (R + full built)" -ForegroundColor Green }
            elseif ($hasR) { Write-Host "  * $v  (R built)" -ForegroundColor Green }
            elseif ($hasFull) { Write-Host "  * $v  (full built)" -ForegroundColor Green }
            elseif ((Test-Path $dir) -or (Test-Path "$dir-full")) { Write-Host "  * $v  (unpacked)" -ForegroundColor Yellow }
            else { Write-Host "  o $v" -ForegroundColor DarkGray }
        }
        Write-Host ""
        Write-Host "Rtools versions ($Arch):"
        foreach ($v in $RtVersions) {
            $dir = "portable-rtools$v-win-$Arch"
            if ((Test-Path "$dir.7z") -or (Test-Path "$dir.zip")) { Write-Host "  * Rtools$v  (built)" -ForegroundColor Green }
            elseif (Test-Path $dir) { Write-Host "  * Rtools$v  (unpacked)" -ForegroundColor Yellow }
            else { Write-Host "  o Rtools$v" -ForegroundColor DarkGray }
        }
    }

    default {
        Write-Host "x Unknown target '$Target' (see: make help)" -ForegroundColor Red
        exit 1
    }
}
