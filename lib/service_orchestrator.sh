#!/bin/bash
# Generic Service Orchestrator
# Manages service lifecycle, dependencies, and composite environments
# Replaces hardcoded orchestration modules

set -euo pipefail

# Module initialization guard
if [[ "${SERVICE_ORCHESTRATOR_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly SERVICE_ORCHESTRATOR_LOADED="true"

# Load dependencies
readonly ORCHESTRATOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$ORCHESTRATOR_LIB_DIR/config.sh"
# shellcheck source=lib/logging.sh
source "$ORCHESTRATOR_LIB_DIR/logging.sh"
# shellcheck source=lib/service.sh
source "$ORCHESTRATOR_LIB_DIR/service.sh"
# shellcheck source=lib/yaml.sh
source "$ORCHESTRATOR_LIB_DIR/yaml.sh"

# Ensure configuration is loaded
config_load_defaults

# =============================================================================
# Service Orchestration Functions
# =============================================================================

# Start a single service with dependency resolution
orchestrator_start_service() {
    local service_name="$1"

    if ! service_validate "$service_name"; then
        return 1
    fi

    local display_name
    display_name=$(service_get_display_name "$service_name")

    # Check if service is already running
    if service_is_running "$service_name"; then
        log_warn "$display_name is already running"
        return 0
    fi

    # Wait for dependencies to be healthy
    log_debug "Checking dependencies for $service_name"
    if ! service_wait_dependencies_healthy "$service_name" 300; then
        log_error "Dependencies for $display_name are not healthy"
        return 1
    fi

    # Start the service
    log_info "Starting $display_name..."
    service_start "$service_name"
}

# Stop a single service
orchestrator_stop_service() {
    local service_name="$1"

    if ! service_validate "$service_name"; then
        return 1
    fi

    local display_name
    display_name=$(service_get_display_name "$service_name")

    if ! service_is_running "$service_name"; then
        log_warn "$display_name is not running"
        return 0
    fi

    service_stop "$service_name"
}

# Get status of a single service
orchestrator_status_service() {
    local service_name="$1"

    if ! service_validate "$service_name"; then
        return 1
    fi

    service_status "$service_name"
}

# =============================================================================
# Composite Environment Functions
# =============================================================================

# Start a composite environment (multiple services with dependency resolution)
orchestrator_start_composite() {
    local composite_name="$1"

    log_step "Starting $composite_name Environment"

    # Get composite services from configuration
    local services
    services=$(yaml_get_composite_services "$composite_name" 2>/dev/null) || {
        log_error "Composite environment '$composite_name' not found in configuration"
        log_error "Available composite environments: $(yaml_get_composite_names 2>/dev/null || echo 'none configured')"
        return 1
    }

    if [[ -z "$services" ]]; then
        log_error "No services defined for composite environment: $composite_name"
        return 1
    fi

    log_info "Composite services: $services"

    # Resolve startup order based on dependencies
    local ordered_services
    if yaml_check_dependencies >/dev/null 2>&1; then
        ordered_services=$(yaml_resolve_startup_order "$services" 2>/dev/null) || {
            log_warn "Could not resolve startup order, using original order"
            ordered_services="$services"
        }
    else
        ordered_services="$services"
    fi

    log_debug "Service startup order: $ordered_services"

    # Start services in dependency order
    local started_services=()
    local failed_service=""

    for service in $ordered_services; do
        log_info "Starting service: $(service_get_display_name "$service")"

        if orchestrator_start_service "$service"; then
            started_services+=("$service")

            # Wait for service to be healthy before starting next
            if ! service_wait_healthy "$service" 120; then
                log_error "Service $(service_get_display_name "$service") failed to become healthy"
                failed_service="$service"
                break
            fi
        else
            log_error "Failed to start service: $(service_get_display_name "$service")"
            failed_service="$service"
            break
        fi
    done

    # If any service failed, rollback started services
    if [[ -n "$failed_service" ]]; then
        log_error "$composite_name environment startup failed at: $(service_get_display_name "$failed_service")"
        log_info "Rolling back started services..."

        # Stop services in reverse order
        for ((i=${#started_services[@]}-1; i>=0; i--)); do
            local rollback_service="${started_services[i]}"
            log_info "Stopping $(service_get_display_name "$rollback_service") (rollback)"
            service_stop "$rollback_service" || true
        done

        return 1
    fi

    # Show success information
    log_success "$composite_name environment started successfully!"
    echo ""
    orchestrator_show_composite_info "$composite_name" "$services"
    return 0
}

# Stop a composite environment
orchestrator_stop_composite() {
    local composite_name="$1"

    log_step "Stopping $composite_name Environment"

    # Get composite services from configuration
    local services
    services=$(yaml_get_composite_services "$composite_name" 2>/dev/null) || {
        log_error "Composite environment '$composite_name' not found in configuration"
        log_error "Available composite environments: $(yaml_get_composite_names 2>/dev/null || echo 'none configured')"
        return 1
    }

    if [[ -z "$services" ]]; then
        log_error "No services defined for composite environment: $composite_name"
        return 1
    fi

    # Stop services in reverse order to respect dependencies
    local services_array=($services)
    for ((i=${#services_array[@]}-1; i>=0; i--)); do
        local service="${services_array[i]}"
        local display_name
        display_name=$(service_get_display_name "$service")

        if service_is_running "$service"; then
            log_info "Stopping $display_name..."
            service_stop "$service" || true
        else
            log_debug "$display_name is not running"
        fi
    done

    log_success "$composite_name environment stopped"
    return 0
}

# Get status of composite environment
orchestrator_status_composite() {
    local composite_name="$1"

    # Get composite services from configuration
    local services
    services=$(yaml_get_composite_services "$composite_name" 2>/dev/null) || {
        log_error "Composite environment '$composite_name' not found in configuration"
        log_error "Available composite environments: $(yaml_get_composite_names 2>/dev/null || echo 'none configured')"
        return 1
    }

    if [[ -z "$services" ]]; then
        log_error "No services defined for composite environment: $composite_name"
        return 1
    fi

    echo -e "${COLOR_BLUE}${composite_name^} Environment Status:${COLOR_NC}"
    echo "==============================="

    local running_count=0
    local total_count=0

    for service in $services; do
        total_count=$((total_count + 1))
        if service_status "$service"; then
            running_count=$((running_count + 1))
        fi
    done

    echo ""
    if [[ $running_count -eq $total_count ]]; then
        echo -e "${COLOR_GREEN}✅ $composite_name environment: All services running ($running_count/$total_count)${COLOR_NC}"
        return 0
    elif [[ $running_count -gt 0 ]]; then
        echo -e "${COLOR_YELLOW}⚠️  $composite_name environment: Partially running ($running_count/$total_count)${COLOR_NC}"
        return 1
    else
        echo -e "${COLOR_RED}❌ $composite_name environment: No services running ($running_count/$total_count)${COLOR_NC}"
        return 2
    fi
}

# =============================================================================
# Information Display Functions
# =============================================================================

# Show composite environment information
orchestrator_show_composite_info() {
    local composite_name="$1"
    local services="$2"

    echo -e "${COLOR_BLUE}🎯 $composite_name Environment URLs:${COLOR_NC}"

    for service in $services; do
        local display_name url
        display_name=$(service_get_display_name "$service")
        url=$(service_get_url "$service")

        if [[ "$url" != "N/A"* ]]; then
            # Get appropriate icon
            local icon="🔧"
            case "$service" in
                *firebase*) icon="🔥" ;;
                *api*) icon="🔌" ;;
                *webapp*|*web*) icon="🌐" ;;
                *app*|*mobile*) icon="📱" ;;
                *metro*) icon="📦" ;;
                *react*) icon="⚛️" ;;
            esac

            echo -e "  $icon $display_name: $url"
        fi
    done

    echo -e "\n${COLOR_BLUE}Management Commands:${COLOR_NC}"
    echo -e "  To stop:        ${CLI_INVOKED_AS:-${CLI_NAME:-custom-cli}} stop $composite_name"
    echo -e "  Check status:   ${CLI_INVOKED_AS:-${CLI_NAME:-custom-cli}} status $composite_name"
    echo -e "  View logs:      ${CLI_INVOKED_AS:-${CLI_NAME:-custom-cli}} logs"
}

# =============================================================================
# Utility Functions
# =============================================================================

# List all available services
orchestrator_list_services() {
    yaml_get_all_services 2>/dev/null || {
        log_warn "Could not load services from configuration"
        echo ""
    }
}

# List all available composite environments
orchestrator_list_composites() {
    yaml_get_composite_names 2>/dev/null || {
        log_warn "Could not load composite environments from configuration"
        echo ""
    }
}

# Check if target is a service or composite
orchestrator_get_target_type() {
    local target="$1"

    # Check if it's a composite first
    local composites
    composites=$(orchestrator_list_composites)
    for composite in $composites; do
        if [[ "$target" == "$composite" ]]; then
            echo "composite"
            return 0
        fi
    done

    # Check if it's a service
    local services
    services=$(orchestrator_list_services)
    for service in $services; do
        if [[ "$target" == "$service" ]]; then
            echo "service"
            return 0
        fi
    done

    echo "unknown"
    return 1
}

# Main orchestration entry point
orchestrator_execute() {
    local action="$1"
    local target="$2"

    local target_type
    target_type=$(orchestrator_get_target_type "$target")

    if [[ "$target_type" == "unknown" ]]; then
        log_error "Unknown service or environment: $target"
        log_info "Available services: $(orchestrator_list_services)"
        log_info "Available environments: $(orchestrator_list_composites)"
        return 1
    fi

    case "$action" in
        start)
            if [[ "$target_type" == "composite" ]]; then
                orchestrator_start_composite "$target"
            else
                orchestrator_start_service "$target"
            fi
            ;;
        stop)
            if [[ "$target_type" == "composite" ]]; then
                orchestrator_stop_composite "$target"
            else
                orchestrator_stop_service "$target"
            fi
            ;;
        status)
            if [[ "$target_type" == "composite" ]]; then
                orchestrator_status_composite "$target"
            else
                orchestrator_status_service "$target"
            fi
            ;;
        restart)
            if [[ "$target_type" == "composite" ]]; then
                orchestrator_stop_composite "$target"
                sleep 2
                orchestrator_start_composite "$target"
            else
                service_restart "$target"
            fi
            ;;
        *)
            log_error "Unknown action: $action"
            return 1
            ;;
    esac
}