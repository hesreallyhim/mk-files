# python-venv.mk
#
# A reusable Makefile for managing Python virtual environments with intelligent
# dependency detection and installation.
#
# Features:
# - Automatically creates a virtual environment (venv/) if it doesn't exist
# - Detects and installs from multiple dependency formats (poetry.lock,
#   requirements.lock, requirements.txt, or pyproject.toml)
# - Uses a stamp file to track dependencies and only re-installs when
#   dependency files change, avoiding unnecessary reinstalls
# - Provides standard targets: install, run, clean, reinstall
#
# Use Value:
# - Drop into any Python project to standardize venv management across teams
# - Reduces boilerplate in project-specific Makefiles
# - Handles different Python packaging tools (Poetry, pip-tools, pip) automatically
# - Ensures reproducible environments with minimal configuration
#
# Usage:
#   include python-venv.mk
#   (Override VENV, PY, or other variables as needed before the include)
#
# ---- config ----
VENV := venv
PY   := python3
PIP  := $(VENV)/bin/pip
PYBIN:= $(VENV)/bin/python
STAMP:= $(VENV)/.deps-ok

# Dependency inputs that should trigger re-install when they change.
# Only the files that actually exist will be considered (via $(wildcard ...)).
DEPS := $(wildcard pyproject.toml poetry.lock requirements.lock requirements.txt uv.lock Pipfile.lock setup.cfg setup.py)

.PHONY: help all install run clean reinstall venv

help:  ## Display this help message
	@echo "Python Virtual Environment Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  help       - Display this help message"
	@echo "  install    - Create venv and install dependencies"
	@echo "  run        - Install dependencies and run main.py"
	@echo "  clean      - Remove virtual environment"
	@echo "  reinstall  - Clean and reinstall from scratch"
	@echo "  all        - Default target (runs 'run')"
	@echo ""
	@echo "Configuration variables:"
	@echo "  VENV  = $(VENV)   - Virtual environment directory"
	@echo "  PY    = $(PY)     - Python interpreter"
	@echo ""
	@echo "Detected dependency files:"
	@echo "  $(DEPS)"

all: run

# Create venv if missing
$(PYBIN):
	$(PY) -m venv $(VENV)

# Install deps if any input changed or venv was recreated
$(STAMP): $(PYBIN) $(DEPS)
	$(PIP) install -U pip
	@set -e; \
	if [ -f poetry.lock ]; then \
		echo "[install] using poetry.lock"; \
		if command -v poetry >/dev/null 2>&1; then \
			poetry export --without-hashes -f requirements.txt -o $(VENV)/requirements.txt; \
			$(PIP) install -r $(VENV)/requirements.txt; \
		else \
			echo "Poetry not found; falling back to editable install from pyproject."; \
			$(PIP) install -e .; \
		fi; \
	elif [ -f requirements.lock ]; then \
		echo "[install] using requirements.lock"; \
		$(PIP) install -r requirements.lock; \
	elif [ -f requirements.txt ]; then \
		echo "[install] using requirements.txt"; \
		$(PIP) install -r requirements.txt; \
	else \
		echo "[install] editable install from pyproject"; \
		$(PIP) install -e .; \
	fi
	touch $(STAMP)

install: $(STAMP)

# Example command that needs the environment ready
run: install
	$(PYBIN) main.py

# Force a clean re-install
reinstall: clean
	@$(MAKE) install

clean:
	rm -rf $(VENV)
