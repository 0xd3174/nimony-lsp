#!/usr/bin/env bash
# Tier 1 - F10: Hover Information
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F10

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F10 Hover Information ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project"
MAIN_PATH="$FIXTURE_DIR/main.nim"
MAIN_URI="file://$MAIN_PATH"

# Test 1: Hover on proc displays signature
test_start "T1_F10_01" "Hover on proc displays proc signature"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F10_01" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc greet(name: string): string =\n  result = \"Hello \" & name\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":6}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"greet"* || "$OUTPUT" == *"string"* || "$OUTPUT" == *"contents"*) ]]; then
    test_pass "T1_F10_01"
  else
    test_fail "T1_F10_01" "Hover on proc failed: $OUTPUT"
  fi
fi

# Test 2: Hover on proc with docstring includes documentation
test_start "T1_F10_02" "Hover on proc with doc-comment displays docstring"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F10_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc computeTotal(a, b: int): int =\n  ## Computes total sum of two values\n  a + b\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":6}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"Computes total sum"* || "$OUTPUT" == *"computeTotal"*) ]]; then
    test_pass "T1_F10_02"
  else
    test_fail "T1_F10_02" "Hover docstring display failed: $OUTPUT"
  fi
fi

# Test 3: Hover on variable displays variable name and type
test_start "T1_F10_03" "Hover on variable displays name and type"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F10_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"let timeoutSeconds: int = 30\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":5}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"timeoutSeconds"* || "$OUTPUT" == *"int"*) ]]; then
    test_pass "T1_F10_03"
  else
    test_fail "T1_F10_03" "Hover on variable failed: $OUTPUT"
  fi
fi

# Test 4: Hover on keyword displays keyword documentation
test_start "T1_F10_04" "Hover on keyword (e.g. proc, type, discard) displays docs"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F10_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc test() = discard\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":1}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"proc"* || "$OUTPUT" == *"procedure"* || "$OUTPUT" == *"contents"*) ]]; then
    test_pass "T1_F10_04"
  else
    test_fail "T1_F10_04" "Hover on keyword failed: $OUTPUT"
  fi
fi

# Test 5: Hover on built-in type displays type documentation
test_start "T1_F10_05" "Hover on built-in type (e.g. int, string) displays type docs"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F10_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"let val: int = 1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":10}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"int"* || "$OUTPUT" == *"integer"* || "$OUTPUT" == *"contents"*) ]]; then
    test_pass "T1_F10_05"
  else
    test_fail "T1_F10_05" "Hover on built-in type failed: $OUTPUT"
  fi
fi
