#!/bin/bash
# Generic CLI - Version Management
# Provides version information, build details, and semantic versioning support

set -euo pipefail

# =============================================================================
# Version Information Functions
# =============================================================================

# Get the version number
version_get() {
    config_get "global.version" "unknown"
}

# Get the version name/codename
version_get_name() {
    config_get "global.versionName" "Unknown Release"
}

# Get the build date
version_get_build_date() {
    config_get "global.buildDate" "unknown"
}

# Get the current development phase
version_get_phase() {
    config_get "global.phase" "Unknown Phase"
}

# Get the architecture type
version_get_architecture() {
    config_get "global.architecture" "Unknown"
}

# Get git commit hash if available
version_get_commit() {
    if [[ -d "$CLI_ROOT_DIR/.git" ]]; then
        local commit
        commit=$(cd "$CLI_ROOT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        echo "$commit"
    else
        echo "unknown"
    fi
}

# Get git branch if available
version_get_branch() {
    if [[ -d "$CLI_ROOT_DIR/.git" ]]; then
        local branch
        branch=$(cd "$CLI_ROOT_DIR" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        echo "$branch"
    else
        echo "unknown"
    fi
}

# Check if there are uncommitted changes
version_has_uncommitted_changes() {
    if [[ -d "$CLI_ROOT_DIR/.git" ]]; then
        cd "$CLI_ROOT_DIR" && ! git diff-index --quiet HEAD -- 2>/dev/null
    else
        return 1  # No git repo, assume no uncommitted changes
    fi
}

# =============================================================================
# Version Display Functions
# =============================================================================

# Show full version information
version_show_full() {
    local version name build_date phase architecture commit branch
    
    version=$(version_get)
    name=$(version_get_name)
    build_date=$(version_get_build_date)
    phase=$(version_get_phase)
    architecture=$(version_get_architecture)
    commit=$(version_get_commit)
    branch=$(version_get_branch)
    
    echo "${CLI_NAME:-custom-cli} v${version}"
    echo "Release: ${name}"
    echo "Phase: ${phase}"
    echo "Architecture: ${architecture}"
    echo "Build Date: ${build_date}"
    
    if [[ "$commit" != "unknown" ]]; then
        echo "Git Commit: ${commit}"
    fi
    
    if [[ "$branch" != "unknown" ]]; then
        echo "Git Branch: ${branch}"
        
        # Show if there are uncommitted changes
        if version_has_uncommitted_changes; then
            echo "Status: Modified (uncommitted changes)"
        else
            echo "Status: Clean"
        fi
    fi
    
    echo "Root Directory: ${CLI_ROOT_DIR}"
    echo "Configuration: $(config_is_loaded && echo "Loaded" || echo "Not Loaded")"
    echo "Log Level: $(log_get_level)"
}

# Show compact version information
version_show_compact() {
    local version name
    version=$(version_get)
    name=$(version_get_name)
    
    echo "${CLI_NAME:-custom-cli} v${version} (${name})"
}

# Show version for CLI --version flag (standard format)
version_show_standard() {
    local version commit
    version=$(version_get)
    commit=$(version_get_commit)
    
    if [[ "$commit" != "unknown" ]]; then
        echo "${CLI_NAME:-custom-cli} ${version} (${commit})"
    else
        echo "${CLI_NAME:-custom-cli} ${version}"
    fi
}

# =============================================================================
# Semantic Versioning Utilities
# =============================================================================

# Parse version into components
version_parse() {
    local version="$1"
    local major minor patch
    
    # Extract major.minor.patch
    if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
        
        echo "MAJOR=$major"
        echo "MINOR=$minor"
        echo "PATCH=$patch"
    else
        echo "ERROR: Invalid version format: $version" >&2
        return 1
    fi
}

# Compare two versions (returns: -1, 0, 1)
version_compare() {
    local version1="$1"
    local version2="$2"
    
    local v1_parts v2_parts
    v1_parts=$(version_parse "$version1") || return 1
    v2_parts=$(version_parse "$version2") || return 1
    
    # Extract components
    eval "$v1_parts"
    local v1_major=$MAJOR v1_minor=$MINOR v1_patch=$PATCH
    
    eval "$v2_parts"
    local v2_major=$MAJOR v2_minor=$MINOR v2_patch=$PATCH
    
    # Compare major
    if [[ $v1_major -lt $v2_major ]]; then
        echo -1
        return 0
    elif [[ $v1_major -gt $v2_major ]]; then
        echo 1
        return 0
    fi
    
    # Compare minor
    if [[ $v1_minor -lt $v2_minor ]]; then
        echo -1
        return 0
    elif [[ $v1_minor -gt $v2_minor ]]; then
        echo 1
        return 0
    fi
    
    # Compare patch
    if [[ $v1_patch -lt $v2_patch ]]; then
        echo -1
        return 0
    elif [[ $v1_patch -gt $v2_patch ]]; then
        echo 1
        return 0
    fi
    
    # Equal
    echo 0
}

# Check if version is compatible (same major version)
version_is_compatible() {
    local version1="$1"
    local version2="$2"
    
    local v1_parts v2_parts
    v1_parts=$(version_parse "$version1") || return 1
    v2_parts=$(version_parse "$version2") || return 1
    
    eval "$v1_parts"
    local v1_major=$MAJOR
    
    eval "$v2_parts"
    local v2_major=$MAJOR
    
    [[ $v1_major -eq $v2_major ]]
}

# =============================================================================
# Module Information
# =============================================================================

# Get information about loaded modules
version_get_module_info() {
    echo "Loaded Modules:"
    
    # Check which modules are loaded by testing for their functions
    local modules=(
        "config:config_get"
        "logging:log_info"
        "process:process_is_running"
        "health:health_check_port"
        "cli:cli_parse"
    )
    
    local module func status
    for module_def in "${modules[@]}"; do
        module="${module_def%:*}"
        func="${module_def#*:}"
        
        if command -v "$func" >/dev/null 2>&1; then
            status="✅ Loaded"
        else
            status="❌ Not Loaded"
        fi
        
        echo "  ${module}: ${status}"
    done
}

# =============================================================================
# Debug Information
# =============================================================================

# Show comprehensive version debug information
version_debug() {
    log_info "Version Debug Information:"
    echo
    
    version_show_full
    echo
    
    version_get_module_info
    echo
    
    echo "CLI Information:"
    echo "  Primary Command: ${CLI_NAME:-custom-cli}"
    echo "  Executable: ${CLI_EXECUTABLE:-bin/custom-cli}"
    echo "  Deprecated Aliases: dev"
    echo "  Current Invocation: ${CLI_INVOKED_AS:-unknown}"
    echo
    
    echo "Environment:"
    echo "  Shell: ${SHELL:-unknown} (${BASH_VERSION:-unknown})"
    echo "  OS: $(uname -s 2>/dev/null || echo "unknown") $(uname -r 2>/dev/null || echo "")"
    echo "  User: $(whoami 2>/dev/null || echo "unknown")"
    echo "  Working Directory: $(pwd)"
    echo "  PATH: ${PATH}"
}
