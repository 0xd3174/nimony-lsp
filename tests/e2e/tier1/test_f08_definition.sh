#!/usr/bin/env bash
# Tier 1 - F08: Go to Definition
# Authoritative tests derived from ORIGINAL_REQUEST.md §R2, PROJECT.md §F08

source "$(dirname "${BASH_SOURCE[0]}")/../test_framework.sh"

echo -e "\n${C_BOLD}=== Running Tier 1: F08 Go to Definition ===${C_RESET}"

ensure_lsp_harness
LSP_BIN=$(get_lsp_binary)
FIXTURE_DIR="$WORKSPACE_ROOT/tests/e2e/fixtures/basic_project"
MAIN_PATH="$FIXTURE_DIR/main.nim"
MAIN_URI="file://$MAIN_PATH"

# Test 1: Definition on proc call jumps to proc declaration
test_start "T1_F08_01" "Go to Definition on proc call site jumps to proc definition"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F08_01" "nimony-lsp binary not found"
else
  # In main.nim:
  # line 13 (0-based 12): let msg = greet(admin) -> greet is at col 10
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"import utils\ntype User = object\n  name: string\nproc greet(u: User): string = u.name\nlet admin = User(name: \"A\")\nlet msg = greet(admin)\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":5,"character":10}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  # Proc greet is defined at line 3 (0-based)
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"\"line\":3"* || "$OUTPUT" == *"main.nim"* || "$OUTPUT" == *"uri"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F08_01"
  else
    test_fail "T1_F08_01" "Definition on proc call failed: $OUTPUT"
  fi
fi

# Test 2: Definition on local variable jumps to let/var declaration
test_start "T1_F08_02" "Go to Definition on variable use jumps to variable declaration"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F08_02" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"let count = 42\nlet nextCount = count + 1\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":1,"character":17}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"\"line\":0"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F08_02"
  else
    test_fail "T1_F08_02" "Definition on variable failed: $OUTPUT"
  fi
fi

# Test 3: Definition on custom type usage jumps to type declaration
test_start "T1_F08_03" "Go to Definition on type usage jumps to type definition"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F08_03" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"type Config = object\n  port: int\nlet c: Config = Config(port: 80)\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":2,"character":8}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"\"line\":0"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F08_03"
  else
    test_fail "T1_F08_03" "Definition on type failed: $OUTPUT"
  fi
fi

# Test 4: Definition on parameter inside proc body jumps to param definition
test_start "T1_F08_04" "Go to Definition on parameter inside proc body jumps to param"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F08_04" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"proc multiply(deltaVal: int): int =\n  deltaVal * 2\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":1,"character":3}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"\"line\":0"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F08_04"
  else
    test_fail "T1_F08_04" "Definition on param failed: $OUTPUT"
  fi
fi

# Test 5: Definition on imported symbol jumps to imported module file
test_start "T1_F08_05" "Go to Definition on imported symbol jumps to external file"
if [[ -z "$LSP_BIN" ]]; then
  test_fail "T1_F08_05" "nimony-lsp binary not found"
else
  SCRIPT_FILE=$(mktemp)
  cat << EOF > "$SCRIPT_FILE"
SEND_REQ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":1,"rootUri":"file://$FIXTURE_DIR","capabilities":{}}}
WAIT_RESP 1 3000
SEND_NOTIF {"jsonrpc":"2.0","method":"initialized","params":{}}
SEND_NOTIF {"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"$MAIN_URI","languageId":"nim","version":1,"text":"import utils\nlet res = add(1, 2)\n"}}}
SEND_REQ {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"$MAIN_URI"},"position":{"line":1,"character":11}}}
WAIT_RESP 2 5000
EOF
  OUTPUT=$("$HARNESS_BIN" run-script --cmd "$LSP_BIN" --cwd "$FIXTURE_DIR" --script "$SCRIPT_FILE" 2>&1)
  rm -f "$SCRIPT_FILE"
  if [[ "$OUTPUT" == *"RESP:2:"* && ("$OUTPUT" == *"utils.nim"* || "$OUTPUT" == *"range"*) ]]; then
    test_pass "T1_F08_05"
  else
    test_fail "T1_F08_05" "Definition across imported module failed: $OUTPUT"
  fi
fi
