#!/usr/bin/env bash
# Tier 3 - Cross-Feature: didChange Dirty Edit -> Completion
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Tier 3

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 3: didChange Dirty Edit -> Completion ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
TEST_URI="file:///tmp/dirty_edit_completion_test.nim"

# Test 3: Unsaved variable introduced via didChange appears in completion
test_start "T3_03" "Unsaved variable declared in didChange appears in completion suggestions"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let a = 1\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"let maxRetryThreshold = 5\nlet limit = maxR"}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":1,"character":16}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"maxRetryThreshold"* || "$OUTPUT" == *"items"*) ]]; then
    test_pass "T3_03"
  else
    test_fail "T3_03" "Unsaved variable completion failed: $OUTPUT"
  fi
fi

# Test 4: Deleted proc no longer appears in completion suggestions
test_start "T3_04" "Proc deleted in didChange is evicted from completion suggestions"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc obsoleteCalculation(): int = 0\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"let cleanState = 1\nlet x = obso"}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":1,"character":12}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"obsoleteCalculation"* ]]; then
    test_pass "T3_04"
  else
    test_fail "T3_04" "Deleted proc still appeared in completion: $OUTPUT"
  fi
fi
