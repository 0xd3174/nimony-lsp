#!/usr/bin/env bash
# Tier 1 - F01 & F02: Nix Flake DevShell & Nimony Availability
# Authoritative tests derived from ORIGINAL_REQUEST.md §R1, PROJECT.md §Feature Inventory F01/F02

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F01/F02 Environment & Compiler Availability ===${C_RESET}"

# Test 1: nimony --help
test_start "T1_F01_F02_01" "Verify nimony --help succeeds with valid commands"
NIMONY_BIN=$(get_nimony_binary)
if [[ -z "$NIMONY_BIN" ]]; then
  test_fail "T1_F01_F02_01" "nimony binary not found in PATH or Nix store"
else
  OUTPUT=$("$NIMONY_BIN" --help 2>&1)
  STATUS=$?
  if [[ $STATUS -eq 0 ]] && [[ "$OUTPUT" == *"Usage: nimony"* || "$OUTPUT" == *"check"* ]]; then
    test_pass "T1_F01_F02_01"
  else
    test_fail "T1_F01_F02_01" "nimony --help output unexpected: $OUTPUT"
  fi
fi

# Test 2: nimony --version
test_start "T1_F01_F02_02" "Verify nimony --version emits compiler version"
if [[ -z "$NIMONY_BIN" ]]; then
  test_fail "T1_F01_F02_02" "nimony binary not found"
else
  OUTPUT=$("$NIMONY_BIN" --version 2>&1)
  STATUS=$?
  if [[ $STATUS -eq 0 ]] && [[ "$OUTPUT" =~ [0-9]+\.[0-9]+\.[0-9]+ || "$OUTPUT" == *"Nimony"* ]]; then
    test_pass "T1_F01_F02_02"
  else
    test_fail "T1_F01_F02_02" "nimony --version failed: $OUTPUT"
  fi
fi

# Test 3: nim --version (Nim 2.2+)
test_start "T1_F01_F02_03" "Verify host nim --version satisfies Nim 2.2+ requirement"
if command -v nim >/dev/null 2>&1; then
  NIM_VER=$(nim --version 2>&1)
  if [[ "$NIM_VER" == *"Nim Compiler Version 2."* ]]; then
    test_pass "T1_F01_F02_03"
  else
    test_fail "T1_F01_F02_03" "nim version is not 2.x: $NIM_VER"
  fi
else
  # Check in nix
  NIM_VER=$(nix shell nixpkgs#nim -c nim --version 2>&1)
  if [[ "$NIM_VER" == *"Nim Compiler Version 2."* ]]; then
    test_pass "T1_F01_F02_03"
  else
    test_fail "T1_F01_F02_03" "nim not available in nix shell: $NIM_VER"
  fi
fi

# Test 4: rustc and cargo availability
test_start "T1_F01_F02_04" "Verify rustc and cargo are present and functional"
RUST_CHECK=$(nix shell nixpkgs#rustc nixpkgs#cargo -c bash -c "rustc --version && cargo --version" 2>&1)
RUST_STATUS=$?
if [[ $RUST_STATUS -eq 0 ]] && [[ "$RUST_CHECK" == *"rustc"* && "$RUST_CHECK" == *"cargo"* ]]; then
  test_pass "T1_F01_F02_04"
else
  test_fail "T1_F01_F02_04" "rustc/cargo verification failed: $RUST_CHECK"
fi

# Test 5: zeditor availability
test_start "T1_F01_F02_05" "Verify zeditor package availability in Nix"
if command -v zeditor >/dev/null 2>&1; then
  test_pass "T1_F01_F02_05"
else
  ZED_CHECK=$(nix eval --impure --expr 'let pkgs = import <nixpkgs> {}; in pkgs.zed-editor.name' 2>&1)
  if [[ "$ZED_CHECK" == *"zed-editor"* ]]; then
    test_pass "T1_F01_F02_05"
  else
    test_fail "T1_F01_F02_05" "zed-editor not resolvable in nixpkgs: $ZED_CHECK"
  fi
fi

# Test 6: wasm32-wasip1 compilation target support
test_start "T1_F01_F02_06" "Verify wasm32-wasip1 target is supported by Rust toolchain"
WASM_CHECK=$(nix eval --impure --expr '
  let
    rust-overlay = builtins.fetchGit { url = "https://github.com/oxalica/rust-overlay"; };
    pkgs = import <nixpkgs> { overlays = [ (import rust-overlay) ]; };
    rust = pkgs.rust-bin.stable.latest.default.override { targets = [ "wasm32-wasip1" ]; };
  in rust.name' 2>&1)
if [[ "$WASM_CHECK" == *"rust"* ]]; then
  test_pass "T1_F01_F02_06"
else
  test_fail "T1_F01_F02_06" "rust-overlay wasm32-wasip1 target evaluation failed: $WASM_CHECK"
fi
