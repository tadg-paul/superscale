# ABOUTME: Build entry points for Superscale.
# ABOUTME: Provides build, test, install, release, and model conversion targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

BINARY_NAME := superscale
BUILD_DIR := .build/release
LINK_DIR := $(HOME)/.local/bin
RELEASE_VERSION ?=
SKIP_TESTS ?=

.PHONY: help build build-debug gui test test-ssim test-gui test-one-off test-visual clean install uninstall release release-gui release-models sync convert-models download-models

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

download-models: ## Download missing models from GitHub release
	@./scripts/download-models.sh

build: download-models ## Build release binary
	swift build -c release

build-debug: download-models ## Build debug binary
	swift build

GUI_BUILD_DIR = $(shell xcodebuild -project SuperscaleApp/SuperscaleApp.xcodeproj -scheme SuperscaleWithTests -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $$3}')

gui: download-models fetch-licences ## Build and launch the GUI app
	xcodebuild -project SuperscaleApp/SuperscaleApp.xcodeproj -scheme SuperscaleWithTests -configuration Debug build -quiet
	@ln -sfn "$(CURDIR)/models" "$(GUI_BUILD_DIR)/Superscale.app/Contents/MacOS/models"
	@open "$(GUI_BUILD_DIR)/Superscale.app"

fetch-licences: ## Download licence texts for face model download flow
	@mkdir -p SuperscaleApp/SuperscaleApp/Resources
	@curl -sL https://raw.githubusercontent.com/NVlabs/stylegan2/refs/heads/master/LICENSE.txt \
		-o SuperscaleApp/SuperscaleApp/Resources/LICENCE_NVIDIA.txt
	@curl -sL https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode.txt \
		-o SuperscaleApp/SuperscaleApp/Resources/LICENCE_CC_BY_NC_SA.txt

test: ## Run regression tests (excludes slow SSIM quality gate)
	swift test --skip SSIM_RT064

test-gui: ## Run GUI UI tests via XCUITest
	xcodebuild test -project SuperscaleApp/SuperscaleApp.xcodeproj -scheme SuperscaleWithTests -destination 'platform=macOS'

test-ssim: ## Run SSIM quality regression against PyTorch references (~2.5 min)
	swift test --filter SSIM_RT064

test-one-off: ## Run one-off tests
ifdef ISSUE
	swift test --filter "OT.*$(ISSUE)"
else
	swift test --filter "OT"
endif

test-visual: build-debug ## Upscale test images for visual inspection (UT-002)
	@if [ -d Tests/visual_output ] && ls Tests/visual_output/* >/dev/null 2>&1; then \
		echo "Cleaning stale visual output..."; \
		if command -v trash >/dev/null 2>&1; then \
			trash Tests/visual_output/*; \
		else \
			rm -f -- Tests/visual_output/*; \
		fi; \
	fi
	@mkdir -p Tests/visual_output
	@for img in Tests/images/*; do \
		base=$$(basename "$$img"); \
		cp -- "$$img" Tests/visual_output/original_$$base; \
		echo "Upscaling $$img..."; \
		.build/debug/$(BINARY_NAME) "$$img" -o Tests/visual_output/; \
	done
	@echo ""
	@echo "Visual output saved to Tests/visual_output/"
	@echo "Inspect before/after images there."

clean: ## Remove build artefacts
	rm -rf .build

install: build ## Build and symlink to ~/.local/bin
	@mkdir -p "$(LINK_DIR)"
	@ln -sf "$(CURDIR)/$(BUILD_DIR)/$(BINARY_NAME)" "$(LINK_DIR)/$(BINARY_NAME)"
	@ln -sfn "$(CURDIR)/models" "$(CURDIR)/$(BUILD_DIR)/models"
	@echo "Installed: $(LINK_DIR)/$(BINARY_NAME)"
	@case ":$$PATH:" in \
		*":$(LINK_DIR):"*) ;; \
		*) echo "WARNING: $(LINK_DIR) is not in your PATH. Add it to your shell profile." ;; \
	esac

uninstall: ## Remove symlink from ~/.local/bin
	@if [ -L "$(LINK_DIR)/$(BINARY_NAME)" ]; then rm -f "$(LINK_DIR)/$(BINARY_NAME)"; fi
	@echo "Uninstalled."

convert-models: ## Convert PyTorch models to CoreML (requires Python venv)
	@if [ ! -d ".venv" ]; then \
		echo "Creating venv with Python 3.12..."; \
		/opt/homebrew/bin/python3.12 -m venv .venv; \
		. .venv/bin/activate && pip install --upgrade pip && pip install -r scripts/requirements-convert.txt; \
	fi
	. .venv/bin/activate && python scripts/convert_model.py --all --input-dir checkpoints --output-dir models

release: ## Tag a release and update Homebrew formula (usage: make release [VERSION=x.y.z])
ifndef SKIP_TESTS
	@$(MAKE) test
	@$(MAKE) test-ssim
else
	@echo "SKIP_TESTS=1: skipping regression tests (caller asserts they already pass)"
endif
	@./scripts/release.sh $(RELEASE_VERSION)

release-gui: ## Build GUI .app, package DMG, update Homebrew cask
ifndef SKIP_TESTS
	@$(MAKE) test
	@$(MAKE) test-ssim
else
	@echo "SKIP_TESTS=1: skipping regression tests (caller asserts they already pass)"
endif
	@./scripts/release-gui.sh

release-models: ## Upload model artefacts to GitHub Release (usage: make release-models)
	@./scripts/release-models.sh

sync: ## Stage all, commit, pull (merge), push
	@if git diff --quiet && git diff --cached --quiet && [ -z "$$(git ls-files --others --exclude-standard)" ]; then \
		echo "Nothing to commit."; \
	else \
		git add --all && \
		git commit -m "sync: $$(date +%Y-%m-%d)" && \
		echo "Committed."; \
	fi
	@if [ -f .gitmodules ]; then \
		git submodule update --init --recursive; \
	fi
	@./scripts/check-models.sh
	git pull --rebase=false
	git push
