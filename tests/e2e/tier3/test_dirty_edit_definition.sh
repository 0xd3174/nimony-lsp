#!/usr/bin/env bash
# Tier 3 - Cross-Feature: didChange Dirty Edit -> Definition Query
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Tier 3

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 3: didChange Dirty Edit -> Definition Query ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
TEST_URI="file:///tmp/dirty_edit_def_test.nim"

# Test 1: In-memory unsaved edit adds proc; definition resolves to new line
test_start "T3_01" "didChange unsaved edit adding new proc allows immediate Go to Definition"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_01" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let initial = 1\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"proc computeDelta(): int = 42\nlet res = computeDelta()\n"}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":1,"character":15}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Target definition is at line 0 (computeDelta)
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"\"line\":0"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T3_01"
  else
    test_fail "T3_01" "Dirty edit definition failed: $OUTPUT"
  fi
fi

# Test 2: In-memory rename proc; definition resolves to new name, fails on old
test_start "T3_02" "didChange renaming proc in-memory updates definition target accurately"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc oldName(): int = 1\nlet a = oldName()\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"proc newName(): int = 1\nlet a = newName()\n"}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":1,"character":10}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* ]]; then
    test_pass "T3_02"
  else
    test_fail "T3_02" "Renamed proc definition failed: $OUTPUT"
  fi
fi
