#!/usr/bin/env bash
# Adversarial Coordinate Translation & Cross-Feature Integration Stress Test Suite
# Developed by Challenger 2 for Milestone 2 EMPIRICAL review

source "$(dirname "${BASH_SOURCE[0]}")/test_framework.sh"

echo -e "\n${C_BOLD}=== Running Adversarial Stress Suite: Coordinates & Cross-Feature Integration ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

# ADV_01: Completion on line with multi-byte UTF-8 character (e.g. 'é')
test_start "ADV_01" "Completion on line with 2-byte UTF-8 character (café) does not panic or crash"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_01" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_utf8.nim","languageId":"nim","version":1,"text":"let café = 1\nlet x = 2\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/adv_test_utf8.nim"},"position":{"line":0,"character":8}}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"panicked"* || "$OUTPUT" == *"RESP:2:TIMEOUT"* || "$OUTPUT" == *"char boundary"* ]]; then
    test_fail "ADV_01" "Server panicked on UTF-8 character boundary: $OUTPUT"
  elif [[ "$OUTPUT" == *"RESP:2:"* ]]; then
    test_pass "ADV_01"
  else
    test_fail "ADV_01" "Unexpected output: $OUTPUT"
  fi
fi

# ADV_02: Completion on line with 4-byte astral plane emoji surrogate pair (🚀)
test_start "ADV_02" "Completion on line with astral plane emoji surrogate pair (🚀) does not panic"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_emoji.nim","languageId":"nim","version":1,"text":"let 🚀 = 2\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/adv_test_emoji.nim"},"position":{"line":0,"character":6}}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"panicked"* || "$OUTPUT" == *"RESP:2:TIMEOUT"* || "$OUTPUT" == *"char boundary"* ]]; then
    test_fail "ADV_02" "Server panicked on emoji surrogate boundary: $OUTPUT"
  elif [[ "$OUTPUT" == *"RESP:2:"* ]]; then
    test_pass "ADV_02"
  else
    test_fail "ADV_02" "Unexpected output: $OUTPUT"
  fi
fi

# ADV_03: Empty file boundary conditions across navigation, hover, completion, highlight
test_start "ADV_03" "Empty file boundary requests (def, hover, highlight, completion) return gracefully"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_empty.nim","languageId":"nim","version":1,"text":""}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/adv_test_empty.nim"},"position":{"line":0,"character":0}}}
WAIT_RESP 2 3000
SEND_REQ {"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/adv_test_empty.nim"},"position":{"line":0,"character":0}}}
WAIT_RESP 3 3000
SEND_REQ {"jsonrpc":"2.0","id":4,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"file:///tmp/adv_test_empty.nim"},"position":{"line":0,"character":0}}}
WAIT_RESP 4 3000
SEND_REQ {"jsonrpc":"2.0","id":5,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/adv_test_empty.nim"},"position":{"line":0,"character":0}}}
WAIT_RESP 5 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}"* && \
        "$OUTPUT" == *"RESP:3:{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":null}"* && \
        "$OUTPUT" == *"RESP:4:{\"jsonrpc\":\"2.0\",\"id\":4,\"result\":null}"* && \
        "$OUTPUT" == *"RESP:5:"* ]]; then
    test_pass "ADV_03"
  else
    test_fail "ADV_03" "Empty file requests did not return gracefully: $OUTPUT"
  fi
fi

# ADV_04: Extreme out-of-bounds line/character positions
test_start "ADV_04" "Extreme out-of-bounds coordinates (line: 99999, col: 99999) return null safely"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_oob.nim","languageId":"nim","version":1,"text":"let a = 1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/adv_test_oob.nim"},"position":{"line":99999,"character":99999}}}
WAIT_RESP 2 3000
SEND_REQ {"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///tmp/adv_test_oob.nim"},"position":{"line":99999,"character":99999}}}
WAIT_RESP 3 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}"* && \
        "$OUTPUT" == *"RESP:3:{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":null}"* ]]; then
    test_pass "ADV_04"
  else
    test_fail "ADV_04" "OOB requests failed: $OUTPUT"
  fi
fi

# ADV_05: Go to Definition on same line following astral plane emoji
test_start "ADV_05" "Go to Definition on symbol declared on same line after emoji (🚀) resolves accurately"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_def_emoji.nim","languageId":"nim","version":1,"text":"let 🚀 = 1; proc foo*(): int = 42\nlet x = foo()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/adv_test_def_emoji.nim"},"position":{"line":1,"character":9}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"\"start\":{\"character\":17,\"line\":0}"* && "$OUTPUT" == *"\"end\":{\"character\":20,\"line\":0}"* ]]; then
    test_pass "ADV_05"
  else
    test_fail "ADV_05" "Emoji definition target range incorrect: $OUTPUT"
  fi
fi

# ADV_06: Find References on identifier referenced across lines with astral emojis and accented chars
test_start "ADV_06" "Find References accurately calculates UTF-16 ranges across emoji & accented lines"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_06" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_refs_utf8.nim","languageId":"nim","version":1,"text":"proc sharedFunc*(): int = 1\nlet 🚀 = sharedFunc()\nlet café = sharedFunc()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"file:///tmp/adv_test_refs_utf8.nim"},"position":{"line":0,"character":6},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"\"start\":{\"character\":9,\"line\":1}"* && "$OUTPUT" == *"\"start\":{\"character\":11,\"line\":2}"* ]]; then
    test_pass "ADV_06"
  else
    test_fail "ADV_06" "References ranges inaccurate: $OUTPUT"
  fi
fi

# ADV_07: Live debounced diagnostics on line containing astral emoji
test_start "ADV_07" "Live debounced diagnostics report accurate UTF-16 range for error following emoji"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_07" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_diag_emoji.nim","languageId":"nim","version":1,"text":"let 🚀: int = \"hello\"\n"}}}
WAIT_DIAG 4000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"\"character\":14,\"line\":0"* && "$OUTPUT" == *"type mismatch"* ]]; then
    test_pass "ADV_07"
  else
    test_fail "ADV_07" "Diagnostic range for emoji line inaccurate: $OUTPUT"
  fi
fi

# ADV_08: Cross-feature dirty unsaved edits interacting with Go to Definition
test_start "ADV_08" "Unsaved dirty didChange edit interacts correctly with immediate Go to Definition"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_08" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_dirty_def.nim","languageId":"nim","version":1,"text":"let a = 1\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///tmp/adv_test_dirty_def.nim","version":2},"contentChanges":[{"text":"let 🚀 = 1; proc dirtyFunc*(): int = 99\nlet y = dirtyFunc()\n"}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/adv_test_dirty_def.nim"},"position":{"line":1,"character":9}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"\"start\":{\"character\":17,\"line\":0}"* && "$OUTPUT" == *"\"end\":{\"character\":26,\"line\":0}"* ]]; then
    test_pass "ADV_08"
  else
    test_fail "ADV_08" "Dirty edit definition failed: $OUTPUT"
  fi
fi

# ADV_09: Incremental didChange edits across multibyte UTF-8 lines
test_start "ADV_09" "Incremental didChange edits across multibyte UTF-8 lines avoid coordinate drift"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_09" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_incr_drift.nim","languageId":"nim","version":1,"text":"let café = 1\nlet foo = 2\n"}}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///tmp/adv_test_incr_drift.nim","version":2},"contentChanges":[{"range":{"start":{"line":1,"character":4},"end":{"line":1,"character":7}},"text":"bar"}]}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/adv_test_incr_drift.nim"},"position":{"line":1,"character":4}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"\"start\":{\"character\":4,\"line\":1}"* && "$OUTPUT" == *"\"end\":{\"character\":7,\"line\":1}"* ]]; then
    test_pass "ADV_09"
  else
    test_fail "ADV_09" "Incremental didChange coordinate drifted: $OUTPUT"
  fi
fi

# ADV_10: Document formatting with minimal diff on astral emoji source code
test_start "ADV_10" "Document formatting produces valid minimal edit on source containing astral emojis"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "ADV_10" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/adv_test_fmt_emoji.nim","languageId":"nim","version":1,"text":"proc testFunc*():string=\"🚀\"\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file:///tmp/adv_test_fmt_emoji.nim"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"proc testFunc*(): string = \\\"🚀\\\""* ]]; then
    test_pass "ADV_10"
  else
    test_fail "ADV_10" "Emoji formatting edit failed: $OUTPUT"
  fi
fi

echo -e "\n======================================================"
echo -e "          ADVERSARIAL STRESS SUITE SUMMARY            "
echo -e "======================================================"
echo -e "  Total Tests:   $TESTS_TOTAL"
echo -e "  Passed:        $TESTS_PASSED"
echo -e "  Failed:        $TESTS_FAILED"
echo -e "  Skipped:       $TESTS_SKIPPED"
echo -e "======================================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${C_RED}STATUS: $TESTS_FAILED ADVERSARIAL STRESS TESTS FAILED${C_RESET}"
  exit 1
else
  echo -e "${C_GREEN}STATUS: ALL ADVERSARIAL TESTS PASSED${C_RESET}"
  exit 0
fi
