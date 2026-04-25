# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  build.ps1 - Build portable R and/or Rtools for Windows                 ║
# ║                                                                         ║
# ║  Three build modes:                                                     ║
# ║    Default:        Portable R from CRAN installer (binary packages)     ║
# ║    -IncludeRtools: Portable R + bundled Rtools (source compilation)     ║
# ║    -RtoolsOnly:    Standalone portable Rtools toolchain                 ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Usage: .\build.ps1 -RVersion "4.6.0"
#        .\build.ps1 -RVersion "4.6.0" -IncludeRtools
#        .\build.ps1 -RtoolsOnly -RtoolsVersion "45"
# Help:  .\build.ps1 -Help

param(
    [Parameter(Mandatory=$false)]
    [string]$RVersion,

    [string]$Architecture = "x64",

    [string]$OutputDir = ".",

    [switch]$IncludeRtools,

    [switch]$RtoolsOnly,

    [string]$RtoolsVersion,

    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ── Logging ──────────────────────────────────────────────────────────────────

function Step($msg)   { Write-Host "==> $msg" -ForegroundColor Blue }
function Ok($msg)     { Write-Host "    $([char]0x2713) $msg" -ForegroundColor Green }
function Warn($msg)   { Write-Host "    ! $msg" -ForegroundColor Yellow }
function Err($msg)    { Write-Host "    x $msg" -ForegroundColor Red }
function Detail($msg) { Write-Host "    $msg" -ForegroundColor DarkGray }

# ── Help ─────────────────────────────────────────────────────────────────────

if ($Help -or (-not $RVersion -and -not $RtoolsOnly)) {
    Write-Host @"

Usage: .\build.ps1 -RVersion <VERSION> [-Architecture <ARCH>] [-IncludeRtools]
       .\build.ps1 -RtoolsOnly -RtoolsVersion <VER> [-Architecture <ARCH>]

Build portable R and/or Rtools distributions for Windows. No system
installation or third-party tools required.

Modes:
  Default            Portable R only (binary packages work out of the box)
  -IncludeRtools     Portable R + bundled Rtools (source compilation works)
  -RtoolsOnly        Standalone Rtools toolchain

Parameters:
  -RVersion       R version to build (e.g., 4.5.3, 4.4.1)
  -Architecture   Target architecture: x64 (default) or aarch64
  -IncludeRtools  Bundle Rtools with R for source package compilation
  -RtoolsOnly     Build standalone Rtools (no R)
  -RtoolsVersion  Rtools version for standalone mode (43, 44, or 45)
  -OutputDir      Output directory (default: current directory)
  -Help           Show this help

Examples:
  .\build.ps1 -RVersion "4.6.0"                          # R only (x64)
  .\build.ps1 -RVersion "4.6.0" -IncludeRtools           # R + Rtools
  .\build.ps1 -RVersion "4.5.2" -Architecture "aarch64" -IncludeRtools
  .\build.ps1 -RtoolsOnly -RtoolsVersion "45"            # Rtools standalone
  .\build.ps1 -RtoolsOnly -RtoolsVersion "44" -Architecture "aarch64"

Output:
  portable-r-{VERSION}-win-{ARCH}\            R only
  portable-r-{VERSION}-win-{ARCH}.zip

  portable-r-{VERSION}-win-{ARCH}-full\       R + Rtools
  portable-r-{VERSION}-win-{ARCH}-full.zip

  portable-rtools{VER}-win-{ARCH}\            Rtools standalone
  portable-rtools{VER}-win-{ARCH}.zip

Supported R versions:
  x64:     4.3.0 - 4.6.0
  aarch64: 4.4.0 - 4.5.2 (from r-project.org experimental builds)

Rtools version mapping:
  R 4.3.x -> Rtools43 (x64 and aarch64)
  R 4.4.x -> Rtools44 (x64 and aarch64)
  R 4.5.x -> Rtools45 (x64 and aarch64)
  R 4.6.x -> Rtools45 (x64; a dedicated Rtools46 has not yet been announced)
"@
    exit 0
}

# ── Load versions from versions.json ─────────────────────────────────────────
# All supported versions, Rtools mappings, and URLs are managed in versions.json.
# Run check-updates.sh to detect new releases, or edit versions.json directly.

$versionsJsonPath = Join-Path $PSScriptRoot "versions.json"
if (-not (Test-Path $versionsJsonPath)) {
    Err "versions.json not found at $versionsJsonPath"
    exit 1
}
$versions = Get-Content $versionsJsonPath -Raw | ConvertFrom-Json

$VersionsX64     = @($versions.r.x64)
$VersionsAarch64 = @($versions.r.aarch64)

# Build Rtools mapping from versions.json. Iterates r_series (series -> rtools,
# many-to-one: e.g. both 4.5 and 4.6 map to Rtools45) so each series gets its own
# entry, even when sharing an Rtools major.
$RtoolsMap = @{}
foreach ($seriesProp in $versions.rtools.r_series.PSObject.Properties) {
    $series = $seriesProp.Name
    $rtVerName = $seriesProp.Value
    $rtProp = $versions.rtools.PSObject.Properties | Where-Object { $_.Name -eq $rtVerName }
    if (-not $rtProp) { continue }
    $rt = $rtProp.Value
    $entry = @{
        Version     = $rtVerName
        FileX64     = $rt.x64.file
        FileAarch64 = $rt.aarch64.file
    }
    $defaultUrl = "https://cran.r-project.org/bin/windows/Rtools/rtools${rtVerName}/files"
    if ($rt.aarch64.url -and $rt.aarch64.url -ne $defaultUrl) {
        $entry.UrlAarch64 = $rt.aarch64.url
    }
    $RtoolsMap[$series] = $entry
}

# Reverse mapping: Rtools version -> R series
$RtoolsVersionToSeries = @{}
foreach ($prop in $versions.rtools.r_series.PSObject.Properties) {
    $RtoolsVersionToSeries[$prop.Value] = $prop.Name
}

# ── Arguments ────────────────────────────────────────────────────────────────

# Normalize architecture name
if ($Architecture -eq "arm64") {
    $Architecture = "aarch64"
}

# Validate mode combinations
if ($IncludeRtools -and $RtoolsOnly) {
    Err "-IncludeRtools and -RtoolsOnly cannot be used together"
    exit 1
}

# RtoolsOnly mode: derive Rtools info from -RtoolsVersion or -RVersion
if ($RtoolsOnly) {
    if (-not $RtoolsVersion -and -not $RVersion) {
        Err "-RtoolsOnly requires -RtoolsVersion (e.g., 45) or -RVersion"
        exit 1
    }
    if ($RtoolsVersion) {
        if (-not $RtoolsVersionToSeries.ContainsKey($RtoolsVersion)) {
            Err "Unknown Rtools version: $RtoolsVersion (supported: 43, 44, 45)"
            exit 1
        }
    } else {
        # Derive from R version
        $RtoolsVersion = $RtoolsMap[$RVersion.Substring(0, 3)].Version
        if (-not $RtoolsVersion) {
            Err "No Rtools mapping for R $RVersion"
            exit 1
        }
    }
}

# Validate R version (when building R)
$buildR = -not $RtoolsOnly
if ($buildR) {
    if (-not $RVersion) {
        Err "-RVersion is required"
        exit 1
    }

    $supported = if ($Architecture -eq "aarch64") { $VersionsAarch64 } else { $VersionsX64 }
    if ($RVersion -notin $supported) {
        Err "R $RVersion is not available for $Architecture"
        Detail "Supported versions: $($supported -join ', ')"
        exit 1
    }
}

# Resolve Rtools info (when building Rtools)
$buildRtools = $IncludeRtools -or $RtoolsOnly
if ($buildRtools) {
    if (-not $RtoolsVersion) {
        $rtoolsSeries = $RVersion.Substring(0, 3)
        $rtoolsInfo = $RtoolsMap[$rtoolsSeries]
    } else {
        $rtoolsSeries = $RtoolsVersionToSeries[$RtoolsVersion]
        $rtoolsInfo = $RtoolsMap[$rtoolsSeries]
    }

    if (-not $rtoolsInfo) {
        Err "No Rtools mapping for series $rtoolsSeries"
        exit 1
    }

    $rtVer = $rtoolsInfo.Version
    $rtFile = if ($Architecture -eq "aarch64") { $rtoolsInfo.FileAarch64 } else { $rtoolsInfo.FileX64 }

    # Resolve download URL: use custom URL if set, otherwise default CRAN path
    $rtCustomUrl = if ($Architecture -eq "aarch64" -and $rtoolsInfo.UrlAarch64) {
        $rtoolsInfo.UrlAarch64
    } else { $null }

    if (-not $rtFile) {
        Err "Rtools$rtVer does not support $Architecture"
        exit 1
    }

    $rtToolchainBin = if ($Architecture -eq "aarch64") {
        "aarch64-w64-mingw32.static.posix"
    } else {
        "x86_64-w64-mingw32.static.posix"
    }
}

# Set installer filename for R
if ($buildR) {
    if ($Architecture -eq "aarch64") {
        $rInstallerFile = "R-${RVersion}-aarch64.exe"
    } else {
        $rInstallerFile = "R-${RVersion}-win.exe"
    }
}

# Set output name
if ($RtoolsOnly) {
    $outputName = "portable-rtools${rtVer}-win-${Architecture}"
} elseif ($IncludeRtools) {
    $outputName = "portable-r-${RVersion}-win-${Architecture}-full"
} else {
    $outputName = "portable-r-${RVersion}-win-${Architecture}"
}

$outputPath = Join-Path $OutputDir $outputName

# ── Banner ───────────────────────────────────────────────────────────────────

Write-Host ""
if ($RtoolsOnly) {
    Write-Host "Portable Rtools$rtVer for Windows ($Architecture)" -ForegroundColor White
} elseif ($IncludeRtools) {
    Write-Host "Portable R $RVersion + Rtools$rtVer for Windows ($Architecture)" -ForegroundColor White
} else {
    Write-Host "Portable R $RVersion for Windows ($Architecture)" -ForegroundColor White
}
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Download R installer
# x64 builds come from CRAN (current at /base/, older at /base/old/{VERSION}/).
# ARM64 builds come from R's experimental aarch64 repository.
# ═══════════════════════════════════════════════════════════════════════════════

if ($buildR) {
    Step "Downloading R installer"

    if (-not (Test-Path $rInstallerFile)) {
        if ($Architecture -eq "aarch64") {
            $primaryUrl = "https://www.r-project.org/nosvn/winutf8/aarch64/R-4-signed/$rInstallerFile"
            $fallbackUrl = $primaryUrl
        } else {
            $baseUrl = "https://cloud.r-project.org/bin/windows/base"
            $primaryUrl = "${baseUrl}/$rInstallerFile"
            $fallbackUrl = "${baseUrl}/old/${RVersion}/$rInstallerFile"
        }

        Detail $primaryUrl
        $curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curlExe) {
            $null = & curl.exe -fSL -o $rInstallerFile $primaryUrl 2>&1
            if ($LASTEXITCODE -ne 0) {
                Detail "Not at primary URL, trying archive..."
                $null = & curl.exe -fSL -o $rInstallerFile $fallbackUrl 2>&1
            }
            Ok "Downloaded $rInstallerFile"
        } else {
            try {
                Invoke-WebRequest -Uri $primaryUrl -OutFile $rInstallerFile
                Ok "Downloaded $rInstallerFile"
            } catch {
                Detail "Not at primary URL, trying archive..."
                Invoke-WebRequest -Uri $fallbackUrl -OutFile $rInstallerFile
                Ok "Downloaded $rInstallerFile (from archive)"
            }
        }
    } else {
        Ok "Using cached $rInstallerFile"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Download Rtools installer
# Most versions from CRAN at /bin/windows/Rtools/rtools{VER}/files/.
# Rtools43 aarch64 from r-project.org/nosvn/winutf8/rtools43-aarch64/.
# ═══════════════════════════════════════════════════════════════════════════════

if ($buildRtools) {
    Step "Downloading Rtools$rtVer installer"

    if (-not (Test-Path $rtFile)) {
        if ($rtCustomUrl) {
            $rtUrl = "${rtCustomUrl}/${rtFile}"
        } else {
            $rtUrl = "https://cran.r-project.org/bin/windows/Rtools/rtools${rtVer}/files/${rtFile}"
        }

        Detail $rtUrl
        $curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curlExe) {
            $null = & curl.exe -fSL -o $rtFile $rtUrl 2>&1
            if ($LASTEXITCODE -ne 0) {
                Err "Failed to download $rtFile"
                exit 1
            }
            Ok "Downloaded $rtFile"
        } else {
            try {
                Invoke-WebRequest -Uri $rtUrl -OutFile $rtFile
                Ok "Downloaded $rtFile"
            } catch {
                Err "Failed to download $rtFile"
                exit 1
            }
        }
    } else {
        Ok "Using cached $rtFile"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Extraction helper
# Uses 7z to extract Inno Setup .exe directly (fast, no side effects).
# Falls back to running the installer silently if 7z is not available.
# ═══════════════════════════════════════════════════════════════════════════════

function Extract-InnoSetup($InstallerPath, $DestDir) {
    # Use innoextract (purpose-built for Inno Setup, fast and reliable).
    # Install it automatically if not present.
    $innoextract = Get-Command innoextract -ErrorAction SilentlyContinue
    if (-not $innoextract) {
        # Try choco first (works on both x64 and ARM64 runners)
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if ($choco) {
            Detail "Installing innoextract via choco..."
            & choco install innoextract -y --no-progress 2>&1 | Select-Object -Last 3 | ForEach-Object { Detail "  $_" }
            # Refresh PATH after choco install
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            $innoextract = Get-Command innoextract -ErrorAction SilentlyContinue
        }

        # Fallback: download from GitHub releases
        if (-not $innoextract) {
            Detail "Installing innoextract from GitHub releases..."
            $innoDir = Join-Path $env:TEMP "innoextract"
            New-Item -ItemType Directory -Path $innoDir -Force | Out-Null
            $innoZip = Join-Path $env:TEMP "innoextract.zip"
            $curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
            if ($curlExe) {
                & curl.exe -fSL -o $innoZip "https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-windows.zip" 2>&1 | ForEach-Object { Detail "  $_" }
            } else {
                Invoke-WebRequest -Uri "https://github.com/dscharrer/innoextract/releases/download/1.9/innoextract-1.9-windows.zip" -OutFile $innoZip
            }
            Expand-Archive -Path $innoZip -DestinationPath $innoDir -Force
            $innoExe = Get-ChildItem -Path $innoDir -Recurse -Filter "innoextract.exe" | Select-Object -First 1
            if ($innoExe) {
                $env:PATH = "$($innoExe.DirectoryName);$env:PATH"
                Detail "Found: $($innoExe.FullName)"
            }
            $innoextract = Get-Command innoextract -ErrorAction SilentlyContinue
        }

        if ($innoextract) {
            Detail "innoextract ready: $((& innoextract --version 2>&1 | Select-Object -First 1))"
        } else {
            Warn "Could not install innoextract"
        }
    }

    $extracted = $false
    if ($innoextract) {
        Detail "Extracting with innoextract (fast)"
        $innoVer = & innoextract --version 2>&1 | Select-Object -First 1
        Detail "  $innoVer"
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }
        $output = & innoextract -d $DestDir --extract $InstallerPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            # innoextract puts files under app/ (no curly braces)
            $appDir = Join-Path $DestDir "app"
            if (Test-Path $appDir) {
                Get-ChildItem $appDir | ForEach-Object {
                    Move-Item -LiteralPath $_.FullName -Destination $DestDir -Force
                }
                Remove-Item -Recurse -Force $appDir -ErrorAction SilentlyContinue
            }
            $itemCount = (Get-ChildItem $DestDir | Measure-Object).Count
            Detail "Extracted $itemCount top-level items"
            $extracted = $true
        } else {
            Warn "innoextract failed (exit $LASTEXITCODE): $($output | Select-Object -Last 3)"
            # Clean up partial extraction
            if (Test-Path $DestDir) { Remove-Item -Recurse -Force $DestDir -ErrorAction SilentlyContinue }
        }
    }

    if (-not $extracted) {
        # Fallback: run the Inno Setup installer silently with a timeout.
        # Some Inno Setup 6.2+ installers hang indefinitely on CI runners.
        Detail "Using silent install (10 min timeout)"
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
        }
        $proc = Start-Process -PassThru -FilePath $InstallerPath -ArgumentList @(
            "/VERYSILENT",
            "/SUPPRESSMSGBOXES",
            "/CURRENTUSER",
            "/NOICONS",
            "/DIR=$DestDir"
        )
        $finished = $proc.WaitForExit(1800000)  # 30 minute timeout
        if (-not $finished) {
            $proc.Kill()
            Err "Silent install timed out after 30 minutes"
            exit 1
        }
        if ($proc.ExitCode -ne 0) {
            Err "Installer exited with code $($proc.ExitCode)"
            exit 1
        }
        # Clean up installer artifacts
        Remove-Item -Path (Join-Path $DestDir "unins*.exe") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $DestDir "unins*.dat") -Force -ErrorAction SilentlyContinue
        Remove-Item -Path (Join-Path $DestDir "unins*.msg") -Force -ErrorAction SilentlyContinue
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Extract R installer
# ═══════════════════════════════════════════════════════════════════════════════

if ($buildR) {
    Step "Extracting R installer"

    if (Test-Path $outputPath) {
        Remove-Item -Recurse -Force $outputPath
    }

    $absRInstaller = (Resolve-Path $rInstallerFile).Path
    $absOutput = Join-Path (Resolve-Path $OutputDir).Path $outputName

    Extract-InnoSetup $absRInstaller $absOutput
    Ok "Extracted R files"
} else {
    # RtoolsOnly: create output directory
    if (Test-Path $outputPath) {
        Remove-Item -Recurse -Force $outputPath
    }
    New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
    $absOutput = (Resolve-Path $outputPath).Path
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Extract Rtools installer
# ═══════════════════════════════════════════════════════════════════════════════

if ($buildRtools) {
    Step "Extracting Rtools$rtVer"

    $absRtInstaller = (Resolve-Path $rtFile).Path

    if ($RtoolsOnly) {
        $rtInstallDir = $absOutput
    } else {
        $rtInstallDir = Join-Path $absOutput "rtools${rtVer}"
    }

    # Rtools installers use newer Inno Setup versions that innoextract 1.9
    # cannot handle. Use silent install directly for all architectures.
    Detail "Using silent install"
    $proc = Start-Process -PassThru -FilePath $absRtInstaller -ArgumentList @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/CURRENTUSER",
        "/NOICONS",
        "/DIR=$rtInstallDir"
    )
    $finished = $proc.WaitForExit(1800000)  # 30 minute timeout
    if (-not $finished) {
        $proc.Kill()
        Err "Rtools silent install timed out after 30 minutes"
        exit 1
    }
    if ($proc.ExitCode -ne 0) {
        Err "Rtools installer exited with code $($proc.ExitCode)"
        exit 1
    }
    Remove-Item -Path (Join-Path $rtInstallDir "unins*.exe") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $rtInstallDir "unins*.dat") -Force -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $rtInstallDir "unins*.msg") -Force -ErrorAction SilentlyContinue
    Ok "Extracted Rtools$rtVer files"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Configure for portability
# R for Windows is already relocatable. We configure library paths, CRAN mirror,
# and (when Rtools is bundled) the toolchain PATH via Renviron.site.
# ═══════════════════════════════════════════════════════════════════════════════

if ($buildR) {
    Step "Configuring Rprofile.site"

    $etcDir = Join-Path $outputPath "etc"
    if (-not (Test-Path $etcDir)) {
        New-Item -ItemType Directory -Path $etcDir -Force | Out-Null
    }

    $rprofileContent = @"
# Portable R configuration
# All packages install to the local library/ directory
.libPaths(.Library)

# Suppress the default CRAN mirror prompt
local({
  r <- getOption("repos")
  r["CRAN"] <- "https://cloud.r-project.org"
  options(repos = r)
})
"@

    Set-Content -Path (Join-Path $etcDir "Rprofile.site") -Value $rprofileContent -Encoding UTF8
    Ok "Local library paths and CRAN mirror configured"

    $libraryDir = Join-Path $outputPath "library"
    if (-not (Test-Path $libraryDir)) {
        New-Item -ItemType Directory -Path $libraryDir -Force | Out-Null
    }

    # Configure Renviron.site for bundled Rtools PATH
    if ($IncludeRtools) {
        Step "Configuring Renviron.site for Rtools"

        # Use single-quoted here-string to prevent PowerShell from expanding
        # ${R_HOME} and ${PATH}. Those are Renviron variable references that R
        # expands at startup before passing to the environment.
        #
        # Setting RTOOLS{VER}_HOME is the standard R mechanism for non-default
        # Rtools locations. Makeconf, Rcmd_environ, and Rprofile.windows all
        # derive compiler flags (-I/-L), PATH, and tool discovery from it.
        $renvironContent = @'
# Portable Rtools configuration
# RTOOLS{VER}_HOME (x64) or RTOOLS{VER}_AARCH64_HOME (arm64) tells R where
# the bundled toolchain lives. Makeconf uses
# it for compiler/linker flags (-I/-L), and Rcmd_environ/Rprofile use it to
# find gcc, make, etc. R expands ${R_HOME} before passing to the environment.
__RTOOLS_HOME_VAR__=${R_HOME}/__RTOOLS_DIR__

# Alternative approaches (not needed when RTOOLS{VER}_HOME is set, but
# documented here for reference):
#
# R_CUSTOM_TOOLS_SOFT overrides LOCAL_SOFT in Makeconf directly, taking
# precedence over RTOOLS{VER}_HOME for -I/-L compiler/linker flags:
# R_CUSTOM_TOOLS_SOFT=${R_HOME}/__RTOOLS_DIR__/__TOOLCHAIN_BIN__
#
# R_CUSTOM_TOOLS_PATH overrides PATH used by R CMD and Rprofile.windows
# for finding gcc, make, etc:
# R_CUSTOM_TOOLS_PATH=${R_HOME}/__RTOOLS_DIR__/__TOOLCHAIN_BIN__/bin;${R_HOME}/__RTOOLS_DIR__/usr/bin
#
# Explicit PATH prepend (redundant when RTOOLS{VER}_HOME is set, since
# Rcmd_environ and Rprofile.windows derive PATH from it):
# PATH="${R_HOME}/__RTOOLS_DIR__/__TOOLCHAIN_BIN__/bin;${R_HOME}/__RTOOLS_DIR__/usr/bin;${PATH}"
'@
        # RTOOLS45_HOME for x64, RTOOLS45_AARCH64_HOME for arm64
        $rtoolsHomeVar = if ($Architecture -eq "aarch64") { "RTOOLS${rtVer}_AARCH64_HOME" } else { "RTOOLS${rtVer}_HOME" }
        $renvironContent = $renvironContent.Replace("__RTOOLS_HOME_VAR__", $rtoolsHomeVar)
        $renvironContent = $renvironContent.Replace("__RTOOLS_DIR__", "rtools${rtVer}")
        $renvironContent = $renvironContent.Replace("__TOOLCHAIN_BIN__", $rtToolchainBin)

        Set-Content -Path (Join-Path $etcDir "Renviron.site") -Value $renvironContent -Encoding UTF8
        Ok "Rtools$rtVer PATH configured in Renviron.site"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Verify the build
# ═══════════════════════════════════════════════════════════════════════════════

Step "Verifying build"

if ($buildR) {
    $rscript = Join-Path $outputPath "bin" "Rscript.exe"
    if (Test-Path $rscript) {
        $ver = & $rscript --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Ok "Rscript --version: $ver"
        } else {
            Err "Rscript --version failed"
        }

        $result = & $rscript -e "cat(R.version.string)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Ok "Code execution: $result"
        } else {
            Err "Code execution failed"
        }

        $null = & $rscript -e "library(stats); cat(mean(1:10))" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Ok "Package loading (stats)"
        } else {
            Err "Package loading failed"
        }

        # Binary package install (x64 only, CRAN has no ARM64 binaries)
        if ($Architecture -ne "aarch64") {
            $null = & $rscript -e "install.packages('jsonlite', quiet=TRUE); library(jsonlite); cat(toJSON(list(test=TRUE)))" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Ok "Binary package install (jsonlite)"
            } else {
                Warn "Binary package install failed (may need internet)"
            }
        } else {
            Detail "Skipping binary package install (no CRAN ARM64 binaries available)"
        }

        # Rtools verification (only when bundled)
        if ($IncludeRtools) {
            # aarch64 Rtools uses LLVM (clang/clang++) instead of GCC (gcc/g++)
            if ($Architecture -eq "aarch64") {
                $ccCmd = "clang"
                $ccPattern = "clang"
            } else {
                $ccCmd = "gcc"
                $ccPattern = "gcc|GCC"
            }

            $ccResult = & $rscript -e "cat(system('$ccCmd --version', intern=TRUE)[1])" 2>&1
            if ($LASTEXITCODE -eq 0 -and $ccResult -match $ccPattern) {
                Ok "Rtools $ccCmd`: $ccResult"
            } else {
                Warn "Rtools $ccCmd not found via R"
            }

            $makeResult = & $rscript -e "cat(system('make --version', intern=TRUE)[1])" 2>&1
            if ($LASTEXITCODE -eq 0 -and $makeResult -match "Make") {
                Ok "Rtools make: $makeResult"
            } else {
                Warn "Rtools make not found via R"
            }

            # Source package install (the whole point of bundling Rtools)
            $null = & $rscript -e "install.packages('glue', type='source', quiet=TRUE); library(glue); cat(glue('R {R.version.string}'))" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Ok "Source package install (glue)"
            } else {
                Warn "Source package install failed"
            }
        }
    } else {
        Err "Rscript.exe not found at: $rscript"
        Detail "Contents of output directory:"
        Get-ChildItem $outputPath -ErrorAction SilentlyContinue | Format-Table Name
    }
}

if ($RtoolsOnly) {
    # Verify standalone Rtools
    $gccExe = Join-Path $outputPath "${rtToolchainBin}" "bin" "gcc.exe"
    $makeExe = Join-Path $outputPath "usr" "bin" "make.exe"

    if (Test-Path $gccExe) {
        $gccVer = & $gccExe --version 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -eq 0) {
            Ok "gcc: $gccVer"
        } else {
            Err "gcc --version failed"
        }
    } else {
        Err "gcc.exe not found at: $gccExe"
    }

    if (Test-Path $makeExe) {
        $makeVer = & $makeExe --version 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -eq 0) {
            Ok "make: $makeVer"
        } else {
            Err "make --version failed"
        }
    } else {
        Err "make.exe not found at: $makeExe"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 7: Create archive
# ═══════════════════════════════════════════════════════════════════════════════

Step "Creating archive"

# R-only builds use .zip (native Windows support, no extra tools needed).
# R+Rtools builds use .7z (LZMA2 compression keeps the ~3.5GB Rtools bundle
# under GitHub's 2GB release asset limit — zip and gzip can't).
$isFull = $IncludeRtools -or $RtoolsOnly
if ($isFull) {
    $archiveFile = "${outputName}.7z"
} else {
    $archiveFile = "${outputName}.zip"
}
if (Test-Path $archiveFile) { Remove-Item $archiveFile }

$sevenZip = Get-Command 7z -ErrorAction SilentlyContinue
if ($sevenZip) {
    if ($isFull) {
        Detail "Using 7z (LZMA2)"
        & 7z a -t7z -mx=7 -mmt=on $archiveFile $outputPath 2>&1 | Select-Object -Last 5 | ForEach-Object { Detail "  $_" }
    } else {
        Detail "Using 7z (zip)"
        & 7z a -tzip -mx=5 $archiveFile $outputPath 2>&1 | Select-Object -Last 5 | ForEach-Object { Detail "  $_" }
    }
    # 7z exit codes: 0=ok, 1=warning (non-fatal, archive created), 2+=error
    if ($LASTEXITCODE -ge 2) {
        Err "7z failed with exit code $LASTEXITCODE"
        exit 1
    }
} else {
    Detail "Using Compress-Archive (slow, 7z not found)"
    $archiveFile = "${outputName}.zip"
    Compress-Archive -Path $outputPath -DestinationPath $archiveFile
}

$hash = (Get-FileHash -Algorithm SHA256 $archiveFile).Hash.ToLower()
"${hash}  ${archiveFile}" | Out-File -FilePath "${archiveFile}.sha256" -Encoding ASCII
$size = "$([math]::Round((Get-Item $archiveFile).Length / 1MB, 1)) MB"

Ok "$archiveFile ($size)"
Detail "SHA256: $hash"

# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "Build complete" -ForegroundColor Green
Write-Host ""
exit 0
