# Test suite for portable R builds (Windows)
# Detects bundled Rtools and adjusts expectations accordingly.
#
# Usage: .\tests\run-tests.ps1 <PORTABLE_R_DIR>
# Example: .\tests\run-tests.ps1 portable-r-4.5.3-win-x64
#          .\tests\run-tests.ps1 portable-r-4.5.3-win-x64-full

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$RDir
)

$ErrorActionPreference = "Continue"

# ── Logging ────────���─────────────────────────────��───────────────────────────

$script:Pass = 0
$script:Fail = 0
$script:Skip = 0

function Pass($msg)    { Write-Host "  PASS  $msg" -ForegroundColor Green;  $script:Pass++ }
function Fail($msg)    { Write-Host "  FAIL  $msg" -ForegroundColor Red;    $script:Fail++ }
function Skip($msg)    { Write-Host "  SKIP  $msg" -ForegroundColor Yellow; $script:Skip++ }
function Section($msg) { Write-Host "`n-- $msg --" -ForegroundColor Blue }

# ── Setup ─────────────────────────────────────────────��──────────────────────

if (-not (Test-Path $RDir)) {
    Write-Host "Error: $RDir does not exist" -ForegroundColor Red
    exit 1
}

$RDir = (Resolve-Path $RDir).Path
$Rscript = Join-Path $RDir "bin\Rscript.exe"
$RExe = Join-Path $RDir "bin\R.exe"

# Detect bundled Rtools
$rtoolsDir = Get-ChildItem -Path $RDir -Directory -Filter "rtools*" -ErrorAction SilentlyContinue | Select-Object -First 1
$hasRtools = $false
if ($rtoolsDir) {
    $makeCheck = Join-Path $rtoolsDir.FullName "usr\bin\make.exe"
    $hasRtools = Test-Path $makeCheck
}

Write-Host "Testing: $RDir" -ForegroundColor White
if ($hasRtools) {
    Write-Host "Rtools: $($rtoolsDir.Name) (bundled)" -ForegroundColor Cyan
}

# ── 1. Directory structure ───────────────────────────────────────────────────

Section "Directory structure"

$requiredPaths = @(
    "bin\R.exe",
    "bin\Rscript.exe",
    "bin\x64\R.dll",
    "etc\Rprofile.site",
    "library",
    "modules\x64\internet.dll"
)

foreach ($path in $requiredPaths) {
    $full = Join-Path $RDir $path
    if (Test-Path $full) {
        Pass "$path exists"
    } else {
        # Some R versions use different paths, check alternatives
        $alt = $path -replace "\\x64\\", "\"
        $altFull = Join-Path $RDir $alt
        if (Test-Path $altFull) {
            Pass "$alt exists"
        } else {
            Fail "$path missing"
        }
    }
}

# Check Rtools structure if bundled
if ($hasRtools) {
    $rtName = $rtoolsDir.Name
    $rtPaths = @(
        "$rtName\usr\bin\make.exe"
    )

    # Detect toolchain bin directory (x86_64 or aarch64)
    $toolchainDir = Get-ChildItem -Path $rtoolsDir.FullName -Directory -Filter "*-w64-mingw32.static.posix" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($toolchainDir) {
        $rtPaths += "$rtName\$($toolchainDir.Name)\bin\gcc.exe"
    }

    foreach ($path in $rtPaths) {
        $full = Join-Path $RDir $path
        if (Test-Path $full) {
            Pass "$path exists"
        } else {
            Fail "$path missing"
        }
    }

    # Check Renviron.site exists (needed for PATH configuration)
    $renviron = Join-Path $RDir "etc\Renviron.site"
    if (Test-Path $renviron) {
        Pass "etc\Renviron.site exists"
    } else {
        Fail "etc\Renviron.site missing (Rtools PATH not configured)"
    }
}

# ── 2. No installer artifacts ──────────────────��─────────────────────────────

Section "Installer cleanup"

$uninstaller = Get-ChildItem -Path $RDir -Filter "unins*" -ErrorAction SilentlyContinue
if ($uninstaller) {
    Fail "Uninstaller files still present: $($uninstaller.Name -join ', ')"
} else {
    Pass "No uninstaller files in R directory"
}

if ($hasRtools) {
    $rtUninstaller = Get-ChildItem -Path $rtoolsDir.FullName -Filter "unins*" -ErrorAction SilentlyContinue
    if ($rtUninstaller) {
        Fail "Rtools uninstaller files still present: $($rtUninstaller.Name -join ', ')"
    } else {
        Pass "No uninstaller files in Rtools directory"
    }
}

# Check registry (HKCU only)
$regEntry = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
    Where-Object { $_.GetValue("InstallLocation") -like "*$($RDir.Replace('\','\\'))*" }
if ($regEntry) {
    Fail "Registry uninstall entry still present"
} else {
    Pass "No registry uninstall entries"
}

$rcore = Get-ItemProperty "HKCU:\Software\R-core" -ErrorAction SilentlyContinue
if ($rcore) {
    Fail "HKCU:\Software\R-core still present"
} else {
    Pass "No R-core registry entries"
}

# ── 3. Basic execution ───────────���────────────────────────────────��─────────

Section "Basic execution"

# Rscript --version
$ver = & $Rscript --version 2>&1
if ($LASTEXITCODE -eq 0) {
    Pass "Rscript --version: $ver"
} else {
    Fail "Rscript --version"
}

# R --version
$ver = & $RExe --version 2>&1 | Select-Object -First 1
if ($LASTEXITCODE -eq 0) {
    Pass "R --version: $ver"
} else {
    Fail "R --version"
}

# Code execution
$result = & $Rscript -e "cat(R.version.string)" 2>&1
if ($LASTEXITCODE -eq 0) {
    Pass "Code execution: $result"
} else {
    Fail "Code execution"
}

# R_HOME resolves correctly
$rHome = & $Rscript -e "cat(normalizePath(R.home(), winslash='/'))" 2>&1
$expected = $RDir.Replace('\', '/')
if ($rHome -eq $expected) {
    Pass "R_HOME resolves to portable directory"
} else {
    Fail "R_HOME mismatch: expected $expected, got $rHome"
}

# .libPaths is local
$libPath = & $Rscript -e "cat(normalizePath(.libPaths()[1], winslash='/'))" 2>&1
$expectedLib = "$expected/library"
if ($libPath -eq $expectedLib) {
    Pass ".libPaths()[1] is local library/"
} else {
    Fail ".libPaths()[1]: expected $expectedLib, got $libPath"
}

# ── 4. Base packages ──────────��─────────────────────────────────────────────

Section "Base package loading"

foreach ($pkg in @("stats", "graphics", "grDevices", "utils", "methods")) {
    $null = & $Rscript -e "library($pkg)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Pass "library($pkg)"
    } else {
        Fail "library($pkg)"
    }
}

# ── 5. Capabilities ─��───────────────────────────────────────────────────────

Section "R capabilities"

foreach ($cap in @("http/ftp", "sockets", "libcurl")) {
    $result = & $Rscript -e "cat(capabilities('$cap'))" 2>&1
    if ($result -eq "TRUE") {
        Pass "capabilities('$cap')"
    } else {
        Fail "capabilities('$cap') = $result"
    }
}

# ── 6. Internet connectivity ───────────��────────────────────────────────────

Section "Internet connectivity"

$null = & $Rscript -e "u <- url('https://cloud.r-project.org/'); r <- readLines(u, n=1, warn=FALSE); close(u); if(nchar(r)>0) q(status=0) else q(status=1)" 2>&1
if ($LASTEXITCODE -eq 0) {
    Pass "HTTPS connection to CRAN"
} else {
    Fail "HTTPS connection to CRAN"
}

# ── 7. Numeric computation ──────────────���──────────────────────────────��────

Section "Numeric computation"

$null = & $Rscript -e "stopifnot(identical(sum(1:100), 5050L)); stopifnot(all.equal(mean(1:10), 5.5)); stopifnot(all.equal(as.numeric(crossprod(1:5)), 55)); m <- matrix(c(1,2,3,4), 2, 2); stopifnot(all.equal(det(m), -2)); cat('ok')" 2>&1
if ($LASTEXITCODE -eq 0) {
    Pass "Arithmetic, BLAS, and linear algebra"
} else {
    Fail "Numeric computation"
}

# ── 8. Binary package install ────────────────────────────────────────────────

Section "Binary package install"

# Detect architecture from the directory name
$isAarch64 = $RDir -match "aarch64"

if ($isAarch64) {
    Skip "Binary package install (no CRAN ARM64 binaries available)"
} else {

# Install jsonlite and use it in a single call
$result = & $Rscript -e "install.packages('jsonlite', quiet=TRUE); library(jsonlite); stopifnot(grepl('test', toJSON(list(test=TRUE)))); cat('ok')" 2>&1
if ($result -match "ok") {
    Pass "install + load + use jsonlite (single call)"
} else {
    Fail "jsonlite binary package"
}

} # end if not aarch64

# ── 9. Source package install ────��──────────────────────────��────────────────

Section "Source package install"

$result = & $Rscript -e "install.packages('glue', type='source', quiet=TRUE); library(glue); stopifnot(grepl('R version', glue('R {R.version.string}'))); cat('ok')" 2>&1
if ($result -match "ok") {
    Pass "install + load + use glue (from source)"
} else {
    if ($hasRtools) {
        Fail "Source install failed despite bundled Rtools"
    } else {
        Skip "Source install (may need Rtools)"
    }
}

# ── 10. Bundled Rtools ──────────────��────────────────────────────────────────

if ($hasRtools) {
    Section "Bundled Rtools"

    # aarch64 Rtools uses LLVM (clang/clang++) instead of GCC (gcc/g++)
    if ($isAarch64) {
        $ccCmd = "clang"
        $ccPattern = "clang"
        $cppCmd = "clang++"
        $cppPattern = "clang"
    } else {
        $ccCmd = "gcc"
        $ccPattern = "gcc|GCC"
        $cppCmd = "g++.exe"
        $cppPattern = "GCC|[Gg]\+\+|MinGW"
    }

    # C compiler accessible from R
    $ccVer = & $Rscript -e "cat(system('$ccCmd --version', intern=TRUE)[1])" 2>&1
    if ($LASTEXITCODE -eq 0 -and $ccVer -match $ccPattern) {
        Pass "$ccCmd accessible from R: $ccVer"
    } else {
        Fail "$ccCmd not accessible from R (got: $ccVer)"
    }

    # C++ compiler accessible from R
    $cppVer = & $Rscript -e "cat(system('$cppCmd --version', intern=TRUE)[1])" 2>&1
    if ($LASTEXITCODE -eq 0 -and $cppVer -match $cppPattern) {
        Pass "$cppCmd accessible from R: $cppVer"
    } else {
        Fail "$cppCmd not accessible from R (got: $cppVer)"
    }

    # make accessible from R
    $makeVer = & $Rscript -e "cat(system('make --version', intern=TRUE)[1])" 2>&1
    if ($LASTEXITCODE -eq 0 -and $makeVer -match "Make") {
        Pass "make accessible from R: $makeVer"
    } else {
        Fail "make not accessible from R"
    }

    # Renviron.site has PATH configured
    $renvironPath = Join-Path $RDir "etc\Renviron.site"
    if (Test-Path $renvironPath) {
        $content = Get-Content $renvironPath -Raw
        if ($content -match "rtools" -and $content -match "PATH") {
            Pass "Renviron.site configures Rtools PATH"
        } else {
            Fail "Renviron.site does not configure Rtools PATH"
        }
    } else {
        Fail "Renviron.site not found"
    }
}

# ── Summary ────────────────��───────────────────────────────��─────────────────

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
