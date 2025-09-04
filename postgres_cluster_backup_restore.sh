#!/bin/bash

# PostgreSQL Cluster Backup and Restore Script
# This script handles FULL PostgreSQL cluster backup/restore using pg_dumpall
# Unlike the single database script, this backs up ALL databases, users, roles, etc.

set -euo pipefail

# Configuration
BACKUP_DIR="/var/backups/postgresql/cluster"
LOG_FILE="/var/log/postgresql_cluster.log"
PG_USER="postgres"
PG_VERSION="16"

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
PostgreSQL Cluster Backup and Restore Script

This script handles FULL PostgreSQL cluster operations using pg_dumpall.
It backs up/restores ALL databases, users, roles, permissions, and settings.

USAGE:
    $0 [COMMAND] [OPTIONS]

COMMANDS:
    backup                  Create a full cluster backup
    restore                 Restore from a cluster backup
    list                    List available cluster backups
    help                    Show this help message

RESTORE OPTIONS:
    -f, --file FILENAME     Specific backup file to restore from
    -y, --yes              Auto-confirm (non-interactive)
    -s, --services         Comma-separated list of services to stop/start

EXAMPLES:
    $0 backup                                    # Create cluster backup
    $0 restore                                   # Interactive restore
    $0 restore -f cluster_backup_20241201_140530.sql.gz
    $0 list                                      # List available backups
    $0 restore -y -s "nginx,myapp"              # Auto-confirm with services

BACKUP LOCATION:
    $BACKUP_DIR/

BACKUP FILE FORMAT:
    cluster_backup_YYYYMMDD_HHMMSS.sql.gz

RESTORE LOG:
    $LOG_FILE

WARNING: 
- Cluster restore will REPLACE ALL databases, users, and settings!
- This is a DESTRUCTIVE operation - use with extreme caution!
- Always test restores in a non-production environment first!
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

# Create cluster backup
create_cluster_backup() {
    local backup_dir="$BACKUP_DIR"
    local date_stamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/cluster_backup_${date_stamp}.sql.gz"
    
    # Create backup directory
    mkdir -p "$backup_dir"
    
    log "Starting full PostgreSQL cluster backup..."
    log "Backup file: $backup_file"
    
    # Create the backup
    if sudo -u "$PG_USER" pg_dumpall | gzip > "$backup_file"; then
        local file_size=$(du -h "$backup_file" | cut -f1)
        log "✅ Cluster backup completed successfully!"
        log "📦 Backup file: $(basename "$backup_file")"
        log "📏 File size: $file_size"
        
        # Clean up old backups (keep last 7 days)
        find "$backup_dir" -name "cluster_backup_*.sql.gz" -mtime +7 -delete
        log "🧹 Old backups cleaned up (>7 days)"
        
        echo
        info "=== BACKUP SUMMARY ==="
        echo "✅ Full cluster backup completed"
        echo "📦 File: $backup_file"
        echo "📏 Size: $file_size"
        echo "📅 Date: $(date)"
        echo
    else
        error "❌ Cluster backup failed!"
    fi
}

# List available cluster backups
list_cluster_backups() {
    info "Available cluster backup files in $BACKUP_DIR:"
    echo
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        warning "Backup directory not found: $BACKUP_DIR"
        return 1
    fi
    
    local backup_files=($(find "$BACKUP_DIR" -name "cluster_backup_*.sql.gz" -type f | sort -r))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        warning "No cluster backup files found in $BACKUP_DIR"
        return 1
    fi
    
    printf "%-5s %-45s %-20s %-15s\n" "No." "Filename" "Date" "Size"
    echo "-------------------------------------------------------------------------------------"
    
    local i=1
    for file in "${backup_files[@]}"; do
        local filename=$(basename "$file")
        local filedate=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1 || echo "Unknown")
        local filesize=$(du -h "$file" 2>/dev/null | cut -f1 || echo "Unknown")
        printf "%-5s %-45s %-20s %-15s\n" "$i" "$filename" "$filedate" "$filesize"
        ((i++))
    done
    echo
}

# Validate backup file
validate_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
    fi
    
    if [[ ! -r "$backup_file" ]]; then
        error "Backup file is not readable: $backup_file"
    fi
    
    if ! gunzip -t "$backup_file" 2>/dev/null; then
        error "Backup file appears to be corrupted: $backup_file"
    fi
    
    info "Backup file validation passed: $backup_file"
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

# Restore cluster
restore_cluster() {
    local backup_file="$1"
    local auto_confirm="$2"
    local services="$3"
    
    # Validate backup file
    validate_backup "$backup_file"
    
    # Show restore information
    echo
    info "=== CLUSTER RESTORE INFORMATION ==="
    echo "Backup file: $(basename "$backup_file")"
    echo "Backup size: $(du -h "$backup_file" | cut -f1)"
    echo "Backup date: $(stat -c %y "$backup_file" | cut -d'.' -f1)"
    if [[ -n "$services" ]]; then
        echo "Services to restart: $services"
    fi
    echo
    
    # Critical warning
    warning "⚠️  CRITICAL WARNING ⚠️"
    warning "This will COMPLETELY REPLACE your entire PostgreSQL cluster!"
    warning "ALL databases, users, roles, and settings will be DESTROYED!"
    warning "This operation cannot be undone!"
    echo
    
    # Confirmation
    if [[ "$auto_confirm" != "yes" ]]; then
        read -p "Type 'DESTROY AND RESTORE' to confirm this destructive operation: " confirm
        
        if [[ "$confirm" != "DESTROY AND RESTORE" ]]; then
            info "Restore operation cancelled by user"
            exit 0
        fi
    fi
    
    # Stop services
    stop_services "$services"
    
    # Stop PostgreSQL
    log "Stopping PostgreSQL service..."
    systemctl stop postgresql
    
    # Remove existing data (if you want to start completely fresh)
    # UNCOMMENT THESE LINES ONLY IF YOU WANT TO START WITH A COMPLETELY CLEAN SLATE
    # warning "Removing existing PostgreSQL data directory..."
    # rm -rf /var/lib/postgresql/${PG_VERSION}/main/*
    
    # Start PostgreSQL
    log "Starting PostgreSQL service..."
    systemctl start postgresql
    
    # Wait for PostgreSQL to be ready
    sleep 5
    
    # Restore from backup
    log "Starting cluster restore from backup..."
    if gunzip -c "$backup_file" | sudo -u "$PG_USER" psql postgres > /dev/null 2>&1; then
        log "✅ Cluster restore completed successfully!"
    else
        error "❌ Cluster restore failed!"
    fi
    
    # Restart PostgreSQL to ensure all settings take effect
    log "Restarting PostgreSQL to apply all changes..."
    systemctl restart postgresql
    
    # Wait for PostgreSQL to be ready
    sleep 10
    
    # Verify restore
    log "Verifying cluster restore..."
    local db_count=$(sudo -u "$PG_USER" psql -t -c "SELECT COUNT(*) FROM pg_database WHERE datistemplate = false;" | xargs)
    local user_count=$(sudo -u "$PG_USER" psql -t -c "SELECT COUNT(*) FROM pg_user;" | xargs)
    
    log "Restored cluster contains $db_count databases and $user_count users"
    
    # Start services
    start_services "$services"
    
    log "🎉 Cluster restore operation completed successfully!"
    echo
    info "=== RESTORE SUMMARY ==="
    echo "✅ PostgreSQL cluster restored from: $(basename "$backup_file")"
    echo "✅ Databases: $db_count"
    echo "✅ Users: $user_count"
    echo "✅ Log file: $LOG_FILE"
    if [[ -n "$services" ]]; then
        echo "✅ Services restarted: $services"
    fi
    echo
}

# Interactive restore mode
interactive_restore() {
    echo
    info "=== PostgreSQL Cluster Restore - Interactive Mode ==="
    echo
    
    # List available backups
    list_cluster_backups
    
    # Get backup file
    local backup_files=($(find "$BACKUP_DIR" -name "cluster_backup_*.sql.gz" -type f | sort -r))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        error "No cluster backup files available"
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
    restore_cluster "$backup_file" "no" "$services"
}

# Main function
main() {
    local command=""
    local backup_file=""
    local auto_confirm="no"
    local services=""
    
    # Parse command line arguments
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    command="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                backup_file="$BACKUP_DIR/$2"
                shift 2
                ;;
            -y|--yes)
                auto_confirm="yes"
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
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
    
    log "PostgreSQL Cluster Script Started - Command: $command"
    
    # Check permissions and prerequisites
    check_permissions
    
    case $command in
        backup)
            check_postgresql
            mkdir -p "$BACKUP_DIR"
            create_cluster_backup
            ;;
        restore)
            check_postgresql
            if [[ -z "$backup_file" ]]; then
                interactive_restore
            else
                restore_cluster "$backup_file" "$auto_confirm" "$services"
            fi
            ;;
        list)
            list_cluster_backups
            ;;
        help)
            show_help
            ;;
        *)
            error "Unknown command: $command. Use 'help' for usage information."
            ;;
    esac
}

# Run main function
main "$@"
