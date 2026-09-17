# Nimony LSP & Zed Extension

[![CI](https://github.com/nim-lang/nimony-lsp/actions/workflows/ci.yml/badge.svg)](https://github.com/nim-lang/nimony-lsp/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/badge/E2E%20Tests-94%2F94%20PASS-brightgreen)](tests/e2e/run_tests.sh)
[![Unit Tests](https://img.shields.io/badge/Unit%20Tests-25%2F25%20PASS-brightgreen)](crates/nimony-lsp)
[![Target](https://img.shields.io/badge/Zed%20WASM-wasm32--wasip2-blue)](crates/zed-nimony)
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
  - Native WASM binary (`wasm32-wasip2`) that manages `nimony-lsp` lifecycle.

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

## Quick Installation (Zero-Setup / Pre-built)

For everyday usage, you **do not need Rust, compilers, or build tools**. Everything is precompiled and published on [GitHub Releases](https://github.com/nim-lang/nimony-lsp/releases).

### Step 1: Download Prebuilt Files
From the latest [GitHub Releases](https://github.com/nim-lang/nimony-lsp/releases), download:
1. **The LSP Server Binary** for your OS:
   - Linux: `nimony-lsp-linux-x86_64`
   - macOS: `nimony-lsp-macos-arm64` (Apple Silicon M1-M4) or `nimony-lsp-macos-x86_64` (Intel)
   - Windows: `nimony-lsp-windows-x86_64.exe`
2. **The Zed Extension Bundle:**
   - `nimony-extension.tar.gz` (Linux / macOS) or `nimony-extension.zip` (Windows)

Make the binary executable on Linux/macOS (`chmod +x nimony-lsp-*`) and place it in your `$PATH` (e.g. `~/.local/bin/nimony-lsp` or `/usr/local/bin/nimony-lsp`).

---

### Step 2: Install Extension in Zed
Extract the downloaded extension bundle (`nimony-extension.tar.gz` or `.zip`). Inside you'll find a `nimony` folder.

**Option A (Via Zed Command Palette):**
1. Open Zed.
2. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on macOS).
3. Type `zed: install dev extension` and press Enter.
4. Select the extracted `nimony` directory.
5. *Done! The extension is installed and ready immediately.*

**Option B (Direct Copy):**
Alternatively, simply copy the extracted `nimony` folder directly into your Zed extensions directory:
- **Linux:** `~/.local/share/zed/extensions/installed/nimony`
- **macOS:** `~/Library/Application Support/Zed/extensions/installed/nimony`
- **Windows:** `%LOCALAPPDATA%\Zed\extensions\installed\nimony`

---

### Step 3: Configure Zed (`settings.json`)

Open Zed settings (`Ctrl+,` or `Cmd+,`, or via `Ctrl+Shift+P` $\to$ `zed: open settings`), and add:

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
        // If nimony-lsp is in your PATH, you can set:
        "path": "nimony-lsp"
        // Or specify an absolute path to the downloaded binary:
        // Linux/macOS: "path": "/home/user/.local/bin/nimony-lsp"
        // Windows:     "path": "C:/Tools/nimony-lsp.exe"
      }
    }
  }
}
```

Open any `.nim`, `.nims`, or `.nimble` file — syntax highlighting, Go to Definition, live error diagnostics, and formatting will work immediately.

---

## Building from Source & Developer Guide

If you want to compile the project yourself, contribute code, or run the test suite:

👉 **See the dedicated [BUILDING.md](BUILDING.md) guide** for:
- Declarative **Nix & NixOS** workflow (`flake.nix`, `shell.nix`, `direnv`)
- Compiling from source on standard **Linux**, **macOS**, and **Windows**
- Compiling the Tree-sitter Nim grammar (`nim.wasm`) via `scripts/build_grammar.sh`
- Running unit tests and the comprehensive 94-test **5-Tier E2E test suite**
- Local debugging and verbose LSP logging (`NIMONY_LSP_DEBUG=1`)

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
