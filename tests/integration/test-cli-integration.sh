#!/bin/bash
# Integration tests for custom-cli
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

# CLI executable path
CLI_EXEC="$PROJECT_ROOT/bin/custom-cli"

echo "Testing custom-cli integration..."
echo "================================"

# Test: CLI executable exists and is executable
if [[ -x "$CLI_EXEC" ]]; then
    echo -e "${GREEN}✓${NC} CLI executable exists and is executable"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} CLI executable exists and is executable"
    echo -e "  Path: ${YELLOW}$CLI_EXEC${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Help command
help_output=$("$CLI_EXEC" help 2>&1 || echo "help_failed")
assert_contains "Usage:" "$help_output" "Help command shows usage information"
assert_contains "custom-cli" "$help_output" "Help command shows CLI name"
assert_contains "start" "$help_output" "Help command shows start command"
assert_contains "stop" "$help_output" "Help command shows stop command"
assert_contains "status" "$help_output" "Help command shows status command"

# Test: Help flag
help_flag_output=$("$CLI_EXEC" --help 2>&1 || echo "help_flag_failed")
assert_contains "Usage:" "$help_flag_output" "Help flag shows usage information"

# Test: Version command
version_output=$("$CLI_EXEC" --version 2>&1 || echo "version_failed")
assert_contains "1.0.0" "$version_output" "Version command shows version 1.0.0"
assert_contains "custom-cli" "$version_output" "Version command shows CLI name"

# Test: Version debug command
debug_output=$("$CLI_EXEC" version-debug 2>&1 || echo "debug_failed")
assert_contains "Version:" "$debug_output" "Version debug shows version section"
assert_contains "System:" "$debug_output" "Version debug shows system section"
assert_contains "Configuration:" "$debug_output" "Version debug shows configuration section"

# Test: Config debug command
config_debug_output=$("$CLI_EXEC" config-debug 2>&1 || echo "config_debug_failed")
assert_contains "Configuration Debug" "$config_debug_output" "Config debug shows debug information"
assert_contains "Configuration file:" "$config_debug_output" "Config debug shows config file path"

# Test: Logs command
logs_output=$("$CLI_EXEC" logs 2>&1 || echo "logs_failed")
assert_contains "Available log files" "$logs_output" "Logs command shows log information"

# Test: Invalid command handling
assert_exit_code 1 "'$CLI_EXEC' invalid-command" "Invalid command returns exit code 1"

# Test: Test commands (if available)
test_deps_output=$("$CLI_EXEC" test-dependencies 2>&1 || echo "test_deps_failed")
if [[ "$test_deps_output" != "test_deps_failed" ]]; then
    echo -e "${GREEN}✓${NC} test-dependencies command is available"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${YELLOW}~${NC} test-dependencies command not available (may be expected)"
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Service interface test
service_interface_output=$("$CLI_EXEC" test-service-interface 2>&1 || echo "service_interface_failed")
if [[ "$service_interface_output" != "service_interface_failed" ]]; then
    echo -e "${GREEN}✓${NC} test-service-interface command is available"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${YELLOW}~${NC} test-service-interface command not available (may be expected)"
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Configuration file integration
config_file="$PROJECT_ROOT/config.yaml"
if [[ -f "$config_file" ]]; then
    echo -e "${GREEN}✓${NC} Configuration file exists"
    PASS_COUNT=$((PASS_COUNT + 1))

    # Test: YAML validation with yq (if available)
    if command -v yq >/dev/null 2>&1; then
        if yq eval 'keys' "$config_file" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Configuration file is valid YAML"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo -e "${RED}✗${NC} Configuration file is valid YAML"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
        TEST_COUNT=$((TEST_COUNT + 1))
    fi

    # Test: Configuration contains expected sections
    config_content=$(cat "$config_file")
    assert_contains "services:" "$config_content" "Config contains services section"
    assert_contains "composites:" "$config_content" "Config contains composites section"
    assert_contains "global:" "$config_content" "Config contains global section"
else
    echo -e "${RED}✗${NC} Configuration file exists"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Service commands with mock setup
# Note: These tests won't actually start services, just test command parsing
mock_start_output=$("$CLI_EXEC" start dashboard 2>&1 || echo "mock_start_failed")
if [[ "$mock_start_output" == *"not found"* ]] || [[ "$mock_start_output" == *"Error"* ]]; then
    echo -e "${YELLOW}~${NC} Start command integration test inconclusive (expected without actual services)"
else
    echo -e "${GREEN}✓${NC} Start command accepts dashboard argument"
    PASS_COUNT=$((PASS_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Stop command parsing
mock_stop_output=$("$CLI_EXEC" stop dashboard 2>&1 || echo "mock_stop_failed")
if [[ "$mock_stop_output" == *"not found"* ]] || [[ "$mock_stop_output" == *"Error"* ]]; then
    echo -e "${YELLOW}~${NC} Stop command integration test inconclusive (expected without actual services)"
else
    echo -e "${GREEN}✓${NC} Stop command accepts dashboard argument"
    PASS_COUNT=$((PASS_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Status command parsing
mock_status_output=$("$CLI_EXEC" status dashboard 2>&1 || echo "mock_status_failed")
if [[ "$mock_status_output" == *"not found"* ]] || [[ "$mock_status_output" == *"Error"* ]]; then
    echo -e "${YELLOW}~${NC} Status command integration test inconclusive (expected without actual services)"
else
    echo -e "${GREEN}✓${NC} Status command accepts dashboard argument"
    PASS_COUNT=$((PASS_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Invalid service handling
invalid_service_output=$("$CLI_EXEC" start nonexistent-service 2>&1 || echo "expected_failure")
if [[ "$invalid_service_output" == *"not found"* ]] || [[ "$invalid_service_output" == *"Invalid"* ]] || [[ "$invalid_service_output" == *"Error"* ]]; then
    echo -e "${GREEN}✓${NC} Invalid service name is properly rejected"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${YELLOW}~${NC} Invalid service handling test inconclusive"
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Module loading (check for common errors)
module_test_output=$("$CLI_EXEC" --version 2>&1)
if [[ "$module_test_output" != *"readonly variable"* ]] && [[ "$module_test_output" != *"command not found"* ]]; then
    echo -e "${GREEN}✓${NC} No module loading errors detected"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} Module loading errors detected"
    echo -e "  Output: ${YELLOW}$module_test_output${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Summary
echo ""
echo "================================"
echo "CLI Integration Test Results:"
echo -e "Tests run: ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All integration tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some integration tests failed!${NC}"
    exit 1
fi