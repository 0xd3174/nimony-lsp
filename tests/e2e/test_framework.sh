#!/usr/bin/env bash
# E2E Test Framework for nimony-lsp
# Authoritative framework supporting Tiers 1-4

set -o pipefail

# ANSI color definitions
C_RED="\033[31m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_MAGENTA="\033[35m"
C_CYAN="\033[36m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

# Test counters (initialized once)
if [[ -z "${_TEST_FRAMEWORK_LOADED:-}" ]]; then
  _TEST_FRAMEWORK_LOADED=1
  TESTS_TOTAL=0
  TESTS_PASSED=0
  TESTS_FAILED=0
  TESTS_SKIPPED=0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_DIR="$SCRIPT_DIR/harness"
HARNESS_BIN="$HARNESS_DIR/lsp_client"

# Logging helpers
log_info() {
  echo -e "${C_BLUE}[INFO]${C_RESET} $*"
}

log_pass() {
  echo -e "${C_GREEN}[PASS]${C_RESET} $*"
}

log_fail() {
  echo -e "${C_RED}[FAIL]${C_RESET} $*"
}

log_skip() {
  echo -e "${C_YELLOW}[SKIP]${C_RESET} $*"
}

# Test lifecycle hooks
test_start() {
  local id="$1"
  local desc="$2"
  ((TESTS_TOTAL++))
  echo -ne "  ${C_BOLD}${id}${C_RESET}: ${desc} ... "
}

test_pass() {
  local id="$1"
  ((TESTS_PASSED++))
  echo -e "${C_GREEN}PASS${C_RESET}"
}

test_fail() {
  local id="$1"
  local reason="$2"
  ((TESTS_FAILED++))
  echo -e "${C_RED}FAIL${C_RESET}"
  if [[ -n "$reason" ]]; then
    echo -e "    ${C_RED}Reason:${C_RESET} ${reason}"
  fi
}

test_skip() {
  local id="$1"
  local reason="$2"
  ((TESTS_SKIPPED++))
  echo -e "${C_YELLOW}SKIP${C_RESET} (${reason})"
}

# Assertions
assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-"Values do not match"}"
  if [[ "$expected" != "$actual" ]]; then
    echo "Expected: '$expected', Got: '$actual' ($msg)"
    return 1
  fi
  return 0
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-"Substring not found"}"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "Expected substring '$needle' not found in: '$haystack' ($msg)"
    return 1
  fi
  return 0
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-"Substring unexpectedly found"}"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "Unexpected substring '$needle' found in: '$haystack' ($msg)"
    return 1
  fi
  return 0
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-"Exit code mismatch"}"
  if [[ "$expected" -ne "$actual" ]]; then
    echo "Expected exit code $expected, but got $actual ($msg)"
    return 1
  fi
  return 0
}

assert_file_exists() {
  local file="$1"
  local msg="${2:-"File does not exist"}"
  if [[ ! -f "$file" ]]; then
    echo "File '$file' does not exist ($msg)"
    return 1
  fi
  return 0
}

assert_dir_exists() {
  local dir="$1"
  local msg="${2:-"Directory does not exist"}"
  if [[ ! -d "$dir" ]]; then
    echo "Directory '$dir' does not exist ($msg)"
    return 1
  fi
  return 0
}

# Ensure harness is compiled
ensure_lsp_harness() {
  if [[ ! -x "$HARNESS_BIN" ]]; then
    if command -v rustc >/dev/null 2>&1; then
      rustc -D warnings "$HARNESS_DIR/lsp_client.rs" -o "$HARNESS_BIN" 2>/dev/null
    elif command -v nix >/dev/null 2>&1; then
      nix shell nixpkgs#rustc nixpkgs#gcc -c rustc -D warnings "$HARNESS_DIR/lsp_client.rs" -o "$HARNESS_BIN" 2>/dev/null
    fi
  fi

  if [[ ! -x "$HARNESS_BIN" ]]; then
    return 1
  fi
  return 0
}

# Locate nimony-lsp server binary
get_lsp_binary() {
  if [[ -n "${NIMONY_LSP_BIN:-}" && -x "$NIMONY_LSP_BIN" ]]; then
    echo "$NIMONY_LSP_BIN"
    return 0
  fi

  if [[ -x "$WORKSPACE_ROOT/target/debug/nimony-lsp" ]]; then
    echo "$WORKSPACE_ROOT/target/debug/nimony-lsp"
    return 0
  fi

  if [[ -x "$WORKSPACE_ROOT/target/release/nimony-lsp" ]]; then
    echo "$WORKSPACE_ROOT/target/release/nimony-lsp"
    return 0
  fi

  if command -v nimony-lsp >/dev/null 2>&1; then
    command -v nimony-lsp
    return 0
  fi

  return 1
}

# Locate nimony compiler binary
get_nimony_binary() {
  if command -v nimony >/dev/null 2>&1; then
    command -v nimony
    return 0
  fi

  # Check Nix store if built previously
  local store_nimony
  store_nimony=$(find /nix/store -maxdepth 3 -name "nimony" -type f -executable 2>/dev/null | grep -E "nimony-[0-9].*/bin/nimony" | head -n 1)
  if [[ -n "$store_nimony" && -x "$store_nimony" ]]; then
    echo "$store_nimony"
    return 0
  fi

  return 1
}

# Locate nimpretty binary
get_nimpretty_binary() {
  if command -v nimpretty >/dev/null 2>&1; then
    command -v nimpretty
    return 0
  fi

  local store_nimpretty
  store_nimpretty=$(find /nix/store -maxdepth 3 -name "nimpretty" -type f -executable 2>/dev/null | head -n 1)
  if [[ -n "$store_nimpretty" && -x "$store_nimpretty" ]]; then
    echo "$store_nimpretty"
    return 0
  fi

  return 1
}

# Print summary box
print_summary() {
  echo ""
  echo -e "${C_BOLD}======================================================${C_RESET}"
  echo -e "${C_BOLD}                   E2E TEST SUMMARY                   ${C_RESET}"
  echo -e "${C_BOLD}======================================================${C_RESET}"
  echo -e "  Total Tests:   ${C_BOLD}${TESTS_TOTAL}${C_RESET}"
  echo -e "  Passed:        ${C_GREEN}${TESTS_PASSED}${C_RESET}"
  echo -e "  Failed:        ${C_RED}${TESTS_FAILED}${C_RESET}"
  echo -e "  Skipped:       ${C_YELLOW}${TESTS_SKIPPED}${C_RESET}"
  echo -e "${C_BOLD}======================================================${C_RESET}"
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${C_GREEN}${C_BOLD}STATUS: ALL ACTIVE TESTS PASSED${C_RESET}"
    return 0
  else
    echo -e "${C_RED}${C_BOLD}STATUS: TEST FAILURES DETECTED${C_RESET}"
    return 1
  fi
}
