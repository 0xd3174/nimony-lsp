.PHONY: all lsp lsp-dev zed check test test-e2e install-lsp clean help

CARGO ?= cargo
PREFIX ?= $(HOME)/.local
BIN_DIR ?= $(PREFIX)/bin
TARGET_WASM = wasm32-wasip1

all: lsp zed ## Build both nimony-lsp and zed-nimony (release)

lsp: ## Build nimony-lsp native binary in release mode
	$(CARGO) build -p nimony-lsp --release

lsp-dev: ## Build nimony-lsp native binary in dev mode
	$(CARGO) build -p nimony-lsp

zed: ## Build zed-nimony extension in release mode (wasm32-wasip1)
	$(CARGO) build -p zed-nimony --target $(TARGET_WASM) --release

check: ## Run cargo check across all workspace members
	$(CARGO) check --workspace

test: ## Run cargo unit and integration tests
	$(CARGO) test --workspace

test-e2e: ## Run the comprehensive 5-tier E2E test suite
	bash tests/e2e/run_tests.sh

install-lsp: lsp ## Install nimony-lsp to $(BIN_DIR)
	mkdir -p $(BIN_DIR)
	cp target/release/nimony-lsp $(BIN_DIR)/nimony-lsp
	@echo "Installed nimony-lsp to $(BIN_DIR)/nimony-lsp"

clean: ## Remove build artifacts
	$(CARGO) clean
	rm -f tests/e2e/harness/lsp_client
	rm -f crates/zed-nimony/extension.wasm

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
