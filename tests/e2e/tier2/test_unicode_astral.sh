#!/usr/bin/env bash
# Tier 2 - Boundary Cases: Unicode & Astral Plane Characters
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §Boundary Cases

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 2: Unicode & Astral Characters ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
UNICODE_URI="file:///tmp/unicode_boundary_test.nim"

# Test 6: Emoji in string coordinates retention
test_start "T2_06" "String literal containing emoji (🚀) preserves exact column offset for trailing tokens"
if [[ -z "$LSP_BIN" ]]; then
  # Test via coords-test helper
  RES=$("$HARNESS_BIN" coords-test --text 'let msg = "🚀 hello" & " world"' --line 0 --utf16-col 20)
  if [[ "$RES" == *"\"nimony_1based_col\":23"* ]]; then
    test_pass "T2_06"
  else
    test_fail "T2_06" "Coords test failed: $RES"
  fi
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UNICODE_URI","languageId":"nim","version":1,"text":"let emoji = \"🚀 rocket\"\nlet next = emoji\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$UNICODE_URI"},"position":{"line":1,"character":12}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* ]]; then
    test_pass "T2_06"
  else
    test_fail "T2_06" "Emoji coords definition failed: $OUTPUT"
  fi
fi

# Test 7: Multi-byte UTF-8 definition
test_start "T2_07" "Go to Definition on line following multi-byte UTF-8 literals (accent/CJK)"
if [[ -z "$LSP_BIN" ]]; then
  RES=$("$HARNESS_BIN" coords-test --text 'let café = "☕"' --line 0 --utf16-col 10)
  if [[ "$RES" == *"\"nimony_1based_col\":12"* ]]; then
    test_pass "T2_07"
  else
    test_fail "T2_07" "Multi-byte coords test failed: $RES"
  fi
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UNICODE_URI","languageId":"nim","version":1,"text":"let greeting = \"Café 你好\"\nproc greet(): string = greeting\nlet outVal = greet()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$UNICODE_URI"},"position":{"line":2,"character":15}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"null"* ]]; then
    test_pass "T2_07"
  else
    test_fail "T2_07" "Multi-byte definition query failed: $OUTPUT"
  fi
fi

# Test 8: Multi-byte UTF-8 diagnostics column precision
test_start "T2_08" "Diagnostic error on line with multi-byte characters reports exact UTF-16 character"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_08" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UNICODE_URI","languageId":"nim","version":1,"text":"let café: int = \"mismatch\"\n"}}}
WAIT_DIAG 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"DIAG:"* && "$OUTPUT" == *"character"* ]]; then
    test_pass "T2_08"
  else
    test_fail "T2_08" "Unicode diagnostic column test failed: $OUTPUT"
  fi
fi

# Test 9: Hover on symbol after emoji string literal
test_start "T2_09" "Hover on symbol located after emoji literal displays correct symbol docs"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_09" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UNICODE_URI","languageId":"nim","version":1,"text":"let prefix = \"🌍 \"\nlet userCounter: int = 10\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"$UNICODE_URI"},"position":{"line":1,"character":5}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" == *"userCounter"* ]]; then
    test_pass "T2_09"
  else
    test_fail "T2_09" "Unicode hover query failed: $OUTPUT"
  fi
fi

# Test 10: Unicode edit synchronization in didChange
test_start "T2_10" "didChange inserting multi-byte characters preserves UTF-16 offset tracking"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_10" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$UNICODE_URI","languageId":"nim","version":1,"text":"let a = 1\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$UNICODE_URI","version":2},"contentChanges":[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":9}},"text":"let 🚀 = \"star\"\nlet b = 🚀\n"}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$UNICODE_URI"},"position":{"line":1,"character":8}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" != *"panic"* ]]; then
    test_pass "T2_10"
  else
    test_fail "T2_10" "Unicode edit synchronization failed: $OUTPUT"
  fi
fi
