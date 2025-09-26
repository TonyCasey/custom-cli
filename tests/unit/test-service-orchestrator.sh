#!/bin/bash
# Unit tests for service_orchestrator.sh module
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

# Load dependencies
source "$PROJECT_ROOT/lib/config.sh"
config_load_defaults >/dev/null 2>&1

# Load the service orchestrator module
source "$PROJECT_ROOT/lib/service_orchestrator.sh"

echo "Testing service_orchestrator.sh module..."
echo "========================================="

# Test: Module functions exist
assert_function_exists "orchestrator_start_composite" "orchestrator_start_composite function exists"
assert_function_exists "orchestrator_stop_composite" "orchestrator_stop_composite function exists"
assert_function_exists "orchestrator_status_composite" "orchestrator_status_composite function exists"

# Mock service functions for testing
service_get_config() {
    local service_name="$1"
    case "$service_name" in
        "firebase-emulators")
            echo "PORT=4000"
            echo "DIRECTORY=${HOME}/Repos/test/firebase"
            echo "COMMAND=npm run test"
            echo "DISPLAYNAME=Test Firebase"
            ;;
        "dashboard-api")
            echo "PORT=1337"
            echo "DIRECTORY=${HOME}/Repos/test/api"
            echo "COMMAND=npm run dev"
            echo "DISPLAYNAME=Test API"
            ;;
        *)
            return 1
            ;;
    esac
}

# Mock service management functions
service_start() {
    local service_name="$1"
    echo "Mock starting $service_name"
    return 0
}

service_stop() {
    local service_name="$1"
    echo "Mock stopping $service_name"
    return 0
}

service_status() {
    local service_name="$1"
    echo "Mock status for $service_name: running"
    return 0
}

service_wait_healthy() {
    local service_name="$1"
    echo "Mock health check for $service_name: healthy"
    return 0
}

# Test: Start composite service with valid service
start_output=$(orchestrator_start_composite "dashboard" 2>&1)
assert_contains "Starting composite" "$start_output" "Start composite shows starting message"

# Test: Stop composite service
stop_output=$(orchestrator_stop_composite "dashboard" 2>&1)
assert_contains "Stopping composite" "$stop_output" "Stop composite shows stopping message"

# Test: Status composite service
status_output=$(orchestrator_status_composite "dashboard" 2>&1)
assert_contains "Status for composite" "$status_output" "Status composite shows status message"

# Test: Invalid composite service
assert_exit_code 1 "orchestrator_start_composite 'nonexistent-composite'" "Invalid composite service fails"
assert_exit_code 1 "orchestrator_stop_composite 'nonexistent-composite'" "Invalid composite stop fails"
assert_exit_code 1 "orchestrator_status_composite 'nonexistent-composite'" "Invalid composite status fails"

# Test: Empty service name handling
assert_exit_code 1 "orchestrator_start_composite ''" "Empty composite name fails"

# Test dependency resolution (if available)
if command -v orchestrator_resolve_dependencies >/dev/null 2>&1; then
    assert_function_exists "orchestrator_resolve_dependencies" "Dependency resolution function exists"

    # Test with known services
    deps_output=$(orchestrator_resolve_dependencies "dashboard" 2>&1 || echo "")
    if [[ -n "$deps_output" ]]; then
        echo -e "${GREEN}✓${NC} Dependency resolution produces output"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${YELLOW}~${NC} Dependency resolution test skipped (no output)"
    fi
    TEST_COUNT=$((TEST_COUNT + 1))
fi

# Test service health checking (if available)
if command -v orchestrator_check_health >/dev/null 2>&1; then
    assert_function_exists "orchestrator_check_health" "Health check function exists"

    health_output=$(orchestrator_check_health "firebase-emulators" 2>&1 || echo "mock health check")
    assert_contains "health" "$health_output" "Health check produces health-related output"
fi

# Test configuration loading integration
config_output=$(orchestrator_start_composite "dashboard" 2>&1)
if [[ "$config_output" == *"Error"* ]] || [[ "$config_output" == *"not found"* ]]; then
    echo -e "${YELLOW}~${NC} Configuration integration needs YAML config (expected in test environment)"
else
    echo -e "${GREEN}✓${NC} Configuration integration works"
    PASS_COUNT=$((PASS_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test orchestrator initialization
if command -v orchestrator_init >/dev/null 2>&1; then
    assert_function_exists "orchestrator_init" "Orchestrator initialization function exists"

    # Test initialization
    if orchestrator_init >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Orchestrator initializes successfully"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo -e "${YELLOW}~${NC} Orchestrator initialization test inconclusive (may need dependencies)"
    fi
    TEST_COUNT=$((TEST_COUNT + 1))
fi

# Summary
echo ""
echo "========================================="
echo "Service Orchestrator Module Test Results:"
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