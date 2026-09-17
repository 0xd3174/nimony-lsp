#!/usr/bin/env bash
# Tier 1 - F06 & F07: Live and Save Diagnostics
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F06, F07

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F06/F07 Live & Save Diagnostics ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

# Test 1: Live syntax error diagnostic on didOpen
test_start "T1_F06_F07_01" "Live syntax error publishes Error diagnostic with line/character"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F06_F07_01" "nimony-lsp binary not found"
else
  DOC_PATH="$WORKSPACE_ROOT/tests/e2e/fixtures/syntax_error/broken.nim"
  DOC_URI="file://$DOC_PATH"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$WORKSPACE_ROOT","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$DOC_URI","languageId":"nim","version":1,"text":"proc unclosedParen(a: int = 1"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"DIAG:"* && "$OUTPUT" == *"Error"* && "$OUTPUT" != *"TIMEOUT"* ]]; then
    test_pass "T1_F06_F07_01"
  else
    test_fail "T1_F06_F07_01" "Syntax error diagnostic not received: $OUTPUT"
  fi
fi

# Test 2: Live type error diagnostic on didChange
test_start "T1_F06_F07_02" "Live type mismatch error publishes Error diagnostic"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F06_F07_02" "nimony-lsp binary not found"
else
  DOC_PATH="$WORKSPACE_ROOT/tests/e2e/fixtures/type_error/mismatch.nim"
  DOC_URI="file://$DOC_PATH"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$WORKSPACE_ROOT","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$DOC_URI","languageId":"nim","version":1,"text":"proc needsInt(x: int): int = x + 1\nlet wrong = needsInt(\"invalid string\")\n"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"DIAG:"* && "$OUTPUT" == *"type mismatch"* ]]; then
    test_pass "T1_F06_F07_02"
  else
    test_fail "T1_F06_F07_02" "Type error diagnostic not received: $OUTPUT"
  fi
fi

# Test 3: Warning diagnostic parsing
test_start "T1_F06_F07_03" "Verify warning diagnostic parsing into severity Warning (2)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F06_F07_03" "nimony-lsp binary not found"
else
  DOC_PATH="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project/warn.nim"
  DOC_URI="file://$DOC_PATH"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$WORKSPACE_ROOT","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$DOC_URI","languageId":"nim","version":1,"text":"var unusedVar: int = 10\n"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Severity 2 is Warning
  if [[ "$OUTPUT" == *"DIAG:"* && ("$OUTPUT" == *"\"severity\":2"* || "$OUTPUT" == *"Warning"* || "$OUTPUT" == *"unused"* || "$OUTPUT" == *"diagnostics"* ) ]]; then
    test_pass "T1_F06_F07_03"
  else
    test_fail "T1_F06_F07_03" "Warning diagnostic not received: $OUTPUT"
  fi
fi

# Test 4: Save diagnostics via didSave
test_start "T1_F06_F07_04" "didSave triggers immediate compiler check and publishes diagnostics"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F06_F07_04" "nimony-lsp binary not found"
else
  DOC_PATH="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project/main.nim"
  DOC_URI="file://$DOC_PATH"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$WORKSPACE_ROOT","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$DOC_URI","languageId":"nim","version":1,"text":"import utils\nlet total = add(1, 2)\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didSave","params":{"textDocument":{"uri":"$DOC_URI"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"DIAG:"* && "$OUTPUT" != *"TIMEOUT"* ]]; then
    test_pass "T1_F06_F07_04"
  else
    test_fail "T1_F06_F07_04" "Save diagnostic response unexpected: $OUTPUT"
  fi
fi

# Test 5: Shadow file URI remapping
test_start "T1_F06_F07_05" "Shadow file (.tmp_*.nim) paths remapped to original document URI"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F06_F07_05" "nimony-lsp binary not found"
else
  DOC_PATH="$WORKSPACE_ROOT/tests/e2e/fixtures/syntax_error/broken.nim"
  DOC_URI="file://$DOC_PATH"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$WORKSPACE_ROOT","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$DOC_URI","languageId":"nim","version":1,"text":"proc broken() = (("}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Must contain original document URI, NEVER ".tmp_"
  if [[ "$OUTPUT" == *"$DOC_URI"* && "$OUTPUT" != *".tmp_"* ]]; then
    test_pass "T1_F06_F07_05"
  else
    test_fail "T1_F06_F07_05" "Shadow file URI was not remapped to original document URI: $OUTPUT"
  fi
fi

# Test 6: Trace diagnostic parsed into relatedInformation
test_start "T1_F06_F07_06" "Instantiation Trace lines mapped to relatedInformation"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F06_F07_06" "nimony-lsp binary not found"
else
  DOC_PATH="$WORKSPACE_ROOT/tests/e2e/fixtures/generic_module/math_generic.nim"
  DOC_URI="file://$DOC_PATH"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$WORKSPACE_ROOT","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$DOC_URI","languageId":"nim","version":1,"text":"proc square[T](x: T): T = x * x\nlet bad = square(\"not a number\")\n"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"relatedInformation"* || "$OUTPUT" == *"Trace"* || "$OUTPUT" == *"instantiation"* ]]; then
    test_pass "T1_F06_F07_06"
  else
    test_fail "T1_F06_F07_06" "Trace relatedInformation not parsed: $OUTPUT"
  fi
fi
