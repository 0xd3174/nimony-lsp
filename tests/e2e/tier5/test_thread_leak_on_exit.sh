#!/usr/bin/env bash
# Empirical reproduction: Shadow file leak when exit arrives while worker thread is active
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/../test_framework.sh"

echo -e "\n${C_BOLD}=== Testing Shadow File Leak Under Rapid Exit / In-Flight Worker Threads ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)

TEST_DIR=$(mktemp -d "/tmp/nimony_thread_leak_XXXXXX")
cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

TEST_FILE="$TEST_DIR/sample.nim"
cat << 'EOF' > "$TEST_FILE"
proc heavyWork(n: int): int =
  var s = 0
  for i in 0 .. n:
    s += i
  s

let res = heavyWork(100)
EOF

TEST_URI="file://$TEST_FILE"

# Send didOpen with modified buffer, immediately request definition, and IMMEDIATELY send shutdown and exit
SCRIPT_FILE="$TEST_DIR/rapid_exit.txt"
cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$TEST_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$TEST_URI","languageId":"nim","version":1,"text":"proc heavyWork(n: int): int =\n  var s = 0\n  for i in 0 .. n:\n    s += i\n  s\n\nlet res = heavyWork(999)\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$TEST_URI"},"position":{"line":7,"character":12}}}
SLEEP 5
SEND_REQ {"jsonrpc":"2.0","id":3,"method":"shutdown","params":{}}
WAIT_RESP 3 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"exit","params":{}}
EOF

"$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$TEST_DIR" --script "$SCRIPT_FILE" > "$TEST_DIR/out.log" 2>&1 || true

# Wait a moment for OS process to fully exit
sleep 0.5

LEAKED=$(find "$TEST_DIR" -maxdepth 1 -name "tmp_*.nim" 2>/dev/null)
LEAKED_COUNT=$(echo "$LEAKED" | grep -c "tmp_" || true)

echo "Leaked count: $LEAKED_COUNT"
if [[ $LEAKED_COUNT -gt 0 ]]; then
  echo "Leaked files: $LEAKED"
  for f in $LEAKED; do
    echo "--- File: $f ---"
    cat "$f"
  done
fi
