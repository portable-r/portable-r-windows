# Test suite for standalone portable Rtools builds (Windows)
# Usage: .\tests\run-rtools-tests.ps1 <PORTABLE_RTOOLS_DIR>
# Example: .\tests\run-rtools-tests.ps1 portable-rtools45-win-x64

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$RtDir
)

$ErrorActionPreference = "Continue"

# ── Logging ───────��───────────────────────��──────────────────────────────────

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

function Pass($msg)    { Write-Host "  PASS  $msg" -ForegroundColor Green;  $script:Pass++ }
function Fail($msg)    { Write-Host "  FAIL  $msg" -ForegroundColor Red;    $script:Fail++ }
function Skip($msg)    { Write-Host "  SKIP  $msg" -ForegroundColor Yellow; $script:Skip++ }
function Section($msg) { Write-Host "`n-- $msg --" -ForegroundColor Blue }

# ── Setup ──────────��──────────────────────────────────────────��──────────────

if (-not (Test-Path $RtDir)) {
    Write-Host "Error: $RtDir does not exist" -ForegroundColor Red
    exit 1
}

$RtDir = (Resolve-Path $RtDir).Path

# Detect toolchain directory (x86_64 or aarch64)
$toolchainDir = Get-ChildItem -Path $RtDir -Directory -Filter "*-w64-mingw32.static.posix" -ErrorAction SilentlyContinue | Select-Object -First 1
$toolchainName = if ($toolchainDir) { $toolchainDir.Name } else { "unknown" }

Write-Host "Testing: $RtDir" -ForegroundColor White
Write-Host "Toolchain: $toolchainName" -ForegroundColor Cyan

# Add Rtools to PATH so tools can find their MSYS2 DLL dependencies
$usrBin = Join-Path $RtDir "usr\bin"
if ($toolchainDir) {
    $tcBin = Join-Path $RtDir "$toolchainName\bin"
    $env:PATH = "$tcBin;$usrBin;$($env:PATH)"
} else {
    $env:PATH = "$usrBin;$($env:PATH)"
}

# ── 1. Directory structure ───────────────────────────────────────────────────

Section "Directory structure"

$requiredPaths = @(
    "usr\bin\make.exe",
    "usr\bin\bash.exe"
)

if ($toolchainDir) {
    $requiredPaths += @(
        "$toolchainName\bin\gcc.exe",
        "$toolchainName\bin\g++.exe"
    )

    # gfortran may be in the toolchain (x64) or may be flang-new (aarch64)
    $gfortranPath = Join-Path $RtDir "$toolchainName\bin\gfortran.exe"
    $flangPath = Join-Path $RtDir "$toolchainName\bin\flang-new.exe"
    if (Test-Path $gfortranPath) {
        $requiredPaths += "$toolchainName\bin\gfortran.exe"
    } elseif (Test-Path $flangPath) {
        $requiredPaths += "$toolchainName\bin\flang-new.exe"
    }
} else {
    Fail "No toolchain directory found (*-w64-mingw32.static.posix)"
}

foreach ($path in $requiredPaths) {
    $full = Join-Path $RtDir $path
    if (Test-Path $full) {
        Pass "$path exists"
    } else {
        Fail "$path missing"
    }
}

# ─�� 2. No installer artifacts ────────────────────────────────────────────────

Section "Installer cleanup"

$uninstaller = Get-ChildItem -Path $RtDir -Filter "unins*" -ErrorAction SilentlyContinue
if ($uninstaller) {
    Fail "Uninstaller files still present: $($uninstaller.Name -join ', ')"
} else {
    Pass "No uninstaller files"
}

# ── 3. Tool execution ─────────────────────────────────────────────────��──────

Section "Tool execution"

# Helper: run a tool and check output matches pattern (avoids $LASTEXITCODE pipe issues)
function Test-Tool($Exe, $Name, $Pattern) {
    $allOutput = & $Exe --version 2>&1
    $firstLine = ($allOutput | Select-Object -First 1) -as [string]
    if ($firstLine -match $Pattern) {
        Pass "${Name}: $firstLine"
    } else {
        Fail "$Name --version (got: $firstLine)"
    }
}

# make --version
$makeExe = Join-Path $RtDir "usr\bin\make.exe"
if (Test-Path $makeExe) {
    Test-Tool $makeExe "make" "Make"
} else {
    Fail "make.exe not found"
}

# C compiler (gcc on x64, clang on aarch64)
if ($toolchainDir) {
    $isAarch64 = $toolchainName -match "aarch64"

    $gccExe = Join-Path $RtDir "$toolchainName\bin\gcc.exe"
    $clangExe = Join-Path $RtDir "$toolchainName\bin\clang.exe"

    if ($isAarch64 -and (Test-Path $clangExe)) {
        Test-Tool $clangExe "clang" "clang"
    } elseif (Test-Path $gccExe) {
        Test-Tool $gccExe "gcc" "gcc"
    } else {
        Fail "No C compiler found (tried gcc.exe, clang.exe)"
    }

    # C++ compiler (g++ on x64, clang++ on aarch64)
    $gppExe = Join-Path $RtDir "$toolchainName\bin\g++.exe"
    $clangppExe = Join-Path $RtDir "$toolchainName\bin\clang++.exe"

    if ($isAarch64 -and (Test-Path $clangppExe)) {
        Test-Tool $clangppExe "clang++" "clang"
    } elseif (Test-Path $gppExe) {
        Test-Tool $gppExe "g++" "g\+\+|GCC"
    } else {
        Fail "No C++ compiler found (tried g++.exe, clang++.exe)"
    }
}

# ── 4. Compilation test ──────────���───────────────────────���──────────────────

Section "Compilation test"

if ($toolchainDir) {
    $gccExe = Join-Path $RtDir "$toolchainName\bin\gcc.exe"
    if (Test-Path $gccExe) {
        $tempDir = Join-Path $env:TEMP "rtools-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        $srcFile = Join-Path $tempDir "hello.c"
        $outFile = Join-Path $tempDir "hello.exe"

        @"
#include <stdio.h>
int main() {
    printf("hello from portable rtools\n");
    return 0;
}
"@ | Set-Content -Path $srcFile -Encoding ASCII

        $null = & $gccExe -o $outFile $srcFile 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $outFile)) {
            $output = & $outFile 2>&1
            if ($output -match "hello from portable rtools") {
                Pass "Compile and run C program"
            } else {
                Fail "Compiled program produced unexpected output: $output"
            }
        } else {
            Fail "gcc failed to compile test program"
        }

        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    } else {
        Skip "Compilation test (gcc not found)"
    }
} else {
    Skip "Compilation test (no toolchain directory)"
}

# ── Summary ─────��────────────────────────────────���───────────────────────────

$Total = $script:Pass + $script:Fail + $script:Skip

Write-Host ""
Write-Host "Results: $($script:Pass) passed, $($script:Fail) failed, $($script:Skip) skipped ($Total total)" -ForegroundColor White

if ($script:Fail -gt 0) {
    Write-Host "FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "ALL PASSED" -ForegroundColor Green
    exit 0
}
