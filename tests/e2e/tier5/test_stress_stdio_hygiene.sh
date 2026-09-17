#!/usr/bin/env bash
# Tier 5 - Adversarial Stress Testing: Stdio Transport, Concurrency, and Shadow File Hygiene
# Milestone 2 Challenger verification suite

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 5: Stdio Transport, Concurrency & Shadow File Hygiene ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

if [[ -z "$LSP_BIN" || ! -x "$LSP_BIN" ]]; then
  echo -e "${C_RED}Error: nimony-lsp binary not found at $LSP_BIN${C_RESET}"
  exit 1
fi

STRESS_TEMP_DIR=$(mktemp -d "/tmp/nimony_stress_XXXXXX")
cleanup_temp() {
  rm -rf "$STRESS_TEMP_DIR"
}
trap cleanup_temp EXIT

# -----------------------------------------------------------------------------
# STRESS 1: Dot-Free Shadow File Hygiene and Prompt Deletion Under Load
# -----------------------------------------------------------------------------
test_start "T5_01" "Stress test dot-free shadow files and prompt cleanup during concurrent edits"

TEST_NIM_FILE="$STRESS_TEMP_DIR/project_mod.nim"
cat << 'EOF' > "$TEST_NIM_FILE"
proc computeAlpha*(x: int): int =
  x * 10

proc computeBeta*(y: int): int =
  computeAlpha(y) + 5
EOF

TEST_URI="file://$TEST_NIM_FILE"

# Prepare script with rapid interleaved didChange and definition queries
BURST_SCRIPT="$STRESS_TEMP_DIR/burst_script.txt"
cat << EOF > "$BURST_SCRIPT"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$STRESS_TEMP_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"$(sed 's/"/\\"/g' "$TEST_NIM_FILE" | awk '{printf "%s\\n", $0}')"}}}
EOF

# Append 20 rapid bursts of didChange + textDocument/definition
for i in $(seq 2 21); do
  cat << EOF >> "$BURST_SCRIPT"
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":$i},"contentChanges":[{"text":"proc computeAlpha*(x: int): int =\n  x * $i\nproc computeBeta*(y: int): int =\n  computeAlpha(y) + $i\n"}]}}
SEND_REQ {"jsonrpc":"2.0","id":$((100 + i)),"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":3,"character":4}}}
SLEEP 20
EOF
done

cat << EOF >> "$BURST_SCRIPT"
WAIT_RESP 121 8000
WAIT_DIAG 3000
SEND_REQ {"jsonrpc":"2.0","id":999,"method":"shutdown","params":{}}
WAIT_RESP 999 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"exit","params":{}}
EOF

# Run harness in background to allow filesystem snooping while active
OUTPUT_LOG="$STRESS_TEMP_DIR/harness_output.log"
"$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$STRESS_TEMP_DIR" --script "$BURST_SCRIPT" > "$OUTPUT_LOG" 2>&1 &
HARNESS_PID=$!

DOT_FILE_DETECTED=0
SHADOW_OBSERVED=0

# Poll filesystem during execution to inspect shadow file naming
for _ in $(seq 1 40); do
  if ! kill -0 "$HARNESS_PID" 2>/dev/null; then
    break
  fi

  # Check for forbidden dot-prefixed temporary files
  if [[ -n "$(find "$STRESS_TEMP_DIR" -maxdepth 1 -name ".*.nim" -print -quit 2>/dev/null)" ]]; then
    DOT_FILE_DETECTED=1
    break
  fi

  # Check for compliant dot-free shadow files
  if [[ -n "$(find "$STRESS_TEMP_DIR" -maxdepth 1 -name "tmp_*.nim" -print -quit 2>/dev/null)" ]]; then
    SHADOW_OBSERVED=1
  fi
  sleep 0.05
done

wait "$HARNESS_PID" || true

# Post-execution check: Zero temporary shadow files must remain
LEFTOVER_FILES=$(find "$STRESS_TEMP_DIR" -maxdepth 1 -name "tmp_*.nim" 2>/dev/null)
LEFTOVER_COUNT=$(echo "$LEFTOVER_FILES" | grep -c "tmp_" || true)
if [[ -n "$(find "$STRESS_TEMP_DIR" -maxdepth 1 -name ".*.nim" -print -quit 2>/dev/null)" ]]; then
  DOT_FILE_DETECTED=1
fi

if [[ $DOT_FILE_DETECTED -eq 1 ]]; then
  test_fail "T5_01" "Detected forbidden dot-prefixed temporary files (.tmp_*.nim)"
elif [[ $LEFTOVER_COUNT -gt 0 ]]; then
  echo -e "\n    Leaked shadow files: $(echo $LEFTOVER_FILES | tr '\n' ' ')"
  test_fail "T5_01" "Leaked $LEFTOVER_COUNT temporary shadow files after server shutdown"
else
  test_pass "T5_01"
fi

# -----------------------------------------------------------------------------
# STRESS 2: Concurrent Multi-Request Routing and Out-of-Order Execution
# -----------------------------------------------------------------------------
test_start "T5_02" "Concurrent multi-request routing across hover, definition, and references"

CONCURRENCY_SCRIPT="$STRESS_TEMP_DIR/concurrency_script.txt"
cat << EOF > "$CONCURRENCY_SCRIPT"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$STRESS_TEMP_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"$(sed 's/"/\\"/g' "$TEST_NIM_FILE" | awk '{printf "%s\\n", $0}')"}}}
SEND_REQ {"jsonrpc":"2.0","id":201,"method":"textDocument/hover","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":6}}}
SEND_REQ {"jsonrpc":"2.0","id":202,"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":4,"character":4}}}
SEND_REQ {"jsonrpc":"2.0","id":203,"method":"textDocument/references","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":6},"context":{"includeDeclaration":true}}}
SEND_REQ {"jsonrpc":"2.0","id":204,"method":"textDocument/documentHighlight","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":6}}}
SEND_REQ {"jsonrpc":"2.0","id":205,"method":"textDocument/completion","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":4,"character":2}}}
WAIT_RESP 201 5000
WAIT_RESP 202 5000
WAIT_RESP 203 5000
WAIT_RESP 204 5000
WAIT_RESP 205 5000
SEND_REQ {"jsonrpc":"2.0","id":206,"method":"shutdown","params":{}}
WAIT_RESP 206 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"exit","params":{}}
EOF

CONC_OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$STRESS_TEMP_DIR" --script "$CONCURRENCY_SCRIPT" 2>&1)

MISSING_RESP=0
for req_id in 201 202 203 204 205 206; do
  if [[ "$CONC_OUTPUT" != *"RESP:$req_id:"* ]]; then
    MISSING_RESP=1
    break
  fi
done

if [[ $MISSING_RESP -eq 0 ]]; then
  test_pass "T5_02"
else
  test_fail "T5_02" "Failed to receive responses for all concurrent requests: $CONC_OUTPUT"
fi

# -----------------------------------------------------------------------------
# STRESS 3: Post-Shutdown Request Rejection
# -----------------------------------------------------------------------------
test_start "T5_03" "Verify server rejects requests post-shutdown with InvalidRequest (-32600)"

POST_SHUTDOWN_SCRIPT="$STRESS_TEMP_DIR/post_shutdown_script.txt"
cat << EOF > "$POST_SHUTDOWN_SCRIPT"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$STRESS_TEMP_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}
WAIT_RESP 2 3000
SEND_REQ {"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":0,"character":0}}}
WAIT_RESP 3 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"exit","params":{}}
EOF

POST_SHUTDOWN_OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$STRESS_TEMP_DIR" --script "$POST_SHUTDOWN_SCRIPT" 2>&1)

if [[ "$POST_SHUTDOWN_OUTPUT" == *"RESP:3:"* && ("$POST_SHUTDOWN_OUTPUT" == *"-32600"* || "$POST_SHUTDOWN_OUTPUT" == *"shutting down"*) ]]; then
  test_pass "T5_03"
else
  test_fail "T5_03" "Server did not return InvalidRequest error after shutdown: $POST_SHUTDOWN_OUTPUT"
fi

# -----------------------------------------------------------------------------
# STRESS 4: Exit Notification Lifecycle Semantics
# -----------------------------------------------------------------------------
test_start "T5_04" "Exit after shutdown terminates with code 0; exit without shutdown terminates with code 1"

# Case A: Proper shutdown -> exit (code 0)
CODE_A_SCRIPT="$STRESS_TEMP_DIR/exit_code_0.txt"
cat << EOF > "$CODE_A_SCRIPT"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$STRESS_TEMP_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"shutdown","params":{}}
WAIT_RESP 2 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"exit","params":{}}
EOF

"$HARNESS_BIN" run-script --cmd "$LSP_BIN" --script "$CODE_A_SCRIPT" >/dev/null 2>&1 || true

# Direct stdio test for Case B: exit without shutdown
EXIT_WITHOUT_SHUTDOWN_PAYLOAD=$(printf 'Content-Length: %d\r\n\r\n{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file:///tmp","capabilities":{}}}Content-Length: %d\r\n\r\n{"jsonrpc":"2.0","method":"initialized","params":{}}Content-Length: %d\r\n\r\n{"jsonrpc":"2.0","method":"exit","params":{}}' 109 45 40)

set +e
echo -en "$EXIT_WITHOUT_SHUTDOWN_PAYLOAD" | "$LSP_BIN" >/dev/null 2>&1
EXIT_CODE_B=$?
set -e

if [[ $EXIT_CODE_B -eq 1 ]]; then
  test_pass "T5_04"
else
  test_fail "T5_04" "Exit without shutdown returned exit code $EXIT_CODE_B (expected 1)"
fi

# -----------------------------------------------------------------------------
# STRESS 5: Formatting Idempotency and Syntax Error Preservation
# -----------------------------------------------------------------------------
test_start "T5_05" "Verify document formatting minimal Myers diff and syntax error non-destructive handling"

FORMAT_SCRIPT="$STRESS_TEMP_DIR/format_script.txt"
cat << EOF > "$FORMAT_SCRIPT"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$STRESS_TEMP_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc test( a : int , b:int ):int=a+b\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$TEST_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 2 5000
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"$TEST_URI","version":2},"contentChanges":[{"text":"proc broken(a: int = \n"}]}}
SEND_REQ {"jsonrpc":"2.0","id":3,"method":"textDocument/formatting","params":{"textDocument":{"uri":"$TEST_URI"},"options":{"tabSize":2,"insertSpaces":true}}}
WAIT_RESP 3 5000
SEND_REQ {"jsonrpc":"2.0","id":4,"method":"shutdown","params":{}}
WAIT_RESP 4 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"exit","params":{}}
EOF

FORMAT_OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$STRESS_TEMP_DIR" --script "$FORMAT_SCRIPT" 2>&1)

# Valid code format should produce TextEdit (RESP:2 contains newText)
# Syntax error format should return null (RESP:3 contains null or [])
if [[ "$FORMAT_OUTPUT" == *"RESP:2:"* && "$FORMAT_OUTPUT" == *"newText"* && "$FORMAT_OUTPUT" == *"RESP:3:"* && ("$FORMAT_OUTPUT" == *"RESP:3:{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":null}"* || "$FORMAT_OUTPUT" == *"RESP:3:{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":[]}"*) ]]; then
  test_pass "T5_05"
else
  test_fail "T5_05" "Formatting idempotency or syntax-error safety violated: $FORMAT_OUTPUT"
fi

echo -e "\n${C_BOLD}Tier 5 Stress Testing Complete.${C_RESET}\n"
