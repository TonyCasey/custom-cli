#!/bin/bash
# Logging Module
# Provides centralized, structured logging with levels and file management

set -euo pipefail

# Module initialization guard
if [[ "${LOGGING_MODULE_LOADED:-}" == "true" ]]; then
    return 0
fi
readonly LOGGING_MODULE_LOADED="true"

# Logging configuration - using defaults since we can't depend on config module
readonly LOGGING_LIB_DIR="${LOGGING_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)}"

# Default logging configuration (avoid circular dependency with config.sh)
LOGS_DIR="${LOGS_DIR:-$(dirname "$LOGGING_LIB_DIR")/.logs}"
LOG_LEVEL_DEFAULT="${LOG_LEVEL_DEFAULT:-1}"  # INFO level

# Default color and icon definitions (avoid circular dependency with config.sh)
COLOR_GREEN="${COLOR_GREEN:-\033[0;32m}"
COLOR_YELLOW="${COLOR_YELLOW:-\033[1;33m}"
COLOR_RED="${COLOR_RED:-\033[0;31m}"
COLOR_BLUE="${COLOR_BLUE:-\033[0;34m}"
COLOR_PURPLE="${COLOR_PURPLE:-\033[0;35m}"
COLOR_NC="${COLOR_NC:-\033[0m}"

ICON_SUCCESS="${ICON_SUCCESS:-✅}"
ICON_WARNING="${ICON_WARNING:-⚠️}"
ICON_ERROR="${ICON_ERROR:-❌}"
ICON_INFO="${ICON_INFO:-ℹ}"
ICON_FIREBASE="${ICON_FIREBASE:-🔥}"
ICON_API="${ICON_API:-🔌}"
ICON_WEBAPP="${ICON_WEBAPP:-🌐}"

# Logging configuration
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# Current log level (can be overridden by environment)
CURRENT_LOG_LEVEL="${BOUNCE_CLI_LOG_LEVEL:-$LOG_LEVEL_INFO}"

# =============================================================================
# Private Functions
# =============================================================================

# Get log level name
_log_level_name() {
    case "$1" in
        "$LOG_LEVEL_DEBUG") echo "DEBUG" ;;
        "$LOG_LEVEL_INFO")  echo "INFO"  ;;
        "$LOG_LEVEL_WARN")  echo "WARN"  ;;
        "$LOG_LEVEL_ERROR") echo "ERROR" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# Get log level color
_log_level_color() {
    case "$1" in
        "$LOG_LEVEL_DEBUG") echo "$COLOR_BLUE"   ;;
        "$LOG_LEVEL_INFO")  echo "$COLOR_GREEN"  ;;
        "$LOG_LEVEL_WARN")  echo "$COLOR_YELLOW" ;;
        "$LOG_LEVEL_ERROR") echo "$COLOR_RED"    ;;
        *) echo "$COLOR_NC" ;;
    esac
}

# Get log level icon
_log_level_icon() {
    case "$1" in
        "$LOG_LEVEL_DEBUG") echo "$ICON_INFO"    ;;
        "$LOG_LEVEL_INFO")  echo "$ICON_SUCCESS" ;;
        "$LOG_LEVEL_WARN")  echo "$ICON_WARNING" ;;
        "$LOG_LEVEL_ERROR") echo "$ICON_ERROR"   ;;
        *) echo "?" ;;
    esac
}

# Check if message should be logged based on level
_should_log() {
    local level="$1"
    [[ "$level" -ge "$CURRENT_LOG_LEVEL" ]]
}

# Format timestamp for logging
_log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Write log entry to console
_log_to_console() {
    local level="$1"
    local message="$2"
    local color="$3"
    local icon="$4"
    
    echo -e "${color}${icon}${COLOR_NC} $message"
}

# Write log entry to file
_log_to_file() {
    local level="$1"
    local message="$2"
    local log_file="$3"
    local level_name="$4"
    local timestamp="$5"
    
    # Create log directory if it doesn't exist
    local log_dir="$(dirname "$log_file")"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir"
    fi
    
    # Write structured log entry
    echo "[$timestamp] [$level_name] $message" >> "$log_file"
}

# Core logging function
_log() {
    local level="$1"
    local message="$2"
    local log_file="${3:-}"
    
    # Check if we should log this level
    if ! _should_log "$level"; then
        return 0
    fi
    
    local level_name="$(_log_level_name "$level")"
    local color="$(_log_level_color "$level")"
    local icon="$(_log_level_icon "$level")"
    local timestamp="$(_log_timestamp)"
    
    # Always log to console
    _log_to_console "$level" "$message" "$color" "$icon"
    
    # Log to file if specified
    if [[ -n "$log_file" ]]; then
        _log_to_file "$level" "$message" "$log_file" "$level_name" "$timestamp"
    fi
}

# =============================================================================
# Public API
# =============================================================================

# Set logging level
log_set_level() {
    local level="$1"
    case "$level" in
        debug|DEBUG) CURRENT_LOG_LEVEL="$LOG_LEVEL_DEBUG" ;;
        info|INFO)   CURRENT_LOG_LEVEL="$LOG_LEVEL_INFO"  ;;
        warn|WARN)   CURRENT_LOG_LEVEL="$LOG_LEVEL_WARN"  ;;
        error|ERROR) CURRENT_LOG_LEVEL="$LOG_LEVEL_ERROR" ;;
        *)
            echo "Error: Invalid log level '$level'. Use: debug, info, warn, error" >&2
            return 1
            ;;
    esac
}

# Get current logging level
log_get_level() {
    _log_level_name "$CURRENT_LOG_LEVEL"
}

# Debug level logging
log_debug() {
    local message="$1"
    local log_file="${2:-}"
    _log "$LOG_LEVEL_DEBUG" "$message" "$log_file"
}

# Info level logging
log_info() {
    local message="$1"
    local log_file="${2:-}"
    _log "$LOG_LEVEL_INFO" "$message" "$log_file"
}

# Warning level logging
log_warn() {
    local message="$1"
    local log_file="${2:-}"
    _log "$LOG_LEVEL_WARN" "$message" "$log_file"
}

# Error level logging
log_error() {
    local message="$1"
    local log_file="${2:-}"
    _log "$LOG_LEVEL_ERROR" "$message" "$log_file" >&2
}

# Step logging (special case for major operations)
log_step() {
    local message="$1"
    local log_file="${2:-}"
    echo -e "\\n${COLOR_YELLOW}$message${COLOR_NC}"
    if [[ -n "$log_file" ]]; then
        _log_to_file "$LOG_LEVEL_INFO" "STEP: $message" "$log_file" "STEP" "$(_log_timestamp)"
    fi
}

# Success logging (special case for completion messages)
log_success() {
    local message="$1"
    local log_file="${2:-}"
    echo -e "${COLOR_GREEN}${ICON_SUCCESS}${COLOR_NC} $message"
    if [[ -n "$log_file" ]]; then
        _log_to_file "$LOG_LEVEL_INFO" "SUCCESS: $message" "$log_file" "SUCCESS" "$(_log_timestamp)"
    fi
}

# Service-specific logging (creates service-specific log files)
log_to_file() {
    local service_name="$1"
    local message="$2"
    local level="${3:-info}"
    
    # Create log file path
    local log_filename="$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').log"
    local log_file="$LOGS_DIR/$log_filename"
    
    case "$level" in
        debug) log_debug "$message" "$log_file" ;;
        info)  log_info "$message" "$log_file" ;;
        warn)  log_warn "$message" "$log_file" ;;
        error) log_error "$message" "$log_file" ;;
        *)
            log_error "Invalid log level '$level' for service logging"
            return 1
            ;;
    esac
}

# Create service log file with header
log_create_service_file() {
    local service_name="$1"
    local command="${2:-}"
    local directory="${3:-}"
    
    local log_filename="$(echo "$service_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-').log"
    local log_file="$LOGS_DIR/$log_filename"
    
    # Create logs directory
    if [[ ! -d "$LOGS_DIR" ]]; then
        mkdir -p "$LOGS_DIR"
        log_info "Created logs directory: $LOGS_DIR"
    fi
    
    # Create log header
    {
        echo "=== $service_name Start Log - $(_log_timestamp) ==="
        if [[ -n "$command" ]]; then
            echo "Command: $command"
        fi
        if [[ -n "$directory" ]]; then
            echo "Directory: $directory"
        fi
        echo "========================================="
    } > "$log_file"
    
    # Log to stderr to avoid interfering with command substitution
    log_info "Logging $service_name to: $log_file" >&2
    echo "$log_file"
}

# List available log files
log_list_files() {
    if [[ ! -d "$LOGS_DIR" ]]; then
        log_info "No log directory found: $LOGS_DIR"
        return 1
    fi
    
    if [[ -z "$(ls -A "$LOGS_DIR" 2>/dev/null)" ]]; then
        log_info "No log files found in: $LOGS_DIR"
        return 1
    fi
    
    echo -e "${COLOR_BLUE}📋 Available log files in $LOGS_DIR:${COLOR_NC}"
    ls -la "$LOGS_DIR" | grep -v "^total" | grep -v "^d" | while read -r line; do
        echo "  $line"
    done
    
    echo ""
    echo -e "${COLOR_YELLOW}To view a log file:${COLOR_NC}"
    echo "  tail -f $LOGS_DIR/[filename]"
    echo "  less $LOGS_DIR/[filename]"
}

# Clean up old log files (optional maintenance)
log_cleanup() {
    local days="${1:-7}"  # Default: remove logs older than 7 days
    
    if [[ ! -d "$LOGS_DIR" ]]; then
        log_info "No log directory found: $LOGS_DIR"
        return 0
    fi
    
    local count=$(find "$LOGS_DIR" -name "*.log" -mtime +"$days" | wc -l)
    if [[ "$count" -eq 0 ]]; then
        log_info "No log files older than $days days found"
        return 0
    fi
    
    log_info "Cleaning up $count log files older than $days days..."
    find "$LOGS_DIR" -name "*.log" -mtime +"$days" -delete
    log_success "Log cleanup completed"
}

# Rotate log file if it gets too large
log_rotate_if_needed() {
    local log_file="$1"
    local max_size_mb="${2:-10}"  # Default: 10MB
    
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi
    
    # Get file size in MB (bash 3.2 compatible)
    local size_bytes=$(stat -f%z "$log_file" 2>/dev/null || echo 0)
    local size_mb=$((size_bytes / 1024 / 1024))
    
    if [[ "$size_mb" -gt "$max_size_mb" ]]; then
        local backup_file="${log_file}.$(date +%Y%m%d_%H%M%S)"
        mv "$log_file" "$backup_file"
        log_info "Rotated log file: $log_file -> $backup_file"
        return 0
    fi
    
    return 1
}

# Die with error message and cleanup
die() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    exit "$exit_code"
}

# Debug helper: Print module information
log_debug_info() {
    log_debug "Logging module loaded"
    log_debug "Current log level: $(log_get_level)"
    log_debug "Logs directory: $LOGS_DIR"
}