# ---- rust-cargo.mk (enhanced) ----
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

TOOLCHAIN    ?= stable
PROFILE      ?= dev
TARGET_DIR   ?= target
FEATURES     ?=
TARGET_ARCH  ?=
CLIPPY_DENY  ?= warnings

CARGO        := cargo +$(TOOLCHAIN)

# Encode params into stamps
FEATURES_HASH := $(shell printf '%s' '$(FEATURES)' | shasum | awk '{print $$1}') # Unique stamps per feature combination
TOOLCHAIN_STAMP := .toolchain-$(TOOLCHAIN)-ok
BUILD_STAMP     := $(TARGET_DIR)/.build-$(PROFILE)-$(TOOLCHAIN)-$(TARGET_ARCH)-$(FEATURES_HASH)-ok

DEPS := $(wildcard Cargo.toml Cargo.lock)
# Expand as needed for deeper workspaces (add */*/*/Cargo.toml etc.)
WORKSPACE_DEPS := $(wildcard */Cargo.toml */*/Cargo.toml)

# Common flags
PROFILE_FLAGS := $(if $(filter $(PROFILE),release),--release,)
FEATURE_FLAGS := $(if $(FEATURES),--features $(FEATURES),)
TARGET_FLAGS  := $(if $(TARGET_ARCH),--target $(TARGET_ARCH),)

.PHONY: help all toolchain build test check clippy clippy-fix fmt fmt-check clean run reinstall nextest

help:
	@echo "Rust Cargo Makefile"
	@echo "Targets: toolchain build test check clippy clippy-fix fmt fmt-check nextest clean run reinstall"
	@echo "Vars: TOOLCHAIN=$(TOOLCHAIN) PROFILE=$(PROFILE) TARGET_ARCH=$(TARGET_ARCH) FEATURES='$(FEATURES)'"

all: build

# Toolchain via rustup
$(TOOLCHAIN_STAMP):
	@echo "[toolchain] checking rustup & installing: $(TOOLCHAIN)"
	@if ! command -v rustup >/dev/null 2>&1; then \
	  echo "ERROR: rustup not found. Install: https://rustup.rs"; exit 1; fi
	rustup toolchain install $(TOOLCHAIN)
	@if [ -n "$(TARGET_ARCH)" ]; then \
	  echo "[toolchain] adding target: $(TARGET_ARCH)"; \
	  rustup target add $(TARGET_ARCH) --toolchain $(TOOLCHAIN); \
	fi
	@touch $@

toolchain: $(TOOLCHAIN_STAMP)

# Order-only: ensure target dir exists
$(TARGET_DIR):
	@mkdir -p $(TARGET_DIR)

# Build with stamp
$(BUILD_STAMP): $(TOOLCHAIN_STAMP) $(DEPS) $(WORKSPACE_DEPS) | $(TARGET_DIR)
	@echo "[build] profile=$(PROFILE) toolchain=$(TOOLCHAIN) target=$(TARGET_ARCH) features='$(FEATURES)'"
	$(CARGO) build $(PROFILE_FLAGS) $(FEATURE_FLAGS) $(TARGET_FLAGS)
	@touch $@

build: $(BUILD_STAMP)

test: $(TOOLCHAIN_STAMP)
	$(CARGO) test $(PROFILE_FLAGS) $(FEATURE_FLAGS) $(TARGET_FLAGS)

check: $(TOOLCHAIN_STAMP)
	$(CARGO) check $(PROFILE_FLAGS) $(FEATURE_FLAGS) $(TARGET_FLAGS)

clippy: $(TOOLCHAIN_STAMP)
	$(CARGO) clippy $(PROFILE_FLAGS) $(FEATURE_FLAGS) $(TARGET_FLAGS) -- -D $(CLIPPY_DENY)

# Attempt to auto-fix clippy lints; may require newer clippy/toolchain
clippy-fix: $(TOOLCHAIN_STAMP)
	@echo "[clippy-fix] attempting in-place fixes"
	@if $(CARGO) clippy $(PROFILE_FLAGS) $(FEATURE_FLAGS) $(TARGET_FLAGS) --fix -Z unstable-options --allow-dirty --allow-staged; then \
	  echo "[clippy-fix] completed"; \
	else \
	  echo "NOTE: clippy --fix may require a newer toolchain; try: TOOLCHAIN=nightly $(MAKE) clippy-fix"; \
	  exit 1; \
	fi

fmt: $(TOOLCHAIN_STAMP)
	$(CARGO) fmt --all

fmt-check: $(TOOLCHAIN_STAMP)
	$(CARGO) fmt --all -- --check

# Run with current profile/flags
run: build
	$(CARGO) run $(PROFILE_FLAGS) $(FEATURE_FLAGS) $(TARGET_FLAGS)

# Nextest (fast test runner)
nextest: $(TOOLCHAIN_STAMP)
	@if ! command -v cargo-nextest >/dev/null 2>&1; then \
	  echo "ERROR: cargo-nextest not found. Install: cargo install cargo-nextest"; exit 1; \
	fi
	$(CARGO) nextest run $(FEATURE_FLAGS) $(TARGET_FLAGS) $(PROFILE_FLAGS)

clean:
	@echo "[clean] cargo clean + remove stamps"
	@$(CARGO) clean || true
	@rm -f .toolchain-*-ok $(TARGET_DIR)/.build-*-ok

reinstall: clean
	$(MAKE) build
