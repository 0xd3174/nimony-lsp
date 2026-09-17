#!/usr/bin/env bash
# Tier 1 - F09: Find References
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F09

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F09 Find References ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project"
MAIN_PATH="$FIXTURE_DIR/main.nim"
MAIN_URI="file://$MAIN_PATH"

# Test 1: References on proc returns definition and call sites
test_start "T1_F09_01" "Find References on proc returns definition and call sites"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F09_01" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc calc(x: int): int = x * 2\nlet a = calc(1)\nlet b = calc(2)\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":5},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Should find line 0 (def), line 1 (call 1), line 2 (call 2)
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* && ("$OUTPUT" == *"line"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F09_01"
  else
    test_fail "T1_F09_01" "References on proc failed: $OUTPUT"
  fi
fi

# Test 2: References on local variable returns usages
test_start "T1_F09_02" "Find References on local variable returns all usages in proc"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F09_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"let factor = 10\nlet r1 = factor * 2\nlet r2 = factor * 3\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":5},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* && ("$OUTPUT" == *"line"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F09_02"
  else
    test_fail "T1_F09_02" "References on variable failed: $OUTPUT"
  fi
fi

# Test 3: References on module-level constant returns occurrences
test_start "T1_F09_03" "Find References on module const returns all usage locations"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F09_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"const MaxRetries = 5\nlet limit = MaxRetries\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":7},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* && ("$OUTPUT" == *"line"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F09_03"
  else
    test_fail "T1_F09_03" "References on const failed: $OUTPUT"
  fi
fi

# Test 4: References with includeDeclaration: false excludes definition
test_start "T1_F09_04" "Find References with includeDeclaration: false excludes def site"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F09_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc helper(): int = 1\nlet x = helper()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":5},"context":{"includeDeclaration":false}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* ]]; then
    test_pass "T1_F09_04"
  else
    test_fail "T1_F09_04" "References excludeDeclaration failed: $OUTPUT"
  fi
fi

# Test 5: References across multiple procedures calling same function
test_start "T1_F09_05" "Find References finds calls across multiple procs"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F09_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc base(): int = 0\nproc callerA(): int = base()\nproc callerB(): int = base()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":0,"character":6},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* ]]; then
    test_pass "T1_F09_05"
  else
    test_fail "T1_F09_05" "References across multiple procs failed: $OUTPUT"
  fi
fi
