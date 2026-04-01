# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  build.ps1 - Build portable R for Windows from CRAN installers          ║
# ║                                                                         ║
# ║  Runs the official CRAN R installer silently to a custom directory,     ║
# ║  configures for local library paths, and packages as a zip archive.     ║
# ║  The resulting distribution runs from any directory without system       ║
# ║  installation. No third-party tools needed.                             ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Usage: .\build.ps1 -RVersion "4.5.3"
# Help:  .\build.ps1 -Help

param(
    [Parameter(Mandatory=$false)]
    [string]$RVersion,

    [string]$Architecture = "x64",

    [string]$OutputDir = ".",

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

if ($Help -or -not $RVersion) {
    Write-Host @"

Usage: .\build.ps1 -RVersion <VERSION> [-Architecture <ARCH>]

Build a portable, relocatable R distribution for Windows from the official
CRAN installer. No system installation or third-party tools required.

Parameters:
  -RVersion       R version to build (e.g., 4.5.3, 4.4.1)
  -Architecture   Target architecture: x64 (default) or aarch64
  -OutputDir      Output directory (default: current directory)
  -Help           Show this help

Examples:
  .\build.ps1 -RVersion "4.5.3"
  .\build.ps1 -RVersion "4.5.2" -Architecture "aarch64"

Output:
  portable-r-{VERSION}-win-{ARCH}\            Unpacked portable R
  portable-r-{VERSION}-win-{ARCH}.zip         Archive for distribution
  portable-r-{VERSION}-win-{ARCH}.zip.sha256

Supported versions:
  x64:     4.3.0 - 4.5.3
  aarch64: 4.4.0 - 4.5.2 (from r-project.org experimental builds)
"@
    exit 0
}

# ── Supported versions ───────────────────────────────────────────────────────
# Update these lists when new R versions are released on CRAN or r-project.org.

$VersionsX64     = @("4.3.0","4.3.1","4.3.2","4.3.3",
                      "4.4.0","4.4.1","4.4.2","4.4.3",
                      "4.5.0","4.5.1","4.5.2","4.5.3")

$VersionsAarch64 = @("4.4.0","4.4.1","4.4.2","4.4.3",
                      "4.5.0","4.5.1","4.5.2")

# ── Arguments ────────────────────────────────────────────────────────────────

# Normalize architecture name
if ($Architecture -eq "aarch64" -or $Architecture -eq "arm64") {
    $Architecture = "aarch64"
}

# Validate version against supported list
$supported = if ($Architecture -eq "aarch64") { $VersionsAarch64 } else { $VersionsX64 }
if ($RVersion -notin $supported) {
    Err "R $RVersion is not available for $Architecture"
    Detail "Supported versions: $($supported -join ', ')"
    exit 1
}

# Set installer filename based on architecture
if ($Architecture -eq "aarch64") {
    $installerFile = "R-${RVersion}-aarch64.exe"
} else {
    $installerFile = "R-${RVersion}-win.exe"
}

$outputName = "portable-r-${RVersion}-win-${Architecture}"
$outputPath = Join-Path $OutputDir $outputName

Write-Host ""
Write-Host "Portable R $RVersion for Windows ($Architecture)" -ForegroundColor White
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Download R installer
# x64 builds come from CRAN (current at /base/, older at /base/old/{VERSION}/).
# ARM64 builds come from R's experimental aarch64 repository.
# ═══════════════════════════════════════════════════════════════════════════════

Step "Downloading R installer"

if (-not (Test-Path $installerFile)) {
    if ($Architecture -eq "aarch64") {
        $primaryUrl = "https://www.r-project.org/nosvn/winutf8/aarch64/R-4-signed/$installerFile"
        $fallbackUrl = $primaryUrl
    } else {
        $baseUrl = "https://cloud.r-project.org/bin/windows/base"
        $primaryUrl = "${baseUrl}/$installerFile"
        $fallbackUrl = "${baseUrl}/old/${RVersion}/$installerFile"
    }

    Detail $primaryUrl
    # Prefer curl.exe for downloads (Invoke-WebRequest is slow on large files)
    $curlExe = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlExe) {
        $null = & curl.exe -fSL -o $installerFile $primaryUrl 2>&1
        if ($LASTEXITCODE -ne 0) {
            Detail "Not at primary URL, trying archive..."
            $null = & curl.exe -fSL -o $installerFile $fallbackUrl 2>&1
        }
        Ok "Downloaded $installerFile"
    } else {
        try {
            Invoke-WebRequest -Uri $primaryUrl -OutFile $installerFile
            Ok "Downloaded $installerFile"
        } catch {
            Detail "Not at primary URL, trying archive..."
            Invoke-WebRequest -Uri $fallbackUrl -OutFile $installerFile
            Ok "Downloaded $installerFile (from archive)"
        }
    }
} else {
    Ok "Using cached $installerFile"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Extract installer via silent install
# Runs the Inno Setup installer with /VERYSILENT to place R files directly into
# the output directory. /CURRENTUSER avoids admin elevation, /NOICONS skips
# Start Menu shortcuts. Installer artifacts (uninstaller, registry entries,
# shortcuts) are cleaned up afterward.
# ═══════════════════════════════════════════════════════════════════════════════

Step "Extracting installer"

if (Test-Path $outputPath) {
    Remove-Item -Recurse -Force $outputPath
}

$absInstaller = (Resolve-Path $installerFile).Path
$absOutput = Join-Path (Resolve-Path $OutputDir).Path $outputName

Detail "Running silent install to: $absOutput"
$proc = Start-Process -Wait -PassThru -FilePath $absInstaller -ArgumentList @(
    "/VERYSILENT",
    "/SUPPRESSMSGBOXES",
    "/CURRENTUSER",
    "/NOICONS",
    "/DIR=$absOutput"
)

if ($proc.ExitCode -ne 0) {
    Err "Installer exited with code $($proc.ExitCode)"
    exit 1
}

Ok "Extracted R files"

# Clean up artifacts left by the silent install
Remove-Item -Path (Join-Path $absOutput "unins*.exe") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $absOutput "unins*.dat") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $absOutput "unins*.msg") -Force -ErrorAction SilentlyContinue

Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
    Where-Object { $_.GetValue("InstallLocation") -like "*$outputName*" } |
    ForEach-Object { Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue }
Remove-Item "HKCU:\Software\R-core" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\R" -Recurse -Force -ErrorAction SilentlyContinue

Ok "Cleaned up installer artifacts, registry entries, and shortcuts"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Configure for portability
# R for Windows is already relocatable (Rscript.exe finds R_HOME relative to
# itself), so no DLL path patching is needed. We just configure library paths
# and the default CRAN mirror.
# ═══════════════════════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Verify the build
# ═══════════════════════════════════════════════════════════════════════════════

Step "Verifying portable R"

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

    # CRAN does not distribute ARM64 Windows binary packages, so skip this test for aarch64
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
} else {
    Err "Rscript.exe not found at: $rscript"
    Detail "Contents of output directory:"
    Get-ChildItem $outputPath -ErrorAction SilentlyContinue | Format-Table Name
}

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Create archive
# ═══════════════════════════════════════════════════════════════════════════════

Step "Creating archive"

$zipFile = "${outputName}.zip"
if (Test-Path $zipFile) { Remove-Item $zipFile }
Compress-Archive -Path $outputPath -DestinationPath $zipFile

$hash = (Get-FileHash -Algorithm SHA256 $zipFile).Hash.ToLower()
"${hash}  ${zipFile}" | Out-File -FilePath "${zipFile}.sha256" -Encoding ASCII
$size = "$([math]::Round((Get-Item $zipFile).Length / 1MB, 1)) MB"

Ok "$zipFile ($size)"
Detail "SHA256: $hash"

# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "Build complete" -ForegroundColor Green
Write-Host ""
