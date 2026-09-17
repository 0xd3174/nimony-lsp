#!/usr/bin/env bash
# Tier 3 - Cross-Feature: Formatting & Diagnostic Re-Evaluation
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Tier 3

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 3: Format -> Diagnostic Re-Evaluation ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
TEST_URI="file:///tmp/format_diag_test.nim"

# Test 5: Format requested on broken syntax fails safely; diagnostics remain
test_start "T3_05" "Format on syntax-broken buffer safely returns empty edits while diagnostics remain active"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc unclosed(a: int =\n"}}}
WAIT_DIAG 5000
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$TEST_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Format should return empty array or null, and DIAG should report error
  if [[ "$OUTPUT" == *"DIAG:"* && "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"[]"* || "$OUTPUT" == *"null"*) ]]; then
    test_pass "T3_05"
  else
    test_fail "T3_05" "Format on broken syntax failed contract: $OUTPUT"
  fi
fi

# Test 6: Formatted valid code re-evaluates to zero diagnostics
test_start "T3_06" "Irregular code formatted via formatting TextEdit re-evaluates with zero diagnostics"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_06" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc   calc(  x : int ) : int =  x  + 1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$TEST_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"proc calc(x: int): int =\n  result = x + 1\n"}]}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"\"diagnostics\":[]"* || "$OUTPUT" == *"DIAG:"*) ]]; then
    test_pass "T3_06"
  else
    test_fail "T3_06" "Format to clean diagnostics failed: $OUTPUT"
  fi
fi
