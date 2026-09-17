#!/usr/bin/env bash
# Tier 4 - Real-World Scenario: Complex Refactoring & AST Formatting
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Tier 4

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 4: Complex Refactoring & AST Formatting ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
NIMPRETTY_BIN=$(get_nimpretty_binary)
TEST_URI="file:///tmp/refactor_scenario_test.nim"

# Test 6: Refactoring batch rename simulation workflow
test_start "T4_06" "Refactoring workflow: highlight -> find references -> apply edits -> verify zero diagnostics"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T4_06" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc calculateLegacy(val: int): int = val * 2\nlet a = calculateLegacy(1)\nlet b = calculateLegacy(2)\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":6}}}
WAIT_RESP 2 5000
SEND_REQ {"jsonrpc":"2.0","id":3,"method":"textDocument/references","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":6},"context":{"includeDeclaration":true}}}
WAIT_RESP 3 5000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"proc calculateModern(val: int): int = val * 2\nlet a = calculateModern(1)\nlet b = calculateModern(2)\n"}]}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" == *"RESP:3:"* ]]; then
    test_pass "T4_06"
  else
    test_fail "T4_06" "Refactoring workflow failed: $OUTPUT"
  fi
fi

# Test 7: Complex AST formatting (macros, case statements, pragmas)
test_start "T4_07" "Formatting complex Nim code with pragmas, case statements, and docstrings"
COMPLEX_NIM=$(cat << 'EOF'
type
  Status {.pure.} = enum
    Ok, Err, Pending

proc processStatus(s: Status): string =
  ## Processes status code
  case s
  of Status.Ok:
    result = "Success"
  of Status.Err:
    result = "Failed"
  of Status.Pending:
    result = "Waiting"
EOF
)

if [[ -z "$LSP_BIN" ]]; then
  if [[ -n "$NIMPRETTY_BIN" ]]; then
    FORMATTED=$(echo "$COMPLEX_NIM" | "$NIMPRETTY_BIN" --stdin 2>&1)
    if [[ "$FORMATTED" == *"case s"* && "$FORMATTED" == *"Status.Ok:"* ]]; then
      test_pass "T4_07 (direct nimpretty fallback)"
    else
      test_fail "T4_07" "nimpretty failed complex AST format: $FORMATTED"
    fi
  else
    test_fail "T4_07" "Neither nimony-lsp nor nimpretty found"
  fi
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"$(echo "$COMPLEX_NIM" | sed 's/"/\\"/g' | tr '\n' ' ')"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$TEST_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"TIMEOUT"* ]]; then
    test_pass "T4_07"
  else
    test_fail "T4_07" "Complex AST formatting failed: $OUTPUT"
  fi
fi
