#!/usr/bin/env bash
# Extended Adversarial Coordinate Translation & Unicode Stress Suite
# Developed by Challenger 2 for Milestone 2 EMPIRICAL Verification

source "$(dirname "${BASH_SOURCE[0]}")/test_framework.sh"

echo -e "\n${C_BOLD}=== Running Extended Adversarial Unicode & Boundary Stress Suite ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

if [[ -z "$LSP_BIN" ]]; then
  echo "LSP binary not found!"
  exit 1
fi

# EXT_01: Cursor positioned exactly in middle of surrogate pair (character: 5 in "let 🚀 = 1")
test_start "EXT_01" "Completion with cursor inside UTF-16 surrogate pair does not panic"
SCRIPT_FILE=$(mktemp)
cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/ext_surrogate_mid.nim","languageId":"nim","version":1,"text":"let 🚀 = 1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/ext_surrogate_mid.nim"},"position":{"line":0,"character":5}}}
WAIT_RESP 2 3000
EOF
OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
rm -f "$SCRIPT_FILE"
if [[ "$OUTPUT" == *"panicked"* || "$OUTPUT" == *"RESP:2:TIMEOUT"* || "$OUTPUT" == *"char boundary"* ]]; then
  test_fail "EXT_01" "Server crashed or panicked on surrogate pair midpoint: $OUTPUT"
elif [[ "$OUTPUT" == *"RESP:2:"* ]]; then
  test_pass "EXT_01"
else
  test_fail "EXT_01" "Unexpected output: $OUTPUT"
fi

# EXT_02: Multiple consecutive astral plane emojis with completion queries
test_start "EXT_02" "Completion following multiple consecutive surrogate pairs (🚀🌟🎉) does not panic"
SCRIPT_FILE=$(mktemp)
cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/ext_multi_emoji.nim","languageId":"nim","version":1,"text":"let 🚀🌟🎉 = 100\nlet x = 2\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/ext_multi_emoji.nim"},"position":{"line":0,"character":10}}}
WAIT_RESP 2 3000
SEND_REQ {"jsonrpc":"2.0","id":3,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///tmp/ext_multi_emoji.nim"},"position":{"line":0,"character":8}}}
WAIT_RESP 3 3000
EOF
OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
rm -f "$SCRIPT_FILE"
if [[ "$OUTPUT" == *"panicked"* || "$OUTPUT" == *"TIMEOUT"* || "$OUTPUT" == *"char boundary"* ]]; then
  test_fail "EXT_02" "Server crashed on consecutive emojis: $OUTPUT"
elif [[ "$OUTPUT" == *"RESP:2:"* && "$OUTPUT" == *"RESP:3:"* ]]; then
  test_pass "EXT_02"
else
  test_fail "EXT_02" "Unexpected output: $OUTPUT"
fi

# EXT_03: Definition query on identifier following heavy multi-byte accent comments
test_start "EXT_03" "Go to Definition resolves accurately across heavy multi-byte accent comments"
SCRIPT_FILE=$(mktemp)
cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/ext_accents.nim","languageId":"nim","version":1,"text":"# Un commentaire en français: é, à, è, ç, ô, û, î, ë, ï, ü\nproc computeValue*(): int = 100\nlet ans = computeValue()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file:///tmp/ext_accents.nim"},"position":{"line":2,"character":12}}}
WAIT_RESP 2 6000
EOF
OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
rm -f "$SCRIPT_FILE"
if [[ "$OUTPUT" == *"\"start\":{\"character\":5,\"line\":1}"* && "$OUTPUT" == *"\"end\":{\"character\":17,\"line\":1}"* ]]; then
  test_pass "EXT_03"
else
  test_fail "EXT_03" "Definition resolution drifted or failed: $OUTPUT"
fi

# EXT_04: Find References across mixed emoji and CJK characters
test_start "EXT_04" "Find References accurately handles mixed emoji and CJK characters"
SCRIPT_FILE=$(mktemp)
cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/ext_refs_cjk.nim","languageId":"nim","version":1,"text":"proc targetFn*(): int = 1\nlet 🚀_val = targetFn()\nlet 你好_val = targetFn()\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/references","params":{"textDocument":{"uri":"file:///tmp/ext_refs_cjk.nim"},"position":{"line":0,"character":6},"context":{"includeDeclaration":true}}}
WAIT_RESP 2 6000
EOF
OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
rm -f "$SCRIPT_FILE"
if [[ "$OUTPUT" == *"\"start\":{\"character\":13,\"line\":1}"* && "$OUTPUT" == *"\"start\":{\"character\":13,\"line\":2}"* ]]; then
  test_pass "EXT_04"
else
  test_fail "EXT_04" "References ranges incorrect: $OUTPUT"
fi

# EXT_05: Formatting on file with 2-byte, 3-byte, and 4-byte UTF-8 without corruption
test_start "EXT_05" "Formatting preserves 2-byte, 3-byte, and 4-byte UTF-8 content faithfully"
SCRIPT_FILE=$(mktemp)
cat << "EOF" > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///tmp/ext_fmt_utf.nim","languageId":"nim","version":1,"text":"proc testUtf*():string=\"café ☕ 🚀\"\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file:///tmp/ext_fmt_utf.nim"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 6000
EOF
OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
rm -f "$SCRIPT_FILE"
if [[ "$OUTPUT" == *"café ☕ 🚀"* ]]; then
  test_pass "EXT_05"
else
  test_fail "EXT_05" "Formatting output corrupted unicode: $OUTPUT"
fi

echo -e "\n======================================================"
echo -e "      EXTENDED ADVERSARIAL STRESS SUITE SUMMARY       "
echo -e "======================================================"
echo -e "  Total Tests:   $TESTS_TOTAL"
echo -e "  Passed:        $TESTS_PASSED"
echo -e "  Failed:        $TESTS_FAILED"
echo -e "  Skipped:       $TESTS_SKIPPED"
echo -e "======================================================"

if [[ $TESTS_FAILED -gt 0 ]]; then
  echo -e "${C_RED}STATUS: $TESTS_FAILED TESTS FAILED${C_RESET}"
  exit 1
else
  echo -e "${C_GREEN}STATUS: ALL EXTENDED TESTS PASSED${C_RESET}"
  exit 0
fi
