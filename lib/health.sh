#!/bin/bash
# Health Check Module
# Provides sophisticated health checking with retry logic and custom timeouts

set -euo pipefail

# Module initialization guard
if [[ "${HEALTH_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly HEALTH_MODULE_LOADED="true"

# Load dependencies
readonly HEALTH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$HEALTH_LIB_DIR/config.sh"
# shellcheck source=lib/logging.sh
source "$HEALTH_LIB_DIR/logging.sh"
# shellcheck source=lib/process.sh
source "$HEALTH_LIB_DIR/process.sh"

# Ensure configuration is loaded
config_load_defaults

# Health check result constants
readonly HEALTH_OK=0
readonly HEALTH_WARNING=1
readonly HEALTH_CRITICAL=2
readonly HEALTH_UNKNOWN=3

# =============================================================================
# Private Functions
# =============================================================================

# Get health status name
_health_status_name() {
    case "$1" in
        "$HEALTH_OK") echo "OK" ;;
        "$HEALTH_WARNING") echo "WARNING" ;;
        "$HEALTH_CRITICAL") echo "CRITICAL" ;;
        "$HEALTH_UNKNOWN") echo "UNKNOWN" ;;
        *) echo "INVALID" ;;
    esac
}

# Get health status color
_health_status_color() {
    case "$1" in
        "$HEALTH_OK") echo "$COLOR_GREEN" ;;
        "$HEALTH_WARNING") echo "$COLOR_YELLOW" ;;
        "$HEALTH_CRITICAL") echo "$COLOR_RED" ;;
        "$HEALTH_UNKNOWN") echo "$COLOR_BLUE" ;;
        *) echo "$COLOR_NC" ;;
    esac
}

# Get health status icon
_health_status_icon() {
    case "$1" in
        "$HEALTH_OK") echo "$ICON_SUCCESS" ;;
        "$HEALTH_WARNING") echo "$ICON_WARNING" ;;
        "$HEALTH_CRITICAL") echo "$ICON_ERROR" ;;
        "$HEALTH_UNKNOWN") echo "$ICON_INFO" ;;
        *) echo "?" ;;
    esac
}

# Retry function with exponential backoff
_health_retry_with_backoff() {
    local max_attempts="$1"
    local initial_delay="$2"
    local command="$3"
    local attempt=1
    local delay="$initial_delay"
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Health check attempt $attempt/$max_attempts: $command"
        
        if eval "$command"; then
            log_debug "Health check succeeded on attempt $attempt"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_debug "Health check failed after $max_attempts attempts"
            return 1
        fi
        
        log_debug "Health check failed, retrying in ${delay}s..."
        sleep "$delay"
        delay=$((delay * 2))  # Exponential backoff
        attempt=$((attempt + 1))
    done
    
    return 1
}

# =============================================================================
# Port Health Checks
# =============================================================================

# Basic port health check
health_check_port() {
    local name="$1"
    local port="$2"
    local timeout="${3:-5}"
    
    local start_time=$(date +%s)
    
    if process_is_port_in_use "$port"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_debug "Port $port health check: OK (${duration}s)"
        return $HEALTH_OK
    else
        log_debug "Port $port health check: CRITICAL (not listening)"
        return $HEALTH_CRITICAL
    fi
}

# Port health check with retry
health_check_port_with_retry() {
    local name="$1"
    local port="$2"
    local timeout="${3:-30}"
    local retry_count="${4:-3}"
    local retry_delay="${5:-2}"
    
    log_debug "Checking $name port health with retry (port: $port, timeout: ${timeout}s, retries: $retry_count)"
    
    if _health_retry_with_backoff "$retry_count" "$retry_delay" "health_check_port '$name' '$port' '$timeout'"; then
        return $HEALTH_OK
    else
        return $HEALTH_CRITICAL
    fi
}

# =============================================================================
# HTTP Health Checks
# =============================================================================

# Basic HTTP health check
health_check_http() {
    local name="$1"
    local url="$2"
    local timeout="${3:-5}"
    local expected_status="${4:-200}"
    
    local start_time=$(date +%s)
    log_debug "HTTP health check: $name -> $url (timeout: ${timeout}s, expected: $expected_status)"
    
    # Use curl with specific options for health checking
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$timeout" --connect-timeout 2 "$url" 2>/dev/null || echo "000")
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    case "$response_code" in
        "$expected_status")
            log_debug "$name HTTP health check: OK ($response_code, ${duration}s)"
            return $HEALTH_OK
            ;;
        "000")
            log_debug "$name HTTP health check: CRITICAL (connection failed, ${duration}s)"
            return $HEALTH_CRITICAL
            ;;
        4*)
            log_debug "$name HTTP health check: WARNING (client error $response_code, ${duration}s)"
            return $HEALTH_WARNING
            ;;
        5*)
            log_debug "$name HTTP health check: CRITICAL (server error $response_code, ${duration}s)"
            return $HEALTH_CRITICAL
            ;;
        *)
            log_debug "$name HTTP health check: WARNING (unexpected status $response_code, ${duration}s)"
            return $HEALTH_WARNING
            ;;
    esac
}

# HTTP health check with retry
health_check_http_with_retry() {
    local name="$1"
    local url="$2"
    local timeout="${3:-5}"
    local expected_status="${4:-200}"
    local retry_count="${5:-3}"
    local retry_delay="${6:-2}"
    
    log_debug "Checking $name HTTP health with retry (url: $url, timeout: ${timeout}s, retries: $retry_count)"
    
    if _health_retry_with_backoff "$retry_count" "$retry_delay" "health_check_http '$name' '$url' '$timeout' '$expected_status'"; then
        return $HEALTH_OK
    else
        return $HEALTH_CRITICAL
    fi
}

# Advanced HTTP health check with response validation
health_check_http_advanced() {
    local name="$1"
    local url="$2"
    local timeout="${3:-5}"
    local expected_status="${4:-200}"
    local expected_content="${5:-}"
    
    local start_time=$(date +%s)
    local temp_file="/tmp/health_check_$$"
    
    log_debug "Advanced HTTP health check: $name -> $url"
    
    # Get response with headers and body
    local response_code
    response_code=$(curl -s -w "%{http_code}" --max-time "$timeout" --connect-timeout 2 -o "$temp_file" "$url" 2>/dev/null || echo "000")
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Clean up temp file on exit
    trap "rm -f '$temp_file'" EXIT
    
    # Check status code first
    if [[ "$response_code" != "$expected_status" ]]; then
        rm -f "$temp_file"
        case "$response_code" in
            "000")
                log_debug "$name advanced HTTP health check: CRITICAL (connection failed, ${duration}s)"
                return $HEALTH_CRITICAL
                ;;
            4*|5*)
                log_debug "$name advanced HTTP health check: CRITICAL (HTTP $response_code, ${duration}s)"
                return $HEALTH_CRITICAL
                ;;
            *)
                log_debug "$name advanced HTTP health check: WARNING (unexpected status $response_code, ${duration}s)"
                return $HEALTH_WARNING
                ;;
        esac
    fi
    
    # Check content if expected content provided
    if [[ -n "$expected_content" ]] && [[ -f "$temp_file" ]]; then
        if grep -q "$expected_content" "$temp_file"; then
            log_debug "$name advanced HTTP health check: OK (content match, ${duration}s)"
        else
            log_debug "$name advanced HTTP health check: WARNING (content mismatch, ${duration}s)"
            rm -f "$temp_file"
            return $HEALTH_WARNING
        fi
    fi
    
    rm -f "$temp_file"
    log_debug "$name advanced HTTP health check: OK (${duration}s)"
    return $HEALTH_OK
}

# =============================================================================
# Service Health Checks
# =============================================================================

# Check service health using configuration
health_check_service() {
    local service_name="$1"
    local retry_count="${2:-1}"
    local retry_delay="${3:-2}"
    
    log_debug "Checking service health: $service_name"
    
    # Get service configuration
    local service_config
    service_config=$(config_get_service "$service_name") || {
        log_error "Unknown service: $service_name"
        return $HEALTH_UNKNOWN
    }
    
    # Parse configuration
    local port="" health_url="" timeout="" display_name=""
    while IFS='=' read -r key value; do
        case "$key" in
            PORT) port="$value" ;;
            HEALTH_URL) health_url="$value" ;;
            TIMEOUT) timeout="$value" ;;
            DISPLAY_NAME) display_name="$value" ;;
        esac
    done <<< "$service_config"
    
    # Default values
    timeout="${timeout:-30}"
    display_name="${display_name:-$service_name}"
    
    log_debug "Service $service_name: port=$port, health_url=$health_url, timeout=$timeout"
    
    # Choose appropriate health check method
    if [[ -n "$health_url" ]]; then
        # HTTP health check
        health_check_http_with_retry "$display_name" "$health_url" 5 200 "$retry_count" "$retry_delay"
    elif [[ -n "$port" ]]; then
        # Port health check
        health_check_port_with_retry "$display_name" "$port" "$timeout" "$retry_count" "$retry_delay"
    else
        log_error "Service $service_name has no port or health URL configured"
        return $HEALTH_UNKNOWN
    fi
}

# =============================================================================
# Composite Health Checks
# =============================================================================

# Check health of multiple services
health_check_services() {
    local services="$1"
    local retry_count="${2:-1}"
    local retry_delay="${3:-2}"
    
    local overall_status=$HEALTH_OK
    local failed_services=()
    local warning_services=()
    
    for service in $services; do
        local status
        status=$(health_check_service "$service" "$retry_count" "$retry_delay")
        local result=$?
        
        case $result in
            $HEALTH_OK)
                log_debug "Service $service: healthy"
                ;;
            $HEALTH_WARNING)
                log_debug "Service $service: warning"
                warning_services+=("$service")
                if [[ $overall_status -eq $HEALTH_OK ]]; then
                    overall_status=$HEALTH_WARNING
                fi
                ;;
            $HEALTH_CRITICAL)
                log_debug "Service $service: critical"
                failed_services+=("$service")
                overall_status=$HEALTH_CRITICAL
                ;;
            *)
                log_debug "Service $service: unknown"
                failed_services+=("$service")
                if [[ $overall_status -ne $HEALTH_CRITICAL ]]; then
                    overall_status=$HEALTH_UNKNOWN
                fi
                ;;
        esac
    done
    
    # Report results
    if [[ ${#failed_services[@]} -gt 0 ]]; then
        log_warn "Failed services: ${failed_services[*]}"
    fi
    
    if [[ ${#warning_services[@]} -gt 0 ]]; then
        log_warn "Services with warnings: ${warning_services[*]}"
    fi
    
    return $overall_status
}

# =============================================================================
# Health Check Reporting
# =============================================================================

# Display health status with formatting
health_display_status() {
    local name="$1"
    local status="$2"
    local details="${3:-}"
    
    local status_name="$(_health_status_name "$status")"
    local color="$(_health_status_color "$status")"
    local icon="$(_health_status_icon "$status")"
    
    if [[ -n "$details" ]]; then
        echo -e "  ${name}: ${color}${icon} ${status_name}${COLOR_NC} - $details"
    else
        echo -e "  ${name}: ${color}${icon} ${status_name}${COLOR_NC}"
    fi
}

# Run comprehensive health check for a service and display results
health_check_and_display() {
    local service_name="$1"
    local retry_count="${2:-3}"
    local retry_delay="${3:-2}"
    
    log_debug "Running comprehensive health check for: $service_name"
    
    # Get service configuration
    local service_config
    service_config=$(config_get_service "$service_name") || {
        health_display_status "$service_name" "$HEALTH_UNKNOWN" "Service not found"
        return $HEALTH_UNKNOWN
    }
    
    # Parse configuration
    local port="" health_url="" display_name=""
    while IFS='=' read -r key value; do
        case "$key" in
            PORT) port="$value" ;;
            HEALTH_URL) health_url="$value" ;;
            DISPLAY_NAME) display_name="$value" ;;
        esac
    done <<< "$service_config"
    
    display_name="${display_name:-$service_name}"
    
    # Run health check
    local start_time=$(date +%s)
    local status
    if [[ -n "$health_url" ]]; then
        health_check_http_with_retry "$display_name" "$health_url" 5 200 "$retry_count" "$retry_delay"
        status=$?
    elif [[ -n "$port" ]]; then
        health_check_port_with_retry "$display_name" "$port" 30 "$retry_count" "$retry_delay"
        status=$?
    else
        status=$HEALTH_UNKNOWN
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Display result with timing
    local details=""
    if [[ -n "$port" ]]; then
        details="port $port"
    fi
    if [[ -n "$health_url" ]]; then
        details="${details:+$details, }HTTP endpoint"
    fi
    details="${details} (${duration}s)"
    
    health_display_status "$display_name" "$status" "$details"
    return $status
}

# =============================================================================
# Wait Functions with Health Checks
# =============================================================================

# Wait for service to become healthy
health_wait_for_service() {
    local service_name="$1"
    local timeout="${2:-60}"
    local check_interval="${3:-5}"
    
    log_info "Waiting for $service_name to become healthy (timeout: ${timeout}s)"
    
    local counter=0
    while [[ $counter -lt $timeout ]]; do
        if health_check_service "$service_name" 1 1; then
            log_success "$service_name is healthy"
            return 0
        fi
        
        log_debug "Service $service_name not yet healthy, waiting..."
        sleep "$check_interval"
        counter=$((counter + check_interval))
    done
    
    log_error "$service_name failed to become healthy within ${timeout}s"
    return 1
}

# =============================================================================
# Utility Functions
# =============================================================================

# Get health check metrics for monitoring
health_get_metrics() {
    local service_name="$1"
    
    local start_time=$(date +%s)
    local status
    status=$(health_check_service "$service_name" 1 0)
    local result=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "service=$service_name status=$(_health_status_name "$result") duration=${duration}s timestamp=$start_time"
}

# Debug: Show health module status
health_debug_info() {
    log_debug "Health check module loaded"
    log_debug "Available functions: port checks, HTTP checks, service checks, composite checks"
    log_debug "Health status codes: OK=$HEALTH_OK, WARNING=$HEALTH_WARNING, CRITICAL=$HEALTH_CRITICAL, UNKNOWN=$HEALTH_UNKNOWN"
}