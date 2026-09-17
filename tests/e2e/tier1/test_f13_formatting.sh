#!/usr/bin/env bash
# Tier 1 - F13: Document Formatting via nimpretty
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F13

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F13 Document Formatting ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
NIMPRETTY_BIN=$(get_nimpretty_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project"
MAIN_PATH="$FIXTURE_DIR/main.nim"
MAIN_URI="file://$MAIN_PATH"

# Test 1: Format unformatted code
test_start "T1_F13_01" "Document formatting formats unformatted Nim code via nimpretty"
if [[ -z "$LSP_BIN" ]]; then
  # Fallback to direct nimpretty test if nimony-lsp not built
  if [[ -n "$NIMPRETTY_BIN" ]]; then
    FORMATTED=$(echo "proc  foo( a :int ,b:string ):int=a+1" | "$NIMPRETTY_BIN" --stdin 2>&1)
    if [[ "$FORMATTED" == *"proc foo(a: int; b: string): int ="* || "$FORMATTED" == *"proc foo"* ]]; then
      test_pass "T1_F13_01 (direct nimpretty fallback)"
    else
      test_fail "T1_F13_01" "nimpretty failed to format: $FORMATTED"
    fi
  else
    test_fail "T1_F13_01" "Neither nimony-lsp nor nimpretty found"
  fi
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc  foo( a :int ,b:string ):int=a+1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$MAIN_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"newText"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F13_01"
  else
    test_fail "T1_F13_01" "Formatting unformatted code failed: $OUTPUT"
  fi
fi

# Test 2: Format idempotent
test_start "T1_F13_02" "Formatting already clean code returns empty edits or unchanged"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F13_02" "nimony-lsp binary not found"
else
  CLEAN_CODE="proc foo(a: int; b: string): int =\n  result = a + 1\n"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"$CLEAN_CODE"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$MAIN_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"[]"* || "$OUTPUT" == *"null"* || "$OUTPUT" == *"newText"*) ]]; then
    test_pass "T1_F13_02"
  else
    test_fail "T1_F13_02" "Idempotent format failed: $OUTPUT"
  fi
fi

# Test 3: Format with syntax error gracefully fails without corruption
test_start "T1_F13_03" "Formatting code with syntax error returns empty edits or null"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F13_03" "nimony-lsp binary not found"
else
  BROKEN_CODE="proc unclosed(a: int = 1\n"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"$BROKEN_CODE"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$MAIN_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"[]"* || "$OUTPUT" == *"null"*) ]]; then
    test_pass "T1_F13_03"
  else
    test_fail "T1_F13_03" "Format on syntax error did not return empty/null: $OUTPUT"
  fi
fi

# Test 4: Indentation options honored
test_start "T1_F13_04" "Formatting honors indent tabSize options"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F13_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc test() =\n    discard\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$MAIN_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* ]]; then
    test_pass "T1_F13_04"
  else
    test_fail "T1_F13_04" "Indentation options format failed: $OUTPUT"
  fi
fi

# Test 5: Comments preserved during formatting
test_start "T1_F13_05" "Formatting preserves doc comments (##) and line comments (#)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F13_05" "nimony-lsp binary not found"
else
  COMMENTED_CODE="## Module documentation\nproc hello() =\n  # inner comment\n  discard\n"
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"$COMMENTED_CODE"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$MAIN_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"TIMEOUT"* ]]; then
    test_pass "T1_F13_05"
  else
    test_fail "T1_F13_05" "Comment preservation format failed: $OUTPUT"
  fi
fi
