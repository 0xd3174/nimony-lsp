#!/usr/bin/env bash
# Tier 1 - F14 to F18: Zed Extension Manifests, Tree-Sitter & WASM Compilation
# Authoritative tests derived from ORIGINAL_REQUEST.md §R3, PROJECT.md §F14-F18

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F14-F18 Zed Extension & WASM Compilation ===${C_RESET}"

ZED_CRATE="$WORKSPACE_ROOT/crates/zed-nimony"

# Test 1: extension.toml manifest validation
test_start "T1_F14_F18_01" "Verify extension.toml manifest schema and metadata"
MANIFEST="$ZED_CRATE/extension.toml"
if [[ ! -f "$MANIFEST" ]]; then
  test_fail "T1_F14_F18_01" "extension.toml does not exist at $MANIFEST"
else
  CONTENT=$(cat "$MANIFEST")
  if [[ "$CONTENT" == *"id = \"nimony\""* ]] && [[ "$CONTENT" == *"schema_version = 1"* ]]; then
    test_pass "T1_F14_F18_01"
  else
    test_fail "T1_F14_F18_01" "extension.toml missing required fields (id = \"nimony\" or schema_version = 1)"
  fi
fi

# Test 2: config.toml language configuration validation
test_start "T1_F14_F18_02" "Verify languages/nimony/config.toml registers .nim, .nims, .nimble"
LANG_CONFIG="$ZED_CRATE/languages/nimony/config.toml"
if [[ ! -f "$LANG_CONFIG" ]]; then
  test_fail "T1_F14_F18_02" "config.toml does not exist at $LANG_CONFIG"
else
  CONTENT=$(cat "$LANG_CONFIG")
  if [[ "$CONTENT" == *"name = \"Nimony\""* ]] && [[ "$CONTENT" == *"nim"* ]] && [[ "$CONTENT" == *"nims"* ]] && [[ "$CONTENT" == *"nimble"* ]]; then
    test_pass "T1_F14_F18_02"
  else
    test_fail "T1_F14_F18_02" "config.toml does not register Nimony language or file extensions (.nim, .nims, .nimble)"
  fi
fi

# Test 3: Tree-sitter query files exist and non-empty
test_start "T1_F14_F18_03" "Verify tree-sitter highlight, bracket, and indent queries exist"
LANG_DIR="$ZED_CRATE/languages/nimony"
MISSING=""
if [[ ! -s "$LANG_DIR/highlights.scm" ]]; then MISSING="$MISSING highlights.scm"; fi
if [[ ! -s "$LANG_DIR/brackets.scm" ]]; then MISSING="$MISSING brackets.scm"; fi
if [[ ! -s "$LANG_DIR/indents.scm" ]]; then MISSING="$MISSING indents.scm"; fi

if [[ -z "$MISSING" ]]; then
  test_pass "T1_F14_F18_03"
else
  test_fail "T1_F14_F18_03" "Missing or empty tree-sitter query files:$MISSING"
fi

# Test 4: Extension source code implements Extension trait and references nimony-lsp
test_start "T1_F14_F18_04" "Verify crates/zed-nimony/src/lib.rs implements zed::Extension for nimony-lsp"
LIB_RS="$ZED_CRATE/src/lib.rs"
if [[ ! -f "$LIB_RS" ]]; then
  test_fail "T1_F14_F18_04" "crates/zed-nimony/src/lib.rs not found"
else
  LIB_CONTENT=$(cat "$LIB_RS")
  if [[ "$LIB_CONTENT" == *"Extension"* ]] && [[ "$LIB_CONTENT" == *"nimony-lsp"* ]] && [[ "$LIB_CONTENT" == *"language_server_command"* ]]; then
    test_pass "T1_F14_F18_04"
  else
    test_fail "T1_F14_F18_04" "src/lib.rs missing Extension implementation or nimony-lsp command resolution"
  fi
fi

# Test 5: WASM compilation to wasm32-wasip1
test_start "T1_F14_F18_05" "Verify cargo build -p zed-nimony --target wasm32-wasip1 --release"
if [[ ! -f "$ZED_CRATE/Cargo.toml" ]]; then
  test_fail "T1_F14_F18_05" "crates/zed-nimony/Cargo.toml not found (M3 not yet implemented)"
else
  BUILD_OUTPUT=$(cargo build -p zed-nimony --target wasm32-wasip1 --release 2>&1)
  BUILD_STATUS=$?
  if [[ $BUILD_STATUS -eq 0 ]]; then
    test_pass "T1_F14_F18_05"
  else
    test_fail "T1_F14_F18_05" "WASM compilation failed: $BUILD_OUTPUT"
  fi
fi
