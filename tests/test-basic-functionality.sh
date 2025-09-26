#!/bin/bash
# Basic functionality test for custom-cli
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Test utilities
test_command() {
    local test_name="$1"
    local command="$2"
    local expected_content="$3"

    TEST_COUNT=$((TEST_COUNT + 1))

    echo -n "Testing $test_name... "

    if output=$(eval "$command" 2>&1); then
        if [[ "$output" == *"$expected_content"* ]]; then
            echo -e "${GREEN}✓ PASS${NC}"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo -e "${RED}✗ FAIL (wrong content)${NC}"
            echo -e "  Expected to contain: ${BLUE}$expected_content${NC}"
            echo -e "  Got: ${YELLOW}${output:0:100}...${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo -e "${RED}✗ FAIL (command failed)${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI_EXEC="$PROJECT_ROOT/bin/custom-cli"

echo -e "${BLUE}🧪 Basic Custom CLI Functionality Test${NC}"
echo -e "${BLUE}====================================${NC}"

# Test CLI executable exists
if [[ -x "$CLI_EXEC" ]]; then
    echo -e "${GREEN}✓${NC} CLI executable exists and is executable"
else
    echo -e "${RED}✗${NC} CLI executable not found or not executable: $CLI_EXEC"
    exit 1
fi

# Basic command tests
test_command "version command" "$CLI_EXEC --version" "1.0.0"
test_command "help command" "$CLI_EXEC help" "Usage:"
test_command "config debug" "$CLI_EXEC config-debug" "Configuration Debug"
test_command "test dependencies" "$CLI_EXEC test-dependencies" "Testing dependency resolution"

# Test invalid command handling
TEST_COUNT=$((TEST_COUNT + 1))
echo -n "Testing invalid command handling... "
if output=$("$CLI_EXEC" invalid-command 2>&1); then
    echo -e "${RED}✗ FAIL (should have failed)${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo -e "${GREEN}✓ PASS${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
fi

# Test configuration file exists
TEST_COUNT=$((TEST_COUNT + 1))
echo -n "Testing configuration file exists... "
if [[ -f "$PROJECT_ROOT/config.yaml" ]]; then
    echo -e "${GREEN}✓ PASS${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗ FAIL${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Test YAML syntax with yq if available
if command -v yq >/dev/null 2>&1; then
    TEST_COUNT=$((TEST_COUNT + 1))
    echo -n "Testing YAML syntax validation... "
    if yq eval 'keys' "$PROJECT_ROOT/config.yaml" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${RED}✗ FAIL${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
else
    echo -e "${YELLOW}~ Skipping YAML validation (yq not available)${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}Test Summary:${NC}"
echo -e "Tests run: ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 All basic functionality tests passed!${NC}"
    echo -e "${GREEN}✅ Custom CLI is working correctly${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}💥 $FAIL_COUNT test(s) failed${NC}"
    exit 1
fi