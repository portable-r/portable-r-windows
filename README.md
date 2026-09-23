# Portable R for Windows

Portable, relocatable R distributions for Windows built from the R installers: CRAN's for x64, and the builds listed under [Available Versions](#available-versions) for ARM64. No installation required. Extract and run.

An **R + Rtools** variant is also available, bundling the full [Rtools](https://cran.r-project.org/bin/windows/Rtools/) toolchain for compiling packages from source.

## Quick Install

**R only** (`.zip`, works in PowerShell or Command Prompt)

```
curl.exe -fSLO https://github.com/portable-r/portable-r-windows/releases/download/v4.6.1/portable-r-4.6.1-win-x64.zip
tar -xf portable-r-4.6.1-win-x64.zip
```

**R + Rtools** (`.7z`, requires [7-Zip](https://7-zip.org/))

```
curl.exe -fSLO https://github.com/portable-r/portable-r-windows/releases/download/v4.6.1/portable-r-4.6.1-win-x64-full.7z
& "$env:ProgramFiles\7-Zip\7z.exe" x portable-r-4.6.1-win-x64-full.7z
```

> Install 7-Zip if needed: `winget install 7zip.7zip`. The `$env:ProgramFiles` expands to `C:\Program Files`, so this works even when 7-Zip is not on PATH. The R + Rtools variant uses `.7z` (~850 MB) because the bundled toolchain (~3.5 GB uncompressed) exceeds GitHub's 2 GB release asset limit under zip compression.

Replace `4.6.1` with your desired version. See [all releases](https://github.com/portable-r/portable-r-windows/releases).

## Usage

```cmd
:: Run an R script
portable-r-4.6.1-win-x64\bin\Rscript.exe my_script.R

:: Start interactive R
portable-r-4.6.1-win-x64\bin\R.exe

:: Install and use packages (works out of the box)
portable-r-4.6.1-win-x64\bin\Rscript.exe -e "install.packages('jsonlite'); library(jsonlite); cat(toJSON(list(hello='world')))"

:: Install from source (R + Rtools variant)
portable-r-4.6.1-win-x64-full\bin\Rscript.exe -e "install.packages('Rcpp', type='source')"
```

No registry changes, no system-wide modifications. Packages install to the local `library\` directory inside the portable R folder.

## Available Versions

ARM64 builds are available for R 4.4.0+:

- **R 4.4.0 – 4.5.3**: [Tomáš Kalibera](#acknowledgements)'s aarch64 builds. Their original home, `r-project.org/nosvn/winutf8/aarch64/`, has been offline since August 2026, so the build fetches the same files from the [r-hub mirror](https://github.com/r-hub/R/releases) and checks each against a SHA256 pinned in `versions.json`. R 4.4.0 – 4.5.1 match archived copies of the originals byte for byte, 4.5.2 carries its original signature, and 4.5.3 is unsigned.
- **R 4.6.0+**: community builds from [r-devel/windows-arm64](https://github.com/r-devel/windows-arm64/releases) (see [contributor.r-project.org/windows-arm64](https://contributor.r-project.org/windows-arm64/)), checked against the SHA256 GitHub publishes for each installer. These are unsigned and not endorsed or supported by R Core.

### Packages on ARM64

CRAN does not publish Windows ARM64 binary packages.

- **R 4.6.0+**: binary packages come from [r-universe](https://r-universe.dev). `etc/Rprofile.site` sets `CRAN = "https://cran.r-universe.dev"` and `BIOC = "https://bioc-release.r-universe.dev"` (the r-devel installers' own default from R 4.6.1 on), and R fetches binaries from:
  - `https://cran.r-universe.dev/bin/windows/clang-aarch64/contrib/4.6/`
  - `https://bioc-release.r-universe.dev/bin/windows/clang-aarch64/contrib/4.6/`

  The `contrib/` directory follows the R version (R-devel uses `contrib/4.7/`). `bioc-release.r-universe.dev` serves the Bioconductor release for your R; `bioc.r-universe.dev` serves Bioconductor devel. If you change `options(repos)`, restore them with:

  ```r
  options(repos = c(CRAN = "https://cran.r-universe.dev",
                    BIOC = "https://bioc-release.r-universe.dev"))
  ```

  `Rscript --vanilla` skips `etc/Renviron.site` and `etc/Rprofile.site`, which hold the binary package type, these repositories and (in the + Rtools variant) the Rtools location. Under `--vanilla`, set `repos` yourself and expect source installs.
- **R 4.4.x – 4.5.x**: no binary packages exist. Packages install from CRAN source, so use the ARM64 + Rtools variant for any package that needs compilation.

<!-- BEGIN RELEASES -->

### R (with optional Rtools bundle)

| R Version | x64 | x64 + Rtools | ARM64 | ARM64 + Rtools |
|-----------|-----|-------------|-------|----------------|
| 4.6.1 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.1/portable-r-4.6.1-win-x64.zip) (104 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.1/portable-r-4.6.1-win-x64-full.7z) (859 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.1/portable-r-4.6.1-win-aarch64.zip) (99 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.1/portable-r-4.6.1-win-aarch64-full.7z) (874 MB) |
| 4.6.0 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.0/portable-r-4.6.0-win-x64.zip) (104 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.0/portable-r-4.6.0-win-x64-full.7z) (859 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.0/portable-r-4.6.0-win-aarch64.zip) (99 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.6.0/portable-r-4.6.0-win-aarch64-full.7z) (874 MB) |
| 4.5.3 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.3/portable-r-4.5.3-win-x64.zip) (103 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.3/portable-r-4.5.3-win-x64-full.7z) (858 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.3/portable-r-4.5.3-win-aarch64.zip) (98 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.3/portable-r-4.5.3-win-aarch64-full.7z) (873 MB) |
| 4.5.2 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.2/portable-r-4.5.2-win-x64.zip) (103 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.2/portable-r-4.5.2-win-x64-full.7z) (858 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.2/portable-r-4.5.2-win-aarch64.zip) (98 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.2/portable-r-4.5.2-win-aarch64-full.7z) (873 MB) |
| 4.5.1 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.1/portable-r-4.5.1-win-x64.zip) (103 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.1/portable-r-4.5.1-win-x64-full.7z) (857 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.1/portable-r-4.5.1-win-aarch64.zip) (98 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.1/portable-r-4.5.1-win-aarch64-full.7z) (873 MB) |
| 4.5.0 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.0/portable-r-4.5.0-win-x64.zip) (102 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.0/portable-r-4.5.0-win-x64-full.7z) (857 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.0/portable-r-4.5.0-win-aarch64.zip) (97 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.5.0/portable-r-4.5.0-win-aarch64-full.7z) (873 MB) |
| 4.4.3 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.3/portable-r-4.4.3-win-x64.zip) (101 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.3/portable-r-4.4.3-win-x64-full.7z) (815 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.3/portable-r-4.4.3-win-aarch64.zip) (96 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.3/portable-r-4.4.3-win-aarch64-full.7z) (769 MB) |
| 4.4.2 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.2/portable-r-4.4.2-win-x64.zip) (99 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.2/portable-r-4.4.2-win-x64-full.7z) (813 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.2/portable-r-4.4.2-win-aarch64.zip) (95 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.2/portable-r-4.4.2-win-aarch64-full.7z) (768 MB) |
| 4.4.1 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.1/portable-r-4.4.1-win-x64.zip) (99 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.1/portable-r-4.4.1-win-x64-full.7z) (812 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.1/portable-r-4.4.1-win-aarch64.zip) (94 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.1/portable-r-4.4.1-win-aarch64-full.7z) (768 MB) |
| 4.4.0 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.0/portable-r-4.4.0-win-x64.zip) (98 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.0/portable-r-4.4.0-win-x64-full.7z) (812 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.0/portable-r-4.4.0-win-aarch64.zip) (94 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.4.0/portable-r-4.4.0-win-aarch64-full.7z) (767 MB) |
| 4.3.3 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.3/portable-r-4.3.3-win-x64.zip) (95 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.3/portable-r-4.3.3-win-x64-full.7z) (794 MB) |  |  |
| 4.3.2 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.2/portable-r-4.3.2-win-x64.zip) (95 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.2/portable-r-4.3.2-win-x64-full.7z) (794 MB) |  |  |
| 4.3.1 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.1/portable-r-4.3.1-win-x64.zip) (94 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.1/portable-r-4.3.1-win-x64-full.7z) (793 MB) |  |  |
| 4.3.0 | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.0/portable-r-4.3.0-win-x64.zip) (94 MB) | [download](https://github.com/portable-r/portable-r-windows/releases/download/v4.3.0/portable-r-4.3.0-win-x64-full.7z) (793 MB) |  |  |

<sub>Last update check: 2026-08-13 · Last release built: 2026-09-23 (R 4.6.1)</sub>

<!-- END RELEASES -->

## URL Pattern

All release assets follow a predictable URL:

```
# R only (.zip)
https://github.com/portable-r/portable-r-windows/releases/download/v{VERSION}/portable-r-{VERSION}-win-{ARCH}.zip

# R + Rtools (.7z)
https://github.com/portable-r/portable-r-windows/releases/download/v{VERSION}/portable-r-{VERSION}-win-{ARCH}-full.7z
```

Where `{VERSION}` is e.g. `4.6.1` and `{ARCH}` is `x64` or `aarch64`. SHA256 checksums are at the same URL with a `.sha256` suffix.

## What Gets Patched

R for Windows is already designed to be relocatable (`Rscript.exe` finds `R_HOME` relative to itself), so the build is simpler than the [macOS version](https://github.com/portable-r/portable-r-macos). No DLL path rewriting or codesigning is needed.

1. Run the R `.exe` installer silently to a custom directory (no system changes)
2. Clean up installer artifacts (uninstaller, registry entries, Start Menu shortcuts)
3. Set `.libPaths(.Library)` in `etc/Rprofile.site` so packages install locally
4. Configure default package repositories (CRAN mirror; r-universe for ARM64 R 4.6+)

The R + Rtools variant additionally extracts the Rtools installer into a `rtools{VER}/` subdirectory and configures `etc/Renviron.site` to prepend the bundled toolchain to `PATH` using `${R_HOME}`, so `gcc`, `make`, and source package compilation work without any system changes. Each R series maps to a specific Rtools version (R 4.5.x uses Rtools45, R 4.4.x uses Rtools44, R 4.3.x uses Rtools43).

## Development

### Building locally

```powershell
.\build.ps1 -RVersion "4.6.1"                            # R only (x64)
.\build.ps1 -RVersion "4.6.1" -IncludeRtools             # R + Rtools
.\build.ps1 -RVersion "4.6.1" -Architecture "aarch64"    # ARM64
.\build.ps1 -RtoolsOnly -RtoolsVersion "45"              # Rtools standalone
.\build.ps1 -Help                                        # Show all options
```

### Testing

A test suite (`tests/run-tests.ps1`) validates the build across directory structure, installer cleanup, execution, base packages, capabilities, internet, numerics, and package installation. When bundled Rtools is detected, it also verifies compiler access and source package compilation.

```powershell
.\tests\run-tests.ps1 "portable-r-4.6.1-win-x64"
.\tests\run-tests.ps1 "portable-r-4.6.1-win-x64-full"
```

### Version management

`versions.json` is the single source of truth for supported R versions, Rtools versions, installer URLs, and installer SHA256 pins; the build scripts, workflows and `Makefile` all read their version lists from it. `check-updates.sh` checks CRAN and the r-devel/windows-arm64 GitHub releases daily to detect new releases. `generate-readme.sh` updates the version tables in this README from GitHub releases, and the line under them: the date of the last daily update check of CRAN and r-devel/windows-arm64 (`LAST_CHECKED`) and of the last release build, which includes an architecture or variant added to an existing release.

### CI / GitHub Actions

Four workflows are available, triggered manually via `workflow_dispatch`:

- **Build Portable R** (`build-portable-r.yml`): Builds a single R version for x64 and ARM64 (when available). The `arch` input (`all`, `x64` or `aarch64`) builds one architecture alone and leaves the other architecture's published files untouched, e.g. to add ARM64 to an existing release. Optional `include_rtools` checkbox builds the R + Rtools variant alongside, and `full_only` builds just that variant (used for Rtools updates, so the published R-only zip is left as it is). After the release is published, regenerates the README download table (`update-readme.yml`) so it always reflects the latest release on GitHub.
- **Build Portable Rtools** (`build-rtools.yml`): Builds standalone Rtools (`.7z`) for a given version.
- **Build All R Versions** (`build-all-versions.yml`): Builds every version `versions.json` lists (or the ones given in `versions`), one at a time, with the same `arch` and `include_rtools` options.
- **Check for Updates** (`check-updates.yml`): Runs daily to detect new R and Rtools releases. Updates `versions.json`, regenerates this README, and triggers builds for just the new versions and architectures (`trigger-builds.sh`). An unreachable upstream source is reported (the run fails at the end) without blocking the other checks, and `LAST_CHECKED` is committed every day.

## Related

- [portable-r-macos](https://github.com/portable-r/portable-r-macos): Portable R for macOS (Apple Silicon and Intel)

## Acknowledgements

This project rests on the years of work [Tomáš Kalibera](https://stat.ethz.ch/pipermail/r-announce/2026/000721.html) put into modernising R on Windows — the UCRT toolchain, Rtools 4.x, and the relocatable installer that makes a "portable" build possible at all. Tomáš passed away on 1 April 2026; without his sustained effort on the Windows port this distribution would not exist. Our deepest thanks, and condolences to his family and colleagues.

At the time of R 4.6.0's release it is not yet clear whether a dedicated Rtools46 will ship or whether Rtools45 will continue to be the supported toolchain for R 4.6.x. This repository currently maps R 4.6.x → Rtools45 and will be updated once R Core announces the toolchain plan.

## License

R itself is licensed under GPL-2 | GPL-3. Rtools components are distributed under their respective licenses (GCC: GPL, MSYS2 tools: various). This repository provides build automation only.
