#!/usr/bin/env bash
# Tier 4 - Real-World Scenario: Multi-File Nim Project Editing
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Tier 4

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 4: Multi-File Project Editing ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project"
MAIN_PATH="$FIXTURE_DIR/main.nim"
UTILS_PATH="$FIXTURE_DIR/utils.nim"
MAIN_URI="file://$MAIN_PATH"
UTILS_URI="file://$UTILS_PATH"

# Test 1: Cross-file Go to Definition
test_start "T4_01" "Go to Definition on imported proc in main.nim jumps across files into utils.nim"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T4_01" "nimony-lsp binary not found"
else
  MAIN_ESC=$(awk '{gsub(/"/, "\\\""); printf "%s\\n", $0}' "$MAIN_PATH")
  UTILS_ESC=$(awk '{gsub(/"/, "\\\""); printf "%s\\n", $0}' "$UTILS_PATH")
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"$MAIN_ESC"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UTILS_URI","languageId":"nim","version":1,"text":"$UTILS_ESC"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":13,"character":13}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"utils.nim"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T4_01"
  else
    test_fail "T4_01" "Cross-file definition failed: $OUTPUT"
  fi
fi

# Test 2: Cross-file Find References
test_start "T4_02" "Find References on imported proc finds usages across both utils.nim and main.nim"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T4_02" "nimony-lsp binary not found"
else
  MAIN_ESC=$(awk '{gsub(/"/, "\\\""); printf "%s\\n", $0}' "$MAIN_PATH")
  UTILS_ESC=$(awk '{gsub(/"/, "\\\""); printf "%s\\n", $0}' "$UTILS_PATH")
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UTILS_URI","languageId":"nim","version":1,"text":"$UTILS_ESC"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"$MAIN_ESC"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$UTILS_URI"},"position":{"line":0,"character":5},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"main.nim"* || "$OUTPUT" == *"utils.nim"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T4_02"
  else
    test_fail "T4_02" "Cross-file references failed: $OUTPUT"
  fi
fi

# Test 3: Cross-module type mismatch propagation
test_start "T4_03" "Changing function signature in imported module propagates type error to caller"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T4_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UTILS_URI","languageId":"nim","version":1,"text":"proc add*(a, b: int): string = \"sum\"\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"import utils\nlet x: int = add(1, 2)\n"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"type mismatch"* || "$OUTPUT" == *"DIAG:"* ]]; then
    test_pass "T4_03"
  else
    test_fail "T4_03" "Cross-module type error not propagated: $OUTPUT"
  fi
fi
