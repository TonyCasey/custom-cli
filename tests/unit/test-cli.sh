#!/bin/bash
# Unit tests for cli.sh module
set -euo pipefail

# Test framework setup
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

# Test counters
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test utilities
assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TEST_COUNT=$((TEST_COUNT + 1))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected: ${BLUE}$expected${NC}"
        echo -e "  Actual:   ${YELLOW}$actual${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_contains() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"

    TEST_COUNT=$((TEST_COUNT + 1))

    if [[ "$actual" == *"$expected"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected to contain: ${BLUE}$expected${NC}"
        echo -e "  Actual:              ${YELLOW}$actual${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local command="$2"
    local test_name="$3"

    TEST_COUNT=$((TEST_COUNT + 1))

    set +e
    eval "$command" >/dev/null 2>&1
    local actual_code=$?
    set -e

    if [[ $actual_code -eq $expected_code ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected exit code: ${BLUE}$expected_code${NC}"
        echo -e "  Actual exit code:   ${YELLOW}$actual_code${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_function_exists() {
    local function_name="$1"
    local test_name="$2"

    TEST_COUNT=$((TEST_COUNT + 1))

    if command -v "$function_name" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Function not found: ${BLUE}$function_name${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Load dependencies
source "$PROJECT_ROOT/lib/config.sh"
config_load_defaults >/dev/null 2>&1

# Load the CLI module
source "$PROJECT_ROOT/lib/cli.sh"

echo "Testing cli.sh module..."
echo "================================"

# Test: Module functions exist
assert_function_exists "cli_usage" "cli_usage function exists"
assert_function_exists "cli_version" "cli_version function exists"
assert_function_exists "cli_version_debug" "cli_version_debug function exists"
assert_function_exists "cli_parse_args" "cli_parse_args function exists"

# Test: Usage output contains expected elements
usage_output=$(cli_usage 2>&1)
assert_contains "Usage:" "$usage_output" "Usage text includes Usage section"
assert_contains "custom-cli" "$usage_output" "Usage text includes custom-cli name"
assert_contains "start" "$usage_output" "Usage text includes start command"
assert_contains "stop" "$usage_output" "Usage text includes stop command"
assert_contains "status" "$usage_output" "Usage text includes status command"
assert_contains "help" "$usage_output" "Usage text includes help command"

# Test: Version output
version_output=$(cli_version 2>&1)
assert_contains "1.0.0" "$version_output" "Version output includes 1.0.0"
assert_contains "custom-cli" "$version_output" "Version output includes custom-cli name"

# Test: Debug version output
debug_output=$(cli_version_debug 2>&1)
assert_contains "Version:" "$debug_output" "Debug version includes Version section"
assert_contains "System:" "$debug_output" "Debug version includes System section"
assert_contains "Configuration:" "$debug_output" "Debug version includes Configuration section"
assert_contains "1.0.0" "$debug_output" "Debug version includes version number"

# Test: Argument parsing
# Test help flag
assert_exit_code 0 "cli_parse_args --help" "Help flag exits successfully"
assert_exit_code 0 "cli_parse_args help" "Help command exits successfully"

# Test version flags
assert_exit_code 0 "cli_parse_args --version" "Version flag exits successfully"
assert_exit_code 0 "cli_parse_args version-debug" "Version debug command exits successfully"

# Test invalid arguments
assert_exit_code 1 "cli_parse_args invalid-command" "Invalid command exits with error"

# Test service validation (using known services from config.yaml)
# Note: These tests depend on the YAML configuration being valid

# Mock the orchestrator functions for testing
orchestrator_start_composite() { echo "mock start $1"; return 0; }
orchestrator_stop_composite() { echo "mock stop $1"; return 0; }
orchestrator_status_composite() { echo "mock status $1"; return 0; }

# Test valid service commands
assert_exit_code 0 "cli_parse_args start dashboard" "Start dashboard command succeeds"
assert_exit_code 0 "cli_parse_args stop dashboard" "Stop dashboard command succeeds"
assert_exit_code 0 "cli_parse_args status dashboard" "Status dashboard command succeeds"

# Test config-debug command
config_debug_output=$(cli_parse_args config-debug 2>&1)
assert_contains "Configuration Debug" "$config_debug_output" "config-debug shows debug info"

# Test logs command
logs_output=$(cli_parse_args logs 2>&1)
assert_contains "Available log files" "$logs_output" "logs command shows available logs"

# Test service validation with invalid service
assert_exit_code 1 "cli_parse_args start nonexistent-service" "Invalid service fails validation"

# Summary
echo ""
echo "================================"
echo "CLI Module Test Results:"
echo -e "Tests run: ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi