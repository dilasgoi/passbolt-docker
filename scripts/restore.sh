#!/bin/bash
#=========================================================================
# Passbolt Docker Restore Script
# Version: 1.0.0
# Created: May 2025
#
# DESCRIPTION:
# Restores a Passbolt Docker installation from a backup archive.
# Handles database restoration, GPG keys, JWT keys, configuration files,
# and user-uploaded images.
#
# USAGE:
#   ./restore.sh [options] <backup_file.tar.gz>
#
# OPTIONS:
#   -f         Force restore without confirmation
#   -s         Skip backup integrity verification
#   -n         Don't start containers after restore
#   -h         Show this help message
#=========================================================================

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
TEMP_DIR="${BASE_DIR}/tmp/restore_$(date +%Y%m%d_%H%M%S)"
LOG_DIR="${BASE_DIR}/logs"
LOG_FILE="${LOG_DIR}/restore_$(date +%Y%m%d_%H%M%S).log"

# Container names
DB_CONTAINER="passbolt-db"
APP_CONTAINER="passbolt-app"
NGINX_CONTAINER="passbolt-nginx"

# Flags
FORCE_RESTORE=0
SKIP_VERIFY=0
NO_START=0

# Color codes for output
COLOR_NC='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'

#=========================================================================
# FUNCTIONS
#=========================================================================

# Function to display usage information
show_help() {
    echo "Usage: $0 [options] <backup_file.tar.gz>"
    echo ""
    echo "Options:"
    echo "  -f         Force restore without confirmation"
    echo "  -s         Skip backup integrity verification"
    echo "  -n         Don't start containers after restore"
    echo "  -h         Show this help message"
    echo ""
}

# Function to log messages
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local formatted_message="[${timestamp}] [${level}] ${message}"

    # Output to console with color
    case $level in
        INFO)    echo -e "${COLOR_BLUE}${formatted_message}${COLOR_NC}" ;;
        WARNING) echo -e "${COLOR_YELLOW}${formatted_message}${COLOR_NC}" ;;
        ERROR)   echo -e "${COLOR_RED}${formatted_message}${COLOR_NC}" ;;
        SUCCESS) echo -e "${COLOR_GREEN}${formatted_message}${COLOR_NC}" ;;
        *)       echo "${formatted_message}" ;;
    esac

    # Write to log file
    echo "${formatted_message}" >> "$LOG_FILE"
}

# Function to print section headers
print_section() {
    echo -e "\n${COLOR_BLUE}=== $1 ===${COLOR_NC}"
}

# Function to print headers
print_header() {
    local text="$1"
    local line=$(printf '=%.0s' $(seq 1 ${#text}))
    echo -e "\n${COLOR_BLUE}${line}${COLOR_NC}"
    echo -e "${COLOR_BLUE}${text}${COLOR_NC}"
    echo -e "${COLOR_BLUE}${line}${COLOR_NC}\n"
}

# Function to create directory if it doesn't exist
create_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        if [ $? -ne 0 ]; then
            log_message "Failed to create directory: $1" "ERROR"
            return 1
        fi
    fi
    return 0
}

# Function to check if container is running
check_container() {
    if ! docker ps | grep -q "$1"; then
        log_message "Container '$1' is not running" "WARNING"
        return 1
    fi
    return 0
}

# Function to confirm restore operation
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

# Function to verify backup file integrity
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

# Function to extract backup archive
extract_backup() {
    local backup_file="$1"
    local extract_dir="$2"

    print_section "Extracting backup"
    log_message "Extracting backup to: $extract_dir" "INFO"

    if tar -xzf "$backup_file" -C "$extract_dir"; then
        log_message "Backup extracted successfully" "SUCCESS"
        return 0
    else
        log_message "Failed to extract backup" "ERROR"
        return 1
    fi
}

# Function to validate backup contents
validate_backup() {
    local extract_dir="$1"

    print_section "Validating backup contents"

    # Check for critical files
    if [ ! -f "${extract_dir}/passbolt_db.sql" ]; then
        log_message "Database dump not found in backup" "ERROR"
        return 1
    fi

    if [ ! -d "${extract_dir}/data/gpg" ] || [ ! -f "${extract_dir}/data/gpg/serverkey.asc" ]; then
        log_message "GPG keys not found in backup" "ERROR"
        return 1
    fi

    log_message "Backup contents validated" "SUCCESS"
    return 0
}

# Function to stop running containers
stop_containers() {
    print_section "Stopping running containers"
    log_message "Stopping all Passbolt containers..." "INFO"

    cd "$BASE_DIR"
    if docker compose down; then
        log_message "Containers stopped successfully" "SUCCESS"
        return 0
    else
        log_message "Failed to stop containers" "WARNING"
        return 1
    fi
}

# Function to restore configuration files
restore_config_files() {
    local source_dir="$1"
    local dest_dir="$2"

    print_section "Restoring configuration files"

    # Restore configuration directories
    if [ -d "${source_dir}/config" ]; then
        create_directory "${dest_dir}/config"
        cp -rf "${source_dir}/config/"* "${dest_dir}/config/" 2>/dev/null
        log_message "Configuration files restored" "SUCCESS"
    else
        log_message "Configuration directory not found in backup" "WARNING"
    fi

    # Restore environment files
    if [ -d "${source_dir}/env" ]; then
        create_directory "${dest_dir}/env"
        cp -rf "${source_dir}/env/"* "${dest_dir}/env/" 2>/dev/null
        log_message "Environment files restored" "SUCCESS"
    else
        log_message "Environment directory not found in backup" "WARNING"
    fi

    # Restore docker-compose.yml
    if [ -f "${source_dir}/docker-compose.yml" ]; then
        cp -f "${source_dir}/docker-compose.yml" "${dest_dir}/" 2>/dev/null
        log_message "Docker Compose file restored" "SUCCESS"
    else
        log_message "Docker Compose file not found in backup" "WARNING"
    fi
}

# Function to restore GPG keys
restore_gpg_keys() {
    local source_dir="$1"
    local dest_dir="$2"

    print_section "Restoring GPG keys"

    if [ ! -d "${source_dir}/data/gpg" ]; then
        log_message "GPG keys directory not found in backup" "ERROR"
        return 1
    fi

    create_directory "${dest_dir}/data/gpg"
    cp -f "${source_dir}/data/gpg/serverkey_private.asc" "${dest_dir}/data/gpg/" 2>/dev/null
    cp -f "${source_dir}/data/gpg/serverkey.asc" "${dest_dir}/data/gpg/" 2>/dev/null

    # Set secure permissions
    chmod 600 "${dest_dir}/data/gpg/"*

    log_message "GPG keys restored" "SUCCESS"
    return 0
}

# Function to restore JWT keys
restore_jwt_keys() {
    local source_dir="$1"
    local dest_dir="$2"

    print_section "Restoring JWT keys"

    if [ ! -d "${source_dir}/data/jwt" ]; then
        log_message "JWT keys directory not found in backup" "WARNING"
        return 1
    fi

    create_directory "${dest_dir}/data/jwt"
    cp -f "${source_dir}/data/jwt/jwt.key" "${dest_dir}/data/jwt/" 2>/dev/null
    cp -f "${source_dir}/data/jwt/jwt.pem" "${dest_dir}/data/jwt/" 2>/dev/null

    # Set secure permissions
    chmod 600 "${dest_dir}/data/jwt/"*

    log_message "JWT keys restored" "SUCCESS"
    return 0
}

# Function to restore user images
restore_user_images() {
    local source_dir="$1"
    local dest_dir="$2"

    print_section "Restoring user images"

    if [ ! -d "${source_dir}/data/images" ]; then
        log_message "User images directory not found in backup" "WARNING"
        return 0
    fi

    create_directory "${dest_dir}/data/images"
    cp -rf "${source_dir}/data/images/"* "${dest_dir}/data/images/" 2>/dev/null

    log_message "User images restored" "SUCCESS"
    return 0
}

# Function to start database container
start_database() {
    print_section "Starting database container"
    log_message "Starting database container..." "INFO"

    cd "$BASE_DIR"
    if docker compose up -d db; then
        log_message "Database container started" "SUCCESS"

        # Wait for database to be ready
        log_message "Waiting for database to be ready..." "INFO"
        sleep 10
        return 0
    else
        log_message "Failed to start database container" "ERROR"
        return 1
    fi
}

# Function to restore database
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

# Function to start all containers
start_containers() {
    print_section "Starting all containers"
    log_message "Starting all Passbolt containers..." "INFO"

    cd "$BASE_DIR"
    if docker compose up -d; then
        log_message "All containers started" "SUCCESS"

        # Wait for Passbolt to be ready
        log_message "Waiting for Passbolt to be ready..." "INFO"
        sleep 20
        return 0
    else
        log_message "Failed to start containers" "ERROR"
        return 1
    fi
}

# Function to check Passbolt health
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

#=========================================================================
# MAIN SCRIPT
#=========================================================================

# Parse command line arguments
while getopts "fsnht" opt; do
    case $opt in
        f) FORCE_RESTORE=1 ;;
        s) SKIP_VERIFY=1 ;;
        n) NO_START=1 ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Check if backup file was provided
shift $((OPTIND-1))
if [ $# -eq 0 ]; then
    log_message "No backup file specified" "ERROR"
    show_help
    exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    log_message "Backup file not found: $BACKUP_FILE" "ERROR"
    exit 1
fi

# Create necessary directories
create_directory "$LOG_DIR"
create_directory "$TEMP_DIR"

# Initialize log file
touch "$LOG_FILE"

# Log start of restore
print_header "PASSBOLT RESTORE PROCESS"
log_message "Starting Passbolt restore process" "INFO"
log_message "Backup file: $BACKUP_FILE" "INFO"

# Confirm restore operation
if ! confirm_restore; then
    rm -rf "$TEMP_DIR"
    exit 0
fi

# Check if Docker is running
if ! docker info &>/dev/null; then
    log_message "Docker is not running or not accessible" "ERROR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Verify backup integrity
if ! verify_backup "$BACKUP_FILE"; then
    log_message "Failed to verify backup integrity. Aborting restore." "ERROR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Extract backup
if ! extract_backup "$BACKUP_FILE" "$TEMP_DIR"; then
    log_message "Failed to extract backup. Aborting restore." "ERROR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Validate backup contents
if ! validate_backup "$TEMP_DIR"; then
    log_message "Backup validation failed. Aborting restore." "ERROR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Stop running containers
stop_containers

# Restore configuration files
restore_config_files "$TEMP_DIR" "$BASE_DIR"

# Restore data directories
create_directory "${BASE_DIR}/data"
restore_gpg_keys "$TEMP_DIR" "$BASE_DIR"
restore_jwt_keys "$TEMP_DIR" "$BASE_DIR"
restore_user_images "$TEMP_DIR" "$BASE_DIR"

# Start containers and restore database
if [ $NO_START -eq 0 ]; then
    # Start database container
    if ! start_database; then
        log_message "Failed to start database. Aborting restore." "ERROR"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Restore database
    if ! restore_database "${TEMP_DIR}/passbolt_db.sql"; then
        log_message "Database restoration failed. Aborting restore." "ERROR"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Start all containers
    if ! start_containers; then
        log_message "Failed to start containers. Restore may be incomplete." "ERROR"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Check Passbolt health
    check_health
else
    log_message "Container start skipped (--no-start option)" "WARNING"
    log_message "You will need to start the containers manually:" "INFO"
    log_message "  cd $BASE_DIR && docker compose up -d" "INFO"
fi

# Clean up temporary files
log_message "Cleaning up temporary files..." "INFO"
rm -rf "$TEMP_DIR"

# Success message
print_header "RESTORE COMPLETED SUCCESSFULLY"
echo -e "${COLOR_GREEN}Passbolt has been restored from backup.${COLOR_NC}"
echo ""
echo "Next steps:"
echo "1. Verify the container status:"
echo "   docker compose ps"
echo ""
echo "2. Check the logs for any errors:"
echo "   docker compose logs passbolt"
echo ""
echo "3. Verify the health of the installation:"
echo "   docker compose exec $APP_CONTAINER su -c '/usr/share/php/passbolt/bin/cake passbolt healthcheck' -s /bin/sh www-data"
echo ""

log_message "Restore process completed" "SUCCESS"
exit 0
