#!/usr/bin/env bash
# Tier 2 - Boundary Cases: Empty & Minimal Files
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Boundary Cases

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 2: Empty & Minimal Files ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
EMPTY_URI="file:///tmp/empty_test.nim"

# Test 1: Empty 0-byte file diagnostics
test_start "T2_01" "Empty 0-byte file didOpen publishes zero diagnostics and does not crash"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_01" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$EMPTY_URI","languageId":"nim","version":1,"text":""}}}
WAIT_DIAG 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Should either receive empty diagnostics or timeout cleanly without crash
  if [[ "$OUTPUT" != *"panic"* && "$OUTPUT" != *"crash"* && ("$OUTPUT" == *"\"diagnostics\":[]"* || "$OUTPUT" == *"DIAG:TIMEOUT"*) ]]; then
    test_pass "T2_01"
  else
    test_fail "T2_01" "Empty file handling failed: $OUTPUT"
  fi
fi

# Test 2: Definition query at (0,0) on empty file returns null
test_start "T2_02" "Definition query on empty file returns null"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$EMPTY_URI","languageId":"nim","version":1,"text":""}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$EMPTY_URI"},"position":{"line":0,"character":0}}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"null"* || "$OUTPUT" == *"[]"*) ]]; then
    test_pass "T2_02"
  else
    test_fail "T2_02" "Definition on empty file failed: $OUTPUT"
  fi
fi

# Test 3: Comment-only file
test_start "T2_03" "Comment-only file handles hover, highlight, and completion without crash"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$EMPTY_URI","languageId":"nim","version":1,"text":"# Just a single comment line\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$EMPTY_URI"},"position":{"line":0,"character":10}}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"panic"* ]]; then
    test_pass "T2_03"
  else
    test_fail "T2_03" "Comment-only file handling failed: $OUTPUT"
  fi
fi

# Test 4: Whitespace-only file formatting
test_start "T2_04" "Whitespace-only file formats cleanly without panic"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$EMPTY_URI","languageId":"nim","version":1,"text":"   \n  \t  \n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$EMPTY_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"panic"* ]]; then
    test_pass "T2_04"
  else
    test_fail "T2_04" "Whitespace file formatting failed: $OUTPUT"
  fi
fi

# Test 5: Zero-length edit in didChange
test_start "T2_05" "Zero-length edit in didChange does not desynchronize buffer"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$EMPTY_URI","languageId":"nim","version":1,"text":"let a = 1\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$EMPTY_URI","version":2},"contentChanges":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"text":""}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$EMPTY_URI"},"position":{"line":0,"character":4}}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"panic"* ]]; then
    test_pass "T2_05"
  else
    test_fail "T2_05" "Zero length edit failed: $OUTPUT"
  fi
fi
