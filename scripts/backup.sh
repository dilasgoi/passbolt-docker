#!/bin/bash
#=========================================================================
# Passbolt Docker Backup Script
# Version: 1.0.0
# Created: May 2025
#
# DESCRIPTION:
# Creates a complete backup of a Passbolt Docker installation.
# Backs up the database, GPG keys, JWT keys, configuration files,
# and user-uploaded images.
#
# USAGE:
#   ./backup.sh [options]
#
# OPTIONS:
#   -d DIR     Specify backup directory (default: ../backups)
#   -r DAYS    Days to keep backups (default: 30)
#   -q         Quiet mode (suppress output except errors)
#   -h         Show this help message
#=========================================================================

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

# Container names
DB_CONTAINER="passbolt-db"
APP_CONTAINER="passbolt-app"

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
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d DIR     Specify backup directory (default: ../backups)"
    echo "  -r DAYS    Days to keep backups (default: 30)"
    echo "  -q         Quiet mode (suppress output except errors)"
    echo "  -h         Show this help message"
    echo ""
}

# Function to log messages
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local formatted_message="[${timestamp}] [${level}] ${message}"

    # Only output to console if not in quiet mode or if it's an error
    if [ $QUIET_MODE -eq 0 ] || [ "$level" == "ERROR" ]; then
        case $level in
            INFO)    echo -e "${COLOR_BLUE}${formatted_message}${COLOR_NC}" ;;
            WARNING) echo -e "${COLOR_YELLOW}${formatted_message}${COLOR_NC}" ;;
            ERROR)   echo -e "${COLOR_RED}${formatted_message}${COLOR_NC}" ;;
            SUCCESS) echo -e "${COLOR_GREEN}${formatted_message}${COLOR_NC}" ;;
            *)       echo "${formatted_message}" ;;
        esac
    fi

    # Always write to log file
    echo "${formatted_message}" >> "$LOG_FILE"
}

# Function to print section headers
print_section() {
    [ $QUIET_MODE -eq 0 ] && echo -e "\n${COLOR_BLUE}=== $1 ===${COLOR_NC}"
}

# Function to create directory if it doesn't exist
create_directory() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        if [ $? -ne 0 ]; then
            log_message "Failed to create directory: $1" "ERROR"
            exit 1
        fi
    fi
}

# Function to check if container is running
check_container() {
    if ! docker ps | grep -q "$1"; then
        log_message "Container '$1' is not running!" "ERROR"
        return 1
    fi
    return 0
}

# Function to backup database
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

# Function to backup GPG keys
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

# Function to backup JWT keys
backup_jwt_keys() {
    print_section "Backing up JWT keys"
    log_message "Backing up JWT keys..."

    mkdir -p "${TEMP_DIR}/data/jwt"

    if docker cp ${APP_CONTAINER}:/etc/passbolt/jwt/jwt.key "${TEMP_DIR}/data/jwt/" && \
       docker cp ${APP_CONTAINER}:/etc/passbolt/jwt/jwt.pem "${TEMP_DIR}/data/jwt/"; then
        chmod 600 "${TEMP_DIR}/data/jwt/"*
        log_message "JWT keys backup completed" "SUCCESS"
        return 0
    else
        log_message "JWT keys backup failed" "WARNING"
        return 1
    fi
}

# Function to backup user-uploaded images
backup_user_images() {
    print_section "Backing up user images"
    log_message "Backing up user-uploaded images..."

    mkdir -p "${TEMP_DIR}/data/images"

    if docker cp ${APP_CONTAINER}:/usr/share/php/passbolt/webroot/img/public/. "${TEMP_DIR}/data/images/"; then
        log_message "User images backup completed" "SUCCESS"
    else
        log_message "User images backup failed or no images found" "WARNING"
    fi
}

# Function to backup configuration files
backup_config_files() {
    print_section "Backing up configuration files"
    log_message "Backing up configuration files..."

    # Copy configuration directories
    if [ -d "${BASE_DIR}/config" ]; then
        cp -r "${BASE_DIR}/config" "${TEMP_DIR}/"
        log_message "Configuration directory backed up" "SUCCESS"
    else
        log_message "Configuration directory not found" "WARNING"
    fi

    # Copy environment files
    if [ -d "${BASE_DIR}/env" ]; then
        cp -r "${BASE_DIR}/env" "${TEMP_DIR}/"
        log_message "Environment files backed up" "SUCCESS"
    else
        log_message "Environment directory not found" "WARNING"
    fi

    # Copy docker-compose.yml
    if [ -f "${BASE_DIR}/docker-compose.yml" ]; then
        cp "${BASE_DIR}/docker-compose.yml" "${TEMP_DIR}/"
        log_message "Docker compose file backed up" "SUCCESS"
    else
        log_message "Docker compose file not found" "WARNING"
    fi
}

# Function to create README file
create_readme() {
    print_section "Creating backup documentation"
    log_message "Creating README file..."

    # Get Passbolt version
    local passbolt_version="Unknown"
    if check_container "$APP_CONTAINER"; then
        passbolt_version=$(docker exec -i "$APP_CONTAINER" cat /etc/container_environment.json 2>/dev/null | grep APP_VERSION || echo "Unknown")
    fi

    # Create README file
    cat > "${TEMP_DIR}/README.txt" << EOF
Passbolt Backup
===============
Date: $(date)
Passbolt Version: $passbolt_version
Server: $(hostname)
Created by: $(whoami)

This backup contains:
- Database dump (MySQL)
- GPG encryption keys
- JWT authentication keys
- Configuration files
- Environment variables
- Docker Compose configuration
- User-uploaded images

To restore this backup, use the restore.sh script.
EOF

    log_message "Backup documentation created" "SUCCESS"
}

# Function to create compressed archive
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

# Function to clean up old backups
cleanup_old_backups() {
    print_section "Cleaning up old backups"
    log_message "Removing backups older than ${RETENTION_DAYS} days..."

    find "$BACKUP_DIR" -name "passbolt_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "passbolt_backup_*.tar.gz.sha256" -type f -mtime +$RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "backup_*.log" -type f -mtime +$RETENTION_DAYS -delete

    log_message "Cleanup completed" "SUCCESS"
}

# Function to display backup summary
display_summary() {
    print_section "Backup Summary"

    echo -e "${COLOR_GREEN}Backup completed successfully!${COLOR_NC}"
    echo ""
    echo "Backup details:"
    echo "- Location: ${BACKUP_FILE}"
    echo "- Size: $(du -h ${BACKUP_FILE} | cut -f1)"
    echo "- Checksum: $(cat ${BACKUP_FILE}.sha256 | cut -d' ' -f1)"
    echo "- Log: ${LOG_FILE}"
    echo ""
}

#=========================================================================
# MAIN SCRIPT
#=========================================================================

# Parse command line arguments
while getopts "d:r:qh" opt; do
    case $opt in
        d) BACKUP_DIR="$OPTARG" ;;
        r) RETENTION_DAYS="$OPTARG" ;;
        q) QUIET_MODE=1 ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Create necessary directories
create_directory "$BACKUP_DIR"
create_directory "$TEMP_DIR"

# Initialize log file
[ -f "$LOG_FILE" ] && rm "$LOG_FILE"
touch "$LOG_FILE"

# Log start of backup
log_message "Starting Passbolt backup process" "INFO"
log_message "Backup will be created at: ${BACKUP_FILE}" "INFO"

# Check if Docker is running
if ! docker info &>/dev/null; then
    log_message "Docker is not running or not accessible" "ERROR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check if required containers are running
if ! check_container "$DB_CONTAINER" || ! check_container "$APP_CONTAINER"; then
    log_message "Required containers are not running. Aborting backup." "ERROR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Perform backup steps
backup_database || { rm -rf "$TEMP_DIR"; exit 1; }
backup_gpg_keys || { rm -rf "$TEMP_DIR"; exit 1; }
backup_jwt_keys
backup_user_images
backup_config_files
create_readme
create_archive || { rm -rf "$TEMP_DIR"; exit 1; }

# Clean up temporary files
log_message "Cleaning up temporary files..." "INFO"
rm -rf "$TEMP_DIR"

# Clean up old backups
cleanup_old_backups

# Display summary if not in quiet mode
[ $QUIET_MODE -eq 0 ] && display_summary

log_message "Backup process completed successfully" "SUCCESS"
exit 0
