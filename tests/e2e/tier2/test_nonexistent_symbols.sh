#!/usr/bin/env bash
# Tier 2 - Boundary Cases: Non-Existent Symbols & Fallback Handling
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Boundary Cases

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 2: Non-Existent Symbols & Fallback Handling ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
TEST_URI="file:///tmp/nonexistent_test.nim"

# Test 16: Definition on whitespace returns null
test_start "T2_16" "Go to Definition on whitespace returns null without error"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_16" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let a = 1\n   \nlet b = 2\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":1,"character":1}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"null"* || "$OUTPUT" == *"[]"*) ]]; then
    test_pass "T2_16"
  else
    test_fail "T2_16" "Definition on whitespace did not return null/empty: $OUTPUT"
  fi
fi

# Test 17: Definition on integer literal returns null
test_start "T2_17" "Go to Definition on literal (e.g. 42) returns null"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_17" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let a = 42\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":9}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"null"* || "$OUTPUT" == *"[]"*) ]]; then
    test_pass "T2_17"
  else
    test_fail "T2_17" "Definition on literal did not return null: $OUTPUT"
  fi
fi

# Test 18: Definition on keyword returns null
test_start "T2_18" "Go to Definition on language keyword (discard) returns null"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_18" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"discard 1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":2}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"null"* || "$OUTPUT" == *"[]"*) ]]; then
    test_pass "T2_18"
  else
    test_fail "T2_18" "Definition on keyword did not return null: $OUTPUT"
  fi
fi

# Test 19: References on undeclared identifier returns empty list or null
test_start "T2_19" "Find References on undeclared identifier returns empty list or null"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_19" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let x = unknownSymbolVar\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":12},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"[]"* || "$OUTPUT" == *"null"*) ]]; then
    test_pass "T2_19"
  else
    test_fail "T2_19" "References on undeclared identifier did not return empty/null: $OUTPUT"
  fi
fi

# Test 20: Hover on undeclared identifier returns null
test_start "T2_20" "Hover on unknown symbol returns null cleanly"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_20" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let a = nonExistentVariable\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":12}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"null"* || "$OUTPUT" == *"\"contents\":null"*) ]]; then
    test_pass "T2_20"
  else
    test_fail "T2_20" "Hover on unknown symbol did not return null: $OUTPUT"
  fi
fi
