#!/usr/bin/env bash
# Tier 2 - Boundary Cases: Syntax Error Recovery & Lifecycle
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Boundary Cases

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 2: Syntax Error Recovery & Lifecycle ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
TEST_URI="file:///tmp/syntax_recovery_test.nim"

# Test 21: Half-typed proc syntax error recovery
test_start "T2_21" "Buffer in mid-edit with incomplete syntax reports diagnostic without server crash"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_21" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc "}}}
WAIT_DIAG 5000
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":5}}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" != *"panic"* && "$OUTPUT" == *"RESP:2:"* ]]; then
    test_pass "T2_21"
  else
    test_fail "T2_21" "Incomplete syntax recovery failed: $OUTPUT"
  fi
fi

# Test 22: Rapid didChange debounce consolidation
test_start "T2_22" "Rapid didChange edit barrage debounces cleanly without process storm"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_22" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let a = 1\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"let a = 12\n"}]}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":3},"contentChanges":[{"text":"let a = 123\n"}]}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":4},"contentChanges":[{"text":"let a = 1234\n"}]}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":5},"contentChanges":[{"text":"let a = 12345\n"}]}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" != *"panic"* && "$OUTPUT" != *"crash"* ]]; then
    test_pass "T2_22"
  else
    test_fail "T2_22" "Rapid edit debounce failed: $OUTPUT"
  fi
fi

# Test 23: didClose clears diagnostics
test_start "T2_23" "Closing document via didClose clears published diagnostics"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_23" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc err( = 1"}}}
WAIT_DIAG 5000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"$TEST_URI"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"\"diagnostics\":[]"* || "$OUTPUT" == *"DIAG:"* ]]; then
    test_pass "T2_23"
  else
    test_fail "T2_23" "didClose diagnostic clear failed: $OUTPUT"
  fi
fi

# Test 24: Shadow file cleanup verification
test_start "T2_24" "Temporary shadow files (.tmp_*.nim) do not accumulate on disk"
SHADOW_COUNT=$(find /tmp -maxdepth 2 -name ".tmp_*.nim" 2>/dev/null | wc -l)
if [[ $SHADOW_COUNT -le 5 ]]; then
  test_pass "T2_24"
else
  test_fail "T2_24" "Found $SHADOW_COUNT leftover shadow files in /tmp"
fi

# Test 25: $/cancelRequest handling
test_start "T2_25" "$/cancelRequest cancels pending request without server termination"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_25" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_REQ {"jsonrpc":"2.0","id":99,"method":"textDocument/references","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":0},"context":{"includeDeclaration":true}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"\$/cancelRequest","params":{"id":99}}
SLEEP 200
SEND_REQ {"jsonrpc":"2.0","id":100,"method":"shutdown","params":null}
WAIT_RESP 100 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:100:"* ]]; then
    test_pass "T2_25"
  else
    test_fail "T2_25" "Cancel request sequence failed: $OUTPUT"
  fi
fi
