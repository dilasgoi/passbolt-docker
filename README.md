# Passbolt Docker Deployment Guide

## Table of Contents
- [Introduction](#introduction)
- [Project Structure](#project-structure)
- [Deployment Guide](#deployment-guide)
  - [Prerequisites](#prerequisites)
  - [Setup Steps](#setup-steps)
  - [Docker Compose Configuration](#docker-compose-configuration)
- [Passbolt Manager Script](#passbolt-manager-script)
  - [How the Manager Script Works](#how-the-manager-script-works)
  - [Available Commands](#available-commands)
  - [Command Details and Implementation](#command-details-and-implementation)
  - [Usage Examples](#usage-examples)
- [Backup and Restore](#backup-and-restore)
  - [Backup System Architecture](#backup-system-architecture)
  - [Backup Process](#backup-process)
  - [Restore Process](#restore-process)
- [Nginx Configuration](#nginx-configuration)
  - [Configuration Structure](#configuration-structure)
  - [Key Configuration Files](#key-configuration-files)
  - [Customizing for Your Environment](#customizing-for-your-environment)
  - [Generating Self-Signed SSL Certificates](#generating-self-signed-ssl-certificates)
  - [Using Let's Encrypt for Production](#using-lets-encrypt-for-production)
  - [Testing Your Configuration](#testing-your-configuration)
- [GPG Key Setup for Docker Deployment](#gpg-key-setup-for-docker-deployment)
  - [Understanding GPG Keys in Passbolt](#understanding-gpg-keys-in-passbolt)
  - [Common Challenges with Docker Deployment](#common-challenges-with-docker-deployment)
  - [Step-by-Step Key Generation Process](#step-by-step-key-generation-process)
  - [Troubleshooting GPG Issues](#troubleshooting-gpg-issues)
  - [Security Best Practices for GPG Keys](#security-best-practices-for-gpg-keys)
- [Two-Factor Authentication](#two-factor-authentication)
  - [Understanding TOTP Authentication](#understanding-totp-authentication)
  - [User Setup for TOTP Authentication](#user-setup-for-totp-authentication)
  - [Recovery Procedures](#recovery-procedures)
- [Troubleshooting](#troubleshooting)
  - [Common Issues and Solutions](#common-issues-and-solutions)
  - [Advanced Troubleshooting](#advanced-troubleshooting)
- [Maintenance Tasks](#maintenance-tasks)
  - [Regular Maintenance Schedule](#regular-maintenance-schedule)
  - [Update Procedure](#update-procedure)
  - [Database Maintenance](#database-maintenance)
  - [Security Maintenance](#security-maintenance)
  - [Backup Management Strategy](#backup-management-strategy)
  - [Disaster Recovery Planning](#disaster-recovery-planning)
- [Best Practices for Production Deployment](#best-practices-for-production-deployment)
- [Conclusion](#conclusion)

## Introduction

This project provides a Docker-based deployment solution for [Passbolt](https://www.passbolt.com/), an open-source password manager for teams. The setup includes:

- Passbolt Community Edition in a Docker container
- MariaDB database for data storage
- Nginx as a reverse proxy for SSL termination
- Custom scripts for backup, restore, and management operations

[Passbolt](https://www.passbolt.com/) is a self-hosted password manager that allows teams to securely store and share credentials within an organization. This deployment uses Docker to simplify installation and maintenance while providing a secure and scalable setup.

## Project Structure

The project is organized as follows:

```
passbolt-docker/
├── backups/                     # Directory for backup archives
├── config/                      # Configuration files
│   ├── images/                  # User-uploaded images storage
│   ├── nginx/                   # Nginx configuration files
│   │   ├── conf.d/              # Nginx site configurations
│   │   ├── nginx.conf           # Main Nginx config
│   │   └── ssl/                 # SSL certificates
│   │       ├── certs/           # Public certificates
│   │       └── private/         # Private keys
│   └── passbolt/                # Passbolt specific configs
│       ├── gpg/                 # GPG keys for encryption
│       └── jwt/  ump -u${MYSQL_USER} -p               # JWT keys for authentication
├── data/                        # Data persistence directories
│   └── mariadb/                 # Database files
├── docker-compose.yml           # Docker Compose configuration
├── env/                         # Environment variable files
│   ├── examples                 # Example env files 
│   │   ├── db.env.example       # MariaDB env example file
│   │   ├── email.env.example    # Email env example file
│   │   ├── nginx.env.example    # Nginx env example file
│   │   ├── passbolt.env.example # Passbolt env example file
│   ├── db.env                   # Database environment
│   ├── email.env                # Email server configuration
│   ├── nginx.env                # Nginx environment
│   └── passbolt.env             # Passbolt configuration
├── logs/                        # Log files
├── README.md                    # Project documentation
└── scripts/                     # Management scripts
    ├── backup.sh                # Database and configuration backup
    ├── passbolt-manager.sh      # Central management script
    └── restore.sh               # Restore from backup
```

## Deployment Guide

### Prerequisites

Before deploying Passbolt, ensure you have the following:

- A server with Docker and Docker Compose installed
- SMTP server for email delivery (registration, password reset, etc.)
- SSL certs for your server 
- Basic understanding of Docker and shell scripting

### Setup Steps

1. **Clone or download this repository**

   ```bash
   git clone https://github.com/yourusername/passbolt-docker.git
   cd passbolt-docker
   ```
2. **Generate GPG keys for Passbolt**

   Follow the instructions in the [GPG Key Setup section](#gpg-key-setup-for-docker-deployment) to generate and configure GPG keys.

3. **Generate JWT keys**

   ```bash
   # Create JWT keys for authentication
   openssl genrsa -out config/passbolt/jwt/jwt.key 4096
   openssl rsa -in config/passbolt/jwt/jwt.key -outform PEM -pubout -out config/passbolt/jwt/jwt.pem
   chmod 640 config/passbolt/jwt/jwt.*
   ```

4. **Configure environment variables**

   Copy the provided example environment files and adjust them to your needs:

   ```bash
   # Example for db.env
   cp env-examples/db.env env/db.env
   # Repeat for other env files
   ```

6. **Configure SSL certificates**

   Place your SSL certificates in the appropriate directories:
   
   ```bash
   # Place your certificates here
   cp /path/to/your/certificate.crt config/nginx/ssl/certs/passbolt.crt
   cp /path/to/your/private.key config/nginx/ssl/private/passbolt.key
   ```

7. **Start the containers**

   ```bash
   docker compose up -d
   ```

8. **Initialize Passbolt**

   After the containers are running, you can create the first admin user:

   ```bash
   ./scripts/passbolt-manager.sh register admin@yourdomain.com "Admin" "User" admin
   ```

### Docker Compose Configuration

The `docker-compose.yml` file is the heart of the Passbolt Docker deployment, defining the services, their relationships, volumes, networks, and other containerization parameters. This file orchestrates the entire setup.

#### Architecture Overview

The deployment consists of three main services:

1. **Database (MariaDB)**: Stores all Passbolt data
2. **Application (Passbolt)**: The core password manager application
3. **Web Server (Nginx)**: Handles SSL termination and acts as a reverse proxy

These services are connected through a dedicated Docker network and rely on a series of mounted volumes and environment files for configuration.

#### Docker Compose File Analysis

Let's break down the `docker-compose.yml` file section by section:

```yaml
services:
  db:
    image: mariadb:10.11
    restart: unless-stopped
    env_file:
      - ./env/db.env
    volumes:
      - ./data/mariadb:/var/lib/mysql
    container_name: passbolt-db
    networks:
      - passbolt-network
    healthcheck:
      test: ["CMD", "mysql", "-u", "passbolt", "-pSuperSecureUser123", "-h", "localhost", "passbolt", "-e", "SELECT 1;"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
```

**Database Service Explained**:

| Parameter | Description | Importance |
|-----------|-------------|------------|
| `image: mariadb:10.11` | Uses MariaDB 10.11 as the database engine | Specifies the exact version for consistency |
| `restart: unless-stopped` | Automatically restarts container unless manually stopped | Provides resilience |
| `env_file: ./env/db.env` | Loads database environment variables | Contains MySQL credentials |
| `volumes: ./data/mariadb:/var/lib/mysql` | Persists database files on the host | Crucial for data persistence |
| `container_name: passbolt-db` | Names the container for easy reference | Used by scripts and other services |
| `networks: passbolt-network` | Places the container on the Passbolt network | Enables communication between services |
| `healthcheck:` | Defines how to check if the database is healthy | Ensures database is ready before passbolt app starts |

The healthcheck section is particularly important as it ensures the Passbolt application won't start until the database is fully initialized and accepting connections. This prevents connection errors during startup.

Remember to set ownership to 999:999 for the `data/mariadb` directory:
```
chown -R 999 config/passbolt/data/mariadb
```

```yaml
  passbolt:
    image: passbolt/passbolt:latest-ce
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    env_file:
      - ./env/passbolt.env
      - ./env/email.env
    volumes:
      - ./config/passbolt/gpg:/etc/passbolt/gpg:ro
      - ./config/passbolt/jwt:/etc/passbolt/jwt:ro
      - ./config/images:/usr/share/php/passbolt/webroot/img/public
    tmpfs:
      - /var/lib/passbolt/tmp/cache:mode=1777,size=100m
    container_name: passbolt-app
    networks:
      - passbolt-network
```

**Passbolt Application Service Explained**:

| Parameter | Description | Importance |
|-----------|-------------|------------|
| `image: passbolt/passbolt:latest-ce` | Uses the official Passbolt Community Edition | Ensures you're using supported software |
| `restart: unless-stopped` | Automatically restarts unless manually stopped | Ensures continuous availability |
| `depends_on: db: condition: service_healthy` | Waits for healthy database | Prevents startup errors |
| `env_file: ./env/passbolt.env, ./env/email.env` | Loads configuration | Contains app settings and SMTP config |
| `volumes:` | Mounts multiple configuration directories | Persists critical security keys and images |
| `tmpfs:` | Uses RAM for temporary files | Improves performance for cache files |
| `container_name: passbolt-app` | Names the container | Used by scripts and other services |

The volume mounts for GPG and JWT keys are mounted as read-only (`ro`) for security, preventing the application from modifying these critical keys.

```yaml
  nginx:
    image: nginx:latest
    restart: unless-stopped
    depends_on:
      - passbolt
    volumes:
      - ./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/nginx/conf.d:/etc/nginx/conf.d:ro
      - ./config/nginx/ssl/certs/passbolt.crt:/etc/ssl/certs/passbolt.crt:ro
      - ./config/nginx/ssl/private/passbolt.key:/etc/ssl/private/passbolt.key:ro
    environment:
      - ./env/nginx.env
    ports:
      - "8080:80"   # HTTP on port 8080
      - "443:443"   # HTTPS on standard port 443
    container_name: passbolt-nginx
    networks:
      - passbolt-network
```

**Nginx Service Explained**:

| Parameter | Description | Importance |
|-----------|-------------|------------|
| `image: nginx:latest` | Uses the latest Nginx image | Provides up-to-date web server |
| `restart: unless-stopped` | Automatically restarts | Maintains availability |
| `depends_on: passbolt` | Waits for Passbolt to start | Ensures proper startup order |
| `volumes:` | Mounts configuration and SSL files | Provides custom configuration and SSL |
| `ports: "8080:80", "443:443"` | Maps container ports to host | Exposes HTTP and HTTPS ports |
| `container_name: passbolt-nginx` | Names the container | Used for reference in scripts |

The Nginx configuration volumes are all mounted as read-only (`ro`) for security, preventing modification from within the container.

```yaml
networks:
  passbolt-network:
    driver: bridge
```

**Network Configuration Explained**:

| Parameter | Description | Importance |
|-----------|-------------|------------|
| `passbolt-network: driver: bridge` | Creates an isolated network | Isolates containers from other Docker services |

#### Volume Mounts and Their Purpose

The Docker Compose configuration includes several volume mounts for data persistence and configuration:

**Database Volumes**:
- `./data/mariadb:/var/lib/mysql`: Stores the MariaDB database files on the host, ensuring data persistence across container restarts and updates.

**Passbolt Volumes**:
- `./config/passbolt/gpg:/etc/passbolt/gpg:ro`: Contains the GPG encryption keys used by Passbolt.
- `./config/passbolt/jwt:/etc/passbolt/jwt:ro`: Contains the JWT tokens used for API authentication.
- `./config/images:/usr/share/php/passbolt/webroot/img/public`: Stores user-uploaded images.

**Nginx Volumes**:
- `./config/nginx/nginx.conf:/etc/nginx/nginx.conf:ro`: Main Nginx configuration file.
- `./config/nginx/conf.d:/etc/nginx/conf.d:ro`: Site-specific configurations.
- `./config/nginx/ssl/certs/passbolt.crt:/etc/ssl/certs/passbolt.crt:ro`: SSL certificate.
- `./config/nginx/ssl/private/passbolt.key:/etc/ssl/private/passbolt.key:ro`: SSL private key.

#### Environment Files

The configuration uses separate environment files to keep sensitive information organized:

**db.env** - Database Configuration:
```
MYSQL_ROOT_PASSWORD=SuperSecureRoot123
MYSQL_DATABASE=passbolt
MYSQL_USER=passbolt
MYSQL_PASSWORD=SuperSecureUser123
```

**passbolt.env** - Application Configuration:
```
# Database configuration
DATASOURCES_DEFAULT_HOST=passbolt-db
DATASOURCES_DEFAULT_USERNAME=passbolt
DATASOURCES_DEFAULT_PASSWORD=SuperSecureUser123
DATASOURCES_DEFAULT_DATABASE=passbolt

# Application URL and SSL settings
APP_FULL_BASE_URL=https://<your_server_domain_or_ip_address>
PASSBOLT_SSL_FORCE=true

# GPG specific environment variables
PASSBOLT_GPG_SERVER_KEY_FINGERPRINT=<your_keys_fingerprint_goes_here>
PASSBOLT_GPG_SERVER_KEY_PUBLIC=/etc/passbolt/gpg/serverkey.asc
PASSBOLT_GPG_SERVER_KEY_PRIVATE=/etc/passbolt/gpg/serverkey_private.asc
# Additional settings...
```

**email.env** - Email Server Configuration:
```
EMAIL_TRANSPORT_DEFAULT_CLASS_NAME=Smtp
EMAIL_TRANSPORT_DEFAULT_HOST=<your_smtp_host>
EMAIL_TRANSPORT_DEFAULT_PORT=587
EMAIL_TRANSPORT_DEFAULT_USERNAME=<your_email_address_goes_here>
EMAIL_TRANSPORT_DEFAULT_PASSWORD=<your_password_goes_here>
EMAIL_TRANSPORT_DEFAULT_TLS=true
EMAIL_TRANSPORT_DEFAULT_SSL=false
EMAIL_DEFAULT_FROM=<your_email_address_or_selected_id_goes_here>
EMAIL_TRANSPORT_DEFAULT_AUTH="LOGIN"
EMAIL_TRANSPORT_DEFAULT_TIMEOUT="180"
```

#### Security Considerations

The Docker Compose file includes several security-focused features:

1. **Read-only mounts** for sensitive configurations (`ro` flag)
2. **Healthchecks** to ensure services start in the correct order
3. **Isolated network** for container communication
4. **Automatic restarts** for service resilience
5. **Separated environment files** for credential management
6. **tmpfs for cache** to improve performance and security

#### Customization Options

You can customize this deployment by modifying:

1. **Database version**: Change `mariadb:10.11` to a different version if needed
2. **Passbolt edition**: Change `passbolt/passbolt:latest-ce` to use a specific version or the Pro edition
3. **Port mappings**: Modify the `ports` section to use different host ports
4. **Volume locations**: Change the host paths in the `volumes` sections
5. **Resource limits**: Add `deploy` sections with resource constraints for production environments

#### Example: Adding Resource Limits

For production deployments, you might want to add resource constraints:

```yaml
services:
  db:
    # Existing configuration...
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 512M
  
  passbolt:
    # Existing configuration...
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

#### Example: Using a Specific Passbolt Version

To lock to a specific version for stability:

```yaml
services:
  passbolt:
    image: passbolt/passbolt:3.12.0-ce
    # Rest of configuration...
```

#### Recommendations for Production

For production deployments, consider these modifications:

1. **Use specific version tags**: Replace `latest-ce` with specific version numbers
2. **Add resource limits**: Prevent resource exhaustion with appropriate constraints
3. **Implement external backup**: Configure automated external backups
4. **Use secrets management**: Consider Docker secrets for sensitive information
5. **Configure monitoring**: Add health monitoring and alerting

## Passbolt Manager Script

The `passbolt-manager.sh` script provides a unified interface for managing your Passbolt instance. It acts as a wrapper around various operations, making maintenance and administration tasks easier.

### How the Manager Script Works

The Passbolt Manager script is designed with a modular architecture that handles different management commands through specialized functions. Here's a breakdown of its structure:

```bash
# Main script structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Container names defined for consistent reference
DB_CONTAINER="passbolt-db"
APP_CONTAINER="passbolt-app"
NGINX_CONTAINER="passbolt-nginx"

# Helper functions for common operations
show_help() { ... }
log_message() { ... }
check_docker() { ... }
# etc...

# Command functions that implement specific operations
cmd_backup() { ... }
cmd_restore() { ... }
cmd_healthcheck() { ... }
# etc...

# Main command handler
case "$COMMAND" in
    backup)
        cmd_backup "$@"
        ;;
    restore)
        cmd_restore "$@"
        ;;
    # etc...
esac
```

The script is designed to be both user-friendly and extensible:

- **Color-coded output**: Uses terminal colors to improve readability
- **Consistent logging**: All commands use a standardized logging mechanism
- **Command-specific help**: Each command has its own detailed help information
- **Error handling**: Checks for prerequisites and validates operations

### Available Commands

| Command | Description | Key Functionality |
|---------|-------------|------------------|
| `backup` | Create a complete backup of Passbolt | Calls `backup.sh` to create a timestamped archive of all data |
| `restore` | Restore from a backup file | Calls `restore.sh` to recover from a backup archive |
| `healthcheck` | Verify the health of the Passbolt installation | Runs the built-in Passbolt healthcheck command |
| `status` | Show the status of all Passbolt containers | Displays container state and resource usage |
| `logs` | Display logs from the containers | Shows container logs with filtering options |
| `cleanup` | Run data integrity cleanup tasks | Performs data integrity maintenance |
| `register` | Register a new user | Creates a new Passbolt user account |
| `reset-password` | Reset a user's password | Triggers the password reset process |
| `test-email` | Test email configuration | Sends a test email to verify SMTP settings |
| `version` | Display the Passbolt version | Shows version information for all components |
| `help` | Show help information | Displays usage information |

### Command Details and Implementation

#### Health Check Command

The healthcheck command performs a comprehensive check of your Passbolt installation:

```bash
cmd_healthcheck() {
    print_header "Passbolt Health Check"

    # Check if Docker is running
    if ! check_docker; then
        return 1
    fi

    # Check if Passbolt container is running
    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running" "ERROR"
        return 1
    fi

    # Run the Passbolt built-in healthcheck
    print_section "Running health check"
    docker exec -i "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt healthcheck" www-data

    # Report results
    if [ $? -eq 0 ]; then
        log_message "Health check passed" "SUCCESS"
    else
        log_message "Health check reported issues" "WARNING"
    fi
}
```

This command:
1. Verifies that Docker is running
2. Checks if the Passbolt application container exists and is running
3. Runs Passbolt's built-in healthcheck command
4. Reports the results with appropriate status indicators

#### User Management

The register command adds new users to your Passbolt instance:

```bash
cmd_register() {
    # Validate parameters
    if [ $# -lt 3 ]; then
        log_message "Missing required parameters" "ERROR"
        show_command_help "register"
        return 1
    fi

    local email="$1"
    local firstname="$2"
    local lastname="$3"
    local role="${4:-user}"  # Default role is "user" if not specified

    # Validate role
    if [ "$role" != "user" ] && [ "$role" != "admin" ]; then
        log_message "Invalid role: $role (must be 'user' or 'admin')" "ERROR"
        return 1
    }

    # Registration command execution
    docker exec "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt register_user -u \"$email\" -f \"$firstname\" -l \"$lastname\" -r \"$role\"" www-data
    
    # Result handling
    if [ $? -eq 0 ]; then
        log_message "User registration process initiated" "SUCCESS"
        log_message "Note: The user will receive an email with setup instructions" "INFO"
    else
        log_message "Failed to register user" "ERROR"
    fi
}
```

This command:
1. Validates the required parameters (email, first name, last name)
2. Sets a default role of "user" if not specified
3. Validates the role input
4. Executes the Passbolt user registration command
5. Provides feedback on the registration process

#### Email Testing

The test-email command verifies your email configuration:

```bash
cmd_test_email() {
    local recipient="$1"

    # Display the current email settings
    if [ -f "${BASE_DIR}/env/email.env" ]; then
        print_section "Current Email Configuration"
        grep -v "PASSWORD" "${BASE_DIR}/env/email.env" || true
    fi

    # Send test email
    print_section "Testing Email Configuration"
    docker exec -i "$APP_CONTAINER" /usr/share/php/passbolt/bin/cake passbolt send_test_email --recipient="$recipient"

    # Alternative method if the first fails
    if [ $? -ne 0 ]; then
        log_message "First attempt failed, trying alternative method..." "WARNING"
        docker exec -i "$APP_CONTAINER" su -m -c "/usr/share/php/passbolt/bin/cake passbolt send_test_email --recipient=\"$recipient\"" -s /bin/sh www-data
    fi

    # Output troubleshooting information if needed
    if [ $? -ne 0 ]; then
        log_message "Failed to send test email" "ERROR"
        print_section "Troubleshooting"
        echo "1. Make sure email.env file is correctly mounted to the container"
        echo "2. Check if container was restarted after changing email settings"
        # etc...
    fi
}
```

This command:
1. Shows the current email configuration (excluding password)
2. Attempts to send a test email
3. Tries an alternative method if the first fails
4. Provides detailed troubleshooting information if the email cannot be sent

### Usage Examples

**Checking the health of your installation**:
```bash
./scripts/passbolt-manager.sh healthcheck
```

**Registering a new user**:
```bash
./scripts/passbolt-manager.sh register user@example.com "John" "Doe" user
```

**Showing container status**:
```bash
./scripts/passbolt-manager.sh status
```

**Following logs with filtering**:
```bash
# Show logs for all containers
./scripts/passbolt-manager.sh logs -f

# Show only app logs
./scripts/passbolt-manager.sh logs -f app

# Show only database logs with last 500 lines
./scripts/passbolt-manager.sh logs -t 500 db
```

**Testing email configuration**:
```bash
./scripts/passbolt-manager.sh test-email test@example.com
```

**Showing Passbolt version information**:
```bash
./scripts/passbolt-manager.sh version
```

**Getting help for a specific command**:
```bash
./scripts/passbolt-manager.sh help register
```

## Backup and Restore

The project includes comprehensive backup and restore functionality to safeguard your Passbolt data. These scripts are designed to create complete, consistent backups and provide a reliable recovery mechanism.

### Backup System Architecture

The backup system is designed with the following principles:

1. **Completeness**: Capture all critical data required to restore Passbolt
2. **Consistency**: Ensure backups represent a consistent state of the system
3. **Verifiability**: Include checksums to verify backup integrity
4. **Automation**: Support scheduled backups through proper exit codes and quiet mode

### Backup Process

The `backup.sh` script creates a complete backup of your Passbolt installation, including:

- Database content (MySQL/MariaDB dump)
- GPG keys for encryption
- JWT keys for authentication
- Configuration files
- Environment variables
- User-uploaded images

#### Backup Script Flowchart

```
┌─────────────────┐
│ Parse Arguments │
└────────┬────────┘
         │
┌────────▼────────┐
│ Create Directory│
│    Structure    │
└────────┬────────┘
         │
┌────────▼────────┐
│  Check Docker & │
│   Containers    │
└────────┬────────┘
         │
┌────────▼────────┐
│ Backup Database │
└────────┬────────┘
         │
┌────────▼────────┐
│ Backup GPG Keys │
└────────┬────────┘
         │
┌────────▼────────┐
│ Backup JWT Keys │
└────────┬────────┘
         │
┌────────▼────────┐
│  Backup Images  │
└────────┬────────┘
         │
┌────────▼────────┐
│    Backup Config│
│       Files     │
└────────┬────────┘
         │
┌────────▼────────┐
│ Create Archive  │
│  & Checksum     │
└────────┬────────┘
         │
┌────────▼────────┐
│  Cleanup Old    │
│    Backups      │
└────────┬────────┘
         │
┌────────▼────────┐
│ Display Summary │
└─────────────────┘
```

#### Code Analysis: Backup Implementation

Let's examine some key components of the backup script:

**Initialization and Configuration**:

```bash
# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BASE_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/passbolt_backup_${TIMESTAMP}.tar.gz"
LOG_FILE="${BACKUP_DIR}/backup_${TIMESTAMP}.log"
TEMP_DIR="${BASE_DIR}/tmp/backup_${TIMESTAMP}"
RETENTION_DAYS=30
QUIET_MODE=0
```

This sets up:
- Directory paths relative to the script location
- Timestamped filenames for backups and logs
- Default settings for retention period and output mode

**Database Backup Function**:

```bash
backup_database() {
    print_section "Backing up database"
    log_message "Backing up database..."

    # Load database credentials from environment file
    if [ -f "${BASE_DIR}/env/db.env" ]; then
        source "${BASE_DIR}/env/db.env"
    else
        log_message "Database environment file not found, using default credentials" "WARNING"
        MYSQL_DATABASE="passbolt"
        MYSQL_USER="passbolt"
        MYSQL_PASSWORD="passbolt"
    fi

    # Execute mysqldump
    if docker exec -i $DB_CONTAINER mysqldump -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE} > "${TEMP_DIR}/passbolt_db.sql"; then
        log_message "Database backup completed" "SUCCESS"
        return 0
    else
        log_message "Database backup failed" "ERROR"
        return 1
    fi
}
```

This function:
1. Sources credentials from the `db.env` file
2. Falls back to default credentials if necessary
3. Executes mysqldump inside the database container
4. Saves the output to a SQL file in the temporary directory
5. Reports success or failure appropriately

**GPG Key Backup**:

```bash
backup_gpg_keys() {
    print_section "Backing up GPG keys"
    log_message "Backing up GPG keys..."

    mkdir -p "${TEMP_DIR}/data/gpg"

    if docker cp ${APP_CONTAINER}:/etc/passbolt/gpg/serverkey_private.asc "${TEMP_DIR}/data/gpg/" && \
       docker cp ${APP_CONTAINER}:/etc/passbolt/gpg/serverkey.asc "${TEMP_DIR}/data/gpg/"; then
        chmod 600 "${TEMP_DIR}/data/gpg/"*
        log_message "GPG keys backup completed" "SUCCESS"
        return 0
    else
        log_message "GPG keys backup failed" "ERROR"
        return 1
    fi
}
```

This function:
1. Creates the directory structure for GPG keys
2. Uses `docker cp` to copy the keys from the container
3. Sets appropriate permissions (important for security)
4. Returns the operation status

**Archive Creation and Verification**:

```bash
create_archive() {
    print_section "Creating archive"
    log_message "Creating compressed archive..."

    if tar -czf "$BACKUP_FILE" -C "$TEMP_DIR" .; then
        log_message "Archive created: $BACKUP_FILE" "SUCCESS"

        # Calculate checksum
        sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"
        log_message "Checksum file created: ${BACKUP_FILE}.sha256" "SUCCESS"

        return 0
    else
        log_message "Failed to create archive" "ERROR"
        return 1
    fi
}
```

This function:
1. Creates a compressed tar.gz archive from the temporary directory
2. Generates a SHA256 checksum file for later verification
3. Reports success or failure

**Retention Policy Implementation**:

```bash
cleanup_old_backups() {
    print_section "Cleaning up old backups"
    log_message "Removing backups older than ${RETENTION_DAYS} days..."

    find "$BACKUP_DIR" -name "passbolt_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "passbolt_backup_*.tar.gz.sha256" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "backup_*.log" -type f -mtime +$RETENTION_DAYS -delete

    log_message "Cleanup completed" "SUCCESS"
}
```

This function:
1. Uses `find` with `-mtime` to identify old files
2. Deletes outdated backups, checksum files, and logs
3. Maintains a clean backup directory according to the retention policy

#### Backup Features

- **Timestamped archives**: All backups are stored with datestamp in the filename
- **SHA256 checksum verification**: Each backup has an accompanying checksum file
- **Automatic cleanup**: Configurable retention period for old backups
- **Detailed logging**: Both console output and log files
- **Quiet mode**: For automated/scheduled backup operations
- **Custom backup location**: Configurable backup directory

#### Running a backup

```bash
./scripts/passbolt-manager.sh backup
```

#### Backup options

```bash
./scripts/passbolt-manager.sh backup -d /path/to/backup/dir -r 60 -q
```

- `-d DIR`: Specify backup directory (default: ../backups)
- `-r DAYS`: Days to keep backups (default: 30)
- `-q`: Quiet mode (suppress output except errors)

#### Scheduling Automated Backups

To schedule daily backups with cron:

```bash
# Edit crontab
crontab -e

# Add an entry for daily backups at 2 AM
0 2 * * * /path/to/passbolt/scripts/backup.sh -q
```

The quiet mode (`-q`) ensures that only errors are output, making it suitable for scheduled tasks.

### Restore Process

The `restore.sh` script provides a robust method for recovering your Passbolt installation from a backup archive.

#### Restore Script Flowchart

```
┌─────────────────┐
│ Parse Arguments │
└────────┬────────┘
         │
┌────────▼────────┐
│   Confirm with  │
│      User       │
└────────┬────────┘
         │
┌────────▼────────┐
│ Verify Backup   │
│   Integrity     │
└────────┬────────┘
         │
┌────────▼────────┐
│ Extract Backup  │
└────────┬────────┘
         │
┌────────▼────────┐
│ Validate Backup │
│    Contents     │
└────────┬────────┘
         │
┌────────▼────────┐
│ Stop Running    │
│   Containers    │
└────────┬────────┘
         │
┌────────▼────────┐
│ Restore Config  │
│     Files       │
└────────┬────────┘
         │
┌────────▼────────┐
│ Restore GPG &   │
│    JWT Keys     │
└────────┬────────┘
         │
┌────────▼────────┐
│ Restore User    │
│    Images       │
└────────┬────────┘
         │
┌────────▼────────┐
│ Start Database  │
│   Container     │
└────────┬────────┘
         │
┌────────▼────────┐
│ Restore Database│
└────────┬────────┘
         │
┌────────▼────────┐
│ Start All       │
│   Containers    │
└────────┬────────┘
         │
┌────────▼────────┐
│  Check Health   │
└─────────────────┘
```

#### Code Analysis: Restore Implementation

Let's examine key components of the restore script:

**Confirmation Mechanism**:

```bash
confirm_restore() {
    if [ $FORCE_RESTORE -eq 1 ]; then
        return 0
    fi

    print_header "CAUTION: Restore Operation"

    echo -e "${COLOR_YELLOW}You are about to restore Passbolt from a backup.${COLOR_NC}"
    echo "This operation will:"
    echo "  1. Stop all running Passbolt containers"
    echo "  2. Replace existing database content"
    echo "  3. Replace GPG and JWT keys"
    echo "  4. Replace configuration files"
    echo ""
    echo -e "${COLOR_YELLOW}Make sure you have a recent backup before proceeding.${COLOR_NC}"
    echo ""

    read -p "Continue with restore? (y/N): " confirm

    if [[ "$confirm" != [Yy]* ]]; then
        log_message "Restore cancelled by user" "WARNING"
        return 1
    fi

    return 0
}
```

This function:
1. Bypasses confirmation if force mode is enabled
2. Displays a warning about the impacts of restore
3. Requires explicit confirmation from the user
4. Returns appropriate status based on user input

**Backup Integrity Verification**:

```bash
verify_backup() {
    local backup_file="$1"
    local checksum_file="${backup_file}.sha256"

    if [ $SKIP_VERIFY -eq 1 ]; then
        log_message "Backup verification skipped (--skip-verify)" "WARNING"
        return 0
    fi

    print_section "Verifying backup integrity"

    # Check if checksum file exists
    if [ ! -f "$checksum_file" ]; then
        log_message "Checksum file not found: $checksum_file" "WARNING"
        log_message "Continuing without verification" "WARNING"
        return 0
    fi

    # Verify checksum
    if sha256sum -c "$checksum_file" &>/dev/null; then
        log_message "Backup integrity verified" "SUCCESS"
        return 0
    else
        log_message "Backup integrity check failed!" "ERROR"
        return 1
    fi
}
```

This function:
1. Locates the checksum file for the backup
2. Skips verification if requested by the user
3. Verifies the backup integrity using SHA256 checksums
4. Provides appropriate feedback based on the result

**Database Restoration**:

```bash
restore_database() {
    local sql_file="$1"

    print_section "Restoring database"
    log_message "Restoring database from backup..." "INFO"

    # Load database credentials from environment file
    if [ -f "${BASE_DIR}/env/db.env" ]; then
        source "${BASE_DIR}/env/db.env"
    else
        log_message "Database environment file not found, using default credentials" "WARNING"
        MYSQL_DATABASE="passbolt"
        MYSQL_USER="passbolt"
        MYSQL_PASSWORD="passbolt"
    fi

    # Execute restore
    if cat "$sql_file" | docker exec -i $DB_CONTAINER mysql -u${MYSQL_USER} -p${MYSQL_PASSWORD} ${MYSQL_DATABASE}; then
        log_message "Database restored successfully" "SUCCESS"
        return 0
    else
        log_message "Database restoration failed" "ERROR"
        return 1
    fi
}
```

This function:
1. Sources database credentials from environment file
2. Pipes the SQL dump into the MySQL client inside the container
3. Reports the success or failure of the database restore

**Health Check After Restore**:

```bash
check_health() {
    print_section "Checking Passbolt health"
    log_message "Running health check..." "INFO"

    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running, cannot check health" "ERROR"
        return 1
    fi

    # Run health check
    if docker exec -i "$APP_CONTAINER" su -c "/usr/share/php/passbolt/bin/cake passbolt healthcheck" -s /bin/sh www-data; then
        log_message "Health check passed" "SUCCESS"
        return 0
    else
        log_message "Health check reported issues" "WARNING"
        return 1
    fi
}
```

This function:
1. Verifies the Passbolt container is running
2. Executes the built-in Passbolt health check
3. Reports the health status after restore

#### Running a restore

```bash
./scripts/passbolt-manager.sh restore /path/to/passbolt_backup_20250507_112532.tar.gz
```

#### Restore options

```bash
./scripts/passbolt-manager.sh restore -f -s -n /path/to/passbolt_backup_20250507_112532.tar.gz
```

- `-f`: Force restore without confirmation
- `-s`: Skip backup integrity verification
- `-n`: Don't start containers after restore

> **⚠️ WARNING**: The restore process will replace all existing data, including:
> - Database content (passwords, users, groups, etc.)
> - GPG and JWT keys (these control encryption and authentication)
> - Configuration files (app settings)
> - User-uploaded images
>
> Always make sure you understand the implications before proceeding with a restore operation.

#### Restore Scenarios

**Disaster Recovery**

In case of a complete system failure:

1. Set up a new server with Docker and Docker Compose
2. Install the basic directory structure
3. Copy your backup file to the new server
4. Run the restore script
5. Verify the health of the restored instance

**Migration to a New Server**

When migrating to a new environment:

1. Create a backup on the source server
2. Transfer the backup to the destination server
3. Set up the basic Passbolt directory structure
4. Run the restore script
5. Update DNS or IP addresses as needed

**Recovery from Data Corruption**

If you experience data corruption issues:

1. Stop all Passbolt containers
2. Restore from the most recent backup
3. Check logs for any errors during the restore process
4. Run the healthcheck to verify data integrity

# Nginx Configuration

The Nginx configuration serves as the web server and reverse proxy for the deployment, handling SSL termination and security headers. This section explains the configuration structure and how to customize it for your environment.

## Configuration Structure

The Nginx configuration is organized as follows:

```
config/nginx/
├── conf.d/                # Virtual host configurations
│   ├── default.conf       # Default server block
│   ├── passbolt.conf      # Passbolt-specific server block
│   └── security.conf      # Common security headers
├── nginx.conf             # Main Nginx configuration
└── ssl/                   # SSL certificates
    ├── certs/             # Public certificates
    └── private/           # Private keys
```

## Key Configuration Files

### 1. Main Configuration (`nginx.conf`)

The main Nginx configuration file contains global settings:

```nginx
user  nginx;
worker_processes  auto;

# Critical performance and security settings
http {
    server_tokens off;  # Hide Nginx version
    client_max_body_size 100M;  # Allow larger file uploads
    
    # Include virtual host configurations
    include /etc/nginx/conf.d/*.conf;
}
```

### 2. Security Headers (`security.conf`)

Defines common security headers:

```nginx
# Security headers for all server blocks
map $host $security_headers {
    default "X-Frame-Options: SAMEORIGIN
             X-Content-Type-Options: nosniff
             X-XSS-Protection: 1; mode=block";
}
```

### 3. Default Server Block (`default.conf`)

Handles requests that don't match other server names:

```nginx
server {
    listen 80 default_server;
    server_name _;
    return 444;  # Connection closed without response
}
```

### 4. Passbolt Server Block (`passbolt.conf`)

The main configuration for the Passbolt application:

```nginx
# HTTP redirect
server {
    listen 80;
    server_name <your_server_name>;
    return 301 https://$host$request_uri;
}

# HTTPS server
server {
    listen 443 ssl;
    server_name <your_server_name>;
    
    # SSL configuration
    ssl_certificate /etc/ssl/certs/passbolt.crt;
    ssl_certificate_key /etc/ssl/private/passbolt.key;
    
    # Proxy to Passbolt app container
    location / {
        proxy_pass https://passbolt-app;
        proxy_set_header Host $host;
    }
}
```

## Customizing for Your Environment

You need to replace `<your_server_name>` in `passbolt.conf` with your actual domain or IP:

```bash
# Edit the passbolt.conf file
sed -i 's/<your_server_name>/passbolt.example.com/g' config/nginx/conf.d/passbolt.conf
```

## Generating Self-Signed SSL Certificates

For testing or internal deployments:

```bash
# Create directories
mkdir -p config/nginx/ssl/{certs,private}

# Generate certificate
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout config/nginx/ssl/private/passbolt.key \
  -out config/nginx/ssl/certs/passbolt.crt \
  -subj "/CN=passbolt.example.com"

# Set permissions
chmod 600 config/nginx/ssl/private/passbolt.key
chmod 644 config/nginx/ssl/certs/passbolt.crt
```

## Using Let's Encrypt for Production

For public-facing deployments, use Let's Encrypt for free, trusted certificates:

```bash
# Install certbot
apt-get update && apt-get install -y certbot

# Obtain certificate (stop Nginx first)
docker-compose down
certbot certonly --standalone -d passbolt.example.com

# Copy certificates
cp /etc/letsencrypt/live/passbolt.example.com/fullchain.pem \
   config/nginx/ssl/certs/passbolt.crt
cp /etc/letsencrypt/live/passbolt.example.com/privkey.pem \
   config/nginx/ssl/private/passbolt.key
```

## Testing Your Configuration

After making changes:

```bash
# Check configuration syntax
docker-compose exec passbolt-nginx nginx -t

# Apply changes
docker-compose restart passbolt-nginx
```

Remember to ensure that the `APP_FULL_BASE_URL` in your `passbolt.env` file matches the server name used in your Nginx configuration.

## GPG Key Setup for Docker Deployment

Passbolt uses GPG (GNU Privacy Guard) keys for encrypting and decrypting passwords. This is a critical security component of the system - these keys protect all passwords stored in the database. When deploying Passbolt in Docker, special consideration is needed for these keys.

### Understanding GPG Keys in Passbolt

Passbolt uses two types of GPG keys:

1. **Server GPG Keys**: Used by the Passbolt server to encrypt/decrypt data
   - **Private Key**: Used by the server to decrypt passwords
   - **Public Key**: Used by clients to encrypt passwords for the server

2. **User GPG Keys**: Generated during user setup
   - Each user has their own keypair
   - The public key is shared with the server
   - The private key is stored in the user's browser extension

### Common Challenges with Docker Deployment

In a Docker environment, there are several challenges with GPG keys:

1. **Passphrase limitations**: The PHP-GNUPG module used by Passbolt does not support passphrase-protected keys in containerized environments.
2. **Persistence**: Keys must persist across container restarts and updates.
3. **Permissions**: Keys need specific ownership and permissions inside the container.
4. **Path consistency**: The GNUPGHOME environment variable must be correctly set.

### Step-by-Step Key Generation Process

#### Step 1: Generate GPG Keys Without Passphrase

```bash
# Change to the Passbolt directory
cd passbolt-docker

# Set your email and name variables
EMAIL="server@yourdomain.com"
REAL_NAME="Passbolt Server Key"
KEY_LENGTH=3072

# Create the GPG directory if it doesn't exist
mkdir -p config/passbolt/gpg

# Generate a new GPG key without a passphrase
gpg --batch --no-tty --gen-key <<EOF
Key-Type: default
Key-Length: $KEY_LENGTH
Subkey-Type: default
Subkey-Length: $KEY_LENGTH
Name-Real: $REAL_NAME
Name-Email: $EMAIL
Expire-Date: 0
%no-protection
%commit
EOF
```

This command:
- Creates a 3072-bit GPG key (strong encryption)
- Sets the real name and email for the key
- Creates a key that never expires
- Most importantly, uses `%no-protection` to create a key without a passphrase

#### Step 2: Export the Keys to the Passbolt Configuration Directory

```bash
# Export the public key
gpg --armor --export $EMAIL > config/passbolt/gpg/serverkey.asc

# Export the private key
gpg --armor --export-secret-key $EMAIL > config/passbolt/gpg/serverkey_private.asc

# Verify the exported keys
echo "Public key:"
gpg --show-keys config/passbolt/gpg/serverkey.asc
echo "Private key:"
gpg --show-keys config/passbolt/gpg/serverkey_private.asc
```

#### Step 3: Set Proper Permissions for the Keys

```bash
# Set secure permissions
chmod 640 config/passbolt/gpg/serverkey*.asc

# Set ownership to www-data (UID 33 in the container)
chown -R 33:33 config/passbolt/gpg
```

The permission setting is crucial:
- `640` means readable by owner and group, not by others
- Setting ownership to the www-data user (UID 33) ensures the application can read the keys

#### Step 4: Get the Key Fingerprint

```bash
# Get the GPG key fingerprint (needed for configuration)
FINGERPRINT=$(gpg --list-keys --with-colons $EMAIL | grep fpr | head -1 | cut -d: -f10)
echo "Your GPG key fingerprint is: $FINGERPRINT"

# Save it for later use
echo "PASSBOLT_GPG_SERVER_KEY_FINGERPRINT=$FINGERPRINT" > gpg_fingerprint.txt
```

The fingerprint is a unique identifier for your GPG key and is required in the Passbolt configuration.

#### Step 5: Update Environment Configuration

Edit `env/passbolt.env` to include these GPG-related settings:

```ini
# GPG specific environment variables
PASSBOLT_GPG_SERVER_KEY_FINGERPRINT=71602B82E05265FC15E17CEEB0976BB67DC24A0F
PASSBOLT_GPG_SERVER_KEY_PUBLIC=/etc/passbolt/gpg/serverkey.asc
PASSBOLT_GPG_SERVER_KEY_PRIVATE=/etc/passbolt/gpg/serverkey_private.asc
PASSBOLT_KEY_EMAIL=server@yourdomain.com

# Additional GPG settings that help with verification issues
GNUPGHOME=/var/lib/passbolt/.gnupg
PASSBOLT_GPG_SERVER_KEY_PASSPHRASE=
PASSBOLT_GPG_HOME=/var/lib/passbolt/.gnupg
```

Note the following important settings:
- `PASSBOLT_GPG_SERVER_KEY_FINGERPRINT`: The fingerprint from Step 4
- `PASSBOLT_GPG_SERVER_KEY_PASSPHRASE=`: An empty string explicitly tells Passbolt there is no passphrase
- `GNUPGHOME` and `PASSBOLT_GPG_HOME`: Both set to the same path to ensure consistency

#### Step 6: Configure Docker Compose

Ensure your `docker-compose.yml` correctly mounts the GPG keys:

```yaml
services:
  passbolt:
    image: passbolt/passbolt:latest-ce
    # ... other configuration ...
    volumes:
      - ./config/passbolt/gpg:/etc/passbolt/gpg:ro
      # ... other volumes ...
``Nginx Configuration

The Nginx configuration serves as the web server and reverse proxy for your Passbolt deployment, handling SSL termination and security headers. This section explains the configuration structure and how to customize it for your environment.
Configuration Structure

The Nginx configuration is organized as follows:

config/nginx/
├── conf.d/                # Virtual host configurations
│   ├── default.conf       # Default server block
│   ├── passbolt.conf      # Passbolt-specific server block
│   └── security.conf      # Common security headers
├── nginx.conf             # Main Nginx configuration
└── ssl/                   # SSL certificates
    ├── certs/             # Public certificates
    └── private/           # Private keys

Key Configuration Files

    Main Configuration (nginx.conf): Contains global settings for performance, security, and logging
    Security Headers (security.conf): Defines security headers applied across all server blocks
    Default Server Block (default.conf): Catch-all configuration that returns a 444 status for undefined hostnames
    Passbolt Server Block (passbolt.conf): The main configuration for Passbolt that:
        Redirects HTTP to HTTPS
        Configures SSL with strong cipher suites
        Adds security headers
        Sets up reverse proxying to the Passbolt container

Customizing for Your Environment

Before deploying, you need to customize the passbolt.conf file:

bash

# Edit the passbolt.conf file to set your domain or IP
sed -i 's/<your_server_name>/passbolt.example.com/g' config/nginx/conf.d/passbolt.conf

Replace passbolt.example.com with your actual domain name or IP address.
Generating Self-Signed SSL Certificates

For testing or internal deployments, you can generate self-signed certificates:

bash

# Create directories if they don't exist
mkdir -p config/nginx/ssl/certs
mkdir -p config/nginx/ssl/private

# Generate a private key
openssl genrsa -out config/nginx/ssl/private/passbolt.key 4096

# Generate a self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
  -keyout config/nginx/ssl/private/passbolt.key \
  -out config/nginx/ssl/certs/passbolt.crt \
  -subj "/CN=passbolt.example.com/O=Passbolt/C=US"

# Set appropriate permissions
chmod 644 config/nginx/ssl/certs/passbolt.crt
chmod 600 config/nginx/ssl/private/passbolt.key

    Note: For production environments, it's strongly recommended to use certificates from a trusted Certificate Authority (CA) like Let's Encrypt.

Using Let's Encrypt for Production

For public-facing deployments, consider using Let's Encrypt for free, trusted certificates:

bash

# Install certbot (on the host)
apt-get update
apt-get install -y certbot

# Obtain a certificate (stop Nginx first)
docker-compose down
certbot certonly --standalone -d passbolt.example.com

# Copy the certificates
cp /etc/letsencrypt/live/passbolt.example.com/fullchain.pem \
   config/nginx/ssl/certs/passbolt.crt
cp /etc/letsencrypt/live/passbolt.example.com/privkey.pem \
   config/nginx/ssl/private/passbolt.key

# Set permissions and restart
chmod 644 config/nginx/ssl/certs/passbolt.crt
chmod 600 config/nginx/ssl/private/passbolt.key
docker-compose up -d

Testing Your Configuration

After making changes, test the Nginx configuration for syntax errors:

bash

docker-compose exec passbolt-nginx nginx -t

If successful, restart Nginx to apply changes:

bash

docker-compose restart passbolt-nginx

Remember to ensure that the APP_FULL_BASE_URL in your passbolt.env file matches the server name used in your Nginx configuration.## Security Considerations

When deploying Passbolt, security should be a top priority as it will store sensitive passwords for your organization.`

The `:ro` suffix mounts the directory as read-only, which is a security best practice.

#### Step 7: Verify the Setup

After starting your containers, verify that the GPG keys are working correctly:

```bash
# Run the Passbolt healthcheck
docker exec -it passbolt-app bash -c "su -s /bin/bash -c '/usr/share/php/passbolt/bin/cake passbolt healthcheck' www-data"
```

Look for a section about GPG in the healthcheck output. A successful setup will show:

```
[PASS] The GnuPG environment is ready to use.
[PASS] The public key can be used to encrypt a message.
[PASS] The private key can be used to decrypt a message.
[PASS] The server key can be used to sign a message.
[PASS] The server key can be used to verify a signature.
```

### Troubleshooting GPG Issues

If you encounter GPG-related problems, here are some common solutions:

#### Issue: "[FAIL] The private key cannot be used to decrypt a message"

This is the most common issue and usually means one of the following:

1. **The key has a passphrase**:
   - Recreate the key without a passphrase using `%no-protection`
   - Ensure `PASSBOLT_GPG_SERVER_KEY_PASSPHRASE=` is set to empty

2. **Permission problems**:
   ```bash
   # Fix permissions
   chmod 640 config/passbolt/gpg/serverkey*.asc
   chown 33:33 config/passbolt/gpg/*
   
   # Check permissions inside the container
   docker exec -it passbolt-app ls -la /etc/passbolt/gpg
   ```

3. **GNUPGHOME not set correctly**:
   - Ensure both `GNUPGHOME` and `PASSBOLT_GPG_HOME` are set to `/var/lib/passbolt/.gnupg`
   - Verify the directory exists inside the container:
   ```bash
   docker exec -it passbolt-app mkdir -p /var/lib/passbolt/.gnupg
   docker exec -it passbolt-app chown -R www-data:www-data /var/lib/passbolt/.gnupg
   docker exec -it passbolt-app chmod 700 /var/lib/passbolt/.gnupg
   ```

#### Issue: "Error loading key"

This typically means the key format is incorrect or the file is not readable:

1. **Verify key format**:
   ```bash
   gpg --show-keys config/passbolt/gpg/serverkey.asc
   gpg --show-keys config/passbolt/gpg/serverkey_private.asc
   ```

2. **Check if the key is ASCII-armored**:
   - Keys should begin with `-----BEGIN PGP PUBLIC KEY BLOCK-----` or `-----BEGIN PGP PRIVATE KEY BLOCK-----`
   - If not, export them again with the `--armor` flag

#### Issue: "Wrong fingerprint in configuration"

If the fingerprint in your configuration doesn't match the actual key:

```bash
# Get the actual fingerprint
gpg --show-keys config/passbolt/gpg/serverkey.asc | grep "Key fingerprint"

# Update the configuration in env/passbolt.env
vi env/passbolt.env
# Update PASSBOLT_GPG_SERVER_KEY_FINGERPRINT value

# Restart the container
docker-compose restart passbolt
```

### Security Best Practices for GPG Keys

1. **Backup your GPG keys securely**:
   ```bash
   # Copy to a secure location
   cp config/passbolt/gpg/serverkey*.asc /secure/backup/location/
   ```

2. **Never share the private key**:
   - The private key should only exist on the Passbolt server
   - Compromise of this key would allow decryption of all passwords

3. **Periodic key rotation**:
   - Consider rotating the server GPG key annually
   - This requires careful planning as it affects all encrypted data

4. **Monitor access to key files**:
   - Set up file integrity monitoring for the GPG key files
   - Log all access attempts to these files

By following these steps and best practices, you'll have a properly configured GPG setup for your Passbolt Docker deployment, which is essential for the secure operation of the password manager.

## Two-Factor Authentication

Passbolt supports two-factor authentication (2FA) using Time-based One-Time Password (TOTP) to add an extra layer of security.

### Understanding TOTP Authentication

TOTP authentication works as follows:
1. Users set up a TOTP app (like Google Authenticator, Authy, or Microsoft Authenticator) on their mobile device
2. The app generates a time-based code that changes every 30 seconds
3. After entering their password, users must also enter the current code from their TOTP app
4. This provides an additional security layer as attackers would need both the password and physical access to the user's device

### User Setup for TOTP Authentication

As a user, you can set up TOTP authentication by following these steps:

1. Log in to Passbolt
2. Go to Profile > Multi-Factor Authentication > Set up TOTP
3. Scan the QR code with your TOTP app (Google Authenticator, Authy, etc.)
4. Enter the verification code from the app to confirm setup
5. Save your recovery codes securely (these will be needed if you lose your device)

After setting up TOTP:
- You'll need to enter both your password and the current TOTP code when logging in
- Each code is valid for 30 seconds, after which a new code is generated
- If you get a "Invalid verification code" message, ensure your device's time is synchronized correctly

### Recovery Procedures

If you lose access to your TOTP device:

1. At the Passbolt login prompt, enter your email and password
2. When prompted for the TOTP code, click "Lost your device?"
3. Enter one of the recovery codes provided during setup
   - Each recovery code can only be used once
   - Recovery codes should be stored securely, separate from your password
4. After using a recovery code, you should immediately set up TOTP on a new device

If you've lost both your TOTP device and recovery codes:
1. Contact your Passbolt administrator
2. They will need to verify your identity through alternative means
3. The administrator can reset your TOTP provider
4. You'll need to set up TOTP again upon your next login

## Troubleshooting

### Common Issues and Solutions

This section covers common issues you might encounter with your Passbolt Docker deployment and their solutions.

#### Database Connection Issues

**Symptom**: Passbolt shows "Could not connect to database" error, or the healthcheck reports database connection problems.

**Solutions**:
1. **Check database service**:
   ```bash
   # Check if database container is running
   docker ps | grep passbolt-db
   
   # Check database logs
   docker logs passbolt-db
   ```

2. **Verify database credentials**:
   - Ensure credentials in `db.env` match those in `passbolt.env`
   - Check that the database host is correctly set to `passbolt-db` in `passbolt.env`

3. **Check database initialization**:
   ```bash
   # Connect to the database to verify it exists
   docker exec -it passbolt-db mysql -uroot -p
   # Enter the root password, then:
   SHOW DATABASES;
   USE passbolt;
   SHOW TABLES;
   ```

4. **Recreate the database** (as a last resort):
   ```bash
   # Stop containers
   docker-compose down
   
   # Remove database volume
   rm -rf ./data/mariadb
   
   # Restart containers (database will be recreated)
   docker-compose up -d
   ```

#### SSL/HTTPS Issues

**Symptom**: Browser shows SSL errors, or Passbolt healthcheck reports SSL issues.

**Solutions**:
1. **Check certificate paths**:
   - Verify that SSL certificates exist at the paths specified in the volume mounts
   ```bash
   ls -la config/nginx/ssl/certs/passbolt.crt
   ls -la config/nginx/ssl/private/passbolt.key
   ```

2. **Verify certificate validity**:
   ```bash
   # Check certificate details
   openssl x509 -in config/nginx/ssl/certs/passbolt.crt -text -noout
   ```

3. **Check Nginx configuration**:
   ```bash
   # Verify Nginx config
   docker exec -it passbolt-nginx nginx -t
   
   # Check Nginx logs
   docker logs passbolt-nginx
   ```

4. **Ensure URL configuration matches certificate**:
   - The `APP_FULL_BASE_URL` in `passbolt.env` should match the domain in your SSL certificate

#### User Registration Issues

**Symptom**: New users can't register, or they don't receive registration emails.

**Solutions**:
1. **Check email configuration**:
   ```bash
   # Test email configuration
   ./scripts/passbolt-manager.sh test-email test@example.com
   
   # Check email logs
   docker logs passbolt-app | grep -i email
   ```

2. **Verify registration settings**:
   - Check that `PASSBOLT_REGISTRATION_PUBLIC=true` is set in `passbolt.env` if you want public registration
   - For invitation-only, try registering a user manually:
   ```bash
   ./scripts/passbolt-manager.sh register newuser@example.com "First" "Last"
   ```

3. **Check SMTP server connectivity**:
   ```bash
   # From inside the container
   docker exec -it passbolt-app bash
   ping smtp.serviciodecorreo.es
   telnet smtp.serviciodecorreo.es 587
   ```

#### GPG Key Issues

**Symptom**: Healthcheck reports GPG key problems or users get encryption/decryption errors.

**Solutions**:
1. **Run a focused GPG healthcheck**:
   ```bash
   docker exec -it passbolt-app su -c "/usr/share/php/passbolt/bin/cake passbolt healthcheck --gpg" -s /bin/sh www-data
   ```

2. **Check key permissions inside container**:
   ```bash
   docker exec -it passbolt-app ls -la /etc/passbolt/gpg
   ```

3. **Validate key files**:
   ```bash
   # Check if keys are valid
   gpg --show-keys config/passbolt/gpg/serverkey.asc
   gpg --show-keys config/passbolt/gpg/serverkey_private.asc
   ```

4. **Verify fingerprint matches**:
   ```bash
   # Get key fingerprint
   gpg --show-keys config/passbolt/gpg/serverkey.asc | grep "Key fingerprint"
   
   # Compare with configuration
   grep FINGERPRINT env/passbolt.env
   ```

For more detailed GPG troubleshooting, refer to the [GPG Key Setup](#gpg-key-setup-for-docker-deployment) section.

#### Container Startup Issues

**Symptom**: Containers fail to start or crash shortly after starting.

**Solutions**:
1. **Check container logs**:
   ```bash
   docker-compose logs --tail=100
   ```

2. **Inspect container state**:
   ```bash
   docker inspect passbolt-app | grep -A 10 "State"
   ```

3. **Check for port conflicts**:
   ```bash
   # See if ports 443 or 8080 are already in use
   netstat -tuln | grep -E '443|8080'
   ```

4. **Check for volume mounting issues**:
   ```bash
   # Verify volume mounts
   docker inspect passbolt-app | grep -A 20 "Mounts"
   ```

#### Data Integrity Issues

**Symptom**: Passbolt reports data integrity problems, or you see unusual behavior.

**Solutions**:
1. **Run the cleanup tool**:
   ```bash
   ./scripts/passbolt-manager.sh cleanup
   ```

2. **Verify database integrity**:
   ```bash
   docker exec -it passbolt-db mysqlcheck -u passbolt -p --all-databases
   ```

3. **Check for disk space issues**:
   ```bash
   df -h
   ```

4. **Restore from a backup** (if necessary):
   ```bash
   ./scripts/passbolt-manager.sh restore /path/to/backup.tar.gz
   ```

### Advanced Troubleshooting

#### Debug Mode

For deeper troubleshooting, you can enable debug mode:

1. **Enable debug in configuration**:
   Edit `env/passbolt.env` and add:
   ```
   APP_DEBUG=true
   ```

2. **Restart the Passbolt container**:
   ```bash
   docker-compose restart passbolt
   ```

3. **View debug logs**:
   ```bash
   docker logs passbolt-app
   ```

#### Database Console

Access the MariaDB console for direct database queries:

```bash
docker exec -it passbolt-db mysql -u passbolt -p passbolt
```

Example useful queries:
```sql
-- Check user count
SELECT COUNT(*) FROM users;

-- Check active/deleted users
SELECT COUNT(*), deleted FROM users GROUP BY deleted;

-- Check resource (password) count
SELECT COUNT(*) FROM resources;
```

#### Reading Passbolt Logs

Passbolt logs can be found inside the container:

```bash
# View application logs
docker exec -it passbolt-app cat /var/log/passbolt/error.log
docker exec -it passbolt-app cat /var/log/passbolt/passbolt.log
```

#### Network Debugging

If you suspect network issues between containers:

```bash
# Install debugging tools in Passbolt container
docker exec -it passbolt-app apt-get update
docker exec -it passbolt-app apt-get install -y iputils-ping net-tools

# Test database connectivity
docker exec -it passbolt-app ping passbolt-db
docker exec -it passbolt-app telnet passbolt-db 3306
```

## Maintenance Tasks

Regular maintenance helps keep your Passbolt instance secure and performant. This section outlines recommended maintenance procedures and best practices.

### Regular Maintenance Schedule

| Frequency | Task | Command/Action |
|-----------|------|----------------|
| Daily | Backup | `./scripts/passbolt-manager.sh backup` |
| Weekly | Health check | `./scripts/passbolt-manager.sh healthcheck` |
| Weekly | Log review | `./scripts/passbolt-manager.sh logs -t 1000` |
| Monthly | Cleanup | `./scripts/passbolt-manager.sh cleanup` |
| Monthly | Update containers | See [Update Procedure](#update-procedure) |
| Quarterly | Security check | Audit users and access controls |
| Annually | GPG key rotation | Replace server GPG keys |

### Update Procedure

To update Passbolt to a newer version:

```bash
# 1. Create a backup first
./scripts/passbolt-manager.sh backup

# 2. Pull the latest images
docker-compose pull

# 3. Restart containers with new images
docker-compose down
docker-compose up -d

# 4. Verify the installation
./scripts/passbolt-manager.sh healthcheck
```

For major version updates, check the [Passbolt release notes](https://github.com/passbolt/passbolt_api/releases) for any specific update instructions.

### Database Maintenance

Periodic database maintenance keeps your Passbolt instance performing optimally:

```bash
# Check and repair tables
docker exec -it passbolt-db mysqlcheck -u passbolt -p --auto-repair passbolt

# Optimize tables
docker exec -it passbolt-db mysqlcheck -u passbolt -p --optimize passbolt
```

### Log Rotation

The Docker containers handle log rotation internally, but you should monitor log directory sizes:

```bash
# Check log directory size
docker exec -it passbolt-app du -sh /var/log/passbolt

# If needed, manually clean old logs
docker exec -it passbolt-app find /var/log/passbolt -name "*.log.*" -mtime +30 -delete
```

### Security Maintenance

Regular security maintenance is critical for a password manager:

1. **Keep containers updated**: Regularly pull and deploy the latest images
2. **Audit user accounts**: Regularly review active users and permissions
3. **Update SSL certificates**: Renew before expiration and deploy
4. **Review access logs**: Check for unusual access patterns
5. **Monitor security announcements**: Follow the Passbolt security feed for vulnerability notices

### Backup Management Strategy

Implement a comprehensive backup strategy:

1. **Automated daily backups**: Schedule with cron
   ```bash
   # Example cron job for daily backup at 2 AM
   0 2 * * * /path/to/passbolt/scripts/backup.sh -q
   ```

2. **Offsite storage**: Copy backups to a remote location
   ```bash
   # Example: Copy to a remote server
   rsync -avz /path/to/passbolt/backups/ user@remote-server:/backup/passbolt/
   ```

3. **Backup testing**: Regularly test restore functionality
   ```bash
   # Create a test environment and restore a backup
   ./scripts/restore.sh -n /path/to/backup.tar.gz
   ```

4. **Retention policy**: Configure backup retention based on your needs
   ```bash
   # Adjust retention period (e.g., keep backups for 60 days)
   ./scripts/backup.sh -r 60
   ```

### Disaster Recovery Planning

Prepare for potential disasters:

1. **Document recovery procedures**: Keep detailed recovery instructions
2. **Maintain offline copies of keys**: Securely store GPG keys offline
3. **Regular recovery drills**: Practice full recovery procedures
4. **Multiple backup copies**: Store backups in multiple secure locations

## Best Practices for Production Deployment

For a production-grade Passbolt deployment, consider these additional recommendations:

### Security Hardening

1. **Use a reverse proxy**: Consider adding Traefik or a dedicated NGINX proxy with enhanced security headers
2. **Implement rate limiting**: Protect against brute force attempts
3. **IP restrictions**: Limit access to trusted IP ranges where possible
4. **Regular security audits**: Perform periodic security assessments

### Performance Optimization

1. **Database tuning**: Adjust MariaDB configuration for your workload
   ```bash
   # Create a custom my.cnf for the MariaDB container
   mkdir -p config/mysql
   # Add custom configuration
   echo "[mysqld]
   innodb_buffer_pool_size = 256M
   key_buffer_size =

## Security Considerations

When deploying Passbolt, security should be a top priority as it will store sensitive passwords for your organization.

### Secure Configuration

1. **Strong Passwords**: Use strong, unique passwords for:
   - Database root and user accounts
   - GPG key generation (if using a passphrase)
   - JWT key protection

2. **Proper Permissions**: Ensure proper file permissions:
   - GPG keys: `chmod 640 config/passbolt/gpg/serverkey*.asc`
   - JWT keys: `chmod 640 config/passbolt/jwt/jwt.*`
   - SSL certificates: `chmod 640 config/nginx/ssl/private/passbolt.key`

3. **Network Security**:
   - Use a firewall to restrict access to Passbolt
   - Consider placing Passbolt behind a VPN for additional security
   - Configure HTTPS properly with strong cipher suites

### Repository Security

When storing your Passbolt configuration in version control:

1. **Use .gitignore**: Configure `.gitignore` to exclude sensitive files:
   ```
   # Ignore actual environment files
   /env/*.env
   # Ignore GPG and JWT keys
   /config/passbolt/gpg/*
   /config/passbolt/jwt/*
   # ... more patterns
   ```

2. **Pre-commit Hook**: Set up a pre-commit hook to prevent accidentally committing sensitive files

3. **Example Files**: Use sanitized example files for documentation:
   - Replace actual credentials with placeholders
   - Store in `env/examples/` directory
   - Document required configuration clearly

4. **Directory Structure**: Preserve the directory structure with `.gitkeep` files:
   ```bash
   touch config/passbolt/gpg/.gitkeep
   touch config/passbolt/jwt/.gitkeep
   # ... other empty directories
   ```

### Production Hardening

For production deployments, consider these additional security measures:

1. **Regular Updates**: Keep Passbolt and all containers updated
2. **Intrusion Detection**: Monitor for unauthorized access attempts
3. **Backup Encryption**: Encrypt backup archives
4. **Access Logging**: Enable and monitor access logs
5. **Multi-Factor Authentication**: Enable TOTP for all users

### Setting Up a Pre-commit Hook for Security

A pre-commit hook is a script that Git runs automatically before a commit is created. In this project, we use a pre-commit hook to prevent sensitive files from being accidentally committed to the repository.

#### Why Use a Pre-commit Hook?

When managing a password manager like Passbolt, you'll be working with sensitive files including:
- GPG encryption keys
- JWT authentication keys
- SSL certificates
- Environment files with credentials

Accidentally committing these files to a public repository could expose sensitive information. The pre-commit hook acts as a safety net to prevent such accidents.

#### Setting Up the Pre-commit Hook

##### Step 1: Create the hooks directory (if it doesn't exist)

```bash
mkdir -p .git/hooks
```

##### Step 2: Create the pre-commit file

```bash
# Create the pre-commit hook file
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
# Pre-commit hook to prevent committing sensitive files

# Check for sensitive files
SENSITIVE_FILES=$(git diff --cached --name-only | grep -E '(serverkey.*\.asc|jwt\.(key|pem)|passbolt\.crt|passbolt\.key|db\.env|email\.env|nginx\.env|passbolt\.env)$')

if [ -n "$SENSITIVE_FILES" ]; then
  echo "ERROR: Attempting to commit sensitive files:"
  echo "$SENSITIVE_FILES"
  echo ""
  echo "These files may contain secrets and should not be committed."
  echo "If you're sure these files don't contain sensitive information,"
  echo "you can use --no-verify to bypass this check."
  exit 1
fi

# Continue with the commit if no sensitive files were found
exit 0
EOF
```

##### Step 3: Make the hook executable

```bash
chmod +x .git/hooks/pre-commit
```


