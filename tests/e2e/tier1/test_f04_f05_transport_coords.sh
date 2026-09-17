#!/usr/bin/env bash
# Tier 1 - F04 & F05: LSP JSON-RPC Transport & Coordinate Translation
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F04, F05

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F04/F05 JSON-RPC Transport & Coordinates ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

# Test 1: Initialize returns server capabilities
test_start "T1_F04_F05_01" "Send initialize request and verify capabilities"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F04_F05_01" "nimony-lsp binary not found"
else
  INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}'
  RESP=$("$HARNESS_BIN" single-request --cmd "$LSP_BIN" --request "$INIT_REQ" --timeout 3000 2>&1)
  STATUS=$?
  if [[ $STATUS -eq 0 ]] && [[ "$RESP" == *"capabilities"* ]]; then
    test_pass "T1_F04_F05_01"
  else
    test_fail "T1_F04_F05_01" "initialize failed (status $STATUS): $RESP"
  fi
fi

# Test 2: Initialized notification accepted
test_start "T1_F04_F05_02" "Send initialized notification without server errors"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F04_F05_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << 'EOF' > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SLEEP 100
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  STATUS=$?
  rm -f "$SCRIPT_FILE"
  if [[ $STATUS -eq 0 ]] && [[ "$OUTPUT" == *"RESP:1:"* ]]; then
    test_pass "T1_F04_F05_02"
  else
    test_fail "T1_F04_F05_02" "initialized notification failed: $OUTPUT"
  fi
fi

# Test 3: Shutdown request returns result: null
test_start "T1_F04_F05_03" "Send shutdown request and verify result: null"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F04_F05_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << 'EOF' > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  STATUS=$?
  rm -f "$SCRIPT_FILE"
  if [[ $STATUS -eq 0 ]] && [[ "$OUTPUT" == *"RESP:2:"* ]] && [[ "$OUTPUT" == *"null"* ]]; then
    test_pass "T1_F04_F05_03"
  else
    test_fail "T1_F04_F05_03" "shutdown failed: $OUTPUT"
  fi
fi

# Test 4: Exit notification cleanly terminates server
test_start "T1_F04_F05_04" "Send exit notification and verify clean termination"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F04_F05_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << 'EOF' > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"shutdown","params":null}
WAIT_RESP 2 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"exit","params":null}
SLEEP 200
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  STATUS=$?
  rm -f "$SCRIPT_FILE"
  if [[ $STATUS -eq 0 ]]; then
    test_pass "T1_F04_F05_04"
  else
    test_fail "T1_F04_F05_04" "exit sequence failed: $OUTPUT"
  fi
fi

# Test 5: ASCII coordinates mapping round-trip
test_start "T1_F04_F05_05" "Verify ASCII UTF-16 to 1-based Nimony column calculation"
RES=$("$HARNESS_BIN" coords-test --text "proc add(a: int): int = a + 1" --line 0 --utf16-col 5)
if [[ "$RES" == *"\"lsp_utf16_col\":5"* ]] && [[ "$RES" == *"\"nimony_1based_col\":6"* ]] && [[ "$RES" == *"\"nimony_0based_byte_offset\":5"* ]]; then
  test_pass "T1_F04_F05_05"
else
  test_fail "T1_F04_F05_05" "ASCII coords conversion failed: $RES"
fi

# Test 6: Multi-byte UTF-8 coordinates mapping
test_start "T1_F04_F05_06" "Verify multi-byte UTF-8 character coordinates translation"
# "let café = 1" -> 'c'(1),'a'(1),'f'(1),'é'(2 bytes in UTF-8, 1 code unit in UTF-16)
# At UTF-16 col 8 (after "let café "):
# byte offset: "let "(4) + "caf"(3) + "é"(2) + " "(1) = 10 bytes -> 1-based col 11
RES_MB=$("$HARNESS_BIN" coords-test --text "let café = 1" --line 0 --utf16-col 9)
if [[ "$RES_MB" == *"\"nimony_1based_col\":11"* ]] && [[ "$RES_MB" == *"\"nimony_0based_byte_offset\":10"* ]]; then
  test_pass "T1_F04_F05_06"
else
  test_fail "T1_F04_F05_06" "Multi-byte coords conversion failed: $RES_MB"
fi

# Test 7: Astral surrogate emoji coordinates mapping
test_start "T1_F04_F05_07" "Verify astral surrogate emoji (4-byte UTF-8, 2 UTF-16) translation"
# "let 🚀 = 1" -> 'l','e','t',' ' (4 UTF-16, 4 bytes), 🚀 (2 UTF-16, 4 bytes), ' ' (1 UTF-16, 1 byte)
# UTF-16 col 7: 4 + 2 + 1 = 7. Bytes: 4 + 4 + 1 = 9. 1-based col: 10.
RES_ASTRAL=$("$HARNESS_BIN" coords-test --text "let 🚀 = 1" --line 0 --utf16-col 7)
if [[ "$RES_ASTRAL" == *"\"nimony_1based_col\":10"* ]] && [[ "$RES_ASTRAL" == *"\"nimony_0based_byte_offset\":9"* ]]; then
  test_pass "T1_F04_F05_07"
else
  test_fail "T1_F04_F05_07" "Astral emoji coords conversion failed: $RES_ASTRAL"
fi
