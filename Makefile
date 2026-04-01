SHELL := pwsh.exe -NoProfile -Command

# ── Configuration ────────────────────────────────────────────────────────────

ARCH     ?= x64
VERSIONS = 4.3.0 4.3.1 4.3.2 4.3.3 4.4.0 4.4.1 4.4.2 4.4.3 4.5.0 4.5.1 4.5.2 4.5.3

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: help build build-all clean clean-all list verify test

help: ## Show this help
	@Write-Host ""; \
	Write-Host "  Portable R for Windows - Build Targets" -ForegroundColor White; \
	Write-Host ""; \
	Write-Host "  build VERSION=x.y.z    Build a single version" -ForegroundColor Cyan; \
	Write-Host "  build-all              Build all supported versions" -ForegroundColor Cyan; \
	Write-Host "  verify VERSION=x.y.z   Test a build without rebuilding" -ForegroundColor Cyan; \
	Write-Host "  list                   List all supported R versions" -ForegroundColor Cyan; \
	Write-Host "  clean VERSION=x.y.z    Remove build artifacts for a version" -ForegroundColor Cyan; \
	Write-Host "  clean-all              Remove all build artifacts" -ForegroundColor Cyan; \
	Write-Host ""; \
	Write-Host "  Examples:"; \
	Write-Host "    make build VERSION=4.5.3"; \
	Write-Host "    make build-all"; \
	Write-Host ""

build: ## Build a single version (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make build VERSION=4.5.3)
endif
	@.\build.ps1 -RVersion "$(VERSION)" -Architecture "$(ARCH)"

build-all: ## Build all supported versions
	@Write-Host "Building $(words $(VERSIONS)) versions" -ForegroundColor White; \
	$$pass = 0; $$fail = 0; \
	foreach ($$v in @("$(VERSIONS)".Split(" "))) { \
		Write-Host "`n-- R $$v --" -ForegroundColor White; \
		try { .\build.ps1 -RVersion $$v -Architecture "$(ARCH)"; $$pass++ } \
		catch { Write-Host "x R $$v failed" -ForegroundColor Red; $$fail++ } \
	}; \
	Write-Host "`nResults: $$pass succeeded, $$fail failed" -ForegroundColor White

verify: ## Verify an existing build (VERSION=x.y.z)
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

list: ## List all supported R versions
	@Write-Host "Supported versions ($(ARCH)):"; \
	foreach ($$v in @("$(VERSIONS)".Split(" "))) { \
		$$dir = "portable-r-$$v-win-$(ARCH)"; \
		if (Test-Path "$$dir.zip") { Write-Host "  * $$v  (built)" -ForegroundColor Green } \
		elseif (Test-Path $$dir) { Write-Host "  * $$v  (unpacked)" -ForegroundColor Yellow } \
		else { Write-Host "  o $$v" -ForegroundColor DarkGray } \
	}

test: ## Run full test suite on a build (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make test VERSION=4.5.3)
endif
	@.\tests\run-tests.ps1 "portable-r-$(VERSION)-win-$(ARCH)"

clean: ## Remove build artifacts for a single version (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make clean VERSION=4.5.3)
endif
	@Remove-Item -Recurse -Force "portable-r-$(VERSION)-win-$(ARCH)" -ErrorAction SilentlyContinue; \
	Remove-Item -Force "portable-r-$(VERSION)-win-$(ARCH).zip" -ErrorAction SilentlyContinue; \
	Remove-Item -Force "portable-r-$(VERSION)-win-$(ARCH).zip.sha256" -ErrorAction SilentlyContinue

clean-all: ## Remove all build artifacts
	@Remove-Item -Recurse -Force portable-r-*-win-*/ -ErrorAction SilentlyContinue; \
	Remove-Item -Force portable-r-*-win-*.zip -ErrorAction SilentlyContinue; \
	Remove-Item -Force portable-r-*-win-*.zip.sha256 -ErrorAction SilentlyContinue; \
	Remove-Item -Force R-*-win.exe -ErrorAction SilentlyContinue
