#!/bin/bash
# Unit tests for config.sh module
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

assert_not_empty() {
    local actual="$1"
    local test_name="$2"

    TEST_COUNT=$((TEST_COUNT + 1))

    if [[ -n "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected: ${BLUE}non-empty value${NC}"
        echo -e "  Actual:   ${YELLOW}empty${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_file_exists() {
    local file_path="$1"
    local test_name="$2"

    TEST_COUNT=$((TEST_COUNT + 1))

    if [[ -f "$file_path" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "  Expected file to exist: ${BLUE}$file_path${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Load the config module
source "$PROJECT_ROOT/lib/config.sh"

echo "Testing config.sh module..."
echo "================================"

# Test: config_load_defaults function exists
if command -v config_load_defaults >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} config_load_defaults function exists"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} config_load_defaults function exists"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Load default configuration
config_load_defaults >/dev/null 2>&1

# Test: CLI name is set and not empty
assert_not_empty "$CLI_NAME" "CLI_NAME is set"

# Test: REPOS_DIR is set and uses HOME
if [[ "$REPOS_DIR" == *"${HOME}"* ]]; then
    echo -e "${GREEN}✓${NC} REPOS_DIR uses HOME variable"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} REPOS_DIR uses HOME variable"
    echo -e "  REPOS_DIR: ${YELLOW}$REPOS_DIR${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: LOGS_DIR is set and not empty
assert_not_empty "$LOGS_DIR" "LOGS_DIR is set"

# Test: CONFIG_FILE points to config.yaml
if [[ "$CONFIG_FILE" == *"config.yaml" ]]; then
    echo -e "${GREEN}✓${NC} CONFIG_FILE points to config.yaml"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} CONFIG_FILE points to config.yaml"
    echo -e "  CONFIG_FILE: ${YELLOW}$CONFIG_FILE${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Configuration file exists
assert_file_exists "$CONFIG_FILE" "config.yaml file exists"

# Test: Version information
assert_not_empty "$CLI_VERSION" "CLI_VERSION is set"
assert_equals "1.0.0" "$CLI_VERSION" "CLI_VERSION is 1.0.0"

# Test: CLI executable path
if [[ "$CLI_EXECUTABLE" == *"bin/custom-cli" ]]; then
    echo -e "${GREEN}✓${NC} CLI_EXECUTABLE points to bin/custom-cli"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} CLI_EXECUTABLE points to bin/custom-cli"
    echo -e "  CLI_EXECUTABLE: ${YELLOW}$CLI_EXECUTABLE${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Debug mode handling
OLD_DEBUG="${DEBUG:-}"
export DEBUG="true"
config_load_defaults >/dev/null 2>&1
assert_equals "true" "$DEBUG" "Debug mode can be enabled"
export DEBUG="$OLD_DEBUG"

# Summary
echo ""
echo "================================"
echo "Config Module Test Results:"
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