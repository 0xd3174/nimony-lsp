#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GRAMMARS_DIR="$REPO_ROOT/crates/zed-nimony/grammars"
OUTPUT_WASM="$GRAMMARS_DIR/nim.wasm"

if [ -f "$OUTPUT_WASM" ]; then
    echo "Grammar already built: $OUTPUT_WASM"
    exit 0
fi

mkdir -p "$GRAMMARS_DIR"

# Check if wasi-sdk is already installed or download it
WASI_SDK_DIR="${WASI_SDK_PATH:-$HOME/.local/share/zed/extensions/build/wasi-sdk}"

if [ ! -d "$WASI_SDK_DIR" ]; then
    echo "Downloading wasi-sdk..."
    WASI_VERSION=24
    WASI_VERSION_FULL=${WASI_VERSION}.0
    TMP_DIR=$(mktemp -d)
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ]; then ARCH="arm64"; fi
    TARBALL="wasi-sdk-${WASI_VERSION_FULL}-${ARCH}-${OS}.tar.gz"
    curl -fsSL "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_VERSION}/${TARBALL}" -o "$TMP_DIR/wasi-sdk.tar.gz"
    mkdir -p "$WASI_SDK_DIR"
    tar -xzf "$TMP_DIR/wasi-sdk.tar.gz" -C "$WASI_SDK_DIR" --strip-components=1
    rm -rf "$TMP_DIR"
fi

CLANG="$WASI_SDK_DIR/bin/clang"

# Clone tree-sitter-nim if needed
SRC_DIR="$GRAMMARS_DIR/nim/src"
if [ ! -f "$SRC_DIR/parser.c" ]; then
    echo "Cloning tree-sitter-nim..."
    rm -rf "$GRAMMARS_DIR/nim"
    git clone https://github.com/alaviss/tree-sitter-nim "$GRAMMARS_DIR/nim"
    (cd "$GRAMMARS_DIR/nim" && git checkout 897e5d346f0b59ed62b517cfb0f1a845ad8f0ab7)
fi

echo "Compiling tree-sitter nim parser with wasi-sdk..."
EXTRA_ARGS=()
if [ -f "$SRC_DIR/scanner.c" ]; then
    EXTRA_ARGS+=("$SRC_DIR/scanner.c")
fi

"$CLANG" \
    --target=wasm32-wasi \
    -O3 \
    -fPIC \
    -shared \
    -fno-exceptions \
    -Wl,--no-entry \
    -Wl,--export-dynamic \
    -Wl,--export=tree_sitter_nim \
    -I "$SRC_DIR" \
    -o "$OUTPUT_WASM" \
    "$SRC_DIR/parser.c" \
    "${EXTRA_ARGS[@]}"

echo "Successfully built $OUTPUT_WASM"
