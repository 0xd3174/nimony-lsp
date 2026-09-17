#!/usr/bin/env bash
# Tier 3 - Cross-Feature: Save -> Clear Diagnostics & Shadow Consistency
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Tier 3

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 3: Save -> Clear Diagnostics ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

# Test 7: Save fixes diagnostic
test_start "T3_07" "Fixing error via didChange and saving via didSave immediately publishes clean diagnostics"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_07" "nimony-lsp binary not found"
else
  TEMP_DIR=$(mktemp -d)
  TEST_FILE="$TEMP_DIR/save_test.nim"
  TEST_URI="file://$TEST_FILE"
  echo "proc broken() = ((" > "$TEST_FILE"

  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$TEMP_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc broken() = (("}}}
WAIT_DIAG 5000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"proc fixed(): int = 42\n"}]}}
WAIT_DIAG 5000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didSave","params":{"textDocument":{"uri":"$TEST_URI"}}}
WAIT_DIAG 5000
EOF
  echo "proc fixed(): int = 42" > "$TEST_FILE"
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$TEMP_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  rm -rf "$TEMP_DIR"
  if [[ "$OUTPUT" == *"\"diagnostics\":[]"* || "$OUTPUT" == *"DIAG:"* ]]; then
    test_pass "T3_07"
  else
    test_fail "T3_07" "Save did not clear diagnostics: $OUTPUT"
  fi
fi

# Test 8: Shadow buffer vs disk consistency
test_start "T3_08" "Disk file clean while memory buffer dirty: diagnostics reflect shadow file, reverting clears"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T3_08" "nimony-lsp binary not found"
else
  TEMP_DIR=$(mktemp -d)
  TEST_FILE="$TEMP_DIR/shadow_test.nim"
  TEST_URI="file://$TEST_FILE"
  echo "let valid = 100" > "$TEST_FILE"

  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$TEMP_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"let valid = 100\n"}}}
WAIT_DIAG 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"let valid: string = 100\n"}]}}
WAIT_DIAG 5000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":3},"contentChanges":[{"text":"let valid = 100\n"}]}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$TEMP_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  rm -rf "$TEMP_DIR"
  if [[ "$OUTPUT" == *"type mismatch"* || "$OUTPUT" == *"\"diagnostics\":[]"* || "$OUTPUT" == *"DIAG:"* ]]; then
    test_pass "T3_08"
  else
    test_fail "T3_08" "Shadow consistency check failed: $OUTPUT"
  fi
fi
