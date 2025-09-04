#!/bin/bash

# PostgreSQL Database Restore Script
# Created for PostgreSQL 16 Production Setup
# Usage: ./postgres_restore.sh [options]

set -euo pipefail

# Configuration (adjust these if needed)
BACKUP_DIR="/var/backups/postgresql/dumps"
LOG_FILE="/var/log/postgresql_restore.log"
PG_USER="postgres"

# Backup types
SINGLE_DB_BACKUP=true  # Current setup uses pg_dump for single database
FULL_CLUSTER_BACKUP=false  # Would use pg_dumpall for entire PostgreSQL cluster

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
PostgreSQL Database Restore Script

IMPORTANT: This script works with SINGLE DATABASE backups created by pg_dump.
The current setup backs up individual databases, not the entire PostgreSQL cluster.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -d, --database NAME     Database name to restore (required for single DB restore)
    -f, --file FILENAME     Specific backup file to restore from
    -l, --list             List available backup files
    -i, --interactive      Interactive mode (default)
    -y, --yes              Auto-confirm (non-interactive)
    -s, --services         Comma-separated list of services to stop/start
    -h, --help             Show this help message

EXAMPLES:
    $0                                    # Interactive mode
    $0 -d mydb -f backup_mydb_20241201_140530.sql.gz
    $0 -l                                # List available backups
    $0 -d mydb -y                        # Auto-confirm restore
    $0 -d mydb -s "nginx,myapp"          # Stop/start specific services

BACKUP FILE FORMAT:
    backup_DBNAME_YYYYMMDD_HHMMSS.sql.gz

BACKUP LOCATION:
    $BACKUP_DIR/

RESTORE LOG:
    $LOG_FILE
EOF
}

# Check if running as root or with sudo
check_permissions() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
    fi
}

# Check if PostgreSQL is running
check_postgresql() {
    if ! systemctl is-active --quiet postgresql; then
        error "PostgreSQL service is not running. Please start it first: sudo systemctl start postgresql"
    fi
}

# List available backup files
list_backups() {
    info "Available backup files in $BACKUP_DIR:"
    echo
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
    fi
    
    local backup_files=($(find "$BACKUP_DIR" -name "backup_*.sql.gz" -type f | sort -r))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        warning "No backup files found in $BACKUP_DIR"
        return 1
    fi
    
    printf "%-5s %-40s %-20s %-15s\n" "No." "Filename" "Date" "Size"
    echo "--------------------------------------------------------------------------------"
    
    local i=1
    for file in "${backup_files[@]}"; do
        local filename=$(basename "$file")
        local filedate=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || echo "Unknown")
        local filesize=$(du -h "$file" 2>/dev/null | cut -f1 || echo "Unknown")
        printf "%-5s %-40s %-20s %-15s\n" "$i" "$filename" "$filedate" "$filesize"
        ((i++))
    done
    echo
}

# Get database list
get_databases() {
    sudo -u "$PG_USER" psql -t -c "SELECT datname FROM pg_database WHERE datistemplate = false;" | grep -v '^ *$' | sed 's/^ *//'
}

# Stop services
stop_services() {
    local services="$1"
    if [[ -n "$services" ]]; then
        IFS=',' read -ra SERVICE_ARRAY <<< "$services"
        for service in "${SERVICE_ARRAY[@]}"; do
            service=$(echo "$service" | xargs) # trim whitespace
            if systemctl is-active --quiet "$service"; then
                log "Stopping service: $service"
                systemctl stop "$service" || warning "Failed to stop service: $service"
            else
                info "Service $service is not running"
            fi
        done
    fi
}

# Start services
start_services() {
    local services="$1"
    if [[ -n "$services" ]]; then
        IFS=',' read -ra SERVICE_ARRAY <<< "$services"
        for service in "${SERVICE_ARRAY[@]}"; do
            service=$(echo "$service" | xargs) # trim whitespace
            log "Starting service: $service"
            systemctl start "$service" || warning "Failed to start service: $service"
        done
    fi
}

# Validate backup file
validate_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    # Check if file is readable
    if [[ ! -r "$backup_file" ]]; then
        error "Backup file is not readable: $backup_file"
    fi
    
    # Check if file is a valid gzip file
    if ! gunzip -t "$backup_file" 2>/dev/null; then
        error "Backup file appears to be corrupted: $backup_file"
    fi
    
    info "Backup file validation passed: $backup_file"
}

# Create emergency backup
create_emergency_backup() {
    local db_name="$1"
    local emergency_dir="$BACKUP_DIR/emergency"
    
    mkdir -p "$emergency_dir"
    
    local emergency_file="$emergency_dir/emergency_backup_${db_name}_$(date +%Y%m%d_%H%M%S).sql.gz"
    
    log "Creating emergency backup before restore: $emergency_file"
    
    if sudo -u "$PG_USER" pg_dump "$db_name" | gzip > "$emergency_file"; then
        log "Emergency backup created successfully"
        echo "Emergency backup location: $emergency_file"
    else
        warning "Failed to create emergency backup, but continuing with restore..."
    fi
}

# Restore database
restore_database() {
    local db_name="$1"
    local backup_file="$2"
    local auto_confirm="$3"
    local services="$4"
    
    # Validate inputs
    validate_backup "$backup_file"
    
    # Check if database exists
    if ! sudo -u "$PG_USER" psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
        error "Database '$db_name' does not exist. Please create it first or check the name."
    fi
    
    # Show restore information
    echo
    info "=== RESTORE INFORMATION ==="
    echo "Database: $db_name"
    echo "Backup file: $(basename "$backup_file")"
    echo "Backup size: $(du -h "$backup_file" | cut -f1)"
    echo "Backup date: $(stat -c %y "$backup_file" | cut -d'.' -f1)"
    if [[ -n "$services" ]]; then
        echo "Services to restart: $services"
    fi
    echo
    
    # Confirmation
    if [[ "$auto_confirm" != "yes" ]]; then
        warning "⚠️  WARNING: This will COMPLETELY REPLACE the database '$db_name'"
        warning "⚠️  All current data will be PERMANENTLY LOST!"
        echo
        read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " confirm
        
        if [[ "$confirm" != "yes" ]]; then
            info "Restore operation cancelled by user"
            exit 0
        fi
    fi
    
    # Stop services
    stop_services "$services"
    
    # Create emergency backup
    create_emergency_backup "$db_name"
    
    # Start restore process
    log "Starting restore process for database: $db_name"
    
    # Drop existing database
    log "Dropping existing database: $db_name"
    if ! sudo -u "$PG_USER" dropdb "$db_name"; then
        error "Failed to drop database: $db_name"
    fi
    
    # Create new database
    log "Creating new database: $db_name"
    if ! sudo -u "$PG_USER" createdb "$db_name"; then
        error "Failed to create database: $db_name"
    fi
    
    # Restore from backup
    log "Restoring data from backup file..."
    if gunzip -c "$backup_file" | sudo -u "$PG_USER" psql "$db_name" > /dev/null 2>&1; then
        log "✅ Database restore completed successfully!"
    else
        error "❌ Database restore failed!"
    fi
    
    # Verify restore
    log "Verifying database restore..."
    local table_count=$(sudo -u "$PG_USER" psql -d "$db_name" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | xargs)
    log "Restored database contains $table_count tables"
    
    # Start services
    start_services "$services"
    
    log "🎉 Restore operation completed successfully!"
    echo
    info "=== RESTORE SUMMARY ==="
    echo "✅ Database '$db_name' restored from: $(basename "$backup_file")"
    echo "✅ Tables restored: $table_count"
    echo "✅ Log file: $LOG_FILE"
    if [[ -n "$services" ]]; then
        echo "✅ Services restarted: $services"
    fi
    echo
}

# Interactive mode
interactive_mode() {
    echo
    info "=== PostgreSQL Database Restore - Interactive Mode ==="
    echo
    
    # List available databases
    info "Available databases:"
    get_databases | nl -w3 -s'. '
    echo
    
    # Get database name
    while [[ -z "$db_name" ]]; do
        read -p "Enter database name to restore: " db_name
        if [[ -z "$db_name" ]]; then
            warning "Database name is required!"
        fi
    done
    
    # List available backups
    echo
    list_backups
    
    # Get backup file
    local backup_files=($(find "$BACKUP_DIR" -name "backup_*.sql.gz" -type f | sort -r))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        error "No backup files available"
    fi
    
    echo "Select backup file:"
    echo "1. Choose by number from list above"
    echo "2. Enter filename manually"
    echo "3. Use latest backup"
    echo
    read -p "Your choice [1-3]: " choice
    
    local backup_file=""
    case $choice in
        1)
            read -p "Enter backup number: " backup_num
            if [[ "$backup_num" =~ ^[0-9]+$ ]] && [[ $backup_num -ge 1 ]] && [[ $backup_num -le ${#backup_files[@]} ]]; then
                backup_file="${backup_files[$((backup_num-1))]}"
            else
                error "Invalid backup number"
            fi
            ;;
        2)
            read -p "Enter backup filename: " filename
            backup_file="$BACKUP_DIR/$filename"
            ;;
        3)
            backup_file="${backup_files[0]}"
            info "Using latest backup: $(basename "$backup_file")"
            ;;
        *)
            error "Invalid choice"
            ;;
    esac
    
    # Get services to restart
    echo
    read -p "Enter services to stop/start (comma-separated, or press Enter to skip): " services
    
    # Perform restore
    restore_database "$db_name" "$backup_file" "no" "$services"
}

# Main function
main() {
    local db_name=""
    local backup_file=""
    local list_mode=false
    local interactive=true
    local auto_confirm="no"
    local services=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--database)
                db_name="$2"
                interactive=false
                shift 2
                ;;
            -f|--file)
                backup_file="$BACKUP_DIR/$2"
                interactive=false
                shift 2
                ;;
            -l|--list)
                list_mode=true
                shift
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -y|--yes)
                auto_confirm="yes"
                interactive=false
                shift
                ;;
            -s|--services)
                services="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use -h for help."
                ;;
        esac
    done
    
    # Create log file
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log "PostgreSQL Restore Script Started"
    
    # Check permissions and prerequisites
    check_permissions
    check_postgresql
    
    # List mode
    if [[ "$list_mode" == true ]]; then
        list_backups
        exit 0
    fi
    
    # Interactive mode
    if [[ "$interactive" == true ]]; then
        interactive_mode
        exit 0
    fi
    
    # Non-interactive mode validation
    if [[ -z "$db_name" ]]; then
        error "Database name is required. Use -d option or run in interactive mode."
    fi
    
    if [[ -z "$backup_file" ]]; then
        # Use latest backup if no file specified
        local latest_backup=$(find "$BACKUP_DIR" -name "backup_${db_name}_*.sql.gz" -type f | sort -r | head -1)
        if [[ -z "$latest_backup" ]]; then
            error "No backup file specified and no backups found for database: $db_name"
        fi
        backup_file="$latest_backup"
        info "Using latest backup: $(basename "$backup_file")"
    fi
    
    # Perform restore
    restore_database "$db_name" "$backup_file" "$auto_confirm" "$services"
}

# Run main function
main "$@"
