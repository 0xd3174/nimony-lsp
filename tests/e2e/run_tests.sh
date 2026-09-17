#!/usr/bin/env bash
# Master E2E Test Runner for nimony-lsp
# Runs the complete, opaque-box, requirement-driven 4-tier E2E test suite

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Mandatory NixOS check: Ensure running inside Nix environment if flake.nix exists
if [[ -z "${IN_NIX_SHELL:-}" && -f "$WORKSPACE_ROOT/flake.nix" ]]; then
  if command -v nix >/dev/null 2>&1; then
    echo -e "\033[34m[INFO]\033[0m Entering Nix development shell via 'nix develop -c'..."
    exec nix develop "$WORKSPACE_ROOT" -c "$0" "$@"
  fi
fi

# Source test framework
source "$SCRIPT_DIR/test_framework.sh"

# Ensure test client harness is compiled
ensure_lsp_harness

TIER_SELECTION="ALL"
FEATURE_SELECTION=""
LIST_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)
      TIER_SELECTION="$2"
      shift 2
      ;;
    --feature)
      FEATURE_SELECTION="$2"
      shift 2
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --tier <1|2|3|4|ALL>    Run specific tier (default: ALL)"
      echo "  --feature <F01..F18>    Run specific feature tests"
      echo "  --list                  List all test cases without running"
      echo "  --help, -h              Display this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ $LIST_ONLY -eq 1 ]]; then
  echo -e "${C_BOLD}Nimony LSP E2E Test Suite - Test Inventory (94 Total Tests)${C_RESET}"
  echo ""
  echo "Tier 1: Feature Coverage (54 tests)"
  echo "  - F01/F02: Environment & Compiler Availability (6 tests)"
  echo "  - F04/F05: JSON-RPC Transport & Coordinates (7 tests)"
  echo "  - F06/F07: Live & Save Diagnostics (6 tests)"
  echo "  - F08: Go to Definition (5 tests)"
  echo "  - F09: Find References (5 tests)"
  echo "  - F10: Hover Information (5 tests)"
  echo "  - F11: Document Highlight (5 tests)"
  echo "  - F12: Completion Engine (5 tests)"
  echo "  - F13: Document Formatting (5 tests)"
  echo "  - F14-F18: Zed Extension & WASM Compilation (5 tests)"
  echo ""
  echo "Tier 2: Boundary & Corner Cases (25 tests)"
  echo "  - Empty & Minimal Files (5 tests)"
  echo "  - Unicode & Astral Characters (5 tests)"
  echo "  - Malformed JSON-RPC Requests (5 tests)"
  echo "  - Non-Existent Symbols (5 tests)"
  echo "  - Syntax Error Recovery & Lifecycle (5 tests)"
  echo ""
  echo "Tier 3: Cross-Feature Combinations (8 tests)"
  echo "  - didChange Dirty Edit -> Definition (2 tests)"
  echo "  - didChange Dirty Edit -> Completion (2 tests)"
  echo "  - Format -> Diagnostic Re-Evaluation (2 tests)"
  echo "  - Save -> Clear Diagnostics (2 tests)"
  echo ""
  echo "Tier 4: Real-World Scenarios (7 tests)"
  echo "  - Multi-File Nim Project Editing (3 tests)"
  echo "  - Generic Math Module Compilation (2 tests)"
  echo "  - Complex Refactoring & AST Formatting (2 tests)"
  exit 0
fi

START_TIME=$(date +%s)

echo -e "${C_BOLD}======================================================${C_RESET}"
echo -e "${C_BOLD}        nimony-lsp E2E Test Suite Execution           ${C_RESET}"
echo -e "${C_BOLD}======================================================${C_RESET}"
echo -e "  Workspace:  $WORKSPACE_ROOT"
echo -e "  Tier Mode:  $TIER_SELECTION"
if [[ -n "$FEATURE_SELECTION" ]]; then
  echo -e "  Feature:    $FEATURE_SELECTION"
fi
LSP_PATH=$(get_lsp_binary || echo "not compiled")
echo -e "  LSP Binary: $LSP_PATH"
echo -e "${C_BOLD}------------------------------------------------------${C_RESET}"

# Execute selected suites
run_suite() {
  local script="$1"
  if [[ -f "$script" ]]; then
    # shellcheck disable=SC1090
    source "$script"
  fi
}

if [[ "$TIER_SELECTION" == "1" || "$TIER_SELECTION" == "ALL" ]]; then
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" =~ ^(F01|F02)$ ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f01_f02_environment.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" =~ ^(F04|F05)$ ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f04_f05_transport_coords.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" =~ ^(F06|F07)$ ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f06_f07_diagnostics.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" == "F08" ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f08_definition.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" == "F09" ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f09_references.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" == "F10" ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f10_hover.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" == "F11" ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f11_document_highlight.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" == "F12" ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f12_completion.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" == "F13" ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f13_formatting.sh"
  fi
  if [[ -z "$FEATURE_SELECTION" || "$FEATURE_SELECTION" =~ ^(F14|F15|F16|F17|F18)$ ]]; then
    run_suite "$SCRIPT_DIR/tier1/test_f14_f18_zed_extension.sh"
  fi
fi

if [[ -z "$FEATURE_SELECTION" ]]; then
  if [[ "$TIER_SELECTION" == "2" || "$TIER_SELECTION" == "ALL" ]]; then
    run_suite "$SCRIPT_DIR/tier2/test_empty_files.sh"
    run_suite "$SCRIPT_DIR/tier2/test_unicode_astral.sh"
    run_suite "$SCRIPT_DIR/tier2/test_malformed_rpc.sh"
    run_suite "$SCRIPT_DIR/tier2/test_nonexistent_symbols.sh"
    run_suite "$SCRIPT_DIR/tier2/test_syntax_recovery.sh"
  fi

  if [[ "$TIER_SELECTION" == "3" || "$TIER_SELECTION" == "ALL" ]]; then
    run_suite "$SCRIPT_DIR/tier3/test_dirty_edit_definition.sh"
    run_suite "$SCRIPT_DIR/tier3/test_dirty_edit_completion.sh"
    run_suite "$SCRIPT_DIR/tier3/test_format_diagnostic.sh"
    run_suite "$SCRIPT_DIR/tier3/test_save_clear_diagnostics.sh"
  fi

  if [[ "$TIER_SELECTION" == "4" || "$TIER_SELECTION" == "ALL" ]]; then
    run_suite "$SCRIPT_DIR/tier4/test_multifile_project.sh"
    run_suite "$SCRIPT_DIR/tier4/test_generic_math_module.sh"
    run_suite "$SCRIPT_DIR/tier4/test_refactoring_scenario.sh"
  fi
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "  Execution completed in ${DURATION}s."
print_summary
EXIT_CODE=$?
exit $EXIT_CODE
