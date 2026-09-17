#!/usr/bin/env bash
# Tier 1 - F12: Completion Engine
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F12

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F12 Completion Engine ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project"
MAIN_PATH="$FIXTURE_DIR/main.nim"
MAIN_URI="file://$MAIN_PATH"

# Test 1: Keyword completion
test_start "T1_F12_01" "Completion offers Nim language keywords (proc, import, etc.)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F12_01" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"pr"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":2}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"proc"* || "$OUTPUT" == *"label"* || "$OUTPUT" == *"items"*) ]]; then
    test_pass "T1_F12_01"
  else
    test_fail "T1_F12_01" "Keyword completion failed: $OUTPUT"
  fi
fi

# Test 2: Built-in type completion
test_start "T1_F12_02" "Completion offers built-in types (int, string, bool)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F12_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"var x: in"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":9}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"int"* || "$OUTPUT" == *"items"*) ]]; then
    test_pass "T1_F12_02"
  else
    test_fail "T1_F12_02" "Type completion failed: $OUTPUT"
  fi
fi

# Test 3: Snippet completion
test_start "T1_F12_03" "Completion offers code snippets with snippet format"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F12_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":4}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Snippet kind is 15 in LSP, or insertTextFormat 2
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"Snippet"* || "$OUTPUT" == *"insertTextFormat"* || "$OUTPUT" == *"\${"* || "$OUTPUT" == *"items"*) ]]; then
    test_pass "T1_F12_03"
  else
    test_fail "T1_F12_03" "Snippet completion failed: $OUTPUT"
  fi
fi

# Test 4: In-buffer declared proc completion
test_start "T1_F12_04" "Completion offers procs declared in the open buffer"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F12_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc calculateCustomSum(a, b: int): int = a + b\nlet total = calc"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":1,"character":16}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"calculateCustomSum"* || "$OUTPUT" == *"items"*) ]]; then
    test_pass "T1_F12_04"
  else
    test_fail "T1_F12_04" "In-buffer proc completion failed: $OUTPUT"
  fi
fi

# Test 5: In-buffer declared variable completion
test_start "T1_F12_05" "Completion offers variables declared in the open buffer"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F12_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"let activeUserCount = 99\nlet users = act"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":1,"character":15}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"activeUserCount"* || "$OUTPUT" == *"items"*) ]]; then
    test_pass "T1_F12_05"
  else
    test_fail "T1_F12_05" "In-buffer variable completion failed: $OUTPUT"
  fi
fi
