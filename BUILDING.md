# Building & Developing Nimony LSP & Zed Extension

This guide covers how to build, test, and debug `nimony-lsp` and `zed-nimony` from source.

---

## Quick Reference (Makefile)

The project includes a `Makefile` that automates all common build and test workflows:

```bash
make help          # Show list of available targets
make all           # Build both nimony-lsp (native) and zed-nimony (WASM) in release mode
make lsp           # Build nimony-lsp native binary in release mode
make lsp-dev       # Build nimony-lsp native binary in dev mode
make zed           # Build zed-nimony extension in release mode (wasm32-wasip2)
make package-zed   # Package precompiled extension bundle into dist/nimony-extension.tar.gz
make check         # Run cargo check across all workspace members
make test          # Run cargo unit tests
make test-e2e      # Run comprehensive 5-tier E2E test suite
make install-lsp   # Install nimony-lsp to ~/.local/bin
make clean         # Remove build artifacts and temporary files
```

---

## 1. Environment & Prerequisites

### Required Tools
- **Rust Toolchain:** Rust 1.80+ with `wasm32-wasip2` target:
  ```bash
  rustup target add wasm32-wasip2
  ```
- **Nimony Compiler:** `nimony` executable in your `$PATH`.
- **Nimpretty Formatter:** `nimpretty` executable in your `$PATH` (comes with standard Nim 2.0+).
- **C Compiler & WASI SDK (for Tree-sitter grammar):** Clang with WASI support (automatically downloaded and configured by `scripts/build_grammar.sh`).

---

## 2. Platform-Specific Setup

### A. Nix / NixOS (Recommended)

All dependencies (`nimony 0.6.3`, `nim 2.2`, `rust` with WebAssembly targets, `gcc`, and `zeditor`) are declared declaratively in `flake.nix`.

```bash
# Enter the development environment (Flakes):
nix develop

# Or classic nix-shell:
nix-shell

# Build everything:
make all

# Run unit and E2E tests:
make test
make test-e2e
```

To automatically load the environment in your terminal or editor, configure `direnv`:
```bash
echo "use flake" > .envrc
direnv allow
```

---

### B. Standard Linux (Ubuntu, Debian, Fedora, Arch)

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# 2. Add WebAssembly target
rustup target add wasm32-wasip2

# 3. Ensure nimony and nimpretty are in PATH
nimony --help
nimpretty --version

# 4. Clone and build
git clone https://github.com/0xd3174/nimony-lsp.git
cd nimony-lsp
make all

# 5. Install LSP binary to ~/.local/bin
make install-lsp
```

---

### C. macOS (Apple Silicon & Intel)

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# 2. Add WebAssembly target
rustup target add wasm32-wasip2

# 3. Build workspace
make all

# 4. Install binary to /usr/local/bin or ~/.local/bin
make install-lsp PREFIX=/usr/local
```

---

### D. Windows (PowerShell)

```powershell
# 1. Add WebAssembly target
rustup target add wasm32-wasip2

# 2. Build LSP native server
cargo build -p nimony-lsp --release

# 3. Build Zed extension WASM
cargo build -p zed-nimony --target wasm32-wasip2 --release
```
Compiled server binary: `target\release\nimony-lsp.exe`.

---

## 3. Building the Components Manually

### A. Native LSP Server (`nimony-lsp`)

To build with Cargo directly:
```bash
# Release build (optimized)
cargo build -p nimony-lsp --release
# Output: target/release/nimony-lsp

# Debug build (fast compile, with debug assertions)
cargo build -p nimony-lsp
# Output: target/debug/nimony-lsp
```

### B. Zed WASM Extension (`zed-nimony`)

Zed extensions run inside a WebAssembly component runtime using WASI 0.2 (`wasm32-wasip2`):
```bash
cargo build -p zed-nimony --target wasm32-wasip2 --release
# Output: target/wasm32-wasip2/release/zed_nimony.wasm
```

### C. Compiling the Tree-sitter Grammar (`nim.wasm`)

Zed requires Tree-sitter parsers to be compiled as WebAssembly shared libraries. A helper script is provided:
```bash
bash scripts/build_grammar.sh
# Output: crates/zed-nimony/grammars/nim.wasm
```
The script will:
1. Detect or download `wasi-sdk` (Clang with WASI target).
2. Clone `https://github.com/alaviss/tree-sitter-nim` at revision `897e5d346f0b59ed62b517cfb0f1a845ad8f0ab7`.
3. Compile `src/parser.c` and `src/scanner.c` to `crates/zed-nimony/grammars/nim.wasm`.

### D. Creating Precompiled Extension Bundles

To produce standalone `.tar.gz` and `.zip` archives containing all `.wasm` binaries, manifest, and syntax queries:
```bash
make package-zed
# Output:
#   dist/nimony/                       (unpacked bundle)
#   dist/nimony-extension.tar.gz       (tarball)
#   dist/nimony-extension.zip          (zip archive)
```

---

## 4. Running the Test Suite

### Unit Tests
The unit test suite verifies UTF-16/byte coordinate mapping, debounce logic, navigation parsing, and completion:
```bash
cargo test --workspace
# or
make test
```

### Comprehensive 5-Tier E2E Test Suite
The E2E test harness (`tests/e2e/run_tests.sh`) runs a dedicated mock JSON-RPC LSP client against `nimony-lsp` and the `nimony` compiler across 94 rigorous test scenarios:
```bash
make test-e2e
# or
bash tests/e2e/run_tests.sh
```

Coverage breakdown:
- **Tier 1 (53 tests):** Core LSP capabilities (Diagnostics, Navigation, Completion, Formatting, WASM extension build).
- **Tier 2 (25 tests):** Edge & boundary cases (Empty files, UTF-8 astral characters/emojis, malformed JSON-RPC, cancellation).
- **Tier 3 (8 tests):** Interactive state lifecycle (Dirty buffer edits $\to$ live diagnostics $\to$ Go to Def $\to$ format).
- **Tier 4 (7 tests):** Multi-file project architecture (Cross-module jump, generic types `Box[T]`, imports).
- **Tier 5 (1 test):** Clean process termination and stdio cleanup.

---

## 5. Local Testing & Debugging in Zed

### Installing Your Local Build as Dev Extension
1. Launch Zed from your terminal (on NixOS: `nix develop -c zeditor .`).
2. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS) and run:
   ```
   zed: install dev extension
   ```
3. Select the `crates/zed-nimony` directory (or the prepackaged `dist/nimony` directory).
4. Zed will link the extension into `~/.local/share/zed/extensions/installed/nimony`.

### Enabling Debug Logs
To view verbose LSP traces and stdio traffic:
1. In your Zed `settings.json`, set the `NIMONY_LSP_DEBUG` environment variable or specify the binary path:
   ```json
   {
     "lsp": {
       "nimony-lsp": {
         "binary": {
           "path": "/absolute/path/to/nimony-lsp/target/release/nimony-lsp",
           "arguments": []
         }
       }
     }
   }
   ```
2. In Zed, open the LSP log view via `Ctrl+Shift+P` $\to$ `zed: open log` or check `~/.local/share/zed/logs/Zed.log`.
