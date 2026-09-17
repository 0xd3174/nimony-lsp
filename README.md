# Nimony LSP & Zed Extension

[![Tests](https://img.shields.io/badge/E2E%20Tests-94%2F94%20PASS-brightgreen)](tests/e2e/run_tests.sh)
[![Unit Tests](https://img.shields.io/badge/Unit%20Tests-25%2F25%20PASS-brightgreen)](crates/nimony-lsp)
[![Target](https://img.shields.io/badge/Zed%20WASM-wasm32--wasip1-blue)](crates/zed-nimony)
[![Nix](https://img.shields.io/badge/Nix-Flake-blueviolet)](flake.nix)

High-performance Language Server Protocol (LSP 3.17) server for the [Nimony](https://github.com/nim-lang/nimony) compiler, paired with an official [Zed](https://zed.dev) editor extension.

---

## Architecture Overview

```mermaid
flowchart LR
    subgraph Editor ["Zed Editor"]
        TS["Tree-sitter Syntax Highlighting"]
        ZedExt["zed-nimony (WASM extension)"]
    end

    subgraph LSP ["nimony-lsp (Native Binary)"]
        RPC["JSON-RPC 2.0 (stdio)"]
        Coords["UTF-16 &lt;--&gt; 1-based Byte Coords"]
        Diag["Debounced Shadow File Diagnostics"]
        Nav["Navigation (Def / Usages / Hover)"]
        Comp["Completion Engine (Procs, Types, Fields)"]
        Fmt["Formatting (nimpretty + Myers Diff)"]
    end

    subgraph Toolchain ["Nimony Toolchain"]
        Nimony["nimony check"]
        Nimpretty["nimpretty"]
    end

    ZedExt -- stdio RPC --> RPC
    RPC --> Coords
    Coords --> Diag
    Coords --> Nav
    Coords --> Comp
    Coords --> Fmt

    Diag -- ".tmp_*.nim" --> Nimony
    Nav -- "--def / --usages" --> Nimony
    Fmt --> Nimpretty
```

---

## Features

- **Live Debounced Diagnostics:** 300ms debounce loop compiling temporary shadow files (`.tmp_*.nim`) and instant checks on save. Parses compiler errors, warnings, and maps instantiation traces to LSP `relatedInformation`.
- **Code Navigation:**
  - **Go to Definition:** Jumps to procs, parameters, variables, types, and external imported modules (`nimony check --def:file,line,col`).
  - **Find References:** Locates all symbol references across the workspace (`nimony check --usages:file,line,col`).
  - **Document Highlights:** Highlights all occurrences of an active identifier (reads vs. writes).
  - **Hover:** Displays symbol definitions, inferred types, signatures, and doc comments.
- **Smart Completion:**
  - Nim language keywords and built-in primitive types.
  - Common code snippets (`proc`, `iterator`, `type object`).
  - Buffer declarations: in-scope procs, variables, generic types (`Box[T]`), and indented object fields.
- **Document Formatting:** Full-document formatting via `nimpretty`, translated into minimal text edits using the Myers diff algorithm.
- **Encoding Safety:** Bidirectional mapping between LSP 0-based UTF-16 code units and Nimony's 1-based byte positions. Fully tested against surrogate pairs, multi-byte UTF-8, and astral emojis (🚀).
- **Zed Extension:**
  - Registers the `Nimony` language for `.nim`, `.nims`, and `.nimble` files.
  - Complete Tree-sitter syntax highlighting (`highlights.scm`), auto-bracket pairing (`brackets.scm`), and indentation rules (`indents.scm`).
  - Native WASM binary (`wasm32-wasip1`) that manages `nimony-lsp` lifecycle.

---

## Repository Structure

```
nimony-lsp/
├── flake.nix                     # Declarative Nix environment (nimony 0.6.3, nim 2.2, rust)
├── Makefile                      # Build automation targets
├── Cargo.toml                    # Root workspace configuration
├── crates/
│   ├── nimony-lsp/               # Native Rust LSP server
│   │   └── src/
│   │       ├── main.rs           # Entry point & stdio initialization
│   │       ├── server.rs         # JSON-RPC loop & document sync
│   │       ├── coords.rs         # UTF-16 <-> 1-based byte position mapping
│   │       ├── diagnostics.rs    # Shadow files, debounce loop & diagnostic parser
│   │       ├── navigation.rs     # Definition, usages, hover & document highlights
│   │       ├── completion.rs     # In-buffer AST regex & snippet completion
│   │       └── formatting.rs     # nimpretty runner & Myers diff
│   └── zed-nimony/               # Zed editor WASM extension
│       ├── extension.toml        # Zed extension manifest
│       ├── languages/nimony/     # Grammar configuration & Tree-sitter queries
│       └── src/lib.rs            # Extension API implementation
└── tests/
    └── e2e/                      # Comprehensive 5-Tier E2E test suite
```

---

## Quickstart (NixOS / Nix Flakes)

Enter the declarative development environment:
```bash
nix develop
```
Inside `nix develop`, all required tools are automatically available in PATH: `nimony` 0.6.3, `nim` 2.2, `gcc`, `rustc`, `cargo` (with `wasm32-wasip1` target), and `zeditor`.

### Build with `make`

The repository includes a `Makefile` for streamlined building and testing:

```bash
# Build both nimony-lsp and zed-nimony extension (release mode)
make all

# Build only the LSP server
make lsp

# Build only the Zed WASM extension
make zed

# Run workspace unit tests (25 tests)
make test

# Run full 5-tier E2E test suite (94 tests)
make test-e2e

# Install nimony-lsp to ~/.local/bin (or customize with PREFIX=...)
make install-lsp

# Show help on all available targets
make help
```

*(Note: If running outside of an active `nix develop` shell, prefix commands with `nix develop -c make <target>`)*

---

## Installing & Configuring in Zed

### 1. Install as Dev Extension
1. Open Zed.
2. Open the Command Palette (`Ctrl+Shift+P` on Linux/Windows, `Cmd+Shift+P` on macOS).
3. Type and select `zed: install dev extension`.
4. Choose the directory: `crates/zed-nimony` (or the absolute path: `/path/to/nimony-lsp/crates/zed-nimony`).

### 2. Configure `settings.json`
To configure Zed to use your built `nimony-lsp` binary, open your Zed settings (`~/.config/zed/settings.json`):

```json
{
  "languages": {
    "Nimony": {
      "language_servers": ["nimony-lsp"],
      "format_on_save": "on"
    }
  },
  "lsp": {
    "nimony-lsp": {
      "binary": {
        "path": "/home/delta/code/nimony-lsp/target/release/nimony-lsp"
      }
    }
  }
}
```

### 3. Adding to System PATH (Fish Shell / NixOS)
If you prefer having `nimony-lsp` in your system `PATH`:

- **Fish Shell:**
  ```fish
  fish_add_path ~/.local/bin
  make install-lsp
  ```
- **NixOS (`/etc/nixos/configuration.nix`):**
  ```nix
  environment.localBinInPath = true; # Adds ~/.local/bin to PATH for all users
  ```
- **Direnv (Per-Project):**
  Add `.envrc` in your Nimony project:
  ```bash
  echo "use flake /path/to/nimony-lsp" > .envrc
  direnv allow
  ```

---

## Test Verification

The project includes an authoritative 5-tier automated test suite covering all LSP capabilities and edge cases:

| Tier | Focus Area | Tests | Status |
| :--- | :--- | :---: | :---: |
| **Tier 1** | Core LSP capabilities (Diagnostics, Navigation, Completion, Formatting, WASM build) | 53 | **PASS** |
| **Tier 2** | Boundary cases (Empty files, UTF-8 astral characters/emojis, malformed JSON-RPC, cancellation) | 25 | **PASS** |
| **Tier 3** | Interactive lifecycle (didChange dirty edits $\to$ definition/completion queries, format $\to$ verify) | 8 | **PASS** |
| **Tier 4** | Multi-file cross-module definitions, generic modules (`Box[T]`), and AST refactoring | 7 | **PASS** |
| **Tier 5** | Stdio cleanliness and thread-leak free process shutdown | 1 | **PASS** |
| **Total** | **Comprehensive E2E Coverage** | **94** | **100% PASS** |

Run tests anytime with:
```bash
nix develop -c make test-e2e
```

---

## License

MIT
