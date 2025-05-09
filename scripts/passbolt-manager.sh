#!/bin/bash
#=========================================================================
# Passbolt Docker Manager Script
# Version: 1.0.0
# Created: May 2025
#
# DESCRIPTION:
# Central management script for Passbolt Docker operations including
# backup, restore, health checks, user management, and maintenance tasks.
#
# USAGE:
#   ./passbolt-manager.sh <command> [options]
#
# COMMANDS:
#   backup           Create a backup of the Passbolt installation
#   restore          Restore from a backup file
#   healthcheck      Check the health of the Passbolt installation
#   status           Show the status of Passbolt containers
#   logs             Show Passbolt logs
#   cleanup          Run the cleanup command to fix data integrity issues
#   register         Register a new user
#   reset-password   Reset a user's password
#   test-email       Send a test email to verify email configuration
#   version          Show Passbolt version
#   help             Show this help message
#=========================================================================

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Container names
DB_CONTAINER="passbolt-db"
APP_CONTAINER="passbolt-app"
NGINX_CONTAINER="passbolt-nginx"

# Color codes for output
COLOR_NC='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_MAGENTA='\033[0;35m'

#=========================================================================
# HELPER FUNCTIONS
#=========================================================================

# Function to display usage information
show_help() {
    echo -e "${COLOR_BLUE}Passbolt Docker Manager${COLOR_NC}"
    echo "============================="
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  backup             Create a backup of the Passbolt installation"
    echo "  restore            Restore from a backup file"
    echo "  healthcheck        Check the health of the Passbolt installation"
    echo "  status             Show the status of Passbolt containers"
    echo "  logs               Show Passbolt logs"
    echo "  cleanup            Run the cleanup command to fix data integrity issues"
    echo "  register           Register a new user"
    echo "  reset-password     Reset a user's password"
    echo "  test-email         Send a test email to verify email configuration"
    echo "  version            Show Passbolt version"
    echo "  help               Show this help message"
    echo ""
    echo "Run '$0 <command> --help' for command-specific help"
    echo ""
}

# Function to display command-specific help
show_command_help() {
    local command="$1"

    case "$command" in
        backup)
            echo "Usage: $0 backup [options]"
            echo ""
            echo "Options:"
            echo "  -d DIR     Specify backup directory (default: ../backups)"
            echo "  -r DAYS    Days to keep backups (default: 30)"
            echo "  -q         Quiet mode (suppress output except errors)"
            echo "  -h         Show this help message"
            ;;
        restore)
            echo "Usage: $0 restore [options] <backup_file.tar.gz>"
            echo ""
            echo "Options:"
            echo "  -f         Force restore without confirmation"
            echo "  -s         Skip backup integrity verification"
            echo "  -n         Don't start containers after restore"
            echo "  -h         Show this help message"
            ;;
        logs)
            echo "Usage: $0 logs [options] [service]"
            echo ""
            echo "Options:"
            echo "  -f         Follow log output"
            echo "  -t LINES   Number of lines to show (default: 100)"
            echo ""
            echo "Service can be: app, db, nginx, or all (default)"
            ;;
        cleanup)
            echo "Usage: $0 cleanup [options]"
            echo ""
            echo "Options:"
            echo "  --dry-run  Test the cleanup without making changes"
            echo "  -h         Show this help message"
            ;;
        register)
            echo "Usage: $0 register <email> <firstname> <lastname> [role]"
            echo ""
            echo "Parameters:"
            echo "  email       User's email address"
            echo "  firstname   User's first name"
            echo "  lastname    User's last name"
            echo "  role        User's role (default: user, options: user, admin)"
            ;;
        reset-password)
            echo "Usage: $0 reset-password <email>"
            echo ""
            echo "Parameters:"
            echo "  email       User's email address"
            ;;
        test-email)
            echo "Usage: $0 test-email <recipient>"
            echo ""
            echo "Parameters:"
            echo "  recipient   Email address to send the test to"
            ;;
        *)
            show_help
            ;;
    esac
}

# Function to log messages
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Select color based on level
    local color=${COLOR_NC}
    case $level in
        INFO)    color=${COLOR_BLUE};;
        WARNING) color=${COLOR_YELLOW};;
        ERROR)   color=${COLOR_RED};;
        SUCCESS) color=${COLOR_GREEN};;
    esac

    # Format the message
    local formatted_message="[${timestamp}] [${level}] ${message}"

    # Output to console with color
    echo -e "${color}${formatted_message}${COLOR_NC}"
}

# Function to print headers
print_header() {
    local text="$1"
    local line=$(printf '=%.0s' $(seq 1 ${#text}))
    echo -e "\n${COLOR_BLUE}${line}${COLOR_NC}"
    echo -e "${COLOR_BLUE}${text}${COLOR_NC}"
    echo -e "${COLOR_BLUE}${line}${COLOR_NC}\n"
}

# Function to print section headers
print_section() {
    echo -e "\n${COLOR_BLUE}=== $1 ===${COLOR_NC}"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info &>/dev/null; then
        log_message "Docker is not running or not accessible" "ERROR"
        return 1
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

#=========================================================================
# COMMAND FUNCTIONS
#=========================================================================

# Function to run the backup script
cmd_backup() {
    "${SCRIPT_DIR}/backup.sh" "$@"
}

# Function to run the restore script
cmd_restore() {
    "${SCRIPT_DIR}/restore.sh" "$@"
}

# Function to run health check
cmd_healthcheck() {
    print_header "Passbolt Health Check"

    if ! check_docker; then
        return 1
    fi

    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running" "ERROR"
        return 1
    fi

    print_section "Running health check"
    docker exec -i "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt healthcheck" www-data

    if [ $? -eq 0 ]; then
        log_message "Health check passed" "SUCCESS"
    else
        log_message "Health check reported issues" "WARNING"
    fi
}

# Function to show container status
cmd_status() {
    print_header "Passbolt Container Status"

    if ! check_docker; then
        return 1
    fi

    print_section "Container Status"
    cd "$BASE_DIR" && docker compose ps

    print_section "Resource Usage"
    docker stats --no-stream "$APP_CONTAINER" "$DB_CONTAINER" "$NGINX_CONTAINER" 2>/dev/null || true
}

# Function to show logs
cmd_logs() {
    # Default values
    local follow=0
    local tail=100
    local service="all"

    # Parse arguments
    while getopts "ft:h" opt; do
        case $opt in
            f) follow=1 ;;
            t) tail="$OPTARG" ;;
            h) show_command_help "logs"; return 0 ;;
            *) show_command_help "logs"; return 1 ;;
        esac
    done

    # Check remaining args for service
    shift $((OPTIND-1))
    if [ $# -gt 0 ]; then
        service="$1"
    fi

    # Validate service
    if [[ "$service" != "app" && "$service" != "db" && "$service" != "nginx" && "$service" != "all" ]]; then
        log_message "Invalid service: $service" "ERROR"
        show_command_help "logs"
        return 1
    fi

    print_header "Passbolt Logs"

    if ! check_docker; then
        return 1
    fi

    # Build log command
    local log_cmd="docker compose logs"

    if [ $follow -eq 1 ]; then
        log_cmd="$log_cmd -f"
    fi

    log_cmd="$log_cmd --tail=$tail"

    # Add service filter
    case $service in
        app)
            log_cmd="$log_cmd $APP_CONTAINER"
            ;;
        db)
            log_cmd="$log_cmd $DB_CONTAINER"
            ;;
        nginx)
            log_cmd="$log_cmd $NGINX_CONTAINER"
            ;;
        all)
            # No service filter
            ;;
    esac

    # Execute command
    cd "$BASE_DIR" && eval "$log_cmd"
}

# Function to run cleanup
cmd_cleanup() {
    local dry_run=0

    # Parse arguments
    if [[ "$1" == "--dry-run" ]]; then
        dry_run=1
    elif [[ "$1" == "--help" || "$1" == "-h" ]]; then
        show_command_help "cleanup"
        return 0
    fi

    print_header "Passbolt Cleanup"

    if ! check_docker; then
        return 1
    fi

    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running" "ERROR"
        return 1
    fi

    if [ $dry_run -eq 1 ]; then
        print_section "Running cleanup (dry run)"
        log_message "Performing a dry run of the cleanup process..." "INFO"
        docker exec -i "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt cleanup --dry-run" www-data
    else
        print_section "Running cleanup"
        log_message "Performing cleanup of data integrity issues..." "INFO"
        docker exec -i "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt cleanup" www-data
    fi

    if [ $? -eq 0 ]; then
        log_message "Cleanup completed successfully" "SUCCESS"
    else
        log_message "Cleanup reported issues" "WARNING"
    fi
}

# Function to register a new user
cmd_register() {
    # Check for help flag
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        show_command_help "register"
        return 0
    fi

    # Check required parameters
    if [ $# -lt 3 ]; then
        log_message "Missing required parameters" "ERROR"
        show_command_help "register"
        return 1
    fi

    local email="$1"
    local firstname="$2"
    local lastname="$3"
    local role="${4:-user}"

    # Validate role
    if [ "$role" != "user" ] && [ "$role" != "admin" ]; then
        log_message "Invalid role: $role (must be 'user' or 'admin')" "ERROR"
        return 1
    fi

    print_header "Register New User"

    if ! check_docker; then
        return 1
    fi

    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running" "ERROR"
        return 1
    fi

    log_message "Registering user: $email ($firstname $lastname) with role: $role" "INFO"

    # Registration command using the correct method
    docker exec "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt register_user -u \"$email\" -f \"$firstname\" -l \"$lastname\" -r \"$role\"" www-data

    if [ $? -eq 0 ]; then
        log_message "User registration process initiated" "SUCCESS"
        log_message "Note: The user will receive an email with setup instructions" "INFO"
    else
        log_message "Failed to register user" "ERROR"
    fi
}

# Function to reset a user's password
cmd_reset_password() {
    # Check for help flag
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        show_command_help "reset-password"
        return 0
    fi

    # Check required parameters
    if [ $# -lt 1 ]; then
        log_message "Missing required parameter: email" "ERROR"
        show_command_help "reset-password"
        return 1
    fi

    local email="$1"

    print_header "Reset User Password"

    if ! check_docker; then
        return 1
    fi

    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running" "ERROR"
        return 1
    fi

    log_message "Sending password reset email to: $email" "INFO"

    # Password recovery command
    docker exec "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt recover_user -u \"$email\"" www-data

    if [ $? -eq 0 ]; then
        log_message "Password recovery email sent successfully" "SUCCESS"
    else
        log_message "Failed to send password recovery email" "ERROR"
    fi
}

# Function to send test email
cmd_test_email() {
    # Check for help flag
    if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
        show_command_help "test-email"
        return 0
    fi

    # Check required parameters
    if [ $# -lt 1 ]; then
        log_message "Missing required parameter: recipient" "ERROR"
        show_command_help "test-email"
        return 1
    fi

    local recipient="$1"

    print_header "Email Configuration Test"

    if ! check_docker; then
        return 1
    fi

    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running" "ERROR"
        return 1
    fi

    log_message "Sending test email to: $recipient" "INFO"

    # Display the current email settings from environment file
    if [ -f "${BASE_DIR}/env/email.env" ]; then
        print_section "Current Email Configuration"
        grep -v "PASSWORD" "${BASE_DIR}/env/email.env" || true
    fi

    # Test email command with direct execution (without su)
    print_section "Testing Email Configuration"
    docker exec -i "$APP_CONTAINER" /usr/share/php/passbolt/bin/cake passbolt send_test_email --recipient="$recipient"

    # If the above fails, try with www-data user explicitly
    if [ $? -ne 0 ]; then
        log_message "First attempt failed, trying alternative method..." "WARNING"
        docker exec -i "$APP_CONTAINER" su -m -c "/usr/share/php/passbolt/bin/cake passbolt send_test_email --recipient=\"$recipient\"" -s /bin/sh www-data
    fi

    if [ $? -eq 0 ]; then
        log_message "Test email sent successfully" "SUCCESS"
    else
        log_message "Failed to send test email" "ERROR"
        log_message "Verify your email configuration in ${BASE_DIR}/env/email.env" "INFO"

        # Show a troubleshooting hint
        print_section "Troubleshooting"
        echo "1. Make sure email.env file is correctly mounted to the container"
        echo "2. Check if container was restarted after changing email settings"
        echo "3. Try restarting the container: docker compose restart $APP_CONTAINER"
        echo "4. Check container logs for more details: docker compose logs $APP_CONTAINER"
    fi
}

# Function to show Passbolt version
cmd_version() {
    print_header "Passbolt Version Information"

    if ! check_docker; then
        return 1
    fi

    if ! check_container "$APP_CONTAINER"; then
        log_message "Passbolt container is not running" "ERROR"
        return 1
    fi

    # Run the version command
    print_section "Passbolt Version"
    docker exec "$APP_CONTAINER" su -s /bin/sh -c "/usr/share/php/passbolt/bin/cake passbolt version" www-data

    # Get additional information
    print_section "System Information"

    # Get PHP version
    local php_version=$(docker exec "$APP_CONTAINER" php -v | head -n 1)
    echo -e "${COLOR_BLUE}PHP:${COLOR_NC} ${php_version}"

    # Get database version
    if check_container "$DB_CONTAINER"; then
        local db_version=$(docker exec "$DB_CONTAINER" mysql --version)
        echo -e "${COLOR_BLUE}Database:${COLOR_NC} ${db_version}"
    else
        echo -e "${COLOR_BLUE}Database:${COLOR_NC} Not running"
    fi

    # Get container image
    local app_image=$(docker inspect --format='{{.Config.Image}}' "$APP_CONTAINER")
    echo -e "${COLOR_BLUE}Container image:${COLOR_NC} ${app_image}"
}

#=========================================================================
# MAIN SCRIPT
#=========================================================================

# No arguments? Show help
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

# Get command
COMMAND="$1"
shift

# Process command
case "$COMMAND" in
    backup)
        cmd_backup "$@"
        ;;
    restore)
        cmd_restore "$@"
        ;;
    healthcheck)
        cmd_healthcheck "$@"
        ;;
    status)
        cmd_status "$@"
        ;;
    logs)
        cmd_logs "$@"
        ;;
    cleanup)
        cmd_cleanup "$@"
        ;;
    register)
        cmd_register "$@"
        ;;
    reset-password)
        cmd_reset_password "$@"
        ;;
    test-email)
        cmd_test_email "$@"
        ;;
    version)
        cmd_version "$@"
        ;;
    help)
        if [ $# -eq 0 ]; then
            show_help
        else
            show_command_help "$1"
        fi
        ;;
    *)
        log_message "Unknown command: $COMMAND" "ERROR"
        show_help
        exit 1
        ;;
esac

exit $?
