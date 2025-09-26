# Custom CLI v1.0.0 🚀

**Create Your Own Custom CLI Commands**

A custom CLI tool where anyone can create their own commands to run one or multiple chained apps using a simple YAML file to arrange the apps and the CLI alias name. Build personalized development workflows with dependency management, health monitoring, and complete customization.

## ✨ Features

- 🎯 **Create Custom Commands** - Design your own CLI with any name you want
- 🔧 **Simple YAML Configuration** - Define your apps and commands in one file
- ⚡ **Chain Multiple Apps** - Start multiple services with dependencies in correct order
- 🏥 **Smart Health Monitoring** - Real health checks, not just port availability
- 📊 **Automatic Orchestration** - Services start and stop in dependency order with rollback
- 🛠️ **npm/yarn Integration** - Run any npm scripts or shell commands
- 🔄 **Unlimited Flexibility** - Create as many custom CLI tools as you need

## 🚀 Quick Start

### 1. Installation
```bash
# Clone or download the CLI to your preferred location
cd ~/Repos/custom-cli

# Run the installation script
./install.sh

# Reload your shell
source ~/.bashrc  # or ~/.zshrc
```

### 2. Setup Configuration
```bash
# Copy the sample configuration and customize it
cp config.yaml.sample config.yaml

# Edit config.yaml to add your projects and services
# Key things to customize:
# - Change 'reposDir' to your projects directory (e.g., ${HOME}/Projects)
# - Update service directories to match your project paths
# - Modify service names, ports, and commands for your apps
# - Set your preferred CLI name in global.cliName
```

### 3. Test Installation
```bash
# Test the CLI
./bin/custom-cli --version
./bin/custom-cli help
```

## 🎯 Creating Custom Aliases

### Method 1: Shell Alias (Recommended)

Create a custom alias to run the CLI with your preferred name:

```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.bash_profile
alias my-dev-cli="~/Repos/custom-cli/bin/custom-cli"
alias frontend-tools="~/Repos/custom-cli/bin/custom-cli"
alias project-manager="~/Repos/custom-cli/bin/custom-cli"

# Reload your shell
source ~/.bashrc  # or ~/.zshrc

# Now use your custom name
my-dev-cli help
frontend-tools start webapp
project-manager status api
```

### Method 2: Custom Wrapper Script

Create a dedicated wrapper script for your project:

```bash
#!/bin/bash
# ~/bin/my-project-cli
exec ~/Repos/custom-cli/bin/custom-cli "$@"
```

```bash
# Make it executable and add to PATH
chmod +x ~/bin/my-project-cli
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Use your custom CLI
my-project-cli help
```

### Method 3: Symlink

```bash
# Create a symlink with your preferred name
ln -s ~/Repos/custom-cli/bin/custom-cli ~/bin/my-cli
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Use the symlinked name
my-cli --version
```

## 🔧 Configuration Guide

### Getting Started with config.yaml

Use the provided sample file as your starting point:

```bash
# Copy the sample configuration
cp config.yaml.sample config.yaml

# Customize for your projects
nano config.yaml  # or your preferred editor
```

### Understanding config.yaml

All services and environments are defined in `config.yaml`. Here's the basic structure:

```yaml
# Individual service definitions
services:
  my-frontend:
    port: 3000
    directory: ${REPOS_DIR}/my-frontend
    command: npm run dev
    timeout: 60
    healthUrl: http://localhost:3000
    displayName: Frontend App
    dependencies: []

  my-api:
    port: 8080
    directory: ${REPOS_DIR}/my-api
    command: npm run start:dev
    timeout: 30
    healthUrl: http://localhost:8080/health
    displayName: API Server
    dependencies: []

# Composite service environments
composites:
  fullstack:
    services:
      - my-api
      - my-frontend
    displayName: Complete Fullstack Environment
    description: API server + Frontend application

# Global configuration
global:
  reposDir: ${HOME}/Projects
  cliName: my-custom-cli
  version: 1.0.0
```

## 📦 Adding npm-based Web Applications

The `config.yaml.sample` file includes many examples of common web applications. You can use these as templates for your own projects.

### Step 1: Define the Service

Add your npm-based application to the `services` section in `config.yaml`. Here are some examples (also available in `config.yaml.sample`):

```yaml
services:
  # React App Example
  react-app:
    port: 3000
    directory: ${REPOS_DIR}/my-react-app
    command: npm start
    timeout: 60
    healthUrl: http://localhost:3000
    displayName: React Application
    dependencies: []

  # Vite App Example
  vite-app:
    port: 5173
    directory: ${REPOS_DIR}/my-vite-app
    command: npm run dev
    timeout: 45
    healthUrl: http://localhost:5173
    displayName: Vite Development Server
    dependencies: []

  # Next.js App Example
  nextjs-app:
    port: 3000
    directory: ${REPOS_DIR}/my-nextjs-app
    command: npm run dev
    timeout: 60
    healthUrl: http://localhost:3000
    displayName: Next.js Application
    dependencies: []

  # Express API Example
  express-api:
    port: 8080
    directory: ${REPOS_DIR}/my-express-api
    command: npm run dev
    timeout: 30
    healthUrl: http://localhost:8080/api/health
    displayName: Express API Server
    dependencies: []

  # Vue.js App Example
  vue-app:
    port: 8080
    directory: ${REPOS_DIR}/my-vue-app
    command: npm run serve
    timeout: 45
    healthUrl: http://localhost:8080
    displayName: Vue.js Application
    dependencies: []
```

### Step 2: Create Composite Environments

Group related services into environments:

```yaml
composites:
  # Frontend-only environment
  frontend:
    services:
      - react-app
    displayName: Frontend Development
    description: React application only

  # Full-stack environment with dependencies
  fullstack:
    services:
      - express-api
      - react-app
    displayName: Complete Development Environment
    description: Express API + React frontend (API starts first)

  # Multi-app environment
  multi-frontend:
    services:
      - react-app
      - vue-app
      - vite-app
    displayName: Multi-Frontend Testing
    description: Multiple frontend frameworks running simultaneously
```

### Step 3: Configure Dependencies

Services can depend on others, ensuring they start in the correct order:

```yaml
services:
  database:
    port: 5432
    directory: ${REPOS_DIR}/database
    command: npm run start:local
    timeout: 30
    healthUrl: ""  # Uses port-based health check
    displayName: Local Database
    dependencies: []

  api-server:
    port: 8080
    directory: ${REPOS_DIR}/api-server
    command: npm run dev
    timeout: 30
    healthUrl: http://localhost:8080/health
    displayName: API Server
    dependencies:
      - database  # Waits for database to be healthy first

  frontend-app:
    port: 3000
    directory: ${REPOS_DIR}/frontend-app
    command: npm start
    timeout: 60
    healthUrl: http://localhost:3000
    displayName: Frontend Application
    dependencies:
      - api-server  # Waits for API to be healthy first
```

## 🎮 Usage Examples

### Using Your Custom CLI

After creating an alias called `my-dev-cli`:

```bash
# Start individual services
my-dev-cli start react-app
my-dev-cli start express-api

# Start composite environments
my-dev-cli start fullstack    # Starts API, then React app
my-dev-cli start frontend     # Starts just the React app

# Check status
my-dev-cli status fullstack
my-dev-cli status react-app

# Stop services
my-dev-cli stop fullstack
my-dev-cli stop react-app

# View logs
my-dev-cli logs

# Get help
my-dev-cli help
```

### Real-world Examples

#### E-commerce Development Stack
```yaml
services:
  postgres-db:
    port: 5432
    directory: ${REPOS_DIR}/ecommerce-db
    command: npm run start:local
    timeout: 30
    displayName: PostgreSQL Database
    dependencies: []

  ecommerce-api:
    port: 3001
    directory: ${REPOS_DIR}/ecommerce-api
    command: npm run dev
    timeout: 30
    healthUrl: http://localhost:3001/api/health
    displayName: E-commerce API
    dependencies:
      - postgres-db

  admin-dashboard:
    port: 3002
    directory: ${REPOS_DIR}/admin-dashboard
    command: npm start
    timeout: 60
    healthUrl: http://localhost:3002
    displayName: Admin Dashboard
    dependencies:
      - ecommerce-api

  customer-frontend:
    port: 3000
    directory: ${REPOS_DIR}/customer-app
    command: npm run dev
    timeout: 60
    healthUrl: http://localhost:3000
    displayName: Customer Frontend
    dependencies:
      - ecommerce-api

composites:
  ecommerce:
    services:
      - postgres-db
      - ecommerce-api
      - admin-dashboard
      - customer-frontend
    displayName: Complete E-commerce Stack
    description: Database + API + Admin Dashboard + Customer Frontend

  api-only:
    services:
      - postgres-db
      - ecommerce-api
    displayName: Backend Services Only
    description: Database + API for backend development
```

#### Microservices Development
```yaml
services:
  user-service:
    port: 3001
    directory: ${REPOS_DIR}/user-service
    command: npm run dev
    healthUrl: http://localhost:3001/health
    displayName: User Service
    dependencies: []

  product-service:
    port: 3002
    directory: ${REPOS_DIR}/product-service
    command: npm run dev
    healthUrl: http://localhost:3002/health
    displayName: Product Service
    dependencies: []

  order-service:
    port: 3003
    directory: ${REPOS_DIR}/order-service
    command: npm run dev
    healthUrl: http://localhost:3003/health
    displayName: Order Service
    dependencies:
      - user-service
      - product-service

  api-gateway:
    port: 8080
    directory: ${REPOS_DIR}/api-gateway
    command: npm run dev
    healthUrl: http://localhost:8080/health
    displayName: API Gateway
    dependencies:
      - user-service
      - product-service
      - order-service

composites:
  microservices:
    services:
      - user-service
      - product-service
      - order-service
      - api-gateway
    displayName: Complete Microservices Stack
    description: All services + API Gateway
```

## 🔧 Advanced Configuration

### Environment Variables

Use environment variables in your configuration:

```yaml
global:
  reposDir: ${HOME}/Projects
  logsDir: ${REPOS_DIR}/custom-cli/.logs

services:
  my-app:
    port: ${PORT:-3000}  # Use PORT env var, default to 3000
    directory: ${REPOS_DIR}/${APP_NAME:-my-app}
    command: npm run ${NODE_ENV:-dev}
```

### Custom Health Checks

Configure different types of health checks:

```yaml
services:
  # HTTP health check
  api-with-health:
    port: 8080
    command: npm run dev
    healthUrl: http://localhost:8080/api/health

  # Port-based health check (no URL)
  simple-service:
    port: 3000
    command: npm start
    healthUrl: ""  # Will check if port is responding

  # No health check (careful!)
  background-service:
    port: ""       # No port to check
    command: npm run background
    healthUrl: ""
```

### Timeouts and Retry Logic

Configure startup timeouts:

```yaml
services:
  slow-service:
    port: 3000
    command: npm run build-and-serve  # Takes longer
    timeout: 120  # Wait up to 2 minutes

  fast-service:
    port: 8080
    command: npm run quick-start
    timeout: 15   # Should start quickly
```

## 🛠️ CLI Commands

```bash
# Version information
my-cli --version                    # Show version
my-cli version-debug                # Detailed system info

# Service management
my-cli start <environment>          # Start service environment
my-cli stop <environment>           # Stop service environment
my-cli status <environment>         # Check service status
my-cli logs                         # View log files

# Debug commands
my-cli config-debug                 # Show configuration
my-cli test-dependencies            # Test dependency resolution
my-cli test-service-interface       # Validate service definitions
my-cli test-logging                 # Test logging system

# Help
my-cli help                         # Show help
```

## 🏗️ Architecture

```
custom-cli/
├── bin/custom-cli          # Main executable
├── config.yaml             # Service & environment definitions
├── lib/                    # Core modules
│   ├── config.sh          # Configuration management
│   ├── logging.sh         # Structured logging
│   ├── service_orchestrator.sh  # Service management
│   ├── yaml.sh            # YAML parsing
│   └── ...                # Other utility modules
├── legacy/                 # Legacy script support
└── tests/                 # Unit tests
```

## 🔍 Troubleshooting

### Common Issues

**Services not found:**
```bash
# Check your configuration
my-cli config-debug

# Verify service names match config.yaml
my-cli test-dependencies
```

**Health checks failing:**
```bash
# Check if the service actually provides a health endpoint
curl http://localhost:3000/health

# Use port-based health checks if no endpoint exists
healthUrl: ""  # In config.yaml
```

**Dependencies not working:**
```bash
# Test dependency resolution
my-cli test-dependencies

# Check service startup order in logs
my-cli logs
```

## 📝 Examples Repository

For more examples and templates, check out:
- React + Express fullstack setup
- Microservices with API Gateway
- Multi-database development environment
- Frontend testing with multiple frameworks

## 🤝 Contributing

1. Fork the repository
2. Add your service configurations to `config.yaml`
3. Test with `./bin/custom-cli test-dependencies`
4. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

---

**Need help?** Run `my-cli help` or check the configuration with `my-cli config-debug`