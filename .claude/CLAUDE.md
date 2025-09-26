# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A professional development environment orchestration system built with modular Bash architecture. Manages multiple development services (Firebase emulators, APIs, web apps) with sophisticated dependency management and health monitoring.

## Essential Commands

### Installation and Setup
```bash
# Quick install (adds to PATH)
./install.sh

# Manual verification
./bounce help
./bounce --version
```

### Development Operations
```bash
# Main dashboard environment (Firebase + API + Web App)
./bounce start dashboard    # Start with dependency orchestration
./bounce status dashboard   # Check health status
./bounce stop dashboard     # Graceful shutdown
./bounce logs              # View available log files

# App environment (mobile development)
./bounce start app         # Uses legacy system
./bounce status app
./bounce stop app

# Version and debug information
./bounce --version         # Standard version output
./bounce version-debug     # Comprehensive system info
./bounce config-debug      # Configuration details
```

### Testing and Validation
```bash
# Run single test
bash tests/unit/test-config.sh

# Run all unit tests
for f in tests/unit/test-*.sh; do bash "$f" || exit 1; done

# Lint scripts with ShellCheck
shellcheck bin/bounce-cli lib/*.sh services/*.sh orchestration/*.sh install.sh bounce bc dev
```

## Architecture Overview

### Modular Structure
- **Entry Points**: `bounce` (primary), `bc` (alias), `dev` (deprecated with warning)
- **Core System**: `bin/bounce-cli` - Main modular entry point
- **Core Utilities** (`lib/`): Configuration, logging, process management, health checks, CLI parsing, versioning
- **Service Modules** (`services/`): Firebase (`firebase.sh`), Dashboard API (`dashboard-api.sh`)
- **Orchestration** (`orchestration/`): Service coordination with dependency management
- **Configuration** (`config/services.conf`): Centralized service definitions

### Service Architecture
Services follow consistent interface patterns:
- `{service}_get_info()` - Service display name
- `{service}_get_port()` - Primary port
- `{service}_start()` - Startup logic
- `{service}_stop()` - Shutdown logic
- `{service}_status()` - Health status check

### Key Configuration Values
Located in `config/services.conf`:
- **REPOS_DIR**: `/Users/tony.casey/Repos` - Base directory for external repositories
- **Services**: Firebase UI (4000), Firestore (8080), Auth (9099), DB (9000), Storage (9199), Dashboard API (1337), Web App (3000)
- **Composite Services**: `COMPOSITE_DASHBOARD_SERVICES="firebase-emulators dashboard-api dashboard-webapp"`

## Development Patterns

### Adding New Services
1. Create service module in `services/{name}.sh` with standard interface
2. Add configuration entries to `config/services.conf`
3. Create orchestration module in `orchestration/` if needed
4. Register service in main entry point case statements

### Dependency Management
Services use health-based dependency waiting:
- Firebase must be healthy before Dashboard API starts
- Dashboard API must be healthy before Web App starts
- Automatic rollback on startup failures

### Logging and Monitoring
- Service-specific log files in `.logs/`
- Structured logging with levels (info, warn, error)
- Health checks with configurable timeouts and retries
- Color-coded status output

## Important Constraints

- **Bash Compatibility**: Must work with macOS Bash 3.2
- **Configuration-Driven**: No hardcoded values in service modules
- **Backwards Compatibility**: All existing CLI commands must work identically
- **External Dependencies**: Services depend on external repositories under `REPOS_DIR`
- **Port Management**: Sophisticated port conflict detection and cleanup

## Common Development URLs

When `bounce start dashboard` is running:
- Dashboard Web App: http://localhost:3000
- Firebase Emulator UI: http://localhost:4000
- Dashboard API: http://localhost:1337/elb-health-check

## Testing Strategy

- Unit tests cover configuration loading, service modules, orchestration
- All tests must pass for changes to core modules
- ShellCheck compliance required for all shell scripts
- Test framework expects standard bash testing patterns