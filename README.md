# Portable R for Windows

Portable, relocatable R distributions for Windows built from official CRAN binaries. No installation required. Extract and run.

## Quick Install

**PowerShell**

```powershell
Invoke-WebRequest -Uri "https://github.com/portable-r/portable-r-windows/releases/download/v4.5.3/portable-r-4.5.3-win-x64.zip" -OutFile portable-r.zip
Expand-Archive portable-r.zip -DestinationPath .
```

**Command Prompt (curl, Windows 10+)**

```cmd
curl -fSLO https://github.com/portable-r/portable-r-windows/releases/download/v4.5.3/portable-r-4.5.3-win-x64.zip
tar -xf portable-r-4.5.3-win-x64.zip
```

Replace `4.5.3` with your desired version. See [all releases](https://github.com/portable-r/portable-r-windows/releases).

## Usage

```cmd
:: Run an R script
portable-r-4.5.3-win-x64\bin\Rscript.exe my_script.R

:: Start interactive R
portable-r-4.5.3-win-x64\bin\R.exe

:: Install and use packages (works out of the box)
portable-r-4.5.3-win-x64\bin\Rscript.exe -e "install.packages('jsonlite'); library(jsonlite); cat(toJSON(list(hello='world')))"
```

No registry changes, no system-wide modifications. Packages install to the local `library\` directory inside the portable R folder.

## Available Versions

ARM64 builds are available for R 4.4.0 through 4.5.2, sourced from [R's experimental aarch64 builds](https://www.r-project.org/nosvn/winutf8/aarch64/R-4-signed/).

| R Version | Windows x64 | Windows ARM64 |
|-----------|-------------|---------------|
| 4.5.3 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.3/portable-r-4.5.3-win-x64.zip) | |
| 4.5.2 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.2/portable-r-4.5.2-win-x64.zip) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.2/portable-r-4.5.2-win-aarch64.zip) |
| 4.5.1 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.1/portable-r-4.5.1-win-x64.zip) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.1/portable-r-4.5.1-win-aarch64.zip) |
| 4.5.0 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.0/portable-r-4.5.0-win-x64.zip) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.0/portable-r-4.5.0-win-aarch64.zip) |
| 4.4.3 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.3/portable-r-4.4.3-win-x64.zip) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.3/portable-r-4.4.3-win-aarch64.zip) |
| 4.4.2 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.2/portable-r-4.4.2-win-x64.zip) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.2/portable-r-4.4.2-win-aarch64.zip) |
| 4.4.1 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.1/portable-r-4.4.1-win-x64.zip) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.1/portable-r-4.4.1-win-aarch64.zip) |
| 4.4.0 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.0/portable-r-4.4.0-win-x64.zip) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.0/portable-r-4.4.0-win-aarch64.zip) |
| 4.3.3 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.3/portable-r-4.3.3-win-x64.zip) | |
| 4.3.2 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.2/portable-r-4.3.2-win-x64.zip) | |
| 4.3.1 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.1/portable-r-4.3.1-win-x64.zip) | |
| 4.3.0 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.0/portable-r-4.3.0-win-x64.zip) | |

## URL Pattern

All release assets follow a predictable URL:

```
https://github.com/portable-r/portable-r-windows/releases/download/v{VERSION}/portable-r-{VERSION}-win-{ARCH}.zip
```

Where `{VERSION}` is e.g. `4.5.3` and `{ARCH}` is `x64` or `aarch64`. SHA256 checksums are at the same URL with a `.sha256` suffix.

## What gets patched

R for Windows is already designed to be relocatable (`Rscript.exe` finds `R_HOME` relative to itself), so the build is simpler than the [macOS version](https://github.com/portable-r/portable-r-macos). No DLL path rewriting or codesigning is needed.

1. Run the R `.exe` installer silently to a custom directory (no system changes)
2. Clean up installer artifacts (uninstaller, registry entries, Start Menu shortcuts)
3. Set `.libPaths(.Library)` in `etc/Rprofile.site` so packages install locally
4. Configure default CRAN mirror
5. Verify the build (version, code execution, package loading, binary package install)
6. Package as a `.zip` archive with SHA256 checksum

## Development

### Building locally

`build.ps1` downloads the CRAN installer, runs it silently to extract R into a custom directory, configures local library paths, verifies the build (including a binary package install test), and packages the result as a `.zip`. No third-party tools are needed.

```powershell
.\build.ps1 -RVersion "4.5.3"                          # x64 (default)
.\build.ps1 -RVersion "4.5.2" -Architecture "aarch64"   # ARM64
.\build.ps1 -Help                                       # Show all options
```

The build script validates the requested version against its built-in supported version lists and exits early with a clear message for unsupported combinations.

### Testing

A test suite (`tests/run-tests.ps1`) validates the build across 9 categories and 26 checks covering directory structure, installer cleanup, execution, base packages, capabilities, internet, numerics, and package installation (both binary and source).

```powershell
.\tests\run-tests.ps1 "portable-r-4.5.3-win-x64"
```

### CI / GitHub Actions

Two workflows are available, both triggered manually via `workflow_dispatch`:

- **Build Portable R** (`build-portable-r.yml`): Builds a single R version for both x64 and ARM64 (when available), runs the test suite, and creates a GitHub release. Runs are serialized so releases are created in order.
- **Build All R Versions** (`build-all-versions.yml`): Builds all supported versions across both architectures with a release job per version. Includes a dry-run option for testing.

Releases are **not created automatically** on push. They must be triggered manually from the [Actions tab](../../actions).

ARM64 builds that are not available for a given R version (e.g., 4.3.x or 4.5.3) are skipped gracefully in CI without failing the workflow.

## Related

- [portable-r-macos](https://github.com/portable-r/portable-r-macos): Portable R for macOS (Apple Silicon and Intel)

## License

R itself is licensed under GPL-2 | GPL-3. This repository provides build automation only.
