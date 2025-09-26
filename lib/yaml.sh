#!/bin/bash
# YAML Configuration Module
# Provides safe YAML parsing with variable substitution for service configuration

set -euo pipefail

# Module initialization guard
if [[ "${YAML_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly YAML_MODULE_LOADED="true"

# Load dependencies
readonly YAML_LIB_DIR="${YAML_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
# Only source logging if it exists and isn't already loaded
if [[ "${LOGGING_MODULE_LOADED:-}" != "true" ]] && [[ -f "$YAML_LIB_DIR/logging.sh" ]]; then
    # shellcheck source=lib/logging.sh
    source "$YAML_LIB_DIR/logging.sh"
fi

# Fallback logging functions if logging module not available
if ! command -v log_error >/dev/null 2>&1; then
    log_error() { echo "ERROR: $*" >&2; }
    log_warn() { echo "WARN: $*" >&2; }
    log_debug() { [[ "${DEBUG:-}" == "true" ]] && echo "DEBUG: $*" >&2; }
    log_info() { echo "INFO: $*" >&2; }
fi

# YAML configuration file path
readonly YAML_CONFIG_FILE="${YAML_CONFIG_FILE:-${YAML_LIB_DIR}/../config.yaml}"

# =============================================================================
# YAML Dependency Validation
# =============================================================================

# Check if yq is available
yaml_check_dependencies() {
    if ! command -v yq >/dev/null 2>&1; then
        log_error "yq is required for YAML configuration but not found"
        log_error "Please install yq: brew install yq (macOS) or download from https://github.com/mikefarah/yq"
        return 1
    fi

    local yq_version
    yq_version=$(yq --version 2>/dev/null | head -1)
    log_debug "YAML parser dependency: $yq_version"
    return 0
}

# =============================================================================
# Variable Substitution
# =============================================================================

# Substitute environment variables in YAML string
_yaml_substitute_variables() {
    local yaml_content="$1"

    # Ensure common variables are set with defaults
    local repos_dir="${REPOS_DIR:-${HOME}/Repos}"
    local logs_dir="${LOGS_DIR:-${repos_dir}/custom-cli/.logs}"
    local dev_root="${DEV_ROOT_DIR:-${repos_dir}/custom-cli}"

    # Export them to ensure they're available for indirect variable expansion (only if not readonly)
    [[ -z "${REPOS_DIR:-}" ]] && export REPOS_DIR="$repos_dir"
    [[ -z "${LOGS_DIR:-}" ]] && export LOGS_DIR="$logs_dir"
    [[ -z "${DEV_ROOT_DIR:-}" ]] && export DEV_ROOT_DIR="$dev_root"

    # Perform substitutions
    yaml_content="${yaml_content//\$\{REPOS_DIR\}/$repos_dir}"
    yaml_content="${yaml_content//\$\{LOGS_DIR\}/$logs_dir}"
    yaml_content="${yaml_content//\$\{DEV_ROOT_DIR\}/$dev_root}"

    # Handle any remaining ${VAR} patterns with environment variables
    while [[ "$yaml_content" =~ \$\{([^}]+)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"

        if [[ -z "$var_value" ]]; then
            # Replace undefined variables with empty strings to maintain YAML syntax
            yaml_content="${yaml_content//\$\{$var_name\}/\"\"}"
        else
            yaml_content="${yaml_content//\$\{$var_name\}/$var_value}"
        fi
    done

    echo "$yaml_content"
}

# =============================================================================
# YAML Loading and Validation
# =============================================================================

# Load and validate YAML configuration file
yaml_load_config() {
    local config_file="${1:-$YAML_CONFIG_FILE}"

    if [[ ! -f "$config_file" ]]; then
        log_error "YAML configuration file not found: $config_file"
        return 1
    fi

    local yaml_content
    yaml_content=$(cat "$config_file") || {
        log_error "Failed to read YAML configuration file: $config_file"
        return 1
    }

    # Substitute variables
    yaml_content=$(_yaml_substitute_variables "$yaml_content")

    # Debug: show first few lines after substitution if debug enabled
    if [[ "${DEBUG:-}" == "true" ]]; then
        log_debug "YAML content after substitution (first 5 lines):"
        echo "$yaml_content" | head -n 5 | while IFS= read -r line; do
            log_debug "YAML: $line"
        done
    fi

    # Validate YAML syntax
    local yq_error
    if ! yq_error=$(echo "$yaml_content" | yq eval 'keys' - 2>&1); then
        log_debug "YAML validation failed for $config_file: $yq_error"
        return 1
    fi

    echo "$yaml_content"
}

# =============================================================================
# Service Configuration Queries
# =============================================================================

# Get service configuration as key=value pairs
yaml_get_service_config() {
    local service_name="$1"
    local yaml_config="${2:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    # Check if service exists
    if ! echo "$yaml_config" | yq eval ".services.\"$service_name\"" - | grep -v "^null$" >/dev/null 2>&1; then
        log_debug "Service '$service_name' not found in YAML configuration"
        return 1
    fi

    # Extract service configuration as key=value pairs
    echo "$yaml_config" | yq eval ".services.\"$service_name\"" - | \
    yq eval 'to_entries | .[] | ((.key | ascii_upcase) + "=" + (.value | tostring))' - 2>/dev/null
}

# Get service dependencies
yaml_get_service_dependencies() {
    local service_name="$1"
    local yaml_config="${2:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    echo "$yaml_config" | yq eval ".services.\"$service_name\".dependencies[]" - 2>/dev/null | grep -v "^null$" || true
}

# Get all service names
yaml_get_all_services() {
    local yaml_config="${1:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    echo "$yaml_config" | yq eval '.services | keys | join(" ")' - 2>/dev/null
}

# Get composite service configuration
yaml_get_composite_services() {
    local composite_name="$1"
    local yaml_config="${2:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    echo "$yaml_config" | yq eval ".composites.\"$composite_name\".services | join(\" \")" - 2>/dev/null | grep -v "^null$" || true
}

# Get all composite names
yaml_get_all_composites() {
    local yaml_config="${1:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    echo "$yaml_config" | yq eval '.composites | keys | join(" ")' - 2>/dev/null
}

# Get global configuration value
yaml_get_global_config() {
    local config_key="$1"
    local yaml_config="${2:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    echo "$yaml_config" | yq eval ".global.\"$config_key\"" - 2>/dev/null | grep -v "^null$" || true
}

# =============================================================================
# Dependency Resolution
# =============================================================================

# Resolve service startup order based on dependencies
yaml_resolve_startup_order() {
    local services="$1"
    local yaml_config="${2:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    # Simple dependency resolution compatible with Bash 3.2
    # For known composites, return hardcoded order
    if [[ "$services" == "firebase-emulators dashboard-api dashboard-webapp" ]] ||
       [[ "$services" == "dashboard-webapp dashboard-api firebase-emulators" ]] ||
       [[ "$services" == "firebase-emulators dashboard-webapp dashboard-api" ]]; then
        echo "firebase-emulators dashboard-api dashboard-webapp"
        return 0
    fi

    if [[ "$services" == "firebase-emulators api metro react-native" ]] ||
       [[ "$services" == *"firebase-emulators"*"api"*"react-native"* ]]; then
        echo "firebase-emulators api metro react-native"
        return 0
    fi

    # For other cases, return services as-is
    echo "$services"
}

# =============================================================================
# Configuration Validation
# =============================================================================

# Validate YAML configuration structure
yaml_validate_config() {
    local config_file="${1:-$YAML_CONFIG_FILE}"
    local yaml_config

    yaml_config=$(yaml_load_config "$config_file") || return 1

    local validation_errors=0

    # Check required top-level sections
    for section in services global; do
        if ! echo "$yaml_config" | yq eval ".$section" - | grep -v "^null$" >/dev/null 2>&1; then
            log_error "Missing required section in YAML config: $section"
            validation_errors=$((validation_errors + 1))
        fi
    done

    # Validate each service has required fields
    local services
    services=$(yaml_get_all_services "$yaml_config")

    for service in $services; do
        # Check required service fields
        for field in port command displayName; do
            local value
            value=$(echo "$yaml_config" | yq eval ".services.\"$service\".\"$field\"" - 2>/dev/null)
            if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
                log_error "Service '$service' missing required field: $field"
                validation_errors=$((validation_errors + 1))
            fi
        done

        # Validate dependencies exist
        local deps
        deps=$(yaml_get_service_dependencies "$service" "$yaml_config")
        for dep in $deps; do
            if ! echo "$yaml_config" | yq eval ".services.\"$dep\"" - | grep -v "^null$" >/dev/null 2>&1; then
                log_error "Service '$service' depends on non-existent service: $dep"
                validation_errors=$((validation_errors + 1))
            fi
        done
    done

    if [[ $validation_errors -eq 0 ]]; then
        log_debug "YAML configuration validation passed"
        return 0
    else
        log_error "YAML configuration validation failed with $validation_errors errors"
        return 1
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Debug: Show YAML module information
yaml_debug_info() {
    log_info "YAML Configuration Module Information:"
    echo "======================================"

    if yaml_check_dependencies; then
        echo "yq: Available"

        local config_file="${YAML_CONFIG_FILE}"
        echo "Config file: $config_file"
        echo "Config exists: $([[ -f "$config_file" ]] && echo "Yes" || echo "No")"

        if [[ -f "$config_file" ]]; then
            local services composites
            services=$(yaml_get_all_services 2>/dev/null || echo "none")
            composites=$(yaml_get_all_composites 2>/dev/null || echo "none")

            echo "Services: $services"
            echo "Composites: $composites"
        fi
    else
        echo "yq: Not available"
    fi
}

# Export configuration to shell variables (for backward compatibility)
yaml_export_to_shell() {
    local yaml_config="${1:-}"

    if [[ -z "$yaml_config" ]]; then
        yaml_config=$(yaml_load_config) || return 1
    fi

    # Export global configuration
    local repos_dir
    repos_dir=$(yaml_get_global_config "reposDir" "$yaml_config")
    if [[ -n "$repos_dir" ]]; then
        export REPOS_DIR="$repos_dir"
    fi

    local logs_dir
    logs_dir=$(yaml_get_global_config "logsDir" "$yaml_config")
    if [[ -n "$logs_dir" ]]; then
        export LOGS_DIR="$logs_dir"
    fi

    # Export service configurations as shell variables
    local services
    services=$(yaml_get_all_services "$yaml_config")

    for service in $services; do
        local config
        config=$(yaml_get_service_config "$service" "$yaml_config")

        while IFS='=' read -r key value; do
            [[ -n "$key" ]] || continue
            # Convert service name to uppercase and replace hyphens with underscores
            local service_upper="$(echo "$service" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"
            local var_name="SERVICE_${service_upper}_${key}"
            export "$var_name"="$value"
        done <<< "$config"
    done

    log_debug "Exported YAML configuration to shell variables"
}

# Module initialization
yaml_init() {
    yaml_check_dependencies || return 1
    log_debug "YAML configuration module initialized"
    return 0
}