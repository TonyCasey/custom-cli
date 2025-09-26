#!/bin/bash
# Unit tests for yaml.sh module
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

# Load the yaml module
source "$PROJECT_ROOT/lib/yaml.sh"

echo "Testing yaml.sh module..."
echo "================================"

# Test: Module loading and functions exist
assert_function_exists "yaml_check_dependencies" "yaml_check_dependencies function exists"
assert_function_exists "yaml_load_config" "yaml_load_config function exists"
assert_function_exists "yaml_get_service_config" "yaml_get_service_config function exists"
assert_function_exists "yaml_get_service_dependencies" "yaml_get_service_dependencies function exists"
assert_function_exists "yaml_get_all_services" "yaml_get_all_services function exists"
assert_function_exists "yaml_get_composite_services" "yaml_get_composite_services function exists"
assert_function_exists "yaml_get_all_composites" "yaml_get_all_composites function exists"
assert_function_exists "yaml_get_global_config" "yaml_get_global_config function exists"

# Test: Check dependencies (yq availability)
if yaml_check_dependencies >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} yq dependency check passes"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} yq dependency check passes"
    echo -e "  yq may not be installed or accessible"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Load configuration
yaml_config=$(yaml_load_config 2>/dev/null)
if [[ -n "$yaml_config" ]]; then
    echo -e "${GREEN}✓${NC} YAML configuration loads successfully"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} YAML configuration loads successfully"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Test: Get all services
services=$(yaml_get_all_services "$yaml_config" 2>/dev/null || echo "")
assert_not_empty "$services" "Services can be retrieved from YAML"

# Expected services from config.yaml
assert_contains "firebase-emulators" "$services" "firebase-emulators service exists"
assert_contains "dashboard-api" "$services" "dashboard-api service exists"
assert_contains "dashboard-webapp" "$services" "dashboard-webapp service exists"

# Test: Get all composites
composites=$(yaml_get_all_composites "$yaml_config" 2>/dev/null || echo "")
assert_not_empty "$composites" "Composites can be retrieved from YAML"
assert_contains "dashboard" "$composites" "dashboard composite exists"
assert_contains "app" "$composites" "app composite exists"

# Test: Get composite services
dashboard_services=$(yaml_get_composite_services "dashboard" "$yaml_config" 2>/dev/null || echo "")
assert_not_empty "$dashboard_services" "Dashboard composite services can be retrieved"
assert_contains "firebase-emulators" "$dashboard_services" "Dashboard includes firebase-emulators"
assert_contains "dashboard-api" "$dashboard_services" "Dashboard includes dashboard-api"
assert_contains "dashboard-webapp" "$dashboard_services" "Dashboard includes dashboard-webapp"

# Test: Get service configuration
firebase_config=$(yaml_get_service_config "firebase-emulators" "$yaml_config" 2>/dev/null || echo "")
assert_not_empty "$firebase_config" "Firebase service config can be retrieved"
assert_contains "PORT=4000" "$firebase_config" "Firebase service has correct port"

# Test: Get service dependencies
api_deps=$(yaml_get_service_dependencies "dashboard-api" "$yaml_config" 2>/dev/null || echo "")
assert_contains "firebase-emulators" "$api_deps" "Dashboard API depends on firebase-emulators"

webapp_deps=$(yaml_get_service_dependencies "dashboard-webapp" "$yaml_config" 2>/dev/null || echo "")
assert_contains "firebase-emulators" "$webapp_deps" "Dashboard webapp depends on firebase-emulators"
assert_contains "dashboard-api" "$webapp_deps" "Dashboard webapp depends on dashboard-api"

# Test: Get global configuration
repos_dir=$(yaml_get_global_config "reposDir" "$yaml_config" 2>/dev/null || echo "")
assert_not_empty "$repos_dir" "Global reposDir can be retrieved"
assert_contains "HOME" "$repos_dir" "reposDir uses HOME variable"

cli_name=$(yaml_get_global_config "cliName" "$yaml_config" 2>/dev/null || echo "")
assert_equals "custom-cli" "$cli_name" "CLI name is custom-cli"

version=$(yaml_get_global_config "version" "$yaml_config" 2>/dev/null || echo "")
assert_equals "1.0.0" "$version" "Version is 1.0.0"

# Test: Configuration validation
if yaml_validate_config >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} YAML configuration validation passes"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗${NC} YAML configuration validation passes"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TEST_COUNT=$((TEST_COUNT + 1))

# Summary
echo ""
echo "================================"
echo "YAML Module Test Results:"
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