# node-deps.mk
#
# A reusable Makefile for managing Node.js dependencies with intelligent
# package manager detection and installation.
#
# Features:
# - Automatically detects which package manager to use (pnpm, yarn, npm, or bun)
#   based on lockfiles present in the project
# - Handles all Yarn nodeLinker modes: pnp (default), pnpm, node-modules
# - Detects Yarn linker configuration from .yarnrc.yml
# - Works with pnpm's content-addressable store
# - Uses a stamp file to track dependencies and only re-installs when
#   dependency files change, avoiding unnecessary reinstalls
# - Provides standard targets: install, run, clean, reinstall
#
# Use Value:
# - Drop into any Node.js project to standardize dependency management across teams
# - Reduces boilerplate in project-specific Makefiles
# - Handles different package managers (pnpm, yarn, npm, bun) automatically
# - Works with all Yarn linker modes (PnP, pnpm-style, node-modules)
# - Ensures reproducible environments with minimal configuration
# - Perfect complement to python-venv.mk for polyglot projects
#
# Usage:
#   include node-deps.mk
#   (Override NODE_MODULES, NODE, or other variables as needed before the include)
#
# ---- config ----
NODE_MODULES := node_modules
NODE         := node
# Use a project-root stamp file that works regardless of install strategy
STAMP        := .deps-ok

# Dependency inputs that should trigger re-install when they change.
# Only the files that actually exist will be considered (via $(wildcard ...)).
DEPS := $(wildcard package.json package-lock.json yarn.lock pnpm-lock.yaml bun.lockb .yarnrc.yml .npmrc)

.PHONY: help all install run clean reinstall node-modules

help:  ## Display this help message
	@echo "Node.js Dependency Management Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  help       - Display this help message"
	@echo "  install    - Install dependencies using detected package manager"
	@echo "  run        - Install dependencies and run index.js"
	@echo "  clean      - Remove dependencies (node_modules, .pnp.*, .yarn/cache, etc.)"
	@echo "  reinstall  - Clean and reinstall from scratch"
	@echo "  all        - Default target (runs 'run')"
	@echo ""
	@echo "Configuration variables:"
	@echo "  NODE_MODULES = $(NODE_MODULES)   - Dependencies directory (for traditional installs)"
	@echo "  NODE         = $(NODE)            - Node.js interpreter"
	@echo "  STAMP        = $(STAMP)           - Stamp file location"
	@echo ""
	@echo "Detected dependency files:"
	@echo "  $(DEPS)"
	@echo ""
	@echo "Package manager detection priority:"
	@echo "  1. pnpm (pnpm-lock.yaml)"
	@echo "  2. yarn (yarn.lock, auto-detects nodeLinker: pnp/pnpm/node-modules)"
	@echo "  3. bun (bun.lockb)"
	@echo "  4. npm (package-lock.json or fallback)"

all: run

# Install deps if any input changed
# Note: We don't depend on $(NODE_MODULES) existing because:
# - Yarn PnP (nodeLinker: pnp) doesn't create node_modules
# - pnpm uses a content-addressable store with symlinks
$(STAMP): $(DEPS)
	@set -e; \
	if [ -f pnpm-lock.yaml ]; then \
		echo "[install] using pnpm (pnpm-lock.yaml detected)"; \
		if command -v pnpm >/dev/null 2>&1; then \
			pnpm install --frozen-lockfile; \
		else \
			echo "ERROR: pnpm-lock.yaml found but pnpm not installed"; \
			echo "Install pnpm: npm install -g pnpm"; \
			exit 1; \
		fi; \
	elif [ -f yarn.lock ]; then \
		if command -v yarn >/dev/null 2>&1; then \
			LINKER="pnp (default)"; \
			if [ -f .yarnrc.yml ]; then \
				if grep -q "nodeLinker:" .yarnrc.yml 2>/dev/null; then \
					DETECTED=$$(grep "nodeLinker:" .yarnrc.yml | sed 's/.*nodeLinker:[[:space:]]*//; s/[[:space:]]*$$//'); \
					if [ -n "$$DETECTED" ]; then \
						LINKER="$$DETECTED"; \
					fi; \
				fi; \
			fi; \
			echo "[install] using yarn (yarn.lock detected, nodeLinker: $$LINKER)"; \
			yarn install --immutable; \
		else \
			echo "ERROR: yarn.lock found but yarn not installed"; \
			echo "Install yarn: npm install -g yarn"; \
			exit 1; \
		fi; \
	elif [ -f bun.lockb ]; then \
		echo "[install] using bun (bun.lockb detected)"; \
		if command -v bun >/dev/null 2>&1; then \
			bun install --frozen-lockfile; \
		else \
			echo "ERROR: bun.lockb found but bun not installed"; \
			echo "Install bun: curl -fsSL https://bun.sh/install | bash"; \
			exit 1; \
		fi; \
	elif [ -f package-lock.json ]; then \
		echo "[install] using npm (package-lock.json detected)"; \
		npm ci; \
	elif [ -f package.json ]; then \
		echo "[install] using npm (fallback, no lockfile found)"; \
		echo "WARNING: No lockfile found. Consider running 'npm install' to create one."; \
		npm install; \
	else \
		echo "ERROR: No package.json found"; \
		exit 1; \
	fi
	@touch $(STAMP)

install: $(STAMP)

# Example command that needs the environment ready
run: install
	$(NODE) index.js

# Force a clean re-install
reinstall: clean
	@$(MAKE) install

clean:
	@echo "[clean] Removing dependencies..."
	@# Traditional node_modules (npm, bun, yarn with nodeLinker: node-modules)
	@rm -rf $(NODE_MODULES)
	@# Yarn PnP artifacts (nodeLinker: pnp)
	@rm -rf .pnp.* .yarn/cache .yarn/unplugged .yarn/build-state.yml .yarn/install-state.gz
	@# Yarn pnpm mode artifacts (nodeLinker: pnpm)
	@rm -rf .yarn/cache .yarn/unplugged
	@# Bun cache
	@rm -rf node_modules.bun
	@# Stamp file
	@rm -f $(STAMP)
