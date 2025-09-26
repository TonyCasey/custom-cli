#!/bin/bash
# Generic Service Module
# Provides a unified interface for managing any service defined in config.yaml
# Eliminates the need for hardcoded service-specific modules

set -euo pipefail

# Module initialization guard
if [[ "${SERVICE_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly SERVICE_MODULE_LOADED="true"

# Load dependencies
readonly SERVICE_LIB_DIR="${SERVICE_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"
# shellcheck source=lib/config.sh
source "$SERVICE_LIB_DIR/config.sh"
# shellcheck source=lib/logging.sh
source "$SERVICE_LIB_DIR/logging.sh"
# shellcheck source=lib/process.sh
source "$SERVICE_LIB_DIR/process.sh"
# shellcheck source=lib/health.sh
source "$SERVICE_LIB_DIR/health.sh"
# shellcheck source=lib/yaml.sh
source "$SERVICE_LIB_DIR/yaml.sh"

# Ensure configuration is loaded
config_load_defaults

# =============================================================================
# Service Information Functions
# =============================================================================

# Get service configuration from YAML
service_get_config() {
    local service_name="$1"

    if ! yaml_check_dependencies >/dev/null 2>&1; then
        log_error "YAML dependencies not available for generic service operations"
        return 1
    fi

    # Use yaml.sh to get service configuration
    local config_result
    config_result=$(yaml_get_service_config "$service_name" 2>/dev/null) || {
        log_error "Service '$service_name' not found in configuration"
        return 1
    }

    echo "$config_result"
}

# Get specific service property
service_get_property() {
    local service_name="$1"
    local property="$2"
    local default_value="${3:-}"

    local config
    config=$(service_get_config "$service_name") || return 1

    local value
    value=$(echo "$config" | grep "^${property}=" | cut -d'=' -f2- | sed 's/^"//' | sed 's/"$//')

    if [[ -n "$value" ]]; then
        # Perform variable substitution
        value=$(echo "$value" | envsubst)
        echo "$value"
    else
        echo "$default_value"
    fi
}

# Get service display name
service_get_display_name() {
    local service_name="$1"
    service_get_property "$service_name" "displayName" "$service_name"
}

# Get service port
service_get_port() {
    local service_name="$1"
    service_get_property "$service_name" "port" ""
}

# Get service directory
service_get_directory() {
    local service_name="$1"
    service_get_property "$service_name" "directory" ""
}

# Get service command
service_get_command() {
    local service_name="$1"
    service_get_property "$service_name" "command" ""
}

# Get service timeout
service_get_timeout() {
    local service_name="$1"
    service_get_property "$service_name" "timeout" "30"
}

# Get service health URL
service_get_health_url() {
    local service_name="$1"
    service_get_property "$service_name" "healthUrl" ""
}

# Get service dependencies
service_get_dependencies() {
    local service_name="$1"

    if yaml_check_dependencies >/dev/null 2>&1; then
        yaml_get_service_dependencies "$service_name" 2>/dev/null | tr '\n' ' ' | sed 's/ $//' || echo ""
    else
        echo ""
    fi
}

# =============================================================================
# Service Lifecycle Functions
# =============================================================================

# Start a service
service_start() {
    local service_name="$1"
    local display_name
    display_name=$(service_get_display_name "$service_name")

    log_step "Starting $display_name"

    # Get service configuration
    local directory command port timeout
    directory=$(service_get_directory "$service_name")
    command=$(service_get_command "$service_name")
    port=$(service_get_port "$service_name")
    timeout=$(service_get_timeout "$service_name")

    # Validate required properties
    if [[ -z "$directory" ]]; then
        log_error "$display_name: directory not specified in configuration"
        return 1
    fi

    if [[ -z "$command" ]]; then
        log_error "$display_name: command not specified in configuration"
        return 1
    fi

    # Validate directory exists
    if [[ ! -d "$directory" ]]; then
        log_error "$display_name directory not found: $directory"
        return 1
    fi

    log_info "$display_name Configuration:"
    echo "  📁 Directory: $directory"
    echo "  ⚙️ Command: $command"
    if [[ -n "$port" ]]; then
        echo "  🔌 Port: $port"
    fi

    # Start the service using process module
    local pid
    pid=$(process_start_background "$display_name" "$command" "$directory") || {
        log_error "Failed to start $display_name"
        return 1
    }

    log_debug "$display_name started with PID: $pid"

    # Wait for service to be ready (if port is specified)
    if [[ -n "$port" ]]; then
        if process_wait_for_port "$display_name" "$port" "$timeout"; then
            log_success "$display_name is listening on port $port"
        else
            log_error "$display_name failed to start within ${timeout}s"
            return 1
        fi

        # Perform health check if URL is specified
        local health_url
        health_url=$(service_get_health_url "$service_name")
        if [[ -n "$health_url" ]]; then
            log_debug "Performing health check on $health_url"
            if process_test_http_endpoint "$display_name" "$health_url" 10; then
                log_success "$display_name health check passed"
            else
                log_warn "$display_name health check failed - service may not be fully ready"
            fi
        fi
    else
        # No port to check, just wait a moment
        sleep 2
    fi

    log_success "$display_name started successfully!"
    return 0
}

# Stop a service
service_stop() {
    local service_name="$1"
    local display_name
    display_name=$(service_get_display_name "$service_name")

    log_info "Stopping $display_name..."

    local port
    port=$(service_get_port "$service_name")

    # Kill process by port if port is specified
    if [[ -n "$port" ]]; then
        log_debug "Killing $display_name processes on port: $port"
        process_kill_port "$port" "TERM" 10

        # Verify process is stopped
        sleep 2
        if process_is_port_in_use "$port"; then
            log_warn "$display_name process still running on port $port"
            log_info "Force killing $display_name process..."
            process_kill_port "$port" "KILL" 5
        fi
    else
        # Try to kill by process name pattern (service name)
        log_debug "Killing $display_name processes by name pattern"
        process_kill_pattern "$service_name" "TERM" 10
    fi

    log_success "$display_name stopped"
    return 0
}

# Restart a service
service_restart() {
    local service_name="$1"
    local display_name
    display_name=$(service_get_display_name "$service_name")

    log_info "Restarting $display_name..."
    service_stop "$service_name"
    sleep 2
    service_start "$service_name"
}

# =============================================================================
# Service Status and Health Functions
# =============================================================================

# Check service status
service_status() {
    local service_name="$1"
    local display_name port health_url icon
    display_name=$(service_get_display_name "$service_name")
    port=$(service_get_port "$service_name")
    health_url=$(service_get_health_url "$service_name")
    icon=$(service_get_icon "$service_name")

    if [[ -n "$port" ]]; then
        process_check_service_by_port "$icon $display_name" "$port" "$health_url"
    else
        # Check by process pattern or name if no port
        local process_pattern
        process_pattern=$(service_get_property "$service_name" "processPattern" "")

        local is_running=false
        if [[ -n "$process_pattern" ]] && pgrep -f "$process_pattern" >/dev/null 2>&1; then
            is_running=true
        elif process_is_running_by_name "$service_name"; then
            is_running=true
        fi

        if [[ "$is_running" == "true" ]]; then
            echo -e "  ${COLOR_GREEN}✅ $icon $display_name: Running${COLOR_NC}"
            return 0
        else
            echo -e "  ${COLOR_RED}❌ $icon $display_name: Not Running${COLOR_NC}"
            return 1
        fi
    fi
}

# Health check for service
service_health() {
    local service_name="$1"
    local display_name port health_url
    display_name=$(service_get_display_name "$service_name")
    port=$(service_get_port "$service_name")
    health_url=$(service_get_health_url "$service_name")

    log_debug "Performing $display_name health check"

    # Check port if specified
    if [[ -n "$port" ]]; then
        if ! health_check_port "$display_name" "$port" 5; then
            log_debug "$display_name health check failed - port not accessible"
            return 2  # CRITICAL
        fi

        # Check health URL if specified
        if [[ -n "$health_url" ]]; then
            local result
            result=$(health_check_http "$display_name" "$health_url" 10 200)
            local status=$?

            case $status in
                0)
                    log_debug "$display_name health check: OK (HTTP endpoint responding)"
                    return 0  # OK
                    ;;
                1)
                    log_debug "$display_name health check: WARNING (HTTP endpoint issues)"
                    return 1  # WARNING
                    ;;
                *)
                    log_debug "$display_name health check: CRITICAL (HTTP endpoint failed)"
                    return 2  # CRITICAL
                    ;;
            esac
        else
            log_debug "$display_name health check: OK (port accessible)"
            return 0  # OK
        fi
    else
        # Check by process name
        if process_is_running_by_name "$service_name"; then
            log_debug "$display_name health check: OK (process running)"
            return 0  # OK
        else
            log_debug "$display_name health check: CRITICAL (process not running)"
            return 2  # CRITICAL
        fi
    fi
}

# Wait for service to be healthy
service_wait_healthy() {
    local service_name="$1"
    local timeout="${2:-60}"
    local display_name
    display_name=$(service_get_display_name "$service_name")

    log_info "Waiting for $display_name to be healthy (timeout: ${timeout}s)"

    local counter=0
    while [[ $counter -lt $timeout ]]; do
        if service_health "$service_name" >/dev/null 2>&1; then
            log_success "$display_name is healthy"
            return 0
        fi

        log_debug "$display_name not yet healthy, waiting..."
        sleep 5
        counter=$((counter + 5))
    done

    log_error "$display_name failed to become healthy within ${timeout}s"
    return 1
}

# =============================================================================
# Service Utility Functions
# =============================================================================

# Check if service is running
service_is_running() {
    local service_name="$1"
    local port
    port=$(service_get_port "$service_name")

    if [[ -n "$port" ]]; then
        process_is_port_in_use "$port"
    else
        process_is_running_by_name "$service_name"
    fi
}

# Get service URL
service_get_url() {
    local service_name="$1"
    local port
    port=$(service_get_port "$service_name")

    if [[ -n "$port" ]]; then
        echo "http://localhost:$port"
    else
        echo "N/A (no port configured)"
    fi
}

# Get service processes
service_get_processes() {
    local service_name="$1"
    local port
    port=$(service_get_port "$service_name")

    if [[ -n "$port" ]]; then
        process_get_port_info "$port"
    else
        process_list_by_name "$service_name"
    fi
}

# =============================================================================
# Service Discovery and Auto-Registration
# =============================================================================

# Discover all services from YAML configuration
service_discover_all() {
    log_debug "Discovering all services from YAML configuration..."

    if ! yaml_check_dependencies >/dev/null 2>&1; then
        log_debug "YAML dependencies not available, falling back to shell config"
        return 1
    fi

    local all_services
    all_services=$(yaml_get_all_services 2>/dev/null || echo "")

    if [[ -n "$all_services" ]]; then
        log_debug "Discovered services: $all_services"
        echo "$all_services"
        return 0
    else
        log_debug "No services found in YAML configuration"
        return 1
    fi
}

# Initialize service discovery
service_init_discovery() {
    log_debug "Initializing service discovery system..."

    # Try to discover services from YAML
    local discovered_services
    if discovered_services=$(service_discover_all 2>/dev/null); then
        log_debug "Service discovery initialized with YAML backend"
        log_debug "Available services: $discovered_services"
        return 0
    else
        log_debug "Service discovery falling back to configuration-based discovery"
        return 1
    fi
}

# =============================================================================
# Service Dependency Functions
# =============================================================================

# Check service dependencies are healthy
service_check_dependencies_health() {
    local service_name="$1"
    local deps
    deps=$(service_get_dependencies "$service_name")

    if [[ -z "$deps" ]]; then
        log_debug "Service '$service_name' has no dependencies"
        return 0
    fi

    log_debug "Checking dependencies for '$service_name': $deps"

    local failed_deps=()
    for dep in $deps; do
        if ! service_health "$dep" >/dev/null 2>&1; then
            failed_deps+=("$dep")
        fi
    done

    if [[ ${#failed_deps[@]} -gt 0 ]]; then
        log_error "Service '$service_name' has unhealthy dependencies: ${failed_deps[*]}"
        return 1
    fi

    log_debug "All dependencies for '$service_name' are healthy"
    return 0
}

# Wait for service dependencies to be healthy
service_wait_dependencies_healthy() {
    local service_name="$1"
    local timeout="${2:-300}"
    local deps
    deps=$(service_get_dependencies "$service_name")

    if [[ -z "$deps" ]]; then
        log_debug "Service '$service_name' has no dependencies to wait for"
        return 0
    fi

    log_info "Waiting for dependencies of '$service_name' to be healthy: $deps"

    for dep in $deps; do
        local dep_display_name
        dep_display_name=$(service_get_display_name "$dep")
        log_info "Waiting for dependency: $dep_display_name"

        if ! service_wait_healthy "$dep" "$timeout"; then
            log_error "Dependency '$dep_display_name' failed to become healthy"
            return 1
        fi
    done

    log_success "All dependencies for '$service_name' are healthy"
    return 0
}

# =============================================================================
# Debug and Utility Functions
# =============================================================================

# Debug service information
service_debug() {
    local service_name="$1"
    local display_name
    display_name=$(service_get_display_name "$service_name")

    log_info "$display_name Service Debug Information:"
    echo "========================================"

    echo "Service Name: $service_name"
    echo "Display Name: $display_name"
    echo "Directory: $(service_get_directory "$service_name")"
    echo "Command: $(service_get_command "$service_name")"
    echo "Port: $(service_get_port "$service_name")"
    echo "Timeout: $(service_get_timeout "$service_name")"
    echo "Health URL: $(service_get_health_url "$service_name")"
    echo "Dependencies: $(service_get_dependencies "$service_name")"
    echo ""

    echo "URLs:"
    echo "Service URL: $(service_get_url "$service_name")"
    local health_url
    health_url=$(service_get_health_url "$service_name")
    if [[ -n "$health_url" ]]; then
        echo "Health URL: $health_url"
    fi
    echo ""

    echo "Running Status:"
    if service_is_running "$service_name"; then
        echo "Status: Running"
        echo "Health: $(service_health "$service_name" >/dev/null 2>&1 && echo "Healthy" || echo "Unhealthy")"
        echo ""
        echo "Process Information:"
        service_get_processes "$service_name" || echo "No process information available"
    else
        echo "Status: Not Running"
    fi
}

# List all available services with status
service_list_all() {
    log_info "Available Services:"
    echo "=================="

    local services
    if services=$(service_discover_all 2>/dev/null); then
        for service in $services; do
            local display_name icon
            display_name=$(service_get_display_name "$service" 2>/dev/null || echo "$service")

            # Get icon based on service type or name pattern
            case "$service" in
                *firebase*) icon="🔥" ;;
                *api*) icon="🔌" ;;
                *webapp*|*web*) icon="🌐" ;;
                *app*|*mobile*) icon="📱" ;;
                *metro*|*bundler*) icon="📦" ;;
                *) icon="🔧" ;;
            esac

            local status_icon
            if service_is_running "$service" 2>/dev/null; then
                if service_health "$service" >/dev/null 2>&1; then
                    status_icon="✅"
                else
                    status_icon="⚠️"
                fi
            else
                status_icon="❌"
            fi

            local port
            port=$(service_get_port "$service" 2>/dev/null || echo "")

            echo "  $status_icon $icon $display_name ($service)${port:+ - port $port}"
        done
    else
        log_error "Could not discover services - YAML configuration not available"
        return 1
    fi
}

# List all available service names (for scripting)
service_list_names() {
    if yaml_check_dependencies >/dev/null 2>&1; then
        yaml_get_all_services
    else
        log_error "YAML dependencies not available - cannot list services"
        return 1
    fi
}

# Validate service exists in configuration
service_validate() {
    local service_name="$1"

    if ! service_get_config "$service_name" >/dev/null 2>&1; then
        log_error "Service '$service_name' not found in configuration"

        # Show available services as help
        local available_services
        if available_services=$(service_discover_all 2>/dev/null); then
            log_info "Available services: $available_services"
        fi

        return 1
    fi

    return 0
}

# Get service type from configuration
service_get_type() {
    local service_name="$1"
    service_get_property "$service_name" "type" "unknown"
}

# Get service icon from configuration
service_get_icon() {
    local service_name="$1"
    local configured_icon
    configured_icon=$(service_get_property "$service_name" "icon" "")

    if [[ -n "$configured_icon" ]]; then
        echo "$configured_icon"
    else
        # Fallback to type-based or name-based icon
        local service_type
        service_type=$(service_get_type "$service_name")

        case "$service_type" in
            api) echo "🔌" ;;
            webapp) echo "🌐" ;;
            emulator-suite) echo "🔥" ;;
            mobile-app) echo "📱" ;;
            bundler) echo "📦" ;;
            *)
                case "$service_name" in
                    *firebase*) echo "🔥" ;;
                    *api*) echo "🔌" ;;
                    *webapp*|*web*) echo "🌐" ;;
                    *app*|*mobile*) echo "📱" ;;
                    *metro*|*bundler*) echo "📦" ;;
                    *) echo "🔧" ;;
                esac
                ;;
        esac
    fi
}

# Initialize service system
service_init() {
    log_debug "Initializing generic service system..."

    # Initialize service discovery
    service_init_discovery

    log_debug "Generic service system initialized"
    return 0
}

# Initialize service system when module loads
service_init