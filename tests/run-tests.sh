#!/bin/bash
# Test runner for custom-cli
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test directories
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_TEST_DIR="$TEST_DIR/unit"
INTEGRATION_TEST_DIR="$TEST_DIR/integration"

# Counters
TOTAL_TESTS=0
TOTAL_PASSED=0
TOTAL_FAILED=0

echo -e "${BLUE}🧪 Custom CLI Test Suite${NC}"
echo -e "${BLUE}========================${NC}"

# Function to run a test file
run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)

    echo ""
    echo -e "${BLUE}Running $test_name...${NC}"
    echo "----------------------------------------"

    if [[ -x "$test_file" ]]; then
        if bash "$test_file"; then
            echo -e "${GREEN}✅ $test_name PASSED${NC}"
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
        else
            echo -e "${RED}❌ $test_name FAILED${NC}"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi
    else
        echo -e "${YELLOW}⚠️  $test_name SKIPPED (not executable)${NC}"
        chmod +x "$test_file" 2>/dev/null || true
        if bash "$test_file"; then
            echo -e "${GREEN}✅ $test_name PASSED (after chmod)${NC}"
            TOTAL_PASSED=$((TOTAL_PASSED + 1))
        else
            echo -e "${RED}❌ $test_name FAILED${NC}"
            TOTAL_FAILED=$((TOTAL_FAILED + 1))
        fi
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Make test files executable
find "$TEST_DIR" -name "test-*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

# Run unit tests
echo -e "${YELLOW}📋 Unit Tests${NC}"
echo "=============="

if [[ -d "$UNIT_TEST_DIR" ]]; then
    for test_file in "$UNIT_TEST_DIR"/test-*.sh; do
        if [[ -f "$test_file" ]]; then
            run_test_file "$test_file"
        fi
    done
else
    echo -e "${YELLOW}No unit test directory found${NC}"
fi

# Run integration tests
echo ""
echo -e "${YELLOW}🔗 Integration Tests${NC}"
echo "==================="

if [[ -d "$INTEGRATION_TEST_DIR" ]]; then
    for test_file in "$INTEGRATION_TEST_DIR"/test-*.sh; do
        if [[ -f "$test_file" ]]; then
            run_test_file "$test_file"
        fi
    done
else
    echo -e "${YELLOW}No integration test directory found${NC}"
fi

# Final summary
echo ""
echo "========================================"
echo -e "${BLUE}🎯 Test Suite Summary${NC}"
echo "========================================"
echo -e "Total tests: ${BLUE}$TOTAL_TESTS${NC}"
echo -e "Passed: ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Failed: ${RED}$TOTAL_FAILED${NC}"

if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}🎉 All tests passed successfully!${NC}"
    echo -e "${GREEN}✅ Custom CLI is ready for use${NC}"
    exit 0
else
    echo ""
    echo -e "${RED}💥 $TOTAL_FAILED test(s) failed${NC}"
    echo -e "${RED}❌ Please review the failures above${NC}"
    exit 1
fi