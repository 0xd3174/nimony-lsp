#!/usr/bin/env bash
# Tier 1 - F11: Document Highlight
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F11

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F11 Document Highlight ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project"
MAIN_PATH="$FIXTURE_DIR/main.nim"
MAIN_URI="file://$MAIN_PATH"

# Test 1: Proc name highlight
test_start "T1_F11_01" "Document highlight on proc identifier highlights occurrences"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F11_01" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc helper(): int = 1\nlet x = helper()\nlet y = helper()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":6}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"range"* || "$OUTPUT" == *"kind"*) ]]; then
    test_pass "T1_F11_01"
  else
    test_fail "T1_F11_01" "Proc highlight failed: $OUTPUT"
  fi
fi

# Test 2: Variable read access highlight
test_start "T1_F11_02" "Document highlight on variable read site highlights variable"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F11_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"let score = 100\nlet bonus = score + 50\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":1,"character":13}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"range"* || "$OUTPUT" == *"kind"*) ]]; then
    test_pass "T1_F11_02"
  else
    test_fail "T1_F11_02" "Variable read highlight failed: $OUTPUT"
  fi
fi

# Test 3: Variable write/declaration highlight
test_start "T1_F11_03" "Document highlight on variable declaration indicates write or text"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F11_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"var counter = 0\ncounter = counter + 1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":5}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"range"* || "$OUTPUT" == *"kind"*) ]]; then
    test_pass "T1_F11_03"
  else
    test_fail "T1_F11_03" "Variable write highlight failed: $OUTPUT"
  fi
fi

# Test 4: Parameter highlight inside proc
test_start "T1_F11_04" "Document highlight on parameter highlights parameter occurrences"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F11_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc scale(factorVal: int): int =\n  factorVal * factorVal\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":12}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"range"* || "$OUTPUT" == *"kind"*) ]]; then
    test_pass "T1_F11_04"
  else
    test_fail "T1_F11_04" "Parameter highlight failed: $OUTPUT"
  fi
fi

# Test 5: Non-symbol highlight returns empty or null
test_start "T1_F11_05" "Document highlight on whitespace returns empty array or null"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F11_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"let a = 1\n   \nlet b = 2\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":1,"character":1}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"[]"* || "$OUTPUT" == *"null"*) ]]; then
    test_pass "T1_F11_05"
  else
    test_fail "T1_F11_05" "Whitespace highlight did not return empty/null: $OUTPUT"
  fi
fi
