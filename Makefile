SHELL := pwsh.exe -NoProfile -Command

# ── Configuration ────────────────────────────────────────────────────────────

ARCH       ?= x64
VERSIONS   = 4.3.0 4.3.1 4.3.2 4.3.3 4.4.0 4.4.1 4.4.2 4.4.3 4.5.0 4.5.1 4.5.2 4.5.3
RTVERSIONS = 43 44 45

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: help build build-full build-rtools build-all test test-full test-rtools clean clean-all list

help: ## Show this help
	@Write-Host ""; \
	Write-Host "  Portable R + Rtools for Windows - Build Targets" -ForegroundColor White; \
	Write-Host ""; \
	Write-Host "  R only:" -ForegroundColor DarkGray; \
	Write-Host "  build VERSION=x.y.z         Build portable R" -ForegroundColor Cyan; \
	Write-Host "  test VERSION=x.y.z          Test a portable R build" -ForegroundColor Cyan; \
	Write-Host ""; \
	Write-Host "  R + Rtools:" -ForegroundColor DarkGray; \
	Write-Host "  build-full VERSION=x.y.z    Build portable R + Rtools" -ForegroundColor Cyan; \
	Write-Host "  test-full VERSION=x.y.z     Test an R + Rtools build" -ForegroundColor Cyan; \
	Write-Host ""; \
	Write-Host "  Rtools standalone:" -ForegroundColor DarkGray; \
	Write-Host "  build-rtools RTVERSION=45   Build standalone Rtools" -ForegroundColor Cyan; \
	Write-Host "  test-rtools RTVERSION=45    Test a standalone Rtools build" -ForegroundColor Cyan; \
	Write-Host ""; \
	Write-Host "  Batch:" -ForegroundColor DarkGray; \
	Write-Host "  build-all                   Build all R versions (R only)" -ForegroundColor Cyan; \
	Write-Host "  build-all-full              Build all R versions (R + Rtools)" -ForegroundColor Cyan; \
	Write-Host "  build-all-rtools            Build all Rtools versions" -ForegroundColor Cyan; \
	Write-Host "  list                        List supported versions" -ForegroundColor Cyan; \
	Write-Host "  clean VERSION=x.y.z         Remove build artifacts for a version" -ForegroundColor Cyan; \
	Write-Host "  clean-all                   Remove all build artifacts" -ForegroundColor Cyan; \
	Write-Host ""; \
	Write-Host "  Examples:"; \
	Write-Host "    make build VERSION=4.5.3"; \
	Write-Host "    make build-full VERSION=4.5.3"; \
	Write-Host "    make build-rtools RTVERSION=45"; \
	Write-Host "    make build-all"; \
	Write-Host ""

# ── R only ───────────────────────────────────────────────────────────────────

build: ## Build portable R (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make build VERSION=4.5.3)
endif
	@.\build.ps1 -RVersion "$(VERSION)" -Architecture "$(ARCH)"

build-all: ## Build all R versions
	@Write-Host "Building $(words $(VERSIONS)) versions" -ForegroundColor White; \
	$$pass = 0; $$fail = 0; \
	foreach ($$v in @("$(VERSIONS)".Split(" "))) { \
		Write-Host "`n-- R $$v --" -ForegroundColor White; \
		try { .\build.ps1 -RVersion $$v -Architecture "$(ARCH)"; $$pass++ } \
		catch { Write-Host "x R $$v failed" -ForegroundColor Red; $$fail++ } \
	}; \
	Write-Host "`nResults: $$pass succeeded, $$fail failed" -ForegroundColor White

test: ## Test a portable R build (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make test VERSION=4.5.3)
endif
	@.\tests\run-tests.ps1 "portable-r-$(VERSION)-win-$(ARCH)"

# ── R + Rtools ───────────────────────────────────────────────────────────────

build-full: ## Build portable R + Rtools (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make build-full VERSION=4.5.3)
endif
	@.\build.ps1 -RVersion "$(VERSION)" -Architecture "$(ARCH)" -IncludeRtools

build-all-full: ## Build all R versions with Rtools
	@Write-Host "Building $(words $(VERSIONS)) versions (R + Rtools)" -ForegroundColor White; \
	$$pass = 0; $$fail = 0; \
	foreach ($$v in @("$(VERSIONS)".Split(" "))) { \
		Write-Host "`n-- R $$v + Rtools --" -ForegroundColor White; \
		try { .\build.ps1 -RVersion $$v -Architecture "$(ARCH)" -IncludeRtools; $$pass++ } \
		catch { Write-Host "x R $$v + Rtools failed" -ForegroundColor Red; $$fail++ } \
	}; \
	Write-Host "`nResults: $$pass succeeded, $$fail failed" -ForegroundColor White

test-full: ## Test an R + Rtools build (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make test-full VERSION=4.5.3)
endif
	@.\tests\run-tests.ps1 "portable-r-$(VERSION)-win-$(ARCH)-full"

# ── Rtools standalone ────────────────────────────────────────────────────────

build-rtools: ## Build standalone Rtools (RTVERSION=43|44|45)
ifndef RTVERSION
	$(error RTVERSION is required. Usage: make build-rtools RTVERSION=45)
endif
	@.\build.ps1 -RtoolsOnly -RtoolsVersion "$(RTVERSION)" -Architecture "$(ARCH)"

build-all-rtools: ## Build all Rtools versions
	@Write-Host "Building $(words $(RTVERSIONS)) Rtools versions" -ForegroundColor White; \
	$$pass = 0; $$fail = 0; \
	foreach ($$v in @("$(RTVERSIONS)".Split(" "))) { \
		Write-Host "`n-- Rtools$$v --" -ForegroundColor White; \
		try { .\build.ps1 -RtoolsOnly -RtoolsVersion $$v -Architecture "$(ARCH)"; $$pass++ } \
		catch { Write-Host "x Rtools$$v failed" -ForegroundColor Red; $$fail++ } \
	}; \
	Write-Host "`nResults: $$pass succeeded, $$fail failed" -ForegroundColor White

test-rtools: ## Test a standalone Rtools build (RTVERSION=43|44|45)
ifndef RTVERSION
	$(error RTVERSION is required. Usage: make test-rtools RTVERSION=45)
endif
	@.\tests\run-rtools-tests.ps1 "portable-rtools$(RTVERSION)-win-$(ARCH)"

# ── Verify ───────────────────────────────────────────────────────────────────

verify: ## Quick verify an existing build (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make verify VERSION=4.5.3)
endif
	@$$dir = "portable-r-$(VERSION)-win-$(ARCH)"; \
	if (-not (Test-Path $$dir)) { Write-Host "x $$dir not found" -ForegroundColor Red; exit 1 }; \
	$$r = Join-Path $$dir "bin\Rscript.exe"; \
	Write-Host "Verifying $$dir" -ForegroundColor White; \
	& $$r --version 2>&1 | ForEach-Object { Write-Host "  $$_" -ForegroundColor Green }; \
	& $$r -e "cat(R.version.string, '\n')" 2>&1 | ForEach-Object { Write-Host "  $$_" -ForegroundColor Green }; \
	Write-Host "$([char]0x2713) All checks passed" -ForegroundColor Green

# ── Clean ────────────────────────────────────────────────────────────────────

clean: ## Remove build artifacts for a single version (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make clean VERSION=4.5.3)
endif
	@Remove-Item -Recurse -Force "portable-r-$(VERSION)-win-$(ARCH)" -ErrorAction SilentlyContinue; \
	Remove-Item -Force "portable-r-$(VERSION)-win-$(ARCH).zip" -ErrorAction SilentlyContinue; \
	Remove-Item -Force "portable-r-$(VERSION)-win-$(ARCH).zip.sha256" -ErrorAction SilentlyContinue; \
	Remove-Item -Recurse -Force "portable-r-$(VERSION)-win-$(ARCH)-full" -ErrorAction SilentlyContinue; \
	Remove-Item -Force "portable-r-$(VERSION)-win-$(ARCH)-full.zip" -ErrorAction SilentlyContinue; \
	Remove-Item -Force "portable-r-$(VERSION)-win-$(ARCH)-full.zip.sha256" -ErrorAction SilentlyContinue

clean-all: ## Remove all build artifacts
	@Remove-Item -Recurse -Force portable-r-*-win-*/ -ErrorAction SilentlyContinue; \
	Remove-Item -Force portable-r-*-win-*.zip -ErrorAction SilentlyContinue; \
	Remove-Item -Force portable-r-*-win-*.zip.sha256 -ErrorAction SilentlyContinue; \
	Remove-Item -Recurse -Force portable-rtools*-win-*/ -ErrorAction SilentlyContinue; \
	Remove-Item -Force portable-rtools*-win-*.zip -ErrorAction SilentlyContinue; \
	Remove-Item -Force portable-rtools*-win-*.zip.sha256 -ErrorAction SilentlyContinue; \
	Remove-Item -Force R-*-win.exe -ErrorAction SilentlyContinue; \
	Remove-Item -Force R-*-aarch64.exe -ErrorAction SilentlyContinue; \
	Remove-Item -Force rtools4*-*.exe -ErrorAction SilentlyContinue

list: ## List all supported versions
	@Write-Host "R versions ($(ARCH)):"; \
	foreach ($$v in @("$(VERSIONS)".Split(" "))) { \
		$$dir = "portable-r-$$v-win-$(ARCH)"; \
		$$dirFull = "portable-r-$$v-win-$(ARCH)-full"; \
		$$hasR = Test-Path "$$dir.zip"; \
		$$hasFull = Test-Path "$$dirFull.zip"; \
		if ($$hasR -and $$hasFull) { Write-Host "  * $$v  (R + full built)" -ForegroundColor Green } \
		elseif ($$hasR) { Write-Host "  * $$v  (R built)" -ForegroundColor Green } \
		elseif ($$hasFull) { Write-Host "  * $$v  (full built)" -ForegroundColor Green } \
		elseif ((Test-Path $$dir) -or (Test-Path $$dirFull)) { Write-Host "  * $$v  (unpacked)" -ForegroundColor Yellow } \
		else { Write-Host "  o $$v" -ForegroundColor DarkGray } \
	}; \
	Write-Host ""; \
	Write-Host "Rtools versions ($(ARCH)):"; \
	foreach ($$v in @("$(RTVERSIONS)".Split(" "))) { \
		$$dir = "portable-rtools$$v-win-$(ARCH)"; \
		if (Test-Path "$$dir.zip") { Write-Host "  * Rtools$$v  (built)" -ForegroundColor Green } \
		elseif (Test-Path $$dir) { Write-Host "  * Rtools$$v  (unpacked)" -ForegroundColor Yellow } \
		else { Write-Host "  o Rtools$$v" -ForegroundColor DarkGray } \
	}
