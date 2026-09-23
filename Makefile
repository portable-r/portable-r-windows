# Build targets for portable R and Rtools on Windows (run: make help).
# Each recipe runs make.ps1 directly, with no shell in between: no SHELL
# override (native Windows make resolves it to a path with spaces) and no
# shell metacharacters (so make can start pwsh itself). Settings reach
# make.ps1 through the environment.

# ── Configuration ────────────────────────────────────────────────────────────

ARCH ?= x64
export ARCH VERSION RTVERSION

RUN = pwsh -NoProfile -ExecutionPolicy Bypass -File make.ps1

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: help build build-full build-rtools build-all build-all-full build-all-rtools \
	test test-full test-rtools verify clean clean-all list

help: ## Show this help
	@$(RUN) help

build: ## Build portable R (VERSION=x.y.z)
	@$(RUN) build

build-full: ## Build portable R + Rtools (VERSION=x.y.z)
	@$(RUN) build-full

build-rtools: ## Build standalone Rtools (RTVERSION=43|44|45)
	@$(RUN) build-rtools

build-all: ## Build all R versions listed in versions.json
	@$(RUN) build-all

build-all-full: ## Build all R versions with Rtools
	@$(RUN) build-all-full

build-all-rtools: ## Build all Rtools versions listed in versions.json
	@$(RUN) build-all-rtools

test: ## Test a portable R build (VERSION=x.y.z)
	@$(RUN) test

test-full: ## Test an R + Rtools build (VERSION=x.y.z)
	@$(RUN) test-full

test-rtools: ## Test a standalone Rtools build (RTVERSION=43|44|45)
	@$(RUN) test-rtools

verify: ## Quick verify an existing build (VERSION=x.y.z)
	@$(RUN) verify

clean: ## Remove build artifacts for a single version (VERSION=x.y.z)
	@$(RUN) clean

clean-all: ## Remove all build artifacts
	@$(RUN) clean-all

list: ## List all supported versions
	@$(RUN) list
