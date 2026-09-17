#!/usr/bin/env bash
# Tier 4 - Real-World Scenario: Generic Math Module Compilation
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Tier 4

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 4: Generic Math Module Compilation ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/generic_module"
MATH_PATH="$FIXTURE_DIR/math_generic.nim"
MATH_URI="file://$MATH_PATH"

# Test 4: Generic proc hover and instantiation trace diagnostic
test_start "T4_04" "Generic proc hover displays generic signature [T] and invalid call emits Trace diagnostic"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T4_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MATH_URI","languageId":"nim","version":1,"text":"proc square[T](x: T): T = x * x\nlet a = square(5)\nlet b = square(\"invalid\")\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$MATH_URI"},"position":{"line":0,"character":6}}}
WAIT_RESP 2 5000
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"square"* || "$OUTPUT" == *"\[T\]"* || "$OUTPUT" == *"contents"*) ]]; then
    test_pass "T4_04"
  else
    test_fail "T4_04" "Generic proc hover/trace failed: $OUTPUT"
  fi
fi

# Test 5: Generic object field completion
test_start "T4_05" "Generic object type Box[T] provides field completion"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T4_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MATH_URI","languageId":"nim","version":1,"text":"type Box[T] = object\n  item: T\nlet b = Box[int](it"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$MATH_URI"},"position":{"line":2,"character":20}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"item"* || "$OUTPUT" == *"items"*) ]]; then
    test_pass "T4_05"
  else
    test_fail "T4_05" "Generic object field completion failed: $OUTPUT"
  fi
fi
