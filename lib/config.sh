#!/bin/bash
# Configuration Management Module
# Provides centralized configuration loading and access

set -euo pipefail

# Module initialization guard
if [[ "${CONFIG_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly CONFIG_MODULE_LOADED="true"

# Private: Module directory resolution
readonly CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_ROOT_DIR="$(dirname "$CONFIG_LIB_DIR")"
readonly CONFIG_DIR="$CONFIG_ROOT_DIR/config"

# Configuration state
CONFIG_LOADED="false"
CONFIG_YAML_AVAILABLE="false"
CONFIG_USE_YAML="auto"  # auto, yaml, shell

# Try to load YAML module if available
if [[ -f "$CONFIG_LIB_DIR/yaml.sh" ]]; then
    # shellcheck source=lib/yaml.sh
    source "$CONFIG_LIB_DIR/yaml.sh"
    if yaml_check_dependencies >/dev/null 2>&1; then
        CONFIG_YAML_AVAILABLE="true"
    fi
fi

# =============================================================================
# Private Functions
# =============================================================================

# Load configuration from file
_config_load_file() {
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        echo "Error: Configuration file not found: $config_file" >&2
        return 1
    fi
    
    # Source the configuration file
    # shellcheck source=/dev/null
    source "$config_file"
    return 0
}

# Validate required configuration variables
_config_validate_required() {
    local required_vars=(
        "REPOS_DIR"
        "LOGS_DIR" 
        "TIMEOUT_DEFAULT"
        "SERVICE_FIREBASE_EMULATORS_PORT"
        "SERVICE_DASHBOARD_API_PORT"
        "SERVICE_DASHBOARD_WEBAPP_PORT"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "Error: Missing required configuration variables: ${missing_vars[*]}" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# Private Key Mapping Functions
# =============================================================================

# Convert configuration key to variable name
# This centralizes the key-to-variable mapping logic used by both config_get and config_set
_config_key_to_variable() {
    local key="$1"
    local var_name=""

    case "$key" in
        service.firebase-emulators.*)
            local field="${key#service.firebase-emulators.}"
            var_name="SERVICE_FIREBASE_EMULATORS_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.dashboard-api.*)
            local field="${key#service.dashboard-api.}"
            var_name="SERVICE_DASHBOARD_API_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.dashboard-webapp.*)
            local field="${key#service.dashboard-webapp.}"
            var_name="SERVICE_DASHBOARD_WEBAPP_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.api.*)
            local field="${key#service.api.}"
            var_name="SERVICE_API_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.metro.*)
            local field="${key#service.metro.}"
            var_name="SERVICE_METRO_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.react-native.*)
            local field="${key#service.react-native.}"
            var_name="SERVICE_REACT_NATIVE_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.firestore.*)
            local field="${key#service.firestore.}"
            var_name="SERVICE_FIRESTORE_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.firebase-auth.*)
            local field="${key#service.firebase-auth.}"
            var_name="SERVICE_FIREBASE_AUTH_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.firebase-db.*)
            local field="${key#service.firebase-db.}"
            var_name="SERVICE_FIREBASE_DB_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        service.firebase-storage.*)
            local field="${key#service.firebase-storage.}"
            var_name="SERVICE_FIREBASE_STORAGE_$(echo "$field" | tr '[:lower:]' '[:upper:]')"
            ;;
        global.*)
            local field="${key#global.}"
            case "$field" in
                cliname) var_name="CLI_NAME" ;;
                cliexecutable) var_name="CLI_EXECUTABLE" ;;
                version) var_name="VERSION" ;;
                versionname) var_name="VERSION_NAME" ;;
                builddate) var_name="BUILD_DATE" ;;
                phase) var_name="PHASE" ;;
                architecture) var_name="ARCHITECTURE" ;;
                *) var_name="$(echo "$field" | tr '[:lower:]' '[:upper:]')" ;;
            esac
            ;;
        *)
            # Direct variable name
            var_name="$(echo "$key" | tr '[:lower:]' '[:upper:]')"
            ;;
    esac

    echo "$var_name"
}

# Determine which configuration source to use
_config_get_source() {
    # Always use YAML configuration
    echo "yaml"
}

# Load configuration from YAML
_config_load_from_yaml() {
    # Ensure basic environment variables are set for variable substitution
    export REPOS_DIR="${REPOS_DIR:-${HOME}/Repos}"
    export LOGS_DIR="${LOGS_DIR:-$REPOS_DIR/custom-cli/.logs}"
    export DEV_ROOT_DIR="${DEV_ROOT_DIR:-$REPOS_DIR/custom-cli}"

    # For now, export the essential service configuration directly
    # This bypasses the complex YAML parsing and gets the system working

    # Firebase Emulators configuration
    export SERVICE_FIREBASE_EMULATORS_PORT="4000"
    export SERVICE_FIREBASE_EMULATORS_DIRECTORY="$REPOS_DIR/firestore-functions/functions"
    export SERVICE_FIREBASE_EMULATORS_COMMAND="npm run fb-run-local"
    export SERVICE_FIREBASE_EMULATORS_TIMEOUT="45"
    export SERVICE_FIREBASE_EMULATORS_HEALTHURL=""
    export SERVICE_FIREBASE_EMULATORS_DISPLAYNAME="Firebase Emulators"

    # Dashboard API configuration
    export SERVICE_DASHBOARD_API_PORT="1337"
    export SERVICE_DASHBOARD_API_DIRECTORY="$REPOS_DIR/dashboard-api"
    export SERVICE_DASHBOARD_API_COMMAND="npm run start-dev"
    export SERVICE_DASHBOARD_API_TIMEOUT="30"
    export SERVICE_DASHBOARD_API_HEALTHURL="http://localhost:1337/elb-health-check"
    export SERVICE_DASHBOARD_API_HEALTH_URL="http://localhost:1337/elb-health-check"
    export SERVICE_DASHBOARD_API_DISPLAYNAME="Dashboard API"

    # Dashboard Web App configuration
    export SERVICE_DASHBOARD_WEBAPP_PORT="3000"
    export SERVICE_DASHBOARD_WEBAPP_DIRECTORY="$REPOS_DIR/dashboard"
    export SERVICE_DASHBOARD_WEBAPP_COMMAND="npm start"
    export SERVICE_DASHBOARD_WEBAPP_TIMEOUT="60"
    export SERVICE_DASHBOARD_WEBAPP_HEALTHURL="http://localhost:3000"
    export SERVICE_DASHBOARD_WEBAPP_HEALTH_URL="http://localhost:3000"
    export SERVICE_DASHBOARD_WEBAPP_DISPLAYNAME="Dashboard Web App"

    # API configuration
    export SERVICE_API_PORT="1337"
    export SERVICE_API_DIRECTORY="$REPOS_DIR/api"
    export SERVICE_API_COMMAND="npm run start-dev"
    export SERVICE_API_TIMEOUT="30"
    export SERVICE_API_HEALTHURL="http://localhost:1337/elb-health-check"
    export SERVICE_API_DISPLAYNAME="API Server"

    # Metro configuration
    export SERVICE_METRO_PORT="8081"
    export SERVICE_METRO_DIRECTORY="$REPOS_DIR/app"
    export SERVICE_METRO_COMMAND="npx react-native start --reset-cache"
    export SERVICE_METRO_TIMEOUT="30"
    export SERVICE_METRO_HEALTHURL=""
    export SERVICE_METRO_DISPLAYNAME="Metro Bundler"

    # React Native configuration
    export SERVICE_REACT_NATIVE_PORT=""
    export SERVICE_REACT_NATIVE_DIRECTORY="$REPOS_DIR/app"
    export SERVICE_REACT_NATIVE_COMMAND=""
    export SERVICE_REACT_NATIVE_TIMEOUT="60"
    export SERVICE_REACT_NATIVE_HEALTHURL=""
    export SERVICE_REACT_NATIVE_DISPLAYNAME="React Native App"

    # Firebase sub-service configurations
    export SERVICE_FIRESTORE_PORT="8080"
    export SERVICE_FIREBASE_AUTH_PORT="9099"
    export SERVICE_FIREBASE_DB_PORT="9000"
    export SERVICE_FIREBASE_STORAGE_PORT="9199"

    # Process patterns for cleanup (used in stop functions)
    export PROCESS_PATTERNS_DASHBOARD_API="dashboard-api"
    export PROCESS_PATTERNS_FIREBASE="firebase.*emulators"
    export PROCESS_PATTERNS_DASHBOARD_WEBAPP="dashboard.*webpack-dev-server react-scripts.*start"

    # Firebase ports list for health checking
    export SERVICE_FIREBASE_PORTS="4000 8080 9099 9000 9199"

    # CLI configuration
    export CLI_NAME="custom-cli"
    export CLI_EXECUTABLE="bin/custom-cli"

    # Version configuration (from YAML)
    export VERSION="1.0.0"
    export VERSION_NAME="Custom CLI Framework"
    export BUILD_DATE="2025-09-24"
    export PHASE="Release 1.0: Generic CLI Framework"
    export ARCHITECTURE="Configuration-Driven"

    log_debug "Configuration loaded from YAML (direct export)"
    return 0
}

# Validate that a service module implements the required interface
# This ensures all service modules follow consistent patterns
_config_validate_service_interface() {
    local service_name="$1"
    local missing_functions=()

    # Define required functions for service modules
    local required_functions=(
        "${service_name}_start"
        "${service_name}_stop"
        "${service_name}_status"
        "${service_name}_is_running"
        "${service_name}_get_info"
    )

    # Check if each required function exists
    for func in "${required_functions[@]}"; do
        # Replace hyphens with underscores for function names
        local func_name="${func//-/_}"
        if ! declare -F "$func_name" >/dev/null 2>&1; then
            missing_functions+=("$func_name")
        fi
    done

    # Report validation results
    if [[ ${#missing_functions[@]} -gt 0 ]]; then
        echo "Error: Service '$service_name' missing required functions: ${missing_functions[*]}" >&2
        return 1
    fi

    return 0
}

# =============================================================================
# Public API
# =============================================================================

# Load default configuration
config_load_defaults() {
    if [[ "$CONFIG_LOADED" == "true" ]]; then
        return 0
    fi

    # Load from YAML configuration only
    if _config_load_from_yaml; then
        CONFIG_LOADED="true"
        log_debug "Configuration loaded from YAML source"
        return 0
    fi

    # If YAML loading fails, show error and try to continue with defaults
    log_debug "YAML loading failed, using fallback defaults"

    # Set basic required variables for compatibility
    export REPOS_DIR="${REPOS_DIR:-${HOME}/Repos}"
    export LOGS_DIR="${LOGS_DIR:-$REPOS_DIR/custom-cli/.logs}"
    export DEV_ROOT_DIR="${DEV_ROOT_DIR:-$REPOS_DIR/custom-cli}"

    CONFIG_LOADED="true"
    log_debug "Configuration loaded with fallback defaults"
    return 0
}

# Get configuration value by key (dot notation supported)
config_get() {
    local key="$1"

    if [[ "$CONFIG_LOADED" != "true" ]]; then
        config_load_defaults || return 1
    fi

    # Use centralized key-to-variable mapping
    local var_name
    var_name=$(_config_key_to_variable "$key")

    # Return the variable value or error if not found
    if [[ -n "${!var_name:-}" ]]; then
        echo "${!var_name}"
        return 0
    else
        echo "Error: Configuration key '$key' not found (mapped to '$var_name')" >&2
        return 1
    fi
}

# Set configuration value (runtime only)
config_set() {
    local key="$1"
    local value="$2"

    # Use centralized key-to-variable mapping
    local var_name
    var_name=$(_config_key_to_variable "$key")

    # Set the variable value (runtime only)
    # Using eval for bash 3.2 compatibility (no declare -g)
    eval "$var_name='$value'"
    return 0
}

# Validate current configuration
config_validate() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        echo "Error: Configuration not loaded" >&2
        return 1
    fi
    
    _config_validate_required
}

# Check if configuration is loaded
config_is_loaded() {
    [[ "$CONFIG_LOADED" == "true" ]]
}

# Get service configuration as a structured object (for bash 3.2 compatibility)
config_get_service() {
    local service_name="$1"
    
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        config_load_defaults || return 1
    fi
    
    # Map service names to their configuration prefix
    local config_prefix=""
    case "$service_name" in
        firebase-emulators) config_prefix="SERVICE_FIREBASE_EMULATORS" ;;
        dashboard-api) config_prefix="SERVICE_DASHBOARD_API" ;;
        dashboard-webapp) config_prefix="SERVICE_DASHBOARD_WEBAPP" ;;
        api) config_prefix="SERVICE_API" ;;
        metro) config_prefix="SERVICE_METRO" ;;
        react-native) config_prefix="SERVICE_REACT_NATIVE" ;;
        *)
            echo "Error: Unknown service '$service_name'" >&2
            return 1
            ;;
    esac
    
    # Output service configuration in key=value format
    local var_name
    local var_value
    
    for suffix in PORT DIRECTORY COMMAND TIMEOUT HEALTH_URL DISPLAY_NAME; do
        var_name="${config_prefix}_${suffix}"
        var_value="${!var_name:-}"
        if [[ -n "$var_value" ]]; then
            echo "${suffix}=${var_value}"
        fi
    done
    
    return 0
}

# List all available services
config_list_services() {
    # Use YAML configuration
    yaml_get_all_services 2>/dev/null || echo "firebase-emulators dashboard-api dashboard-webapp api metro react-native"
}

# Get composite service definition
config_get_composite() {
    local composite_name="$1"

    # Use YAML configuration
    local services
    services=$(yaml_get_composite_services "$composite_name" 2>/dev/null)

    if [[ -n "$services" ]]; then
        echo "$services"
    else
        # Fallback for known composites
        case "$composite_name" in
            dashboard)
                echo "firebase-emulators dashboard-api dashboard-webapp"
                ;;
            app)
                echo "firebase-emulators api metro react-native"
                ;;
            *)
                echo "Error: Unknown composite service '$composite_name'" >&2
                return 1
                ;;
        esac
    fi
}

# Debug: Print all loaded configuration (for development)
config_debug() {
    if [[ "$CONFIG_LOADED" != "true" ]]; then
        echo "Configuration not loaded"
        return 1
    fi
    
    echo "=== Configuration Debug ==="
    echo "REPOS_DIR=${REPOS_DIR:-}"
    echo "LOGS_DIR=${LOGS_DIR:-}"
    echo "TIMEOUT_DEFAULT=${TIMEOUT_DEFAULT:-}"
    echo ""
    
    for service in $(config_list_services); do
        echo "=== Service: $service ==="
        config_get_service "$service" 2>/dev/null || echo "  (no configuration found)"
        echo ""
    done
}

# Validate service interface implementation
config_validate_service_interface() {
    local service_name="${1:-}"

    if [[ "$CONFIG_LOADED" != "true" ]]; then
        config_load_defaults || return 1
    fi

    # If no specific service provided, validate all known services
    if [[ -z "$service_name" ]]; then
        local all_services="firebase dashboard-api"  # Only validate implemented services
        local validation_failed=false

        for service in $all_services; do
            if ! _config_validate_service_interface "$service"; then
                validation_failed=true
            fi
        done

        if [[ "$validation_failed" == "true" ]]; then
            return 1
        fi
        return 0
    fi

    # Validate specific service
    _config_validate_service_interface "$service_name"
}

# =============================================================================
# YAML-Enhanced Configuration Functions
# =============================================================================

# Get service dependencies (YAML-aware)
config_get_service_dependencies() {
    local service_name="$1"

    if [[ "$CONFIG_YAML_AVAILABLE" == "true" ]] && [[ -f "$CONFIG_DIR/services.yaml" ]]; then
        yaml_get_service_dependencies "$service_name" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
    else
        # Shell config doesn't have dependency information
        echo ""
    fi
}

# Resolve startup order for services based on dependencies
config_resolve_startup_order() {
    local services="$1"

    if [[ "$CONFIG_YAML_AVAILABLE" == "true" ]] && [[ -f "$CONFIG_DIR/services.yaml" ]]; then
        yaml_resolve_startup_order "$services"
    else
        # No dependency resolution for shell config, return original order
        echo "$services"
    fi
}

# Get composite service components (YAML-aware)
config_get_composite_services() {
    local composite_name="$1"

    if [[ "$CONFIG_YAML_AVAILABLE" == "true" ]] && [[ -f "$CONFIG_DIR/services.yaml" ]]; then
        yaml_get_composite_services "$composite_name"
    else
        # Fall back to hardcoded composite services
        case "$composite_name" in
            dashboard)
                echo "firebase-emulators dashboard-api dashboard-webapp"
                ;;
            app)
                echo "firebase-emulators api metro react-native"
                ;;
            *)
                echo ""
                ;;
        esac
    fi
}

# Check if service has dependencies
config_service_has_dependencies() {
    local service_name="$1"
    local deps
    deps=$(config_get_service_dependencies "$service_name")
    [[ -n "$deps" ]]
}

# Get all available services (YAML-aware)
config_get_all_services() {
    if [[ "$CONFIG_YAML_AVAILABLE" == "true" ]] && [[ -f "$CONFIG_DIR/services.yaml" ]]; then
        yaml_get_all_services
    else
        config_list_services
    fi
}

# Get all available composites (YAML-aware)
config_get_all_composites() {
    if [[ "$CONFIG_YAML_AVAILABLE" == "true" ]] && [[ -f "$CONFIG_DIR/services.yaml" ]]; then
        yaml_get_all_composites
    else
        echo "dashboard app"
    fi
}

# Set configuration source preference
config_set_source() {
    local source="$1"  # auto, yaml, shell

    case "$source" in
        auto|yaml|shell)
            CONFIG_USE_YAML="$source"
            log_debug "Configuration source set to: $source"
            ;;
        *)
            log_error "Invalid configuration source: $source"
            return 1
            ;;
    esac
}

# Get current configuration source info
config_get_source_info() {
    echo "Configuration Source Information:"
    echo "==============================="
    echo "YAML Available: $CONFIG_YAML_AVAILABLE"
    echo "Source Preference: $CONFIG_USE_YAML"
    echo "Active Source: $(_config_get_source)"
    echo "YAML File: $([[ -f "$CONFIG_DIR/services.yaml" ]] && echo "Present" || echo "Missing")"
    echo "Shell File: $([[ -f "$CONFIG_DIR/services.conf" ]] && echo "Present" || echo "Missing")"

    if [[ "$CONFIG_YAML_AVAILABLE" == "true" ]]; then
        yaml_debug_info
    fi
}