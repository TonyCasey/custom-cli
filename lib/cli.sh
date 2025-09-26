#!/bin/bash
# CLI Module
# Provides clean command line argument parsing and validation

set -euo pipefail

# Module initialization guard
if [[ "${CLI_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly CLI_MODULE_LOADED="true"

# Load dependencies
if [[ -z "${CLI_LIB_DIR:-}" ]]; then
    readonly CLI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
# shellcheck source=lib/config.sh
source "$CLI_LIB_DIR/config.sh"
# shellcheck source=lib/logging.sh
source "$CLI_LIB_DIR/logging.sh"

# Ensure configuration is loaded
config_load_defaults

# CLI state
declare -a CLI_ARGS=()
CLI_ACTION=""
CLI_SERVICE=""
CLI_PARSED="false"

# =============================================================================
# Private Functions
# =============================================================================

# Validate action argument
_cli_validate_action() {
    local action="$1"
    case "$action" in
        start|stop|status|logs|help|version|config-debug|version-debug|test-logging|test-service-interface|test-dependencies)
            echo "$action"
            return 0
            ;;
        --help|-h)
            echo "help"
            return 0
            ;;
        *)
            log_error "Invalid action '$action'"
            log_error "Valid actions: start, stop, status, logs, help"
            return 1
            ;;
    esac
}

# Validate service argument
_cli_validate_service() {
    local service="$1"

    # Get valid services from configuration
    local valid_services
    if valid_services=$(yaml_get_composite_names 2>/dev/null); then
        for valid_service in $valid_services; do
            if [[ "$service" == "$valid_service" ]]; then
                return 0
            fi
        done
    else
        log_warn "Could not load service names from configuration, allowing all services"
        return 0
    fi

    log_error "Invalid service '$service'"
    log_error "Valid services: $valid_services"
    return 1
}

# Check if action requires service argument
_cli_action_requires_service() {
    local action="$1"
    case "$action" in
        start|stop|status)
            return 0  # Requires service
            ;;
        *)
            return 1  # Does not require service
            ;;
    esac
}

# =============================================================================
# Public API
# =============================================================================

# Check for version flags (handled early, before normal parsing)
cli_check_version_flags() {
    local args=("$@")
    
    # Check if any argument is a version flag
    for arg in "${args[@]}"; do
        case "$arg" in
            --version|-version|-v|version)
                return 0  # Is a version flag
                ;;
        esac
    done
    
    return 1  # Not a version flag
}

# Parse command line arguments
cli_parse() {
    local args=("$@")
    CLI_ARGS=("${args[@]}")
    
    # Handle version flags early (before other processing)
    if cli_check_version_flags "$@"; then
        CLI_ACTION="version"
        CLI_SERVICE=""
        CLI_PARSED="true"
        log_debug "Version flag detected, setting action to 'version'"
        return 0
    fi
    
    # Handle no arguments
    if [[ ${#args[@]} -eq 0 ]]; then
        CLI_ACTION="help"
        CLI_SERVICE=""
        CLI_PARSED="true"
        return 0
    fi
    
    # Parse action (first argument)
    local raw_action="${args[0]}"
    CLI_ACTION="$(_cli_validate_action "$raw_action")" || {
        CLI_PARSED="false"
        return 1
    }
    
    # Handle special case where validation returns normalized action
    if [[ "$CLI_ACTION" != "$raw_action" ]]; then
        log_debug "Normalized action: $raw_action -> $CLI_ACTION"
    fi
    
    # Parse service (second argument, if present)
    if [[ ${#args[@]} -gt 1 ]]; then
        CLI_SERVICE="${args[1]}"
        
        # Validate service if action requires it
        if _cli_action_requires_service "$CLI_ACTION"; then
            _cli_validate_service "$CLI_SERVICE" || {
                CLI_PARSED="false"
                return 1
            }
        else
            log_warn "Service '$CLI_SERVICE' provided but action '$CLI_ACTION' does not require a service"
        fi
    else
        CLI_SERVICE=""
        
        # Check if service is required
        if _cli_action_requires_service "$CLI_ACTION"; then
            log_error "Action '$CLI_ACTION' requires a service argument"
            log_error "Usage: ${CLI_INVOKED_AS:-${CLI_NAME:-custom-cli}} $CLI_ACTION <service>"
            CLI_PARSED="false"
            return 1
        fi
    fi
    
    # Handle extra arguments
    if [[ ${#args[@]} -gt 2 ]]; then
        local extra_args=("${args[@]:2}")
        log_warn "Extra arguments ignored: ${extra_args[*]}"
    fi
    
    CLI_PARSED="true"
    log_debug "CLI parsed successfully: action='$CLI_ACTION', service='$CLI_SERVICE'"
    return 0
}

# Get parsed action
cli_get_action() {
    if [[ "$CLI_PARSED" != "true" ]]; then
        log_error "CLI not parsed. Call cli_parse() first."
        return 1
    fi
    echo "$CLI_ACTION"
}

# Get parsed service
cli_get_service() {
    if [[ "$CLI_PARSED" != "true" ]]; then
        log_error "CLI not parsed. Call cli_parse() first."
        return 1
    fi
    echo "$CLI_SERVICE"
}

# Check if CLI has been parsed
cli_is_parsed() {
    [[ "$CLI_PARSED" == "true" ]]
}

# Get all original arguments
cli_get_args() {
    echo "${CLI_ARGS[*]}"
}

# =============================================================================
# Help and Usage
# =============================================================================

# Display usage information
cli_usage() {
    local script_name="${1:-${CLI_INVOKED_AS:-${CLI_NAME:-custom-cli}}}"

    # Get CLI name and description from config
    local cli_display_name="$script_name CLI"
    local cli_description="Development Environment Control"

    cat << EOF
$cli_display_name (Configuration-Driven Architecture)

Usage: $script_name [ACTION] [SERVICE]
       $script_name [--version|-version|-v]

Actions:
  start     Start a service environment
  stop      Stop a service environment
  status    Check service environment status
  logs      View logs
  help      Show this help

Services:
EOF

    # Dynamically list available services from configuration
    local available_services
    if available_services=$(yaml_get_composite_names 2>/dev/null); then
        for service in $available_services; do
            local service_description
            if service_description=$(yaml_get_composite_description "$service" 2>/dev/null); then
                printf "  %-12s %s\n" "$service" "$service_description"
            else
                printf "  %-12s Service environment: %s\n" "$service" "$service"
            fi
        done
    else
        echo "  (Services configured in config.yaml)"
    fi

    cat << EOF

Examples:
EOF

    # Generate dynamic examples
    if [[ -n "${available_services:-}" ]]; then
        local first_service=$(echo "$available_services" | awk '{print $1}')
        local second_service=$(echo "$available_services" | awk '{print $2}')
        if [[ -n "$first_service" ]]; then
            echo "  $script_name start $first_service"
            echo "  $script_name stop $first_service"
            echo "  $script_name status $first_service"
        fi
        if [[ -n "$second_service" ]]; then
            echo "  $script_name start $second_service"
            echo "  $script_name stop $second_service"
            echo "  $script_name status $second_service"
        fi
    fi

    cat << EOF
  $script_name logs

Version Flags:
  $script_name --version        # Show version info
  $script_name -version         # Show version info
  $script_name -v               # Show version info

Debug Commands:
  $script_name config-debug     # Show configuration
  $script_name version          # Show version info (alternative)
  $script_name version-debug    # Show detailed version info
  $script_name test-logging     # Test logging levels
  $script_name test-service-interface # Test service interface validation
  $script_name test-dependencies # Test dependency resolution and YAML config
EOF
}

# Display detailed help for a specific action
cli_help_action() {
    local action="$1"
    local script_name="${2:-${CLI_INVOKED_AS:-${CLI_NAME:-custom-cli}}}"
    
    case "$action" in
        start)
            cat << EOF
Start Service Command

Usage: $script_name start <service>

Description:
  Starts the specified service environment. This includes all required
  dependencies and performs health checks to ensure services are ready.

  Available service environments are defined in config.yaml and may include
  multiple components that start in dependency order.

Examples:
EOF
            # Generate dynamic examples for start command
            local available_services
            if available_services=$(yaml_get_composite_names 2>/dev/null); then
                local first_service=$(echo "$available_services" | awk '{print $1}')
                local second_service=$(echo "$available_services" | awk '{print $2}')
                if [[ -n "$first_service" ]]; then
                    echo "  $script_name start $first_service   # Start $first_service environment"
                fi
                if [[ -n "$second_service" ]]; then
                    echo "  $script_name start $second_service   # Start $second_service environment"
                fi
            fi

            cat << EOF

The start command will:
  1. Stop any existing instances of the service
  2. Start all required components in the correct order
  3. Wait for each component to become healthy
  4. Display access URLs and status information
EOF
            ;;
        stop)
            cat << EOF
Stop Service Command

Usage: $script_name stop <service>

Description:
  Stops the specified service environment and all its components.
  Uses graceful shutdown where possible.

Examples:
EOF
            # Generate dynamic examples for stop command
            local available_services
            if available_services=$(yaml_get_composite_names 2>/dev/null); then
                local first_service=$(echo "$available_services" | awk '{print $1}')
                local second_service=$(echo "$available_services" | awk '{print $2}')
                if [[ -n "$first_service" ]]; then
                    echo "  $script_name stop $first_service   # Stop $first_service environment"
                fi
                if [[ -n "$second_service" ]]; then
                    echo "  $script_name stop $second_service   # Stop $second_service environment"
                fi
            fi

            cat << EOF

The stop command will:
  1. Terminate processes gracefully (SIGTERM first)
  2. Force kill if graceful shutdown fails (SIGKILL)
  3. Clean up ports and temporary files
  4. Display confirmation of shutdown
EOF
            ;;
        status)
            cat << EOF
Status Check Command

Usage: $script_name status <service>

Description:
  Checks the status of all components in the specified service environment.
  Performs both port checks and HTTP health checks where applicable.

Examples:
EOF
            # Generate dynamic examples for status command
            local available_services
            if available_services=$(yaml_get_composite_names 2>/dev/null); then
                local first_service=$(echo "$available_services" | awk '{print $1}')
                local second_service=$(echo "$available_services" | awk '{print $2}')
                if [[ -n "$first_service" ]]; then
                    echo "  $script_name status $first_service   # Check $first_service environment status"
                fi
                if [[ -n "$second_service" ]]; then
                    echo "  $script_name status $second_service   # Check $second_service environment status"
                fi
            fi

            cat << EOF

The status command shows:
  1. Port listening status for each component
  2. HTTP health check results (if configured)
  3. Overall service health summary
  4. Detailed component information
EOF
            ;;
        logs)
            cat << EOF
Logs Command

Usage: $script_name logs

Description:
  Lists available log files and provides instructions for viewing them.
  All services write structured logs with timestamps.

Log Files:
  - Service-specific logs (e.g., firebase-emulators.log, dashboard-api.log)
  - Component logs (e.g., app-build.log, metro.log)
  - Structured format with timestamps and log levels

Examples:
  $script_name logs                           # List available log files
  tail -f .logs/dashboard-api.log   # Follow dashboard API logs
  less .logs/firebase-emulators.log # View Firebase emulator logs

Log Features:
  - Automatic log rotation when files get large
  - Structured format with timestamps
  - Service startup information and headers
  - Error and debug information
EOF
            ;;
        *)
            log_error "No detailed help available for action: $action"
            cli_usage "${CLI_INVOKED_AS:-${CLI_NAME:-custom-cli}}"
            return 1
            ;;
    esac
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate that required dependencies are available
cli_validate_dependencies() {
    local action="${1:-}"
    local service="${2:-}"
    
    # Check for required system commands
    local required_commands=("lsof" "curl" "npm")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install the missing dependencies and try again"
        return 1
    fi
    
    # Check for Android development tools if app service is being used
    if [[ "$service" == "app" ]]; then
        if ! command -v "adb" &> /dev/null; then
            log_error "Android Debug Bridge (adb) not found"
            log_error "Please install Android SDK and ensure adb is in your PATH"
            return 1
        fi
        
        if ! command -v "emulator" &> /dev/null; then
            log_warn "Android emulator command not found"
            log_warn "You may need to add \$ANDROID_HOME/emulator to your PATH"
        fi
    fi
    
    # Validate repository directories exist
    local repos_dir="$(config_get "REPOS_DIR")"
    if [[ ! -d "$repos_dir" ]]; then
        log_error "Repositories directory not found: $repos_dir"
        log_error "Please ensure your repositories are cloned to the expected location"
        return 1
    fi
    
    # Validate specific service directories if service is specified
    if [[ -n "$service" ]]; then
        local composite_services
        composite_services="$(config_get_composite "$service")" || {
            log_error "Unknown service: $service"
            return 1
        }
        
        for svc in $composite_services; do
            local svc_config
            svc_config="$(config_get_service "$svc")" || continue
            
            local directory=""
            while IFS='=' read -r key value; do
                if [[ "$key" == "DIRECTORY" ]]; then
                    directory="$value"
                    break
                fi
            done <<< "$svc_config"
            
            if [[ -n "$directory" ]] && [[ ! -d "$directory" ]]; then
                log_error "Service directory not found: $directory (required for $svc)"
                return 1
            fi
        done
    fi
    
    return 0
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if action is a debug command
cli_is_debug_action() {
    local action="${1:-$CLI_ACTION}"
    case "$action" in
        version|config-debug|test-logging|test-service-interface|test-dependencies)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get command summary for logging
cli_get_command_summary() {
    if [[ "$CLI_PARSED" != "true" ]]; then
        echo "unparsed"
        return 1
    fi
    
    if [[ -n "$CLI_SERVICE" ]]; then
        echo "$CLI_ACTION $CLI_SERVICE"
    else
        echo "$CLI_ACTION"
    fi
}

# Validate that a service has required configuration
cli_validate_service_config() {
    local service="$1"
    
    # Get composite services
    local composite_services
    composite_services="$(config_get_composite "$service")" || {
        log_error "Service '$service' is not configured"
        return 1
    }
    
    # Validate each component service
    for svc in $composite_services; do
        local svc_config
        svc_config="$(config_get_service "$svc")" || {
            log_error "Component service '$svc' is not configured (required for $service)"
            return 1
        }
        
        # Check that required configuration exists
        local has_port=false has_directory=false
        while IFS='=' read -r key value; do
            case "$key" in
                PORT) 
                    if [[ -n "$value" ]]; then
                        has_port=true
                    fi
                    ;;
                DIRECTORY) 
                    if [[ -n "$value" ]]; then
                        has_directory=true
                    fi
                    ;;
            esac
        done <<< "$svc_config"
        
        if [[ "$has_port" == "false" ]] && [[ "$svc" != "react-native" ]]; then
            log_warn "Service '$svc' has no port configured"
        fi
        
        if [[ "$has_directory" == "false" ]]; then
            log_warn "Service '$svc' has no directory configured"
        fi
    done
    
    return 0
}

# Debug: Show CLI module status
cli_debug_info() {
    log_debug "CLI module loaded"
    log_debug "Parsed: $CLI_PARSED"
    if [[ "$CLI_PARSED" == "true" ]]; then
        log_debug "Action: ${CLI_ACTION:-none}"
        log_debug "Service: ${CLI_SERVICE:-none}"
        log_debug "Original args: ${CLI_ARGS[*]}"
    fi
}