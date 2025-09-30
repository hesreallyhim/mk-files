# rust-cargo.mk
#
# A reusable Makefile for managing Rust projects with intelligent toolchain
# management and build optimization.
#
# Features:
# - Automatic toolchain installation via rustup (stable, nightly, beta, or specific versions)
# - Detects workspace vs single-crate projects automatically
# - Uses stamp files to track builds and skip cargo when nothing changed
# - Build profile support (dev/release) with separate tracking
# - Optional cross-compilation target support
# - Provides standard targets: toolchain, build, test, check, clippy, fmt, clean, run
#
# Use Value:
# - Drop into any Rust project to standardize build workflows across teams
# - Reduces boilerplate in project-specific Makefiles
# - Ensures correct toolchain is installed before building
# - Optimizes build times by skipping cargo invocations when nothing changed
# - Works with both single-crate and workspace projects
# - Perfect complement to python-venv.mk and node-deps.mk for polyglot projects
#
# Usage:
#   include rust-cargo.mk
#   (Override TOOLCHAIN, PROFILE, or other variables as needed before the include)
#
# ---- config ----
TOOLCHAIN    := stable
CARGO        := cargo +$(TOOLCHAIN)
PROFILE      := dev
TARGET_DIR   := target
FEATURES     :=
TARGET_ARCH  :=
TOOLCHAIN_STAMP := .toolchain-ok
BUILD_STAMP     := $(TARGET_DIR)/.build-$(PROFILE)-ok

# Dependency inputs that should trigger re-build when they change.
# Only the files that actually exist will be considered (via $(wildcard ...)).
DEPS := $(wildcard Cargo.toml Cargo.lock)

# For workspaces, include all member Cargo.toml files
WORKSPACE_DEPS := $(wildcard */Cargo.toml */*/Cargo.toml)

.PHONY: help all toolchain build test check clippy fmt clean run reinstall

help:  ## Display this help message
	@echo "Rust Cargo Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  help       - Display this help message"
	@echo "  toolchain  - Ensure correct Rust toolchain is installed"
	@echo "  build      - Build the project (respects PROFILE)"
	@echo "  test       - Run tests"
	@echo "  check      - Fast syntax check without codegen"
	@echo "  clippy     - Run Clippy linter"
	@echo "  fmt        - Format code with rustfmt"
	@echo "  clean      - Remove build artifacts and stamps"
	@echo "  run        - Build and run the project"
	@echo "  reinstall  - Clean and rebuild from scratch"
	@echo "  all        - Default target (runs 'build')"
	@echo ""
	@echo "Configuration variables:"
	@echo "  TOOLCHAIN    = $(TOOLCHAIN)    - Rust toolchain (stable, nightly, beta, or version)"
	@echo "  PROFILE      = $(PROFILE)      - Build profile (dev or release)"
	@echo "  TARGET_DIR   = $(TARGET_DIR)   - Build output directory"
	@echo "  FEATURES     = $(FEATURES)     - Optional feature flags"
	@echo "  TARGET_ARCH  = $(TARGET_ARCH)  - Optional cross-compilation target"
	@echo ""
	@echo "Detected dependency files:"
	@echo "  $(DEPS)"
	@if [ -n "$(WORKSPACE_DEPS)" ]; then \
		echo ""; \
		echo "Detected workspace members:"; \
		echo "  $(WORKSPACE_DEPS)"; \
	fi

all: build

# Ensure toolchain is installed via rustup
$(TOOLCHAIN_STAMP):
	@echo "[toolchain] Checking for rustup..."
	@if ! command -v rustup >/dev/null 2>&1; then \
		echo "ERROR: rustup not found"; \
		echo "Install rustup: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"; \
		exit 1; \
	fi
	@echo "[toolchain] Installing/updating toolchain: $(TOOLCHAIN)"
	@rustup toolchain install $(TOOLCHAIN)
	@if [ -n "$(TARGET_ARCH)" ]; then \
		echo "[toolchain] Installing cross-compilation target: $(TARGET_ARCH)"; \
		rustup target add $(TARGET_ARCH) --toolchain $(TOOLCHAIN); \
	fi
	@touch $(TOOLCHAIN_STAMP)

toolchain: $(TOOLCHAIN_STAMP)

# Build with stamp tracking
# Note: Cargo handles incremental compilation internally; this stamp mainly helps
# skip cargo invocation overhead when dependency files haven't changed
$(BUILD_STAMP): $(TOOLCHAIN_STAMP) $(DEPS) $(WORKSPACE_DEPS)
	@echo "[build] Building with profile: $(PROFILE)"
	@set -e; \
	BUILD_CMD="$(CARGO) build"; \
	if [ "$(PROFILE)" = "release" ]; then \
		BUILD_CMD="$$BUILD_CMD --release"; \
	fi; \
	if [ -n "$(FEATURES)" ]; then \
		BUILD_CMD="$$BUILD_CMD --features $(FEATURES)"; \
	fi; \
	if [ -n "$(TARGET_ARCH)" ]; then \
		BUILD_CMD="$$BUILD_CMD --target $(TARGET_ARCH)"; \
	fi; \
	$$BUILD_CMD
	@touch $(BUILD_STAMP)

build: $(BUILD_STAMP)

# Run tests
test: $(TOOLCHAIN_STAMP)
	$(CARGO) test $(if $(FEATURES),--features $(FEATURES))

# Fast check without codegen (useful for quick feedback)
check: $(TOOLCHAIN_STAMP)
	$(CARGO) check $(if $(FEATURES),--features $(FEATURES))

# Run Clippy linter
clippy: $(TOOLCHAIN_STAMP)
	$(CARGO) clippy $(if $(FEATURES),--features $(FEATURES)) -- -D warnings

# Format code
fmt: $(TOOLCHAIN_STAMP)
	$(CARGO) fmt --all

# Clean build artifacts
clean:
	@echo "[clean] Removing build artifacts..."
	@$(CARGO) clean
	@rm -f $(TOOLCHAIN_STAMP) $(TARGET_DIR)/.build-*-ok

# Run the project
run: build
	@if [ "$(PROFILE)" = "release" ]; then \
		$(CARGO) run --release $(if $(FEATURES),--features $(FEATURES)) $(if $(TARGET_ARCH),--target $(TARGET_ARCH)); \
	else \
		$(CARGO) run $(if $(FEATURES),--features $(FEATURES)) $(if $(TARGET_ARCH),--target $(TARGET_ARCH)); \
	fi

# Force a clean rebuild
reinstall: clean
	@$(MAKE) build
