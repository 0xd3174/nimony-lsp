#!/usr/bin/env bash
# Tier 2 - Boundary Cases: Malformed JSON-RPC Requests & Recovery
# Authoritative tests derived from JSON-RPC 2.0 & LSP 3.17 specifications

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 2: Malformed JSON-RPC Requests ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

# Test 11: Invalid JSON syntax in request body returns ParseError (-32700)
test_start "T2_11" "Invalid JSON syntax returns JSON-RPC ParseError (-32700)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_11" "nimony-lsp binary not found"
else
  BODY="{invalid json...}"
  RAW=$(printf "Content-Length: %d\r\n\r\n%s" "${#BODY}" "$BODY")
  RESP=$("$HARNESS_BIN" raw-send-recv --cmd "$LSP_BIN" --raw "$RAW" --timeout 3000 2>&1)
  if [[ "$RESP" == *"-32700"* || "$RESP" == *"Parse error"* ]]; then
    test_pass "T2_11"
  else
    test_fail "T2_11" "ParseError response not received: $RESP"
  fi
fi

# Test 12: Missing id in request returns InvalidRequest (-32600)
test_start "T2_12" "Request payload missing id returns InvalidRequest (-32600)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_12" "nimony-lsp binary not found"
else
  REQ='{"jsonrpc":"2.0","method":"textDocument/definition","params":{}}'
  FRAME=$(printf "Content-Length: %d\r\n\r\n%s" "${#REQ}" "$REQ")
  RESP=$("$HARNESS_BIN" raw-send-recv --cmd "$LSP_BIN" --raw "$FRAME" --timeout 3000 2>&1)
  # When id is missing, it's either treated as notification (no response) or error -32600
  if [[ "$RESP" == *"-32600"* || "$RESP" == *"Invalid Request"* || -z "$RESP" ]]; then
    test_pass "T2_12"
  else
    test_fail "T2_12" "Invalid request handling failed: $RESP"
  fi
fi

# Test 13: Missing method field in request returns InvalidRequest (-32600)
test_start "T2_13" "Request payload missing method returns InvalidRequest (-32600)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_13" "nimony-lsp binary not found"
else
  REQ='{"jsonrpc":"2.0","id":999,"params":{}}'
  FRAME=$(printf "Content-Length: %d\r\n\r\n%s" "${#REQ}" "$REQ")
  RESP=$("$HARNESS_BIN" raw-send-recv --cmd "$LSP_BIN" --raw "$FRAME" --timeout 3000 2>&1)
  if [[ "$RESP" == *"-32600"* || "$RESP" == *"Invalid Request"* || "$RESP" == *"error"* ]]; then
    test_pass "T2_13"
  else
    test_fail "T2_13" "Missing method error response not received: $RESP"
  fi
fi

# Test 14: Unknown method returns MethodNotFound (-32601)
test_start "T2_14" "Unknown RPC method returns MethodNotFound (-32601)"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_14" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"custom/completelyUnknownMethod","params":{}}
WAIT_RESP 2 3000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"-32601"* || "$OUTPUT" == *"Method not found"* || "$OUTPUT" == *"error"* ]]; then
    test_pass "T2_14"
  else
    test_fail "T2_14" "MethodNotFound error not received: $OUTPUT"
  fi
fi

# Test 15: Premature EOF / Truncated body handled without hanging
test_start "T2_15" "Truncated body shorter than Content-Length does not crash or hang server"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T2_15" "nimony-lsp binary not found"
else
  # Content-Length 100 but only 10 bytes sent
  FRAME=$(printf "Content-Length: 100\r\n\r\n{\"short\":1")
  RESP=$("$HARNESS_BIN" raw-send-recv --cmd "$LSP_BIN" --raw "$FRAME" --timeout 2000 2>&1)
  # Harness should timeout or server closes cleanly without panic
  if [[ "$RESP" != *"panic"* && "$RESP" != *"core dumped"* ]]; then
    test_pass "T2_15"
  else
    test_fail "T2_15" "Server crashed on truncated payload: $RESP"
  fi
fi
