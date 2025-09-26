#!/bin/bash
# Process Management Module
# Provides process lifecycle management, port operations, and monitoring

set -euo pipefail

# Module initialization guard
if [[ "${PROCESS_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly PROCESS_MODULE_LOADED="true"

# Load dependencies
readonly PROCESS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config.sh
source "$PROCESS_LIB_DIR/config.sh"
# shellcheck source=lib/logging.sh
source "$PROCESS_LIB_DIR/logging.sh"

# Ensure configuration is loaded
config_load_defaults

# =============================================================================
# Private Functions
# =============================================================================

# Get PIDs for processes listening on a port
_get_pids_by_port() {
    local port="$1"
    lsof -ti:"$port" 2>/dev/null || true
}

# Get PIDs by process pattern
_get_pids_by_pattern() {
    local pattern="$1"
    pgrep -f "$pattern" 2>/dev/null || true
}

# Check if a process is still running
_is_process_running() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

# Wait for process to exit with timeout
_wait_for_process_exit() {
    local pid="$1"
    local timeout="${2:-10}"
    local counter=0
    
    while [[ $counter -lt $timeout ]]; do
        if ! _is_process_running "$pid"; then
            return 0
        fi
        sleep 1
        counter=$((counter + 1))
    done
    
    return 1  # Timeout
}

# =============================================================================
# Port Management
# =============================================================================

# Check if a port is in use
process_is_port_in_use() {
    local port="$1"
    [[ -n "$(_get_pids_by_port "$port")" ]]
}

# Get process information for a port
process_get_port_info() {
    local port="$1"
    
    if ! process_is_port_in_use "$port"; then
        return 1
    fi
    
    # Get detailed process information
    lsof -ti:"$port" 2>/dev/null | while read -r pid; do
        if [[ -n "$pid" ]]; then
            local cmd=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            local args=$(ps -p "$pid" -o args= 2>/dev/null || echo "")
            echo "PID=$pid COMMAND=$cmd ARGS=$args"
        fi
    done
}

# Kill processes on a specific port
process_kill_port() {
    local port="$1"
    local signal="${2:-TERM}"
    local timeout="${3:-10}"
    
    local pids="$(_get_pids_by_port "$port")"
    if [[ -z "$pids" ]]; then
        log_debug "No processes found on port $port"
        return 0
    fi
    
    log_info "Killing processes on port $port (PIDs: $pids)"
    
    # First try graceful termination
    if [[ "$signal" == "TERM" ]]; then
        # Try killing individual processes first
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        
        # Also try killing process groups in case they were started with setsid
        for pid in $pids; do
            kill -TERM "-$pid" 2>/dev/null || true
        done
        
        # Wait for graceful shutdown
        local all_stopped=true
        for pid in $pids; do
            if ! _wait_for_process_exit "$pid" "$timeout"; then
                log_warn "Process $pid did not exit gracefully, using KILL"
                kill -KILL "$pid" 2>/dev/null || true
                kill -KILL "-$pid" 2>/dev/null || true  # Kill process group too
                all_stopped=false
            fi
        done
        
        if [[ "$all_stopped" == "true" ]]; then
            log_debug "All processes on port $port terminated gracefully"
        fi
    else
        # Direct signal - try both individual process and process group
        echo "$pids" | xargs kill "-$signal" 2>/dev/null || true
        for pid in $pids; do
            kill "-$signal" "-$pid" 2>/dev/null || true
        done
    fi
    
    # Verify processes are gone
    sleep 1
    if process_is_port_in_use "$port"; then
        log_warn "Some processes may still be running on port $port"
        return 1
    fi
    
    log_info "Successfully killed processes on port $port"
    return 0
}

# Kill multiple ports
process_kill_ports() {
    local ports="$1"
    local signal="${2:-TERM}"
    local timeout="${3:-10}"
    
    local failed_ports=()
    
    for port in $ports; do
        if ! process_kill_port "$port" "$signal" "$timeout"; then
            failed_ports+=("$port")
        fi
    done
    
    if [[ ${#failed_ports[@]} -gt 0 ]]; then
        log_error "Failed to kill processes on ports: ${failed_ports[*]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Process Pattern Management
# =============================================================================

# Kill processes by pattern
process_kill_pattern() {
    local pattern="$1"
    local signal="${2:-TERM}"
    local timeout="${3:-10}"
    
    local pids="$(_get_pids_by_pattern "$pattern")"
    if [[ -z "$pids" ]]; then
        log_debug "No processes found matching pattern: $pattern"
        return 0
    fi
    
    log_info "Killing processes matching pattern '$pattern' (PIDs: $pids)"
    
    # First try graceful termination
    if [[ "$signal" == "TERM" ]]; then
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        
        # Wait for graceful shutdown
        local all_stopped=true
        for pid in $pids; do
            if ! _wait_for_process_exit "$pid" "$timeout"; then
                log_warn "Process $pid did not exit gracefully, using KILL"
                kill -KILL "$pid" 2>/dev/null || true
                all_stopped=false
            fi
        done
        
        if [[ "$all_stopped" == "true" ]]; then
            log_debug "All processes matching '$pattern' terminated gracefully"
        fi
    else
        # Direct signal
        echo "$pids" | xargs kill "-$signal" 2>/dev/null || true
    fi
    
    # Verify processes are gone
    sleep 1
    local remaining_pids="$(_get_pids_by_pattern "$pattern")"
    if [[ -n "$remaining_pids" ]]; then
        log_warn "Some processes matching '$pattern' may still be running (PIDs: $remaining_pids)"
        return 1
    fi
    
    log_info "Successfully killed processes matching pattern: $pattern"
    return 0
}

# Kill processes by multiple patterns
process_kill_patterns() {
    local patterns="$1"
    local signal="${2:-TERM}"
    local timeout="${3:-10}"
    
    local failed_patterns=()
    
    # Split patterns by space and process each
    echo "$patterns" | tr ' ' '\n' | while read -r pattern; do
        if [[ -n "$pattern" ]] && ! process_kill_pattern "$pattern" "$signal" "$timeout"; then
            failed_patterns+=("$pattern")
        fi
    done
    
    if [[ ${#failed_patterns[@]} -gt 0 ]]; then
        log_error "Failed to kill processes for patterns: ${failed_patterns[*]}"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Background Process Management
# =============================================================================

# Start a background process with logging
process_start_background() {
    local name="$1"
    local command="$2"
    local working_dir="$3"
    local log_file="${4:-}"
    
    log_debug "Starting background process: $name"
    log_debug "Command: $command"
    log_debug "Working directory: $working_dir"
    
    # Validate working directory
    if [[ ! -d "$working_dir" ]]; then
        log_error "Working directory does not exist: $working_dir"
        return 1
    fi
    
    # Change to working directory
    cd "$working_dir"
    
    # Create or use provided log file
    if [[ -z "$log_file" ]]; then
        log_file=$(log_create_service_file "$name" "$command" "$working_dir")
    fi
    
    # Start process in background with proper file descriptor management
    log_info "Starting $name in background..."
    
    # EBADF Fix: Use a cross-platform approach to avoid EBADF (bad file descriptor) errors
    # The issue was that nohup with direct redirection can cause file descriptor inheritance
    # problems when the parent process exits, leading to EBADF errors in child processes.
    # 
    # Solution: Create a temporary wrapper script that explicitly manages file descriptors:
    # - stdin redirected to /dev/null
    # - stdout/stderr redirected to log file
    # - Uses exec to replace the wrapper process with the actual command
    # 
    # This approach works on both macOS and Linux without requiring setsid or other platform-specific commands.
    local wrapper_script="$(mktemp)"
    
    # Write the wrapper script
    cat > "$wrapper_script" << 'EOF'
#!/bin/bash
# Process wrapper to handle file descriptors safely
exec 0</dev/null
exec 1>>"$1"
exec 2>&1
shift
exec "$@"
EOF
    
    chmod +x "$wrapper_script"
    
    # Start the process using the wrapper
    nohup bash "$wrapper_script" "$log_file" bash -c "$command" >/dev/null 2>&1 &
    
    local pid=$!
    
    # Clean up the temporary wrapper script after a moment
    # (giving it time to be executed by nohup)
    ( sleep 3; rm -f "$wrapper_script" ) &
    
    # Give process a moment to start
    sleep 2
    
    # Verify process is still running
    if ! _is_process_running "$pid"; then
        log_error "Background process $name (PID $pid) failed to start or exited immediately"
        log_error "Check log file: $log_file"
        # Clean up immediately on failure
        rm -f "$wrapper_script"
        return 1
    fi
    
    log_info "Background process $name started successfully (PID: $pid)"
    log_debug "Log file: $log_file"
    
    # Return the PID for tracking
    echo "$pid"
    return 0
}

# =============================================================================
# Service Waiting Functions
# =============================================================================

# Wait for a port to become available (service to start)
process_wait_for_port() {
    local name="$1"
    local port="$2"
    local timeout="${3:-30}"
    local counter=0
    
    log_debug "Waiting for $name on port $port (timeout: ${timeout}s)"
    echo -n "  Waiting for $name to be ready..."
    
    while [[ $counter -lt $timeout ]]; do
        if process_is_port_in_use "$port"; then
            echo -e " ${COLOR_GREEN}${ICON_SUCCESS}${COLOR_NC}"
            log_debug "$name is ready on port $port"
            return 0
        fi
        sleep 1
        counter=$((counter + 1))
        echo -n "."
    done
    
    echo -e " ${COLOR_RED}${ICON_ERROR} (timeout)${COLOR_NC}"
    log_error "$name failed to start on port $port within ${timeout}s"
    return 1
}

# Wait for an HTTP endpoint to become available
process_wait_for_http() {
    local name="$1"
    local url="$2"
    local timeout="${3:-30}"
    local counter=0
    
    log_debug "Waiting for $name HTTP endpoint: $url (timeout: ${timeout}s)"
    echo -n "  Waiting for $name HTTP endpoint to be ready..."
    
    while [[ $counter -lt $timeout ]]; do
        if curl -s --max-time 2 "$url" > /dev/null 2>&1; then
            echo -e " ${COLOR_GREEN}${ICON_SUCCESS}${COLOR_NC}"
            log_debug "$name HTTP endpoint is ready: $url"
            return 0
        fi
        sleep 1
        counter=$((counter + 1))
        echo -n "."
    done
    
    echo -e " ${COLOR_RED}${ICON_ERROR} (timeout)${COLOR_NC}"
    log_error "$name HTTP endpoint failed to respond within ${timeout}s: $url"
    return 1
}

# =============================================================================
# Process Monitoring
# =============================================================================

# Check if a service is running by port
process_check_service_by_port() {
    local name="$1"
    local port="$2"
    local health_url="${3:-}"
    
    if process_is_port_in_use "$port"; then
        echo -e "  ${name}: ${COLOR_GREEN}${ICON_SUCCESS} Running (port $port)${COLOR_NC}"
        
        # If health URL provided, check it too
        if [[ -n "$health_url" ]]; then
            if curl -s --max-time 2 "$health_url" > /dev/null 2>&1; then
                echo -e "    Health Check: ${COLOR_GREEN}${ICON_SUCCESS} OK${COLOR_NC}"
            else
                echo -e "    Health Check: ${COLOR_YELLOW}${ICON_WARNING} Not Responding${COLOR_NC}"
            fi
        fi
        return 0
    else
        echo -e "  ${name}: ${COLOR_RED}${ICON_ERROR} Not Running${COLOR_NC}"
        return 1
    fi
}

# Test an HTTP endpoint
process_test_http_endpoint() {
    local name="$1"
    local url="$2"
    local timeout="${3:-5}"
    
    log_debug "Testing $name endpoint: $url"
    echo -n "  Testing $name endpoint..."
    
    if curl -s --max-time "$timeout" "$url" > /dev/null 2>&1; then
        echo -e " ${COLOR_GREEN}${ICON_SUCCESS}${COLOR_NC}"
        return 0
    else
        echo -e " ${COLOR_YELLOW}${ICON_WARNING} (not responding)${COLOR_NC}"
        return 1
    fi
}

# =============================================================================
# Utility Functions
# =============================================================================

# Get process count by pattern
process_count_by_pattern() {
    local pattern="$1"
    local pids="$(_get_pids_by_pattern "$pattern")"
    if [[ -n "$pids" ]]; then
        echo "$pids" | wc -w
    else
        echo "0"
    fi
}

# Check if process is running by name/pattern
process_is_running_by_name() {
    local name="$1"
    pgrep -f "$name" >/dev/null 2>&1
}

# List processes by name/pattern
process_list_by_name() {
    local name="$1"
    local pids
    pids=$(pgrep -f "$name" 2>/dev/null || echo "")

    if [[ -n "$pids" ]]; then
        echo "Processes matching '$name':"
        echo "$pids" | while read -r pid; do
            if ps -p "$pid" >/dev/null 2>&1; then
                ps -p "$pid" -o pid,ppid,command | tail -n +2 | sed 's/^/  /'
            fi
        done
    else
        echo "No processes found matching '$name'"
    fi
}

# List all processes on given ports
process_list_by_ports() {
    local ports="$1"

    for port in $ports; do
        if process_is_port_in_use "$port"; then
            echo "Port $port:"
            process_get_port_info "$port" | while read -r info; do
                echo "  $info"
            done
        fi
    done
}

# Debug: Show process module status
process_debug_info() {
    log_debug "Process management module loaded"
    log_debug "Available functions: port management, pattern matching, background processes, monitoring"
}