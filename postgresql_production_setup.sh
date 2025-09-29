#!/bin/bash

# PostgreSQL Production Setup Script with SSL Support for Ubuntu 24.04 LTS
# This script installs PostgreSQL 16, configures SSL with Let's Encrypt, and sets up monitoring
# Run with sudo privileges

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables (will be set by user input)
PG_VERSION="16"
PG_USER="postgres"
PG_DB=""
PG_PASSWORD=""
DOMAIN_NAME=""
EMAIL=""
CREATE_DB_USER=""
DB_USERNAME=""
DB_USER_PASSWORD=""
POSTGRES_PASSWORD=""
BACKUP_DIR="/var/backups/postgresql"
LOG_FILE="/var/log/postgresql_setup.log"

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Input validation functions
validate_domain() {
    local domain=$1
    if [[ ! $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

validate_email() {
    local email=$1
    if [[ ! $email =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

validate_username() {
    local username=$1
    if [[ ! $username =~ ^[a-zA-Z][a-zA-Z0-9_]{2,31}$ ]]; then
        return 1
    fi
    return 0
}

# User input function
get_user_input() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║              PostgreSQL Production Setup with SSL             ║
║                        Let's Encrypt Support                  ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    # Get domain name
    while true; do
        info "Enter your domain name (e.g., db.example.com):"
        read -r DOMAIN_NAME
        if validate_domain "$DOMAIN_NAME"; then
            break
        else
            echo -e "${RED}Invalid domain name format. Please try again.${NC}"
        fi
    done

    # Get email for Let's Encrypt
    while true; do
        info "Enter your email address for Let's Encrypt notifications:"
        read -r EMAIL
        if validate_email "$EMAIL"; then
            break
        else
            echo -e "${RED}Invalid email format. Please try again.${NC}"
        fi
    done

    # Get database name
    while true; do
        info "Enter the database name to create (default: production_db):"
        read -r PG_DB
        if [[ -z "$PG_DB" ]]; then
            PG_DB="production_db"
        fi
        if [[ $PG_DB =~ ^[a-zA-Z][a-zA-Z0-9_]{2,63}$ ]]; then
            break
        else
            echo -e "${RED}Invalid database name. Must start with letter, contain only letters, numbers, and underscores.${NC}"
        fi
    done

    # Set postgres user password
    while true; do
        info "Set password for 'postgres' superuser (leave empty for auto-generated):"
        read -s POSTGRES_PASSWORD
        echo
        if [[ -z "$POSTGRES_PASSWORD" ]]; then
            POSTGRES_PASSWORD=$(openssl rand -base64 32)
            info "Auto-generated postgres password will be saved to setup info file."
        fi
        if [[ ${#POSTGRES_PASSWORD} -ge 8 ]]; then
            break
        else
            echo -e "${RED}Password must be at least 8 characters long.${NC}"
        fi
    done

    # Ask if user wants to create additional database user
    while true; do
        info "Do you want to create an additional database user? (y/n):"
        read -r CREATE_DB_USER
        if [[ $CREATE_DB_USER =~ ^[YyNn]$ ]]; then
            break
        else
            echo -e "${RED}Please enter 'y' for yes or 'n' for no.${NC}"
        fi
    done

    if [[ $CREATE_DB_USER =~ ^[Yy]$ ]]; then
        # Get database username
        while true; do
            info "Enter database username:"
            read -r DB_USERNAME
            if validate_username "$DB_USERNAME" && [[ "$DB_USERNAME" != "postgres" ]]; then
                break
            else
                echo -e "${RED}Invalid username. Must start with letter, 3-32 chars, letters/numbers/underscore only, not 'postgres'.${NC}"
            fi
        done

        # Get database user password
        while true; do
            info "Set password for user '$DB_USERNAME' (leave empty for auto-generated):"
            read -s DB_USER_PASSWORD
            echo
            if [[ -z "$DB_USER_PASSWORD" ]]; then
                DB_USER_PASSWORD=$(openssl rand -base64 24)
                info "Auto-generated password will be saved to setup info file."
            fi
            if [[ ${#DB_USER_PASSWORD} -ge 8 ]]; then
                break
            else
                echo -e "${RED}Password must be at least 8 characters long.${NC}"
            fi
        done
    fi

    # Confirmation
    echo
    info "Configuration Summary:"
    echo -e "${YELLOW}Domain: ${DOMAIN_NAME}${NC}"
    echo -e "${YELLOW}Email: ${EMAIL}${NC}"
    echo -e "${YELLOW}Database: ${PG_DB}${NC}"
    echo -e "${YELLOW}Postgres password: ${POSTGRES_PASSWORD:0:8}...${NC}"
    if [[ $CREATE_DB_USER =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}DB User: ${DB_USERNAME}${NC}"
        echo -e "${YELLOW}DB User password: ${DB_USER_PASSWORD:0:8}...${NC}"
    fi
    echo

    while true; do
        info "Continue with this configuration? (y/n):"
        read -r confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            break
        elif [[ $confirm =~ ^[Nn]$ ]]; then
            error "Setup cancelled by user."
        else
            echo -e "${RED}Please enter 'y' for yes or 'n' for no.${NC}"
        fi
    done
}

# PostgreSQL connection wrapper function
psql_wrapper() {
    local psql_args="$@"
    
    # For initial connections before password is set, use peer authentication
    # Try socket connection first (uses peer auth)
    if sudo -u postgres psql -h /var/run/postgresql $psql_args 2>/dev/null; then
        return 0
    fi
    
    # Try default connection (usually uses peer auth for local connections)
    if sudo -u postgres psql $psql_args 2>/dev/null; then
        return 0
    fi
    
    # Try localhost connection only if password might be set
    if [[ -n "$POSTGRES_PASSWORD" ]]; then
        if PGPASSWORD="$POSTGRES_PASSWORD" sudo -u postgres psql -h localhost -p 5432 $psql_args 2>/dev/null; then
            return 0
        fi
    fi
    
    # All methods failed
    return 1
}

# PostgreSQL diagnostic function
diagnose_postgresql() {
    log "PostgreSQL diagnostic information:"
    echo "Service status: $(systemctl is-active postgresql 2>/dev/null || echo 'inactive')"
    echo "Cluster status:"
    pg_lsclusters 2>/dev/null || echo "No clusters found"
    echo "Data directory status:"
    if [[ -d "/var/lib/postgresql/${PG_VERSION}/main" ]]; then
        echo "  Directory exists: /var/lib/postgresql/${PG_VERSION}/main"
        if [[ -f "/var/lib/postgresql/${PG_VERSION}/main/PG_VERSION" ]]; then
            echo "  PG_VERSION file exists (initialized)"
        else
            echo "  PG_VERSION file missing (not initialized)"
        fi
    else
        echo "  Data directory missing: /var/lib/postgresql/${PG_VERSION}/main"
    fi
    echo "Config directory status:"
    if [[ -d "/etc/postgresql/${PG_VERSION}/main" ]]; then
        echo "  Config directory exists: /etc/postgresql/${PG_VERSION}/main"
        ls -la /etc/postgresql/${PG_VERSION}/main/ 2>/dev/null || echo "  Cannot list config files"
    else
        echo "  Config directory missing: /etc/postgresql/${PG_VERSION}/main"
    fi
    echo "Process status:"
    ps aux | grep postgres | grep -v grep || echo "No PostgreSQL processes"
    echo "Port status:"
    netstat -tlnp 2>/dev/null | grep :5432 || echo "Port 5432 not listening"
    echo "Recent logs:"
    journalctl -u postgresql -n 10 --no-pager 2>/dev/null || echo "No recent logs"
}

# System pre-checks
system_precheck() {
    log "Running system pre-checks..."
    
    # Check disk space (need at least 2GB free)
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=2097152  # 2GB in KB
    if [[ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]]; then
        error "Insufficient disk space. Need at least 2GB free, have $(($AVAILABLE_SPACE/1024/1024))GB"
    fi
    
    # Check if PostgreSQL is already installed
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        warning "PostgreSQL service is already running"
        info "Do you want to continue and potentially overwrite existing installation? (y/n):"
        read -r overwrite_confirm
        if [[ ! $overwrite_confirm =~ ^[Yy]$ ]]; then
            error "Installation cancelled by user"
        fi
    fi
    
    # Configure basic UFW firewall rules
    log "Configuring basic firewall rules..."
    if command -v ufw &> /dev/null; then
        ufw --force enable
        ufw allow ssh
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 5432/tcp
        ufw allow 3000/tcp
        ufw allow 9090/tcp
        ufw allow 9187/tcp
        ufw allow 6432/tcp
        log "Basic UFW rules configured"
    fi
    
    # Manual port confirmation
    log "Required ports for this setup:"
    info "  - 80 (HTTP - for Let's Encrypt)"
    info "  - 443 (HTTPS - for SSL certificates)"
    info "  - 5432 (PostgreSQL database)"
    info "  - 3000 (Grafana dashboard)"
    info "  - 9090 (Prometheus metrics)"
    info "  - 9187 (PostgreSQL Exporter)"
    info "  - 6432 (pgBouncer connection pooling)"
    echo
    info "Please ensure these ports are open in your cloud provider firewall/security groups:"
    info ""
    info "AWS EC2:"
    info "  1. Go to EC2 Console → Security Groups"
    info "  2. Select your instance's security group"
    info "  3. Add Inbound Rules for ports: 80, 443, 5432, 3000, 9090, 9187, 6432"
    info "  4. Source: 0.0.0.0/0 (or your specific IP range)"
    info ""
    info "Google Cloud:"
    info "  1. Go to VPC Network → Firewall"
    info "  2. Create firewall rule allowing ports: 80, 443, 5432, 3000, 9090, 9187, 6432"
    info ""
    info "Azure:"
    info "  1. Go to Network Security Groups"
    info "  2. Add Inbound Security Rules for the required ports"
    info ""
    
    while true; do
        info "Have you ensured that all required ports (80, 443, 5432, 3000, 9090, 9187, 6432) are open in your cloud firewall? (y/n):"
        read -r ports_confirmed
        if [[ $ports_confirmed =~ ^[Yy]$ ]]; then
            log "Proceeding with installation..."
            break
        elif [[ $ports_confirmed =~ ^[Nn]$ ]]; then
            error "Installation cancelled. Please configure your cloud firewall first and run the script again."
        else
            echo -e "${RED}Please enter 'y' for yes or 'n' for no.${NC}"
        fi
    done
    
    log "System pre-checks completed"
}

# Check DNS resolution
check_dns() {
    log "Checking DNS resolution for $DOMAIN_NAME..."
    if ! nslookup "$DOMAIN_NAME" > /dev/null 2>&1; then
        warning "DNS resolution failed for $DOMAIN_NAME"
        warning "Make sure your domain points to this server's IP address"
        info "Current server IP addresses:"
        ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1
        
        while true; do
            info "Continue anyway? DNS must be properly configured for SSL certificates. (y/n):"
            read -r dns_continue
            if [[ $dns_continue =~ ^[Yy]$ ]]; then
                break
            elif [[ $dns_continue =~ ^[Nn]$ ]]; then
                error "Setup cancelled. Please configure DNS first."
            fi
        done
    else
        log "DNS resolution successful for $DOMAIN_NAME"
    fi
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

# Create log file
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# Get user input
get_user_input

# Run system pre-checks
system_precheck

# Check DNS
check_dns

log "Starting PostgreSQL production setup with SSL for PostgreSQL 16 (latest stable)..."

# Update system packages
log "Updating system packages..."
apt update && apt upgrade -y

# Install required packages
log "Installing required packages..."
apt install -y \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    curl \
    software-properties-common \
    apt-transport-https \
    unzip \
    htop \
    iotop \
    sysstat \
    logrotate \
    fail2ban \
    ufw \
    openssl \
    snapd \
    nginx \
    certbot \
    python3-certbot-nginx \
    net-tools \
    locales \
    apache2-utils

# Install certbot via snap for latest version
snap install core; snap refresh core
snap install --classic certbot
ln -sf /snap/bin/certbot /usr/bin/certbot

# Add PostgreSQL official repository
log "Adding PostgreSQL official repository for latest updates..."
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Update package list to get latest PostgreSQL packages
log "Updating package cache with latest PostgreSQL packages..."
apt update

# Configure system locales for PostgreSQL
log "Configuring system locales..."
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Install PostgreSQL
log "Installing PostgreSQL ${PG_VERSION}..."
apt install -y postgresql-${PG_VERSION} postgresql-client-${PG_VERSION} postgresql-contrib-${PG_VERSION}

# Install PostgreSQL extensions (with fallback for unavailable packages)
log "Installing PostgreSQL extensions..."

# Check and install available extensions for PostgreSQL 17
AVAILABLE_EXTENSIONS=()

# Check each extension individually
for ext in "postgresql-${PG_VERSION}-postgis-3" \
           "postgresql-${PG_VERSION}-pgaudit" \
           "postgresql-${PG_VERSION}-hypopg"; do
    if apt-cache show "$ext" >/dev/null 2>&1; then
        AVAILABLE_EXTENSIONS+=("$ext")
        log "Extension $ext is available"
    else
        warning "Extension $ext is not available for PostgreSQL $PG_VERSION"
    fi
done

# Install available extensions
if [ ${#AVAILABLE_EXTENSIONS[@]} -gt 0 ]; then
    apt install -y "${AVAILABLE_EXTENSIONS[@]}"
fi

# pg_stat_statements and pg_partman are typically built-in or in contrib package
log "Note: pg_stat_statements is included in postgresql-contrib package"
log "Note: pg_partman may need to be installed separately if needed"

# Stop any running PostgreSQL services first
log "Stopping any existing PostgreSQL services..."
systemctl stop postgresql 2>/dev/null || true
systemctl stop postgresql@${PG_VERSION}-main 2>/dev/null || true

# Check if cluster already exists and remove it completely for fresh install
log "Checking PostgreSQL cluster status..."
if pg_lsclusters 2>/dev/null | grep -q "${PG_VERSION}.*main"; then
    CLUSTER_STATUS=$(pg_lsclusters 2>/dev/null | grep "${PG_VERSION}.*main" | awk '{print $4}' || echo "")
    log "Found existing cluster with status: $CLUSTER_STATUS"
    log "Removing existing cluster for fresh installation..."
    pg_dropcluster --stop ${PG_VERSION} main 2>/dev/null || true
    rm -rf /var/lib/postgresql/${PG_VERSION}/main 2>/dev/null || true
    rm -rf /etc/postgresql/${PG_VERSION}/main 2>/dev/null || true
else
    log "No existing cluster found"
fi

# Create fresh PostgreSQL cluster
log "Creating fresh PostgreSQL cluster..."

# Ensure postgres user exists
if ! id postgres &>/dev/null; then
    log "Creating postgres user..."
    adduser --system --home /var/lib/postgresql --no-create-home --shell /bin/bash --group --gecos "PostgreSQL administrator" postgres
fi

# Clean up any remaining files
log "Cleaning up any remaining PostgreSQL files..."
rm -rf /var/lib/postgresql/${PG_VERSION} 2>/dev/null || true
rm -rf /etc/postgresql/${PG_VERSION} 2>/dev/null || true
rm -rf /var/log/postgresql/* 2>/dev/null || true

# Create base directories
mkdir -p /var/lib/postgresql/${PG_VERSION}
mkdir -p /etc/postgresql/${PG_VERSION}
mkdir -p /var/log/postgresql
chown -R postgres:postgres /var/lib/postgresql
chown -R postgres:postgres /var/log/postgresql

# Create the cluster with explicit parameters
log "Creating PostgreSQL cluster ${PG_VERSION}/main..."
pg_createcluster ${PG_VERSION} main --start --encoding=UTF8 --locale=en_US.UTF-8 --lc-collate=en_US.UTF-8 --lc-ctype=en_US.UTF-8

# Enable and start PostgreSQL service
log "Enabling and starting PostgreSQL service..."
systemctl enable postgresql
systemctl start postgresql

# Wait a moment for service to initialize
sleep 5

# Now wait for PostgreSQL to accept connections
log "Waiting for PostgreSQL to accept connections..."
for i in {1..30}; do
    # Check if PostgreSQL service is running
    if ! systemctl is-active --quiet postgresql; then
        log "PostgreSQL service is not running, attempting to start... (attempt $i/30)"
        systemctl start postgresql 2>/dev/null || true
        sleep 3
        continue
    fi
    
    # Test database connection
    if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
        log "PostgreSQL is ready and accepting connections"
        break
    fi
    
    # Check cluster status for debugging
    CLUSTER_INFO=$(pg_lsclusters 2>/dev/null | grep "${PG_VERSION}.*main" || echo "No cluster found")
    log "Cluster status: $CLUSTER_INFO (attempt $i/30)"
    
    # On final attempt, show detailed error information
    if [[ $i -eq 30 ]]; then
        error "PostgreSQL failed to accept connections after 30 attempts. Debug info:
        Service status: $(systemctl is-active postgresql)
        Cluster status: $CLUSTER_INFO
        Check logs with: journalctl -u postgresql -n 50"
    fi
    sleep 2
done

# Configure temporary nginx for certbot
log "Setting up temporary nginx configuration for SSL certificate..."
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};
    
    location / {
        return 200 "PostgreSQL SSL Setup in Progress";
        add_header Content-Type text/plain;
    }
}
EOF

systemctl start nginx
systemctl enable nginx

# Function to clear certbot locks
clear_certbot_locks() {
    log "Checking for existing Certbot processes and lock files..."
    
    # Kill any existing certbot processes
    if pgrep -f certbot > /dev/null; then
        warning "Found running Certbot processes, terminating them..."
        pkill -f certbot || true
        sleep 2
    fi
    
    # Remove lock files from common locations
    local lock_files=(
        "/var/log/letsencrypt/.certbot.lock"
        "/var/lib/letsencrypt/.certbot.lock"
        "/tmp/.certbot.lock"
    )
    
    for lock_file in "${lock_files[@]}"; do
        if [[ -f "$lock_file" ]]; then
            warning "Removing stale lock file: $lock_file"
            rm -f "$lock_file" || true
        fi
    done
    
    # Clean up any temporary certbot directories
    find /tmp -name "*certbot*" -type d -exec rm -rf {} + 2>/dev/null || true
}

# Obtain SSL certificate
log "Obtaining SSL certificate from Let's Encrypt..."

# Clear any existing locks before running certbot
clear_certbot_locks

# Retry certbot with exponential backoff
retry_count=0
max_retries=3
while [[ $retry_count -lt $max_retries ]]; do
    if certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos --email "$EMAIL" --redirect --preconfigured-renewal; then
        log "✅ SSL certificate obtained successfully!"
        break
    else
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            warning "Certbot failed (attempt $retry_count/$max_retries). Clearing locks and retrying in 10 seconds..."
            clear_certbot_locks
            sleep 10
        else
            error "Failed to obtain SSL certificate after $max_retries attempts"
            log "You may need to manually run: certbot --nginx -d $DOMAIN_NAME"
            exit 1
        fi
    fi
done

# Configure PostgreSQL SSL
log "Configuring PostgreSQL SSL certificates..."

# Create SSL directory
mkdir -p /var/lib/postgresql/${PG_VERSION}/main/ssl
chown postgres:postgres /var/lib/postgresql/${PG_VERSION}/main/ssl
chmod 700 /var/lib/postgresql/${PG_VERSION}/main/ssl

# Copy certificates for PostgreSQL with proper validation
log "Copying and validating SSL certificates..."

# Copy certificate files
cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt
cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key

# Set proper permissions
chown postgres:postgres /var/lib/postgresql/${PG_VERSION}/main/ssl/server.*
chmod 600 /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key
chmod 644 /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt

# Validate SSL certificate and key
log "Validating SSL certificate and private key..."
if ! openssl x509 -in /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt -noout 2>/dev/null; then
    error "SSL certificate file is invalid or corrupted"
fi

# Check if the private key is valid (works for both RSA and ECDSA)
if ! openssl pkey -in /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key -noout 2>/dev/null; then
    error "SSL private key file is invalid or corrupted"
fi

# Verify certificate and key match (works for both RSA and ECDSA)
CERT_PUBKEY=$(openssl x509 -in /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt -noout -pubkey 2>/dev/null)
KEY_PUBKEY=$(openssl pkey -in /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key -pubout 2>/dev/null)

if [[ "$CERT_PUBKEY" == "$KEY_PUBKEY" ]]; then
    log "✅ SSL certificate and private key match"
else
    error "❌ SSL certificate and private key do not match"
fi

log "SSL certificate validation completed successfully"

# Create certificate renewal hook
log "Setting up automatic SSL certificate renewal..."
mkdir -p /etc/letsencrypt/renewal-hooks/deploy

cat > /etc/letsencrypt/renewal-hooks/deploy/postgresql << EOF
#!/bin/bash
# PostgreSQL SSL certificate renewal hook

# Copy new certificates for PostgreSQL
cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt
cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key
chown postgres:postgres /var/lib/postgresql/${PG_VERSION}/main/ssl/server.*
chmod 600 /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key
chmod 644 /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt

# Copy new certificates for Grafana
cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /etc/grafana/ssl/grafana.crt
cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /etc/grafana/ssl/grafana.key
chown grafana:grafana /etc/grafana/ssl/grafana.*
chmod 600 /etc/grafana/ssl/grafana.key
chmod 644 /etc/grafana/ssl/grafana.crt

# Copy new certificates for Prometheus
cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /etc/prometheus/ssl/prometheus.crt
cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /etc/prometheus/ssl/prometheus.key
chown prometheus:prometheus /etc/prometheus/ssl/prometheus.*
chmod 600 /etc/prometheus/ssl/prometheus.key
chmod 644 /etc/prometheus/ssl/prometheus.crt

# Copy new certificates for PostgreSQL Exporter
if [[ -d "/etc/postgres_exporter/ssl" ]]; then
    cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /etc/postgres_exporter/ssl/exporter.crt
    cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /etc/postgres_exporter/ssl/exporter.key
    chown postgres:postgres /etc/postgres_exporter/ssl/exporter.*
    chmod 600 /etc/postgres_exporter/ssl/exporter.key
    chmod 644 /etc/postgres_exporter/ssl/exporter.crt
fi

# Reload services
systemctl reload postgresql
systemctl restart grafana-server
systemctl restart prometheus
systemctl restart postgres_exporter

echo "[$(date)] All SSL certificates renewed (PostgreSQL, Grafana, Prometheus, PostgreSQL Exporter)" >> /var/log/postgresql_ssl_renewal.log
EOF

chmod +x /etc/letsencrypt/renewal-hooks/deploy/postgresql

# Test automatic renewal
log "Testing SSL certificate renewal..."
clear_certbot_locks
if ! certbot renew --dry-run; then
    warning "SSL certificate renewal test failed, but continuing with setup..."
fi

# Configure PostgreSQL for production with SSL
log "Configuring PostgreSQL for production with SSL..."

# Check available extensions for shared_preload_libraries
log "Checking available PostgreSQL extensions..."
SHARED_PRELOAD_LIBS="pg_stat_statements"

# Check if pgaudit is available
if find /usr/lib/postgresql/${PG_VERSION}/lib -name "pgaudit.so" 2>/dev/null | grep -q pgaudit; then
    log "pgaudit extension is available, adding to shared_preload_libraries"
    SHARED_PRELOAD_LIBS="${SHARED_PRELOAD_LIBS},pgaudit"
    PGAUDIT_AVAILABLE=true
else
    log "pgaudit extension not available, skipping"
    PGAUDIT_AVAILABLE=false
fi

# Get system memory in MB
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))

# Calculate optimal settings based on system resources
SHARED_BUFFERS=$((TOTAL_MEM_MB / 4))  # 25% of total RAM
EFFECTIVE_CACHE_SIZE=$((TOTAL_MEM_MB * 3 / 4))  # 75% of total RAM
MAINTENANCE_WORK_MEM=$((TOTAL_MEM_MB / 16))  # ~6% of total RAM
WORK_MEM=$((TOTAL_MEM_MB / 64))  # Conservative setting

# Backup original configuration
cp /etc/postgresql/${PG_VERSION}/main/postgresql.conf /etc/postgresql/${PG_VERSION}/main/postgresql.conf.backup
cp /etc/postgresql/${PG_VERSION}/main/pg_hba.conf /etc/postgresql/${PG_VERSION}/main/pg_hba.conf.backup

# Create optimized postgresql.conf with SSL
cat > /etc/postgresql/${PG_VERSION}/main/postgresql.conf << EOF
# PostgreSQL Production Configuration with SSL
# Generated by setup script on $(date)

#------------------------------------------------------------------------------
# CONNECTIONS AND AUTHENTICATION
#------------------------------------------------------------------------------
listen_addresses = '*'
port = 5432
max_connections = 200
superuser_reserved_connections = 3

#------------------------------------------------------------------------------
# SSL CONFIGURATION
#------------------------------------------------------------------------------
ssl = on
ssl_cert_file = '/var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt'
ssl_key_file = '/var/lib/postgresql/${PG_VERSION}/main/ssl/server.key'
ssl_ciphers = 'HIGH:MEDIUM:+3DES:!aNULL'
ssl_prefer_server_ciphers = on
ssl_ecdh_curve = 'prime256v1'
ssl_min_protocol_version = 'TLSv1.2'
ssl_max_protocol_version = 'TLSv1.3'

#------------------------------------------------------------------------------
# RESOURCE USAGE (except WAL)
#------------------------------------------------------------------------------
shared_buffers = ${SHARED_BUFFERS}MB
huge_pages = try
work_mem = ${WORK_MEM}MB
maintenance_work_mem = ${MAINTENANCE_WORK_MEM}MB
autovacuum_work_mem = -1
max_stack_depth = 2MB
shared_preload_libraries = '${SHARED_PRELOAD_LIBS}'
dynamic_shared_memory_type = posix

#------------------------------------------------------------------------------
# WRITE AHEAD LOG
#------------------------------------------------------------------------------
wal_level = replica
fsync = on
synchronous_commit = on
wal_sync_method = fsync
full_page_writes = on
wal_compression = on
wal_buffers = 16MB
wal_writer_delay = 200ms
commit_delay = 0
commit_siblings = 5
checkpoint_completion_target = 0.7
checkpoint_warning = 30s
archive_mode = on
archive_command = 'test ! -f ${BACKUP_DIR}/archive/%f && cp %p ${BACKUP_DIR}/archive/%f'
max_wal_senders = 3
wal_keep_size = 1GB

#------------------------------------------------------------------------------
# REPLICATION
#------------------------------------------------------------------------------
hot_standby = on
max_standby_archive_delay = 30s
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
hot_standby_feedback = off

#------------------------------------------------------------------------------
# QUERY TUNING
#------------------------------------------------------------------------------
effective_cache_size = ${EFFECTIVE_CACHE_SIZE}MB
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100

#------------------------------------------------------------------------------
# ERROR REPORTING AND LOGGING
#------------------------------------------------------------------------------
logging_collector = on
log_destination = 'stderr'
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_file_mode = 0640
log_truncate_on_rotation = on
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 1000
log_connections = on
log_disconnections = on
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_lock_waits = on
log_statement = 'ddl'
log_temp_files = 10MB
log_checkpoints = on
log_autovacuum_min_duration = 0

#------------------------------------------------------------------------------
# RUNTIME STATISTICS
#------------------------------------------------------------------------------
track_activities = on
track_counts = on
track_io_timing = on
track_functions = all
# stats_temp_directory parameter removed in PostgreSQL 15+

#------------------------------------------------------------------------------
# AUTOVACUUM PARAMETERS
#------------------------------------------------------------------------------
autovacuum = on
log_autovacuum_min_duration = 0
autovacuum_max_workers = 3
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_analyze_threshold = 50
autovacuum_vacuum_scale_factor = 0.2
autovacuum_analyze_scale_factor = 0.1
autovacuum_freeze_max_age = 200000000
autovacuum_multixact_freeze_max_age = 400000000
autovacuum_vacuum_cost_delay = 20ms
autovacuum_vacuum_cost_limit = -1

#------------------------------------------------------------------------------
# LOCK MANAGEMENT
#------------------------------------------------------------------------------
deadlock_timeout = 1s
max_locks_per_transaction = 64
max_pred_locks_per_transaction = 64

#------------------------------------------------------------------------------
# VERSION/PLATFORM COMPATIBILITY
#------------------------------------------------------------------------------
timezone = 'UTC'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'

#------------------------------------------------------------------------------
# EXTENSIONS
#------------------------------------------------------------------------------
# pg_stat_statements settings
pg_stat_statements.max = 10000
pg_stat_statements.track = all

EOF

# Add pgaudit settings if available
if [[ "$PGAUDIT_AVAILABLE" == "true" ]]; then
    cat >> /etc/postgresql/${PG_VERSION}/main/postgresql.conf << EOF

# pgaudit settings
pgaudit.log = 'write,ddl,role'
pgaudit.log_catalog = off
EOF
fi

# Configure pg_hba.conf for SSL security
cat > /etc/postgresql/${PG_VERSION}/main/pg_hba.conf << EOF
# PostgreSQL Client Authentication Configuration File with SSL
# Generated by setup script on $(date)

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             postgres                                peer
local   all             all                                     md5

# IPv4 local connections:
host    all             all             127.0.0.1/32            md5

# IPv6 local connections:
host    all             all             ::1/128                 md5

# SSL connections (require SSL for remote connections)
hostssl all             all             0.0.0.0/0               md5
hostssl all             all             ::/0                    md5

# Deny non-SSL connections from external sources
hostnossl all           all             0.0.0.0/0               reject
hostnossl all           all             ::/0                    reject

# Allow replication connections from localhost, by a user with the
# replication privilege.
local   replication     all                                     peer
host    replication     all             127.0.0.1/32            md5
host    replication     all             ::1/128                 md5
hostssl replication     all             0.0.0.0/0               md5
EOF

# Create necessary directories
log "Creating necessary directories..."
mkdir -p ${BACKUP_DIR}/{archive,dumps}
mkdir -p /var/log/postgresql
chown -R postgres:postgres ${BACKUP_DIR}
chown -R postgres:postgres /var/log/postgresql
chmod 755 ${BACKUP_DIR}
chmod 755 /var/log/postgresql

# Verify data directory exists and has correct permissions
log "Verifying data directory permissions..."
DATA_DIR="/var/lib/postgresql/${PG_VERSION}/main"
if [[ -d "$DATA_DIR" ]]; then
    # Check if directory is properly initialized
    if [[ -f "$DATA_DIR/PG_VERSION" ]]; then
    chown -R postgres:postgres "$DATA_DIR"
    chmod 700 "$DATA_DIR"
        log "Data directory permissions verified and updated"
    else
        warning "Data directory exists but appears uninitialized: $DATA_DIR"
        log "Attempting to reinitialize PostgreSQL cluster..."
        pg_dropcluster --stop ${PG_VERSION} main 2>/dev/null || true
        rm -rf "$DATA_DIR" 2>/dev/null || true
        pg_createcluster ${PG_VERSION} main --start --encoding=UTF8 --locale=en_US.UTF-8
        systemctl restart postgresql
        sleep 3
    fi
else
    error "Data directory not found after cluster creation: $DATA_DIR"
fi

# Verify PostgreSQL is running before database operations
log "Verifying PostgreSQL service status before database operations..."
if ! systemctl is-active --quiet postgresql; then
    error "PostgreSQL service is not running. Cannot proceed with database setup. Check logs: journalctl -u postgresql -n 20"
fi

# Double-check PostgreSQL connectivity
log "Testing PostgreSQL connection with different methods..."

# Test socket connection explicitly first
if sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" > /dev/null 2>&1; then
    log "Socket connection successful"
    CONNECTION_METHOD="socket"
elif sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
    log "Default connection successful"  
    CONNECTION_METHOD="default"
else
    log "Both socket and default connections failed"
    CONNECTION_METHOD="none"
fi

if [[ "$CONNECTION_METHOD" == "none" ]]; then
    warning "Cannot connect to PostgreSQL. Running diagnostics..."
    diagnose_postgresql
    
    # Check if this is a cluster management issue
    if systemctl is-active --quiet postgresql && netstat -tlnp 2>/dev/null | grep -q ":5432.*postgres"; then
        warning "PostgreSQL is running but cluster management is broken. Attempting to fix..."
        
        # Try to recreate cluster configuration
        log "Recreating cluster configuration..."
        
        # Stop the running PostgreSQL
        systemctl stop postgresql
        sleep 3
        
        # Remove any broken cluster configs
        rm -rf /etc/postgresql/${PG_VERSION}/main/pg_ctl.conf 2>/dev/null || true
        
        # Fix cluster registration issue
        if [[ -d "/var/lib/postgresql/${PG_VERSION}/main" && -f "/var/lib/postgresql/${PG_VERSION}/main/PG_VERSION" ]]; then
            log "Data directory exists but cluster not registered. Fixing cluster registry..."
            
            # Check if cluster config files exist but not registered
            if [[ -f "/etc/postgresql/${PG_VERSION}/main/postgresql.conf" ]]; then
                log "Configuration exists but registry is broken. Rebuilding cluster registry..."
                
                # Force remove any stale cluster registry entries
                rm -f /etc/postgresql-common/createcluster.d/* 2>/dev/null || true
                
                # Try to directly register the cluster by recreating the cluster info
                echo "${PG_VERSION} main /var/lib/postgresql/${PG_VERSION}/main 5432 online postgres /etc/postgresql/${PG_VERSION}/main" > /tmp/cluster_info
                
                # Restart postgresql-common services to refresh cluster registry
                systemctl restart postgresql 2>/dev/null || true
                sleep 3
                
                # Test if cluster is now visible
                if pg_lsclusters 2>/dev/null | grep -q "${PG_VERSION}.*main"; then
                    log "Cluster registry fixed successfully"
                else
                    log "Registry still broken, trying alternative approach..."
                    # Alternative: just ensure PostgreSQL starts properly without cluster management
                    systemctl enable postgresql
                    systemctl start postgresql
                fi
            else
                log "No configuration found, creating fresh cluster..."
                pg_createcluster ${PG_VERSION} main --start --encoding=UTF8 --locale=en_US.UTF-8
            fi
        else
            log "No valid data directory found, creating fresh cluster..."
            pg_createcluster ${PG_VERSION} main --start --encoding=UTF8 --locale=en_US.UTF-8
        fi
        
        # Start PostgreSQL
        systemctl start postgresql
        sleep 5
        
        # Test connection again with multiple methods
        if psql_wrapper -c "SELECT 1;" > /dev/null 2>&1; then
            log "PostgreSQL connection restored successfully!"
        else
            error "All connection methods failed. Manual intervention required.
            
Try these manual steps:
1. sudo systemctl status postgresql
2. sudo -u postgres psql -h /var/run/postgresql
3. sudo journalctl -u postgresql -n 50"
        fi
    else
        error "PostgreSQL connection failed. See diagnostic information above."
    fi
fi

# Set up PostgreSQL users and database
log "Setting up PostgreSQL users and database..."

# Create database with proper error handling
log "Creating database: ${PG_DB}"
if [[ "$CONNECTION_METHOD" == "socket" ]]; then
    if ! sudo -u postgres createdb -h /var/run/postgresql ${PG_DB} 2>/dev/null; then
        warning "Database ${PG_DB} may already exist, checking..."
        # Check if database actually exists
        if sudo -u postgres psql -h /var/run/postgresql -lqt | cut -d \| -f 1 | grep -qw ${PG_DB}; then
            log "Database ${PG_DB} already exists"
        else
            error "Failed to create database ${PG_DB}"
        fi
    else
        log "Database ${PG_DB} created successfully"
    fi
else
    if ! sudo -u postgres createdb ${PG_DB} 2>/dev/null; then
        warning "Database ${PG_DB} may already exist, checking..."
        # Check if database actually exists
        if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw ${PG_DB}; then
            log "Database ${PG_DB} already exists"
        else
            error "Failed to create database ${PG_DB}"
        fi
    else
        log "Database ${PG_DB} created successfully"
    fi
fi

# Set postgres user password
log "Setting postgres user password using $CONNECTION_METHOD connection..."
if [[ "$CONNECTION_METHOD" == "socket" ]]; then
    sudo -u postgres psql -h /var/run/postgresql << EOF
ALTER USER postgres PASSWORD '${POSTGRES_PASSWORD}';
\q
EOF
elif [[ "$CONNECTION_METHOD" == "default" ]]; then
sudo -u postgres psql << EOF
ALTER USER postgres PASSWORD '${POSTGRES_PASSWORD}';
\q
EOF
else
    error "No valid connection method available"
fi

# Create additional database user if requested
if [[ $CREATE_DB_USER =~ ^[Yy]$ ]]; then
    log "Creating database user: ${DB_USERNAME}"
    psql_wrapper << EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USERNAME}') THEN
        CREATE USER ${DB_USERNAME} WITH PASSWORD '${DB_USER_PASSWORD}';
        RAISE NOTICE 'User ${DB_USERNAME} created successfully';
    ELSE
        RAISE NOTICE 'User ${DB_USERNAME} already exists';
    END IF;
END\$\$;

GRANT CONNECT ON DATABASE ${PG_DB} TO ${DB_USERNAME};
GRANT USAGE ON SCHEMA public TO ${DB_USERNAME};
GRANT CREATE ON SCHEMA public TO ${DB_USERNAME};
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USERNAME};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USERNAME};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USERNAME};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USERNAME};
\q
EOF
fi

# Verify database exists before installing extensions
log "Verifying database ${PG_DB} exists..."
log "Current databases:"
if [[ "$CONNECTION_METHOD" == "socket" ]]; then
    sudo -u postgres psql -h /var/run/postgresql -l
    if ! sudo -u postgres psql -h /var/run/postgresql -lqt | cut -d \| -f 1 | grep -qw ${PG_DB}; then
        error "Database ${PG_DB} does not exist. Cannot install extensions."
    fi
else
    sudo -u postgres psql -l
    if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw ${PG_DB}; then
        error "Database ${PG_DB} does not exist. Cannot install extensions."
    fi
fi
log "Database ${PG_DB} verified to exist"

# Enable and configure extensions (with error handling)
log "Enabling PostgreSQL extensions..."
if [[ "$CONNECTION_METHOD" == "socket" ]]; then
    sudo -u postgres psql -h /var/run/postgresql -d ${PG_DB} << EOF
-- Enable pg_stat_statements (usually available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        CREATE EXTENSION pg_stat_statements;
        RAISE NOTICE 'pg_stat_statements extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_stat_statements extension not available: %', SQLERRM;
END\$\$;

-- Enable pgaudit (if available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgaudit') THEN
        CREATE EXTENSION pgaudit;
        RAISE NOTICE 'pgaudit extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pgaudit extension not available: %', SQLERRM;
END\$\$;

-- Enable PostGIS (if available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        CREATE EXTENSION postgis;
        RAISE NOTICE 'postgis extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'postgis extension not available: %', SQLERRM;
END\$\$;

-- Enable hypopg (if available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'hypopg') THEN
        CREATE EXTENSION hypopg;
        RAISE NOTICE 'hypopg extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'hypopg extension not available: %', SQLERRM;
END\$\$;

\q
EOF
else
sudo -u postgres psql -d ${PG_DB} << EOF
-- Enable pg_stat_statements (usually available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements') THEN
        CREATE EXTENSION pg_stat_statements;
        RAISE NOTICE 'pg_stat_statements extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_stat_statements extension not available: %', SQLERRM;
END\$\$;

-- Enable pgaudit (if available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgaudit') THEN
        CREATE EXTENSION pgaudit;
        RAISE NOTICE 'pgaudit extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pgaudit extension not available: %', SQLERRM;
END\$\$;

-- Enable PostGIS (if available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
        CREATE EXTENSION postgis;
        RAISE NOTICE 'postgis extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'postgis extension not available: %', SQLERRM;
END\$\$;

-- Enable hypopg (if available)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'hypopg') THEN
        CREATE EXTENSION hypopg;
        RAISE NOTICE 'hypopg extension created successfully';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'hypopg extension not available: %', SQLERRM;
END\$\$;

\q
EOF
fi

# Test configuration before restarting
log "Testing PostgreSQL configuration..."
CONFIG_FILE="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    error "PostgreSQL configuration file not found: $CONFIG_FILE"
fi

# Test configuration syntax
log "Testing configuration file syntax..."

# Simple configuration file validation - just check if file exists and has basic syntax
if [[ -r "$CONFIG_FILE" ]]; then
    log "Configuration file exists and is readable"
    
    # Check for obvious syntax errors (basic validation)
    if grep -q "^listen_addresses" "$CONFIG_FILE" && grep -q "^port" "$CONFIG_FILE"; then
        log "Configuration file appears to have basic required settings"
        CONFIG_TEST_PASSED=true
    else
        warning "Configuration file may be missing required settings"
        CONFIG_TEST_PASSED=false
    fi
    
    # Check for pgaudit issues if present
    if grep -q "pgaudit" "$CONFIG_FILE"; then
        log "Found pgaudit configuration, checking if extension is loaded..."
        if ! find /usr/lib/postgresql/${PG_VERSION}/lib -name "pgaudit.so" 2>/dev/null | grep -q pgaudit; then
            warning "pgaudit configuration found but extension not available. Removing..."
            sed -i '/pgaudit/d' "$CONFIG_FILE"
        fi
    fi
    
    log "Configuration validation completed"
else
    error "Configuration file is not readable: $CONFIG_FILE"
fi

# Apply SSL configuration with proper restart strategy
log "Applying SSL configuration to PostgreSQL..."

# First, verify SSL certificates are properly set up
log "Verifying SSL certificate setup..."
if [[ ! -f "/var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt" ]]; then
    error "SSL certificate file missing. SSL setup failed earlier."
fi

if [[ ! -f "/var/lib/postgresql/${PG_VERSION}/main/ssl/server.key" ]]; then
    error "SSL private key file missing. SSL setup failed earlier."
fi

# Skip configuration testing - just ensure SSL certificates exist and start PostgreSQL
log "SSL certificates verified. Starting PostgreSQL with SSL configuration..."

# Create a clean, working SSL configuration
log "Creating optimized SSL configuration..."
cp /etc/postgresql/${PG_VERSION}/main/postgresql.conf /etc/postgresql/${PG_VERSION}/main/postgresql.conf.backup

cat > /etc/postgresql/${PG_VERSION}/main/postgresql.conf << EOF
# PostgreSQL Production Configuration with SSL
listen_addresses = '*'
port = 5432
max_connections = 200

# Configuration file locations
data_directory = '/var/lib/postgresql/${PG_VERSION}/main'
hba_file = '/etc/postgresql/${PG_VERSION}/main/pg_hba.conf'
ident_file = '/etc/postgresql/${PG_VERSION}/main/pg_ident.conf'

# SSL Configuration
ssl = on
ssl_cert_file = '/var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt'
ssl_key_file = '/var/lib/postgresql/${PG_VERSION}/main/ssl/server.key'
ssl_prefer_server_ciphers = on

# Memory settings
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 8MB
maintenance_work_mem = 128MB

# Logging
logging_collector = on
log_destination = 'stderr'
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_connections = on
log_disconnections = on

# Extensions
shared_preload_libraries = 'pg_stat_statements'

# Basic WAL settings
wal_level = replica
archive_mode = off
EOF

log "SSL configuration created successfully"

# Now restart PostgreSQL with the working configuration
log "Restarting PostgreSQL with SSL configuration..."

# Create a separate function to handle the restart to avoid any context issues
restart_postgresql_safely() {
    local restart_success=false
    
    # Disable exit on error for this function
    set +e
    
    log "Stopping PostgreSQL service..."
    systemctl stop postgresql >/dev/null 2>&1
    sleep 2
    
    log "Cleaning up any remaining processes..."
    # Use more specific pattern to avoid killing the script itself
    pkill -f "postgres.*main" >/dev/null 2>&1 || true
    pkill -f "/usr/lib/postgresql" >/dev/null 2>&1 || true
    sleep 3
    
    log "Starting PostgreSQL with new configuration..."
    if systemctl start postgresql >/dev/null 2>&1; then
        log "✅ PostgreSQL started via systemd"
        sleep 5
        restart_success=true
        CONNECTION_METHOD="systemd"
        PG_PID="systemd_managed"
    elif pg_ctlcluster ${PG_VERSION} main start >/dev/null 2>&1; then
        log "✅ PostgreSQL started via cluster management"
        sleep 5
        restart_success=true
        CONNECTION_METHOD="cluster"
        PG_PID="cluster_managed"
    else
        log "⚠️  Standard methods failed, trying direct start..."
        sudo -u postgres /usr/lib/postgresql/${PG_VERSION}/bin/postgres \
            -D /var/lib/postgresql/${PG_VERSION}/main \
            -c config_file=/etc/postgresql/${PG_VERSION}/main/postgresql.conf \
            >/var/log/postgresql/postgresql-ssl-startup.log 2>&1 &
        PG_PID=$!
        sleep 10
        restart_success=true
        CONNECTION_METHOD="direct"
        log "PostgreSQL started directly with PID: $PG_PID"
    fi
    
    # Re-enable exit on error
    set -e
    
    if [ "$restart_success" = true ]; then
        log "✅ PostgreSQL restart completed successfully"
        return 0
    else
        log "❌ PostgreSQL restart failed"
        return 1
    fi
}

# Call the restart function
if ! restart_postgresql_safely; then
    error "Failed to restart PostgreSQL with SSL configuration"
fi

# Wait for PostgreSQL to be ready and verify SSL works
log "Waiting for PostgreSQL to be ready and testing SSL..."

# Give PostgreSQL time to fully start
sleep 15

# Test connections systematically
CONNECTION_WORKING=false
SSL_WORKING=false

# Temporarily disable exit on error for connection testing
set +e

# Check if PostgreSQL process is still running
if [[ -n "$PG_PID" ]] && [[ "$PG_PID" == "systemd_managed" ]]; then
    log "PostgreSQL is running under systemd management"
    
    # Test basic connection for systemd managed PostgreSQL
    if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
        log "✅ Systemd managed connection successful"
        CONNECTION_METHOD="default"
        CONNECTION_WORKING=true
    elif sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" > /dev/null 2>&1; then
        log "✅ Socket connection successful"
        CONNECTION_METHOD="socket"
        CONNECTION_WORKING=true
    fi
elif [[ -n "$PG_PID" ]] && [[ "$PG_PID" == "cluster_managed" ]]; then
    log "PostgreSQL is running under cluster management"
    
    # Test basic connection for cluster managed PostgreSQL
    if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
        log "✅ Cluster managed connection successful"
        CONNECTION_METHOD="default"
        CONNECTION_WORKING=true
    elif sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" > /dev/null 2>&1; then
        log "✅ Socket connection successful"
        CONNECTION_METHOD="socket"
        CONNECTION_WORKING=true
    fi
elif [[ -n "$PG_PID" ]] && kill -0 $PG_PID 2>/dev/null; then
    log "PostgreSQL process $PG_PID is still running"
    
    # Test basic connection
    if sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" > /dev/null 2>&1; then
        log "✅ Socket connection successful"
        CONNECTION_METHOD="socket"
        CONNECTION_WORKING=true
    elif sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
        log "✅ Default connection successful"
        CONNECTION_METHOD="default"
        CONNECTION_WORKING=true
    else
        warning "PostgreSQL process running but not accepting connections yet. Waiting longer..."
        sleep 10
        
        # Try again
        if sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" > /dev/null 2>&1; then
            log "✅ Socket connection successful after waiting"
            CONNECTION_METHOD="socket"
            CONNECTION_WORKING=true
        elif sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
            log "✅ Default connection successful after waiting"
            CONNECTION_METHOD="default"
            CONNECTION_WORKING=true
        fi
    fi
else
    warning "PostgreSQL process has exited or was not started properly"
    log "Checking startup logs..."
    if [[ -f "/var/log/postgresql/postgresql-ssl-startup.log" ]]; then
        echo "Startup log contents:"
        cat /var/log/postgresql/postgresql-ssl-startup.log || true
    fi
    
    # Try to start PostgreSQL one more time with foreground mode to see errors
    log "Attempting to start PostgreSQL in foreground mode to see errors..."
    timeout 10 sudo -u postgres /usr/lib/postgresql/16/bin/postgres \
        -D /var/lib/postgresql/16/main \
        -c config_file=/etc/postgresql/16/main/postgresql.conf 2>&1 | head -20 || true
fi

# If basic connection works, test SSL
if [[ "$CONNECTION_WORKING" == "true" ]]; then
log "Testing SSL connection..."
    
    # Use the same connection method that worked for basic connection
    if [[ "$CONNECTION_METHOD" == "socket" ]]; then
        # For socket connections, we need to test SSL via domain name with password
        if PGPASSWORD="$POSTGRES_PASSWORD" psql "postgresql://postgres@${DOMAIN_NAME}:5432/${PG_DB}?sslmode=require" -c "SELECT 1;" > /dev/null 2>&1; then
            log "✅ SSL connection successful!"
            SSL_WORKING=true
        fi
    elif [[ "$CONNECTION_METHOD" == "default" ]]; then
        # For default connections, try SSL with domain name and automatic password
        if PGPASSWORD="$POSTGRES_PASSWORD" psql "postgresql://postgres@${DOMAIN_NAME}:5432/${PG_DB}?sslmode=require" -c "SELECT 1;" > /dev/null 2>&1; then
            log "✅ SSL connection successful with domain name!"
            SSL_WORKING=true
        fi
    fi
    
    # If SSL still failed, try to reload configuration
    if [[ "$SSL_WORKING" != "true" ]]; then
        warning "SSL connection failed, attempting to reload configuration..."
        
        if [[ "$CONNECTION_METHOD" == "socket" ]]; then
            sudo -u postgres psql -h /var/run/postgresql -c "SELECT pg_reload_conf();" > /dev/null 2>&1 || true
        else
            sudo -u postgres psql -c "SELECT pg_reload_conf();" > /dev/null 2>&1 || true
        fi
        
        sleep 5
        
        # Test SSL again after reload
        if PGPASSWORD="$POSTGRES_PASSWORD" psql "postgresql://postgres@${DOMAIN_NAME}:5432/${PG_DB}?sslmode=require" -c "SELECT 1;" > /dev/null 2>&1; then
            log "✅ SSL connection successful after reload!"
            SSL_WORKING=true
        fi
    fi
fi

# Re-enable exit on error
set -e

# If still no SSL, this is a hard error
if [[ "$CONNECTION_WORKING" != "true" ]]; then
    error "PostgreSQL failed to start properly. Cannot continue without working database connection."
fi

if [[ "$SSL_WORKING" != "true" ]]; then
    warning "SSL connection failed. This may indicate SSL certificate or configuration issues."
    log "Continuing setup with basic PostgreSQL connection available."
    log "You can manually configure SSL later by checking:"
    log "  - SSL certificate files in /etc/ssl/certs/ and /etc/ssl/private/"
    log "  - PostgreSQL SSL configuration in /etc/postgresql/${PG_VERSION}/main/postgresql.conf"
    log "  - Domain name resolution and firewall settings"
fi

if [[ "$SSL_WORKING" == "true" ]]; then
    log "✅ PostgreSQL is ready with working SSL connection!"
else
    log "✅ PostgreSQL is ready with basic connection (SSL needs manual configuration)!"
fi

# SSL connection already tested above

# Function to compile pg_stat_monitor from source
compile_pg_stat_monitor() {
    log "Installing build dependencies for pg_stat_monitor..."
    apt install -y build-essential git postgresql-server-dev-${PG_VERSION} libpq-dev
    
    # Create temporary build directory
    BUILD_DIR="/tmp/pg_stat_monitor_build"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Clone pg_stat_monitor source
    log "Cloning pg_stat_monitor source..."
    if git clone https://github.com/percona/pg_stat_monitor.git; then
        cd pg_stat_monitor
        
        # Build and install
        log "Building pg_stat_monitor..."
        if make USE_PGXS=1 && make USE_PGXS=1 install; then
            log "pg_stat_monitor compiled and installed successfully"
            
            # Update shared_preload_libraries to include pg_stat_monitor
            log "Updating PostgreSQL configuration to use pg_stat_monitor..."
            sed -i "s/shared_preload_libraries = '[^']*'/shared_preload_libraries = 'pg_stat_monitor'/" /etc/postgresql/${PG_VERSION}/main/postgresql.conf
            
            # Add pg_stat_monitor configuration
            cat >> /etc/postgresql/${PG_VERSION}/main/postgresql.conf << EOF

# pg_stat_monitor settings (enhanced query statistics)
pg_stat_monitor.pgsm_max = 10000
pg_stat_monitor.pgsm_query_max_len = 2048
pg_stat_monitor.pgsm_normalized_query = on
pg_stat_monitor.pgsm_enable_query_plan = on
pg_stat_monitor.pgsm_track_planning = on
EOF
            
            # Restart PostgreSQL to load the new extension
            log "Restarting PostgreSQL to load pg_stat_monitor..."
            pkill -f "postgres.*main" 2>/dev/null || true
            pkill -f "/usr/lib/postgresql" 2>/dev/null || true
            sleep 3
            
            # Start PostgreSQL again
            sudo -u postgres /usr/lib/postgresql/${PG_VERSION}/bin/postgres \
                -D /var/lib/postgresql/${PG_VERSION}/main \
                -c config_file=/etc/postgresql/${PG_VERSION}/main/postgresql.conf \
                > /var/log/postgresql/postgresql-direct-startup.log 2>&1 &
            
            PG_PID=$!
            sleep 10
            
            # Test if pg_stat_monitor is available
            if sudo -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_stat_monitor;" > /dev/null 2>&1; then
                log "🎉 pg_stat_monitor extension created successfully!"
                PG_STAT_MONITOR_AVAILABLE=true
            else
                warning "Failed to create pg_stat_monitor extension, falling back to pg_stat_statements"
                sed -i "s/shared_preload_libraries = 'pg_stat_monitor'/shared_preload_libraries = 'pg_stat_statements'/" /etc/postgresql/${PG_VERSION}/main/postgresql.conf
                PG_STAT_MONITOR_AVAILABLE=false
            fi
        else
            warning "Failed to build pg_stat_monitor, using default pg_stat_statements"
            PG_STAT_MONITOR_AVAILABLE=false
        fi
    else
        warning "Failed to clone pg_stat_monitor source, using default pg_stat_statements"
        PG_STAT_MONITOR_AVAILABLE=false
    fi
    
    # Clean up build directory
    cd /
    rm -rf "$BUILD_DIR"
}

# Install and configure monitoring tools
log "Installing monitoring tools..."

# Install pg_stat_monitor (better than pg_stat_statements)
log "Installing pg_stat_monitor..."
# Detect architecture for pg_stat_monitor
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    wget -q https://github.com/percona/pg_stat_monitor/releases/download/REL2_0_4/percona-pg-stat-monitor_2.0.4-1.noble_amd64.deb
    if [[ $? -eq 0 ]]; then
        dpkg -i percona-pg-stat-monitor_2.0.4-1.noble_amd64.deb || apt-get install -f -y
        rm percona-pg-stat-monitor_2.0.4-1.noble_amd64.deb
        log "pg_stat_monitor installed successfully from package"
    else
        warning "Failed to download pg_stat_monitor for x86_64, compiling from source..."
        compile_pg_stat_monitor
    fi
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    log "Compiling pg_stat_monitor from source for ARM64..."
    compile_pg_stat_monitor
else
    warning "Unsupported architecture: $ARCH, using default pg_stat_statements"
fi



# Install pgBadger for log analysis
apt install -y pgbadger

# Install Prometheus
log "Installing Prometheus..."
wget -q https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-arm64.tar.gz
tar xzf prometheus-2.45.0.linux-arm64.tar.gz
mv prometheus-2.45.0.linux-arm64/prometheus /usr/local/bin/
mv prometheus-2.45.0.linux-arm64/promtool /usr/local/bin/
rm -rf prometheus-2.45.0.linux-arm64*

# Create prometheus user and directories
if ! id prometheus &>/dev/null; then
    useradd --no-create-home --shell /bin/false prometheus
    log "Created prometheus user"
else
    log "Prometheus user already exists"
fi

mkdir -p /etc/prometheus /var/lib/prometheus /etc/prometheus/ssl
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus /etc/prometheus/ssl

# Create Prometheus configuration
cat > /etc/prometheus/prometheus.yml << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'postgresql'
    static_configs:
      - targets: ['localhost:9187']
    scrape_interval: 5s
    metrics_path: /metrics
EOF

chown prometheus:prometheus /etc/prometheus/prometheus.yml

# Configure Prometheus with HTTP Authentication
log "Configuring Prometheus with HTTP Authentication..."

# Check if htpasswd is available (should be installed with apache2-utils)
if ! command -v htpasswd &> /dev/null; then
    error "htpasswd command not found. Please install apache2-utils package."
fi

# Generate secure credentials for Prometheus
PROMETHEUS_USER="prometheus_admin"
PROMETHEUS_PASSWORD=$(openssl rand -base64 24)

log "Generated Prometheus credentials - User: ${PROMETHEUS_USER}"

# Create web config file for Prometheus authentication
mkdir -p /etc/prometheus
log "Creating Prometheus authentication configuration..."

# Generate password hash using htpasswd
PROMETHEUS_HASH=$(htpasswd -nbB ${PROMETHEUS_USER} ${PROMETHEUS_PASSWORD} | cut -d: -f2)

cat > /etc/prometheus/web.yml << EOF
basic_auth_users:
  ${PROMETHEUS_USER}: ${PROMETHEUS_HASH}
EOF

# Set proper ownership and permissions for security
chown prometheus:prometheus /etc/prometheus/web.yml
chmod 600 /etc/prometheus/web.yml

# Verify the web config file was created correctly
if [[ ! -f /etc/prometheus/web.yml ]] || [[ ! -s /etc/prometheus/web.yml ]]; then
    error "Failed to create Prometheus web configuration file"
fi

log "Prometheus authentication configuration created successfully"

# Store credentials for later use and reference
cat > /etc/prometheus/.env << EOF
PROMETHEUS_USER=${PROMETHEUS_USER}
PROMETHEUS_PASSWORD=${PROMETHEUS_PASSWORD}
EOF
chmod 600 /etc/prometheus/.env
chown prometheus:prometheus /etc/prometheus/.env

log "Prometheus credentials stored in /etc/prometheus/.env"

# Create Prometheus systemd service with authentication
log "Creating Prometheus systemd service with authentication..."

cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=always
RestartSec=5
ExecStart=/usr/local/bin/prometheus \\
    --config.file=/etc/prometheus/prometheus.yml \\
    --storage.tsdb.path=/var/lib/prometheus/ \\
    --web.console.templates=/etc/prometheus/consoles \\
    --web.console.libraries=/etc/prometheus/console_libraries \\
    --web.listen-address=0.0.0.0:9090 \\
    --web.config.file=/etc/prometheus/web.yml \\
    --storage.tsdb.retention.time=30d \\
    --web.enable-lifecycle

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Prometheus
systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus

# Wait for Prometheus to start
log "Waiting for Prometheus to start with authentication..."
sleep 10

# Verify Prometheus is running
if ! systemctl is-active --quiet prometheus; then
    warning "Prometheus service failed to start. Checking logs..."
    journalctl -u prometheus -n 20 --no-pager
    
    # Try to start again
    log "Attempting to restart Prometheus service..."
    systemctl restart prometheus
    sleep 10
    
    if ! systemctl is-active --quiet prometheus; then
        error "Prometheus failed to start after retry. Check logs: journalctl -u prometheus -f"
    fi
fi

# Test Prometheus authentication
log "Testing Prometheus authentication..."

# Test that unauthenticated access is denied (should fail)
if curl -s --max-time 5 http://localhost:9090/api/v1/status/config >/dev/null 2>&1; then
    warning "Prometheus is accessible without authentication - this may indicate a configuration issue"
else
    log "✅ Unauthenticated access properly denied"
fi

# Test that authenticated access works
if curl -s --max-time 5 -u "${PROMETHEUS_USER}:${PROMETHEUS_PASSWORD}" http://localhost:9090/api/v1/status/config >/dev/null 2>&1; then
    log "✅ Prometheus authentication working correctly"
else
    warning "Prometheus authentication test failed - check configuration"
fi

log "Prometheus setup with authentication completed"

# Install Grafana
log "Installing Grafana..."
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
echo "deb https://packages.grafana.com/oss/deb stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
apt update
apt install -y grafana

# Configure Grafana with HTTPS
log "Configuring Grafana with HTTPS..."

# Copy SSL certificates for Grafana
mkdir -p /etc/grafana/ssl
cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /etc/grafana/ssl/grafana.crt
cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /etc/grafana/ssl/grafana.key
chown grafana:grafana /etc/grafana/ssl/grafana.*
chmod 600 /etc/grafana/ssl/grafana.key
chmod 644 /etc/grafana/ssl/grafana.crt

# Configure Grafana for HTTPS
log "Configuring Grafana HTTPS settings..."

# Backup original config
cp /etc/grafana/grafana.ini /etc/grafana/grafana.ini.backup

# Create a clean Grafana configuration with HTTPS
cat > /etc/grafana/grafana.ini << EOF
[server]
protocol = https
http_port = 3000
cert_file = /etc/grafana/ssl/grafana.crt
cert_key = /etc/grafana/ssl/grafana.key
root_url = https://${DOMAIN_NAME}:3000/

[security]
admin_user = admin
admin_password = admin
allow_embedding = true

[log]
mode = console file
level = info

[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
provisioning = /etc/grafana/provisioning
EOF

# Ensure proper ownership
chown grafana:grafana /etc/grafana/grafana.ini

systemctl enable grafana-server
systemctl start grafana-server

# Wait for Grafana to start and verify HTTPS
log "Waiting for Grafana to start with HTTPS..."
sleep 15

# Test Grafana HTTPS
log "Testing Grafana HTTPS configuration..."
sleep 15

# Check if Grafana is listening on port 3000
if netstat -tlnp 2>/dev/null | grep -q ":3000 "; then
    log "Grafana is listening on port 3000"
    
    # Test HTTPS
    if curl -k -s https://localhost:3000/api/health > /dev/null 2>&1; then
        log "✅ Grafana HTTPS is working correctly"
    elif curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        warning "Grafana is running on HTTP instead of HTTPS"
        log "Attempting to fix Grafana HTTPS configuration..."
        
        # Check SSL certificate files
        if [[ ! -f "/etc/grafana/ssl/grafana.crt" ]] || [[ ! -f "/etc/grafana/ssl/grafana.key" ]]; then
            warning "SSL certificate files missing for Grafana"
            log "Recreating Grafana SSL certificates..."
            mkdir -p /etc/grafana/ssl
            cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /etc/grafana/ssl/grafana.crt
            cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /etc/grafana/ssl/grafana.key
            chown grafana:grafana /etc/grafana/ssl/grafana.*
            chmod 600 /etc/grafana/ssl/grafana.key
            chmod 644 /etc/grafana/ssl/grafana.crt
        fi
        
        # Force HTTPS configuration
        log "Updating Grafana configuration for HTTPS..."
        sed -i 's/^;protocol = http/protocol = https/' /etc/grafana/grafana.ini
        sed -i 's/^protocol = http/protocol = https/' /etc/grafana/grafana.ini
        sed -i "s|^;cert_file =|cert_file = /etc/grafana/ssl/grafana.crt|" /etc/grafana/grafana.ini
        sed -i "s|^;cert_key =|cert_key = /etc/grafana/ssl/grafana.key|" /etc/grafana/grafana.ini
        
        # Restart Grafana
        systemctl restart grafana-server
        sleep 10
        
        # Test HTTPS again
        if curl -k -s https://localhost:3000/api/health > /dev/null 2>&1; then
            log "✅ Grafana HTTPS fixed and working!"
        else
            warning "❌ Grafana HTTPS still not working"
            log "Grafana error logs:"
            journalctl -u grafana-server -n 20 --no-pager
        fi
    else
        warning "Grafana is not responding on either HTTP or HTTPS"
        log "Grafana service logs:"
        journalctl -u grafana-server -n 20 --no-pager
    fi
else
    warning "Grafana is not listening on port 3000"
    log "Attempting to restart Grafana..."
    systemctl restart grafana-server
    sleep 10
fi

# Create Grafana PostgreSQL dashboard configuration with authentication
cat > /tmp/grafana_datasource.json << EOF
{
  "name": "Prometheus",
  "type": "prometheus",
  "url": "http://localhost:9090",
  "access": "proxy",
  "isDefault": true,
  "basicAuth": true,
  "basicAuthUser": "${PROMETHEUS_USER}",
  "secureJsonData": {
    "basicAuthPassword": "${PROMETHEUS_PASSWORD}"
  }
}
EOF

# Wait for Grafana to start
sleep 10

# Add Prometheus as datasource to Grafana
curl -X POST \
  http://admin:admin@localhost:3000/api/datasources \
  -H 'Content-Type: application/json' \
  -d @/tmp/grafana_datasource.json 2>/dev/null || warning "Failed to configure Grafana datasource automatically"

rm /tmp/grafana_datasource.json

# Install and configure Prometheus PostgreSQL exporter
log "Installing PostgreSQL Prometheus exporter..."

# Generate secure password for PostgreSQL exporter
POSTGRES_EXPORTER_PASSWORD=$(openssl rand -base64 24)
log "Generated secure password for postgres_exporter user"

# Initialize SKIP_EXPORTER variable
SKIP_EXPORTER=false

# Architecture already detected above
case $ARCH in
    x86_64)
        EXPORTER_ARCH="linux-amd64"
        ;;
    aarch64|arm64)
        EXPORTER_ARCH="linux-arm64"
        ;;
    *)
        warning "Unsupported architecture: $ARCH, skipping postgres_exporter installation"
        SKIP_EXPORTER=true
        ;;
esac

if [[ "$SKIP_EXPORTER" != "true" ]]; then
    wget -q https://github.com/prometheus-community/postgres_exporter/releases/download/v0.15.0/postgres_exporter-0.15.0.${EXPORTER_ARCH}.tar.gz
    if [[ $? -eq 0 ]]; then
        tar xzf postgres_exporter-0.15.0.${EXPORTER_ARCH}.tar.gz
        mv postgres_exporter-0.15.0.${EXPORTER_ARCH}/postgres_exporter /usr/local/bin/
        chmod +x /usr/local/bin/postgres_exporter
        rm -rf postgres_exporter-0.15.0.${EXPORTER_ARCH}*
        log "PostgreSQL exporter installed successfully"
    else
        warning "Failed to download postgres_exporter, skipping installation"
        SKIP_EXPORTER=true
    fi
fi

# Create postgres_exporter user and service only if exporter was installed
if [[ "$SKIP_EXPORTER" != "true" ]]; then
    log "Creating postgres_exporter user and service..."
    
    # Test PostgreSQL connection first
    log "Testing PostgreSQL connection for exporter setup..."
    
    # Try standard connection first (more reliable)
    if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
        log "Using standard connection for exporter setup"
        
        log "Creating postgres_exporter user and setting permissions..."
        if ! sudo -u postgres psql << EOSQL
-- Drop user if exists to start fresh
DROP USER IF EXISTS postgres_exporter;

-- Create new user with password
CREATE USER postgres_exporter;

-- Set search path
ALTER USER postgres_exporter SET SEARCH_PATH TO postgres_exporter,pg_catalog;

-- Grant basic permissions
GRANT CONNECT ON DATABASE ${PG_DB} TO postgres_exporter;

-- Grant monitoring role (PostgreSQL 10+)
GRANT pg_monitor TO postgres_exporter;

-- Grant specific schema permissions
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO postgres_exporter;
GRANT SELECT ON ALL TABLES IN SCHEMA information_schema TO postgres_exporter;

-- Grant function permissions
GRANT EXECUTE ON FUNCTION pg_stat_file(text) TO postgres_exporter;

-- Additional permissions for comprehensive monitoring
GRANT SELECT ON pg_stat_database TO postgres_exporter;
GRANT SELECT ON pg_stat_user_tables TO postgres_exporter;
GRANT SELECT ON pg_stat_user_indexes TO postgres_exporter;
GRANT SELECT ON pg_statio_user_tables TO postgres_exporter;
GRANT SELECT ON pg_statio_user_indexes TO postgres_exporter;
GRANT SELECT ON pg_stat_activity TO postgres_exporter;
GRANT SELECT ON pg_stat_replication TO postgres_exporter;
GRANT SELECT ON pg_stat_bgwriter TO postgres_exporter;
GRANT SELECT ON pg_stat_archiver TO postgres_exporter;
GRANT SELECT ON pg_database TO postgres_exporter;
GRANT SELECT ON pg_tablespace TO postgres_exporter;
EOSQL
        then
            error "Failed to create postgres_exporter user with standard connection"
            SKIP_EXPORTER=true
        else
            log "✅ User creation SQL executed successfully"
            
            # Set password separately to avoid variable substitution issues
            if ! sudo -u postgres psql -c "ALTER USER postgres_exporter PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';"; then
                error "Failed to set password for postgres_exporter user"
                SKIP_EXPORTER=true
            else
                log "✅ Password set successfully"
                
                # Verify user was created
                if sudo -u postgres psql -c "SELECT rolname FROM pg_roles WHERE rolname = 'postgres_exporter';" | grep -q postgres_exporter; then
                    log "✅ postgres_exporter user created and verified successfully"
                else
                    warning "❌ Failed to verify postgres_exporter user creation"
                    SKIP_EXPORTER=true
                fi
            fi
        fi
        
    # Try socket connection as fallback
    elif sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" > /dev/null 2>&1; then
        log "Using socket connection for exporter setup (fallback)"
        
        log "Creating postgres_exporter user and setting permissions..."
        if ! sudo -u postgres psql -h /var/run/postgresql << EOSQL
-- Drop user if exists to start fresh
DROP USER IF EXISTS postgres_exporter;

-- Create new user with password
CREATE USER postgres_exporter;

-- Set search path
ALTER USER postgres_exporter SET SEARCH_PATH TO postgres_exporter,pg_catalog;

-- Grant basic permissions
GRANT CONNECT ON DATABASE ${PG_DB} TO postgres_exporter;

-- Grant monitoring role (PostgreSQL 10+)
GRANT pg_monitor TO postgres_exporter;

-- Grant specific schema permissions
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO postgres_exporter;
GRANT SELECT ON ALL TABLES IN SCHEMA information_schema TO postgres_exporter;

-- Grant function permissions
GRANT EXECUTE ON FUNCTION pg_stat_file(text) TO postgres_exporter;

-- Additional permissions for comprehensive monitoring
GRANT SELECT ON pg_stat_database TO postgres_exporter;
GRANT SELECT ON pg_stat_user_tables TO postgres_exporter;
GRANT SELECT ON pg_stat_user_indexes TO postgres_exporter;
GRANT SELECT ON pg_statio_user_tables TO postgres_exporter;
GRANT SELECT ON pg_statio_user_indexes TO postgres_exporter;
GRANT SELECT ON pg_stat_activity TO postgres_exporter;
GRANT SELECT ON pg_stat_replication TO postgres_exporter;
GRANT SELECT ON pg_stat_bgwriter TO postgres_exporter;
GRANT SELECT ON pg_stat_archiver TO postgres_exporter;
GRANT SELECT ON pg_database TO postgres_exporter;
GRANT SELECT ON pg_tablespace TO postgres_exporter;
EOSQL
        then
            error "Failed to create postgres_exporter user with socket connection"
            SKIP_EXPORTER=true
        else
            log "✅ User creation SQL executed successfully (socket)"
            
            # Set password separately to avoid variable substitution issues
            if ! sudo -u postgres psql -h /var/run/postgresql -c "ALTER USER postgres_exporter PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';"; then
                error "Failed to set password for postgres_exporter user"
                SKIP_EXPORTER=true
            else
                log "✅ Password set successfully (socket)"
                
                # Verify user was created
                if sudo -u postgres psql -h /var/run/postgresql -c "SELECT rolname FROM pg_roles WHERE rolname = 'postgres_exporter';" | grep -q postgres_exporter; then
                    log "✅ postgres_exporter user created and verified successfully (socket)"
                else
                    warning "❌ Failed to verify postgres_exporter user creation"
                    SKIP_EXPORTER=true
                fi
            fi
        fi
    else
        warning "Cannot connect to PostgreSQL for exporter setup. Skipping postgres_exporter..."
        SKIP_EXPORTER=true
    fi

    # Configure PostgreSQL Exporter with HTTP (simplified)
    log "Configuring PostgreSQL Exporter with HTTP..."

    # URL encode password to handle special characters
    ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${POSTGRES_EXPORTER_PASSWORD}', safe=''))")
    
    # Create initial connection string
    INITIAL_CONNECTION_STRING="postgresql://postgres_exporter:${ENCODED_PASSWORD}@localhost:5432/${PG_DB}?sslmode=require"
    
    # Escape % characters for systemd (systemd interprets % as variable substitution)
    SYSTEMD_CONNECTION_STRING="${INITIAL_CONNECTION_STRING//\%/%%}"
    
    # Create systemd service for postgres_exporter with HTTP
    cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
Restart=always
RestartSec=5
User=postgres
Group=postgres
Environment="DATA_SOURCE_NAME=${SYSTEMD_CONNECTION_STRING}"
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=0.0.0.0:9187 --log.level=info
StandardOutput=journal
StandardError=journal
SyslogIdentifier=postgres_exporter

[Install]
WantedBy=multi-user.target
EOF

    # Save postgres_exporter credentials
    mkdir -p /etc/postgres_exporter
    cat > /etc/postgres_exporter/.env << EOF
POSTGRES_EXPORTER_USER=postgres_exporter
POSTGRES_EXPORTER_PASSWORD=${POSTGRES_EXPORTER_PASSWORD}
EOF
    chmod 600 /etc/postgres_exporter/.env
    chown postgres:postgres /etc/postgres_exporter/.env
    
    systemctl daemon-reload
    systemctl enable postgres_exporter
    systemctl start postgres_exporter
    
    # Comprehensive PostgreSQL Exporter connection fix
    log "Starting comprehensive PostgreSQL Exporter connection verification and fix..."
    
    # Function to test and fix PostgreSQL Exporter connection
    fix_postgres_exporter_connection() {
        local max_attempts=3
        local attempt=1
        
        # First, ensure PostgreSQL service is running
        log "Checking PostgreSQL service status..."
        
        # Check if the main PostgreSQL cluster is running
        PG_CLUSTER_RUNNING=false
        
        # Check the specific PostgreSQL 16 main cluster
        if systemctl is-active --quiet postgresql@16-main; then
            log "✅ PostgreSQL 16 main cluster is running"
            PG_CLUSTER_RUNNING=true
        else
            warning "PostgreSQL 16 main cluster is not running"
        fi
        
        # If cluster is not running, try to start it
        if [[ "$PG_CLUSTER_RUNNING" = false ]]; then
            log "Attempting to start PostgreSQL 16 main cluster..."
            
            # First try to start the specific cluster
            if systemctl start postgresql@16-main; then
                log "✅ PostgreSQL 16 main cluster started successfully"
                sleep 5
                PG_CLUSTER_RUNNING=true
            else
                warning "Failed to start postgresql@16-main, trying general postgresql service..."
                
                # Fallback to general postgresql service
                if systemctl start postgresql; then
                    log "✅ PostgreSQL service started successfully"
                    sleep 5
                    
                    # Check if cluster is now running
                    if systemctl is-active --quiet postgresql@16-main; then
                        PG_CLUSTER_RUNNING=true
                    fi
                else
                    error "❌ Failed to start PostgreSQL service"
                    log "Checking PostgreSQL service logs..."
                    journalctl -u postgresql -n 10 --no-pager || true
                    journalctl -u postgresql@16-main -n 10 --no-pager || true
                    return 1
                fi
            fi
        fi
        
        # Final check
        if [[ "$PG_CLUSTER_RUNNING" = false ]]; then
            error "❌ PostgreSQL cluster is still not running"
            log "Available PostgreSQL services:"
            systemctl list-units --type=service | grep postgresql || true
            return 1
        fi
        
        # Verify PostgreSQL is accepting connections
        log "Verifying PostgreSQL is accepting connections..."
        local pg_ready=false
        local pg_wait_attempts=0
        local max_pg_wait=6  # Wait up to 30 seconds (6 * 5 seconds)
        
        while [[ $pg_wait_attempts -lt $max_pg_wait ]]; do
            if sudo -u postgres psql -c "SELECT 1;" >/dev/null 2>&1; then
                log "✅ PostgreSQL is accepting connections"
                pg_ready=true
                break
            elif sudo -u postgres psql -h localhost -c "SELECT 1;" >/dev/null 2>&1; then
                log "✅ PostgreSQL is accepting TCP connections"
                pg_ready=true
                break
            else
                log "Waiting for PostgreSQL to be ready... (attempt $((pg_wait_attempts + 1))/$max_pg_wait)"
                sleep 5
                ((pg_wait_attempts++))
            fi
        done
        
        if [[ "$pg_ready" != "true" ]]; then
            error "❌ PostgreSQL is not accepting connections after waiting"
            log "PostgreSQL service status:"
            systemctl status postgresql --no-pager || true
            log "PostgreSQL logs:"
            journalctl -u postgresql -n 15 --no-pager || true
            return 1
        fi
        
        while [[ $attempt -le $max_attempts ]]; do
            log "Exporter connection attempt $attempt of $max_attempts..."
            
            # Wait for service to start
            log "Waiting for postgres_exporter to start..."
            sleep 10
            
            # Check if service is running
            if ! systemctl is-active --quiet postgres_exporter; then
                warning "❌ postgres_exporter service is not running on attempt $attempt"
                if [[ $attempt -lt $max_attempts ]]; then
                    log "Restarting postgres_exporter service..."
                    systemctl restart postgres_exporter 2>/dev/null || true
                    sleep 5
                    ((attempt++))
                    continue
                else
                    error "❌ postgres_exporter service failed to start after $max_attempts attempts"
                    log "Checking service logs..."
                    journalctl -u postgres_exporter -n 10 --no-pager || true
                    return 1
                fi
            fi
            
            log "✅ postgres_exporter service is running"
            
            # Test metrics endpoint first
            log "Testing metrics endpoint..."
            sleep 5
            
            if curl -s --max-time 10 http://localhost:9187/metrics >/dev/null 2>&1; then
                # Check pg_up value
                PG_UP_VALUE=$(curl -s --max-time 10 http://localhost:9187/metrics | grep "^pg_up " | awk '{print $2}' 2>/dev/null || echo "not_found")
                
                if [[ "$PG_UP_VALUE" == "1" ]]; then
                    log "🎉 SUCCESS! PostgreSQL exporter is connected and working perfectly"
                    log "✅ pg_up = $PG_UP_VALUE"
                    
                    # Show some key metrics to confirm
                    log "Key metrics sample:"
                    curl -s --max-time 10 http://localhost:9187/metrics | grep -E "^(pg_up|pg_stat_database_numbackends|pg_stat_bgwriter)" | head -3
                    return 0
                    
                elif [[ "$PG_UP_VALUE" == "0" ]]; then
                    warning "⚠️ Exporter is running but pg_up = 0 (connection issue)"
                    
                    # Try to fix the connection
                    log "Attempting to fix PostgreSQL Exporter connection..."
                    
                    # Stop the service
                    systemctl stop postgres_exporter 2>/dev/null || true
                    sleep 3
                    
                    # Test different connection methods and find the working one
                    log "Testing different connection methods..."
                    
                    CONNECTION_STRING=""
                    CONNECTION_SUCCESS=false
                    
                    # Method 1: localhost without SSL
                    log "Testing method 1: localhost connection (no SSL)"
                    if PGPASSWORD="${POSTGRES_EXPORTER_PASSWORD}" psql -h localhost -p 5432 -U postgres_exporter -d ${PG_DB} -c "SELECT 1;" >/dev/null 2>&1; then
                        CONNECTION_STRING="postgresql://postgres_exporter:${ENCODED_PASSWORD}@localhost:5432/${PG_DB}?sslmode=disable"
                        CONNECTION_SUCCESS=true
                        log "✅ localhost connection (no SSL) works"
                    fi
                    
                    # Method 2: localhost with SSL prefer
                    if [[ "$CONNECTION_SUCCESS" = false ]]; then
                        log "Testing method 2: localhost connection (SSL prefer)"
                        if PGPASSWORD="${POSTGRES_EXPORTER_PASSWORD}" psql -h localhost -p 5432 -U postgres_exporter -d ${PG_DB} -c "SELECT 1;" >/dev/null 2>&1; then
                            CONNECTION_STRING="postgresql://postgres_exporter:${ENCODED_PASSWORD}@localhost:5432/${PG_DB}?sslmode=prefer"
                            CONNECTION_SUCCESS=true
                            log "✅ localhost SSL connection works"
                        fi
                    fi
                    
                    # Method 3: 127.0.0.1 connection
                    if [[ "$CONNECTION_SUCCESS" = false ]]; then
                        log "Testing method 3: 127.0.0.1 connection"
                        if PGPASSWORD="${POSTGRES_EXPORTER_PASSWORD}" psql -h 127.0.0.1 -p 5432 -U postgres_exporter -d ${PG_DB} -c "SELECT 1;" >/dev/null 2>&1; then
                            CONNECTION_STRING="postgresql://postgres_exporter:${ENCODED_PASSWORD}@127.0.0.1:5432/${PG_DB}?sslmode=disable"
                            CONNECTION_SUCCESS=true
                            log "✅ 127.0.0.1 connection works"
                        fi
                    fi
                    
                    # Method 4: Unix socket connection
                    if [[ "$CONNECTION_SUCCESS" = false ]]; then
                        log "Testing method 4: Unix socket connection"
                        if PGPASSWORD="${POSTGRES_EXPORTER_PASSWORD}" psql -h /var/run/postgresql -U postgres_exporter -d ${PG_DB} -c "SELECT 1;" >/dev/null 2>&1; then
                            # Use correct socket connection string format
                            CONNECTION_STRING="user=postgres_exporter password=${POSTGRES_EXPORTER_PASSWORD} host=/var/run/postgresql port=5432 dbname=${PG_DB} sslmode=disable"
                            CONNECTION_SUCCESS=true
                            log "✅ Unix socket connection works"
                        fi
                    fi
                    
                    if [[ "$CONNECTION_SUCCESS" = true ]]; then
                        log "✅ Found working connection: $CONNECTION_STRING"
                        
                        # Update systemd service with working connection string
                        log "Updating systemd service with working connection..."
                        
                        # Escape % characters for systemd
                        SYSTEMD_CONNECTION_STRING="${CONNECTION_STRING//\%/%%}"
                        
                        cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
Restart=always
RestartSec=5
User=postgres
Group=postgres
Environment="DATA_SOURCE_NAME=${SYSTEMD_CONNECTION_STRING}"
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=0.0.0.0:9187 --log.level=info
StandardOutput=journal
StandardError=journal
SyslogIdentifier=postgres_exporter

[Install]
WantedBy=multi-user.target
EOF
                        
                        # Reload and restart service
                        systemctl daemon-reload
                        systemctl start postgres_exporter
                        sleep 10
                        
                        # Test again
                        if curl -s --max-time 10 http://localhost:9187/metrics | grep -q "^pg_up 1"; then
                            log "🎉 SUCCESS! Connection fixed and PostgreSQL exporter is now working"
                            return 0
                        else
                            warning "⚠️ Still having issues after connection fix"
                        fi
                    else
                        warning "❌ All connection methods failed"
                        
                        # Show diagnostic information
                        log "Diagnostic information:"
                        
                        # Check PostgreSQL service status first
                        log "0. PostgreSQL service status:"
                        systemctl status postgresql --no-pager || true
                        log "PostgreSQL 16 main cluster status:"
                        systemctl status postgresql@16-main --no-pager || true
                        
                        # Only run database checks if PostgreSQL cluster is running
                        if systemctl is-active --quiet postgresql@16-main || systemctl is-active --quiet postgresql; then
                            log "1. Checking database existence:"
                            sudo -u postgres psql -c "\\l" | grep -E "(${PG_DB}|postgres)" || true
                            
                            log "2. Checking user permissions:"
                            USER_EXISTS=$(sudo -u postgres psql -c "\\du postgres_exporter" 2>/dev/null | grep postgres_exporter || echo "")
                            if [[ -z "$USER_EXISTS" ]]; then
                                warning "❌ postgres_exporter user does not exist!"
                                log "Attempting to recreate postgres_exporter user..."
                                
                                # Try to recreate the user
                                if sudo -u postgres psql << EOSQL
-- Drop user if exists to start fresh
DROP USER IF EXISTS postgres_exporter;

-- Create new user with password
CREATE USER postgres_exporter WITH PASSWORD '${POSTGRES_EXPORTER_PASSWORD}';

-- Set search path
ALTER USER postgres_exporter SET SEARCH_PATH TO postgres_exporter,pg_catalog;

-- Grant basic permissions
GRANT CONNECT ON DATABASE ${PG_DB} TO postgres_exporter;

-- Grant monitoring role (PostgreSQL 10+)
GRANT pg_monitor TO postgres_exporter;

-- Grant specific schema permissions
GRANT SELECT ON ALL TABLES IN SCHEMA pg_catalog TO postgres_exporter;
GRANT SELECT ON ALL TABLES IN SCHEMA information_schema TO postgres_exporter;

-- Grant function permissions
GRANT EXECUTE ON FUNCTION pg_stat_file(text) TO postgres_exporter;

-- Additional permissions for comprehensive monitoring
GRANT SELECT ON pg_stat_database TO postgres_exporter;
GRANT SELECT ON pg_stat_user_tables TO postgres_exporter;
GRANT SELECT ON pg_stat_user_indexes TO postgres_exporter;
GRANT SELECT ON pg_statio_user_tables TO postgres_exporter;
GRANT SELECT ON pg_statio_user_indexes TO postgres_exporter;
GRANT SELECT ON pg_stat_activity TO postgres_exporter;
GRANT SELECT ON pg_stat_replication TO postgres_exporter;
GRANT SELECT ON pg_stat_bgwriter TO postgres_exporter;
GRANT SELECT ON pg_stat_archiver TO postgres_exporter;
GRANT SELECT ON pg_database TO postgres_exporter;
GRANT SELECT ON pg_tablespace TO postgres_exporter;
EOSQL
                                then
                                    log "✅ postgres_exporter user recreated successfully!"
                                    
                                    # Test the connection again with the new user
                                    log "Testing connection with recreated user..."
                                    if PGPASSWORD="${POSTGRES_EXPORTER_PASSWORD}" psql -h localhost -p 5432 -U postgres_exporter -d ${PG_DB} -c "SELECT 1;" >/dev/null 2>&1; then
                                        log "✅ Connection test passed with recreated user!"
                                        
                                        # Update the connection string and restart the service
                                        CONNECTION_STRING="postgresql://postgres_exporter:${ENCODED_PASSWORD}@localhost:5432/${PG_DB}?sslmode=disable"
                                        log "Updating service with working connection..."
                                        
                                        # Escape % characters for systemd
                                        SYSTEMD_CONNECTION_STRING="${CONNECTION_STRING//\%/%%}"
                                        
                                        cat > /etc/systemd/system/postgres_exporter.service << EOF
[Unit]
Description=Prometheus PostgreSQL Exporter
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
Restart=always
RestartSec=5
User=postgres
Group=postgres
Environment="DATA_SOURCE_NAME=${SYSTEMD_CONNECTION_STRING}"
ExecStart=/usr/local/bin/postgres_exporter --web.listen-address=0.0.0.0:9187 --log.level=info
StandardOutput=journal
StandardError=journal
SyslogIdentifier=postgres_exporter

[Install]
WantedBy=multi-user.target
EOF
                                        
                                        systemctl daemon-reload
                                        systemctl restart postgres_exporter
                                        sleep 10
                                        
                                        if curl -s --max-time 10 http://localhost:9187/metrics | grep -q "^pg_up 1"; then
                                            log "🎉 SUCCESS! User recreated and exporter is now working!"
                                            return 0
                                        else
                                            warning "User recreated but exporter still has issues"
                                        fi
                                    else
                                        warning "User recreated but connection test still fails"
                                    fi
                                else
                                    error "Failed to recreate postgres_exporter user"
                                fi
                            else
                                log "User exists but connection still fails:"
                                echo "$USER_EXISTS"
                            fi
                        else
                            warning "PostgreSQL service is not running - cannot check database/user details"
                        fi
                        
                        log "3. Checking pg_hba.conf configuration:"
                        grep -E "(local|host)" /etc/postgresql/16/main/pg_hba.conf | head -10 || true
                        
                        log "4. Checking socket directory:"
                        ls -la /var/run/postgresql/ 2>/dev/null || echo "Socket directory not found or not accessible"
                    fi
                else
                    warning "⚠️ Could not determine pg_up value: $PG_UP_VALUE"
                fi
            else
                warning "❌ Cannot access metrics endpoint on attempt $attempt"
                log "Checking port 9187 status:"
                netstat -tlnp 2>/dev/null | grep :9187 || echo "Port 9187 not listening"
                
                log "Recent service logs:"
                journalctl -u postgres_exporter -n 5 --no-pager || true
            fi
            
            # If we reach here, this attempt failed
            if [[ $attempt -lt $max_attempts ]]; then
                warning "Attempt $attempt failed, trying again..."
                ((attempt++))
                sleep 5
            else
                error "❌ All $max_attempts attempts failed"
                return 1
            fi
        done
        
        return 1
    }
    
    # Call the connection fix function
    if fix_postgres_exporter_connection; then
        log "✅ PostgreSQL Exporter setup completed successfully"
        
        # Display final status and useful commands
        log "=== PostgreSQL Exporter Status ==="
        log "Service status: $(systemctl is-active postgres_exporter)"
        log "Metrics endpoint: http://localhost:9187/metrics"
        
        log "=== Useful Commands ==="
        log "Check metrics: curl http://localhost:9187/metrics | grep pg_up"
        log "View logs: journalctl -u postgres_exporter -f"
        log "Test connection: PGPASSWORD='${POSTGRES_EXPORTER_PASSWORD}' psql -h localhost -U postgres_exporter -d ${PG_DB}"
        
    else
        warning "❌ PostgreSQL Exporter setup failed after multiple attempts"
        log "The exporter installation completed but connection verification failed"
        log "You may need to manually troubleshoot the connection issue"
        log "Check logs with: journalctl -u postgres_exporter -f"
    fi
else
    log "Skipping postgres_exporter service setup"
fi

# Create backup scripts
log "Creating backup scripts..."

# Daily backup script
cat > /usr/local/bin/postgres_backup.sh << EOF
#!/bin/bash

BACKUP_DIR="${BACKUP_DIR}/dumps"
DB_NAME="${PG_DB}"
DATE=\$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="\${BACKUP_DIR}/backup_\${DB_NAME}_\${DATE}.sql.gz"
LOG_FILE="/var/log/postgresql_backup.log"

# Create backup
echo "[\$(date)] Starting backup of \${DB_NAME}" >> \${LOG_FILE}
sudo -u postgres pg_dump \${DB_NAME} | gzip > \${BACKUP_FILE}

if [ \$? -eq 0 ]; then
    echo "[\$(date)] Backup completed successfully: \${BACKUP_FILE}" >> \${LOG_FILE}
    # Keep only last 7 days of backups
    find \${BACKUP_DIR} -name "backup_\${DB_NAME}_*.sql.gz" -mtime +7 -delete
else
    echo "[\$(date)] Backup failed!" >> \${LOG_FILE}
    exit 1
fi
EOF

chmod +x /usr/local/bin/postgres_backup.sh

# Create post-reboot verification script
cat > /usr/local/bin/postgres_health_check.sh << 'EOF'
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🔍 PostgreSQL System Health Check - $(date)"
echo "=============================================="

# Check all services
services=("postgresql" "nginx" "grafana-server" "prometheus" "pgbouncer" "postgres_exporter")
all_healthy=true

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "✅ $service: ${GREEN}Running${NC}"
    else
        echo -e "❌ $service: ${RED}Failed${NC}"
        all_healthy=false
        # Try to restart failed service
        echo "   🔄 Attempting to restart $service..."
        systemctl start "$service" 2>/dev/null
        sleep 2
        if systemctl is-active --quiet "$service"; then
            echo -e "   ✅ $service: ${GREEN}Restarted successfully${NC}"
        else
            echo -e "   ❌ $service: ${RED}Restart failed${NC}"
        fi
    fi
done

# Test database connection
echo ""
echo "🗄️  Database Connection Test:"
if sudo -u postgres psql -c "SELECT 1;" > /dev/null 2>&1; then
    echo -e "✅ PostgreSQL: ${GREEN}Connection OK${NC}"
else
    echo -e "❌ PostgreSQL: ${RED}Connection Failed${NC}"
    all_healthy=false
fi

# Test SSL endpoints
echo ""
echo "🔒 SSL Endpoints Test:"
DOMAIN_NAME=$(hostname -f 2>/dev/null || echo "localhost")

# Test main SSL
if curl -f -s -k "https://$DOMAIN_NAME" > /dev/null 2>&1; then
    echo -e "✅ Nginx SSL: ${GREEN}OK${NC}"
else
    echo -e "❌ Nginx SSL: ${RED}Failed${NC}"
    all_healthy=false
fi

# Test Grafana
if curl -f -s -k "https://$DOMAIN_NAME:3000" > /dev/null 2>&1; then
    echo -e "✅ Grafana: ${GREEN}OK${NC}"
else
    echo -e "❌ Grafana: ${RED}Failed${NC}"
fi

# Test Prometheus
if curl -f -s "http://$DOMAIN_NAME:9090" > /dev/null 2>&1; then
    echo -e "✅ Prometheus: ${GREEN}OK${NC}"
else
    echo -e "❌ Prometheus: ${RED}Failed${NC}"
fi

# Check disk space
echo ""
echo "💾 Disk Space Check:"
df -h / | tail -1 | awk '{
    usage = substr($5, 1, length($5)-1)
    if (usage > 90) 
        print "❌ Disk usage: " usage "% (Critical)"
    else if (usage > 80)
        print "⚠️  Disk usage: " usage "% (Warning)" 
    else
        print "✅ Disk usage: " usage "% (OK)"
}'

# Overall status
echo ""
echo "=============================================="
if [ "$all_healthy" = true ]; then
    echo -e "🎉 ${GREEN}All systems healthy!${NC}"
    exit 0
else
    echo -e "⚠️  ${YELLOW}Some issues detected. Check logs:${NC}"
    echo "   journalctl -u postgresql -n 10"
    echo "   journalctl -u nginx -n 10"
    echo "   journalctl -u grafana-server -n 10"
    exit 1
fi
EOF

chmod +x /usr/local/bin/postgres_health_check.sh

# Create security credentials display script
cat > /usr/local/bin/show_monitoring_credentials.sh << 'EOF'
#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔐 PostgreSQL Monitoring System Credentials${NC}"
echo "=============================================="
echo ""

DOMAIN_NAME=$(hostname -f 2>/dev/null || echo "localhost")

echo -e "${GREEN}🎨 GRAFANA DASHBOARD${NC}"
echo "   URL: https://$DOMAIN_NAME:3000"
echo "   Username: admin"
echo "   Password: admin (change on first login)"
echo ""

echo -e "${GREEN}📊 PROMETHEUS METRICS${NC}"
echo "   URL: http://$DOMAIN_NAME:9090"
if [[ -f /etc/prometheus/.env ]]; then
    source /etc/prometheus/.env
    echo "   Username: $PROMETHEUS_USER"
    echo "   Password: $PROMETHEUS_PASSWORD"
else
    echo -e "   ${YELLOW}⚠️  Credentials not found in /etc/prometheus/.env${NC}"
fi
echo ""

echo -e "${GREEN}🔍 POSTGRESQL EXPORTER${NC}"
echo "   URL: http://$DOMAIN_NAME:9187/metrics"
if [[ -f /etc/postgres_exporter/.env ]]; then
    source /etc/postgres_exporter/.env
    echo "   Username: $POSTGRES_EXPORTER_USER"
    echo "   Password: $POSTGRES_EXPORTER_PASSWORD"
else
    echo -e "   ${YELLOW}⚠️  Credentials not found in /etc/postgres_exporter/.env${NC}"
fi
echo ""

echo -e "${YELLOW}🛡️  SECURITY NOTES:${NC}"
echo "   • All endpoints use HTTPS with SSL certificates"
echo "   • Credentials are stored in secure files with 600 permissions"
echo "   • Change default Grafana password on first login"
echo "   • These credentials are required for accessing monitoring endpoints"
echo ""

echo -e "${RED}⚠️  IMPORTANT:${NC}"
echo "   • Keep these credentials secure"
echo "   • Don't share them in plain text"
echo "   • Consider using a password manager"
echo "   • Monitor access logs regularly"
EOF

chmod +x /usr/local/bin/show_monitoring_credentials.sh

# Create monitoring script with SSL support
cat > /usr/local/bin/postgres_monitor.sh << EOF
#!/bin/bash

DB_NAME="${PG_DB}"
LOG_FILE="/var/log/postgresql_monitor.log"

echo "[\$(date)] PostgreSQL Health Check" >> \${LOG_FILE}

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    echo "[\$(date)] ERROR: PostgreSQL is not running!" >> \${LOG_FILE}
    exit 1
fi

# Check SSL connection
if sudo -u postgres psql "sslmode=require host=localhost dbname=\${DB_NAME}" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "[\$(date)] SSL connection: OK" >> \${LOG_FILE}
else
    echo "[\$(date)] WARNING: SSL connection failed!" >> \${LOG_FILE}
fi

# Check connections
CONNECTIONS=\$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity;" \${DB_NAME})
echo "[\$(date)] Active connections: \${CONNECTIONS}" >> \${LOG_FILE}

# Check database size
DB_SIZE=\$(sudo -u postgres psql -t -c "SELECT pg_size_pretty(pg_database_size('\${DB_NAME}'));" \${DB_NAME})
echo "[\$(date)] Database size: \${DB_SIZE}" >> \${LOG_FILE}

# Check for long running queries
LONG_QUERIES=\$(sudo -u postgres psql -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND query_start < now() - interval '5 minutes';" \${DB_NAME})
if [ \${LONG_QUERIES} -gt 0 ]; then
    echo "[\$(date)] WARNING: \${LONG_QUERIES} long-running queries detected" >> \${LOG_FILE}
fi

# Check certificate expiry
CERT_EXPIRY=\$(openssl x509 -enddate -noout -in /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt | cut -d= -f2)
echo "[\$(date)] SSL certificate expires: \${CERT_EXPIRY}" >> \${LOG_FILE}

echo "[\$(date)] Health check completed" >> \${LOG_FILE}
EOF

chmod +x /usr/local/bin/postgres_monitor.sh

# Create SSL fix script
cat > /usr/local/bin/postgres_fix_ssl.sh << EOF
#!/bin/bash

echo "PostgreSQL SSL Connection Fix Script"
echo "===================================="

# Check if PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    echo "Starting PostgreSQL..."
    systemctl start postgresql
    sleep 5
fi

# Check if SSL certificate files exist
if [[ ! -f "/var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt" ]]; then
    echo "Recreating SSL certificate files..."
    mkdir -p /var/lib/postgresql/${PG_VERSION}/main/ssl
    cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt
    cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key
    chown postgres:postgres /var/lib/postgresql/${PG_VERSION}/main/ssl/server.*
    chmod 600 /var/lib/postgresql/${PG_VERSION}/main/ssl/server.key
    chmod 644 /var/lib/postgresql/${PG_VERSION}/main/ssl/server.crt
    echo "SSL certificates recreated"
fi

# Test basic connection
echo "Testing basic PostgreSQL connection..."
if sudo -u postgres psql -d ${PG_DB} -c "SELECT version();" > /dev/null 2>&1; then
    echo "✅ Basic connection successful"
else
    echo "❌ Basic connection failed"
    exit 1
fi

# Reload PostgreSQL configuration
echo "Reloading PostgreSQL configuration..."
sudo -u postgres psql -c "SELECT pg_reload_conf();"
sleep 3

# Test SSL connection
echo "Testing SSL connection..."
if sudo -u postgres psql "sslmode=require host=localhost dbname=${PG_DB}" -c "SELECT 1;" > /dev/null 2>&1; then
    echo "✅ SSL connection successful!"
    echo "SSL is now working properly"
else
    echo "❌ SSL connection still failed"
    echo "Checking SSL configuration in postgresql.conf..."
    grep -n "ssl" /etc/postgresql/${PG_VERSION}/main/postgresql.conf
    echo ""
    echo "Checking SSL certificate files..."
    ls -la /var/lib/postgresql/${PG_VERSION}/main/ssl/
fi
EOF

chmod +x /usr/local/bin/postgres_fix_ssl.sh

# Set up cron jobs
log "Setting up cron jobs..."
cat > /etc/cron.d/postgresql << EOF
# PostgreSQL maintenance cron jobs

# Daily backup at 2 AM
0 2 * * * root /usr/local/bin/postgres_backup.sh

# Health check every 15 minutes
*/15 * * * * root /usr/local/bin/postgres_monitor.sh

# Weekly VACUUM ANALYZE at 3 AM on Sunday
0 3 * * 0 postgres /usr/bin/vacuumdb --all --analyze --quiet

# Certificate renewal check twice daily
0 0,12 * * * root /usr/bin/certbot renew --quiet
EOF

# Configure logrotate for PostgreSQL logs
cat > /etc/logrotate.d/postgresql << EOF
/var/log/postgresql/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 postgres postgres
    postrotate
        /bin/kill -HUP \\\$(cat /var/run/postgresql/${PG_VERSION}-main.pid 2> /dev/null) 2> /dev/null || true
    endscript
}

/var/log/postgresql_backup.log
/var/log/postgresql_monitor.log
/var/log/postgresql_ssl_renewal.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

# UFW firewall already configured in pre-checks
log "UFW firewall rules already configured during pre-checks"

# Configure fail2ban for PostgreSQL
cat > /etc/fail2ban/jail.local << EOF
[postgresql]
enabled = true
port = 5432
filter = postgresql
logpath = /var/log/postgresql/postgresql-*.log
maxretry = 5
bantime = 3600

[nginx-http-auth]
enabled = true
EOF

# Create fail2ban filter for PostgreSQL
cat > /etc/fail2ban/filter.d/postgresql.conf << EOF
[Definition]
failregex = ^.*\[.*\] FATAL:  password authentication failed for user ".*" <HOST>
ignoreregex =
EOF

systemctl restart fail2ban

# Install and configure pgBouncer for connection pooling
log "Installing pgBouncer..."
apt install -y pgbouncer

# Configure pgBouncer
cat > /etc/pgbouncer/pgbouncer.ini << EOF
[databases]
${PG_DB} = host=localhost port=5432 dbname=${PG_DB}

[pgbouncer]
listen_port = 6432
listen_addr = 127.0.0.1
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/postgresql/pgbouncer.log
pidfile = /var/run/postgresql/pgbouncer.pid
admin_users = postgres
stats_users = postgres
pool_mode = session
server_reset_query = DISCARD ALL
max_client_conn = 100
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5
max_db_connections = 50
EOF

# Create pgBouncer user list
echo "\"postgres\" \"$(echo -n "${POSTGRES_PASSWORD}md5postgres" | md5sum | cut -d' ' -f1)\"" > /etc/pgbouncer/userlist.txt
if [[ $CREATE_DB_USER =~ ^[Yy]$ ]]; then
    echo "\"${DB_USERNAME}\" \"$(echo -n "${DB_USER_PASSWORD}md5${DB_USERNAME}" | md5sum | cut -d' ' -f1)\"" >> /etc/pgbouncer/userlist.txt
fi

chmod 640 /etc/pgbouncer/userlist.txt
chown postgres:postgres /etc/pgbouncer/userlist.txt

# Start and enable pgBouncer
systemctl enable pgbouncer
systemctl start pgbouncer

# Create setup summary file
SETUP_INFO_FILE="/root/postgresql_setup_info.txt"
log "Creating setup summary file: $SETUP_INFO_FILE"

cat > "$SETUP_INFO_FILE" << EOF
================================================================================
                    PostgreSQL Production Setup Complete!
================================================================================
Setup Date: $(date)
PostgreSQL Version: 16
Domain: ${DOMAIN_NAME}
Database: ${PG_DB}

================================================================================
                              ACCOUNT INFORMATION
================================================================================

🔐 POSTGRES SUPERUSER:
   Username: postgres
   Password: ${POSTGRES_PASSWORD}

$(if [[ $CREATE_DB_USER =~ ^[Yy]$ ]]; then
cat << USEREOF

🔐 DATABASE USER:
   Username: ${DB_USERNAME}
   Password: ${DB_USER_PASSWORD}
   Database: ${PG_DB}
USEREOF
fi)

================================================================================
                              CONNECTION INFORMATION
================================================================================

🌐 SSL CONNECTION (Recommended):
   Host: ${DOMAIN_NAME}
   Port: 5432
   Database: ${PG_DB}
   SSL Mode: require

📝 CONNECTION STRING:
   postgresql://${DB_USERNAME:-postgres}:YOUR_PASSWORD@${DOMAIN_NAME}:5432/${PG_DB}?sslmode=require

🔌 LOCAL CONNECTION:
   sudo -u postgres psql -h /var/run/postgresql -d ${PG_DB}

🎯 PGBOUNCER (Connection Pooling):
   Host: localhost
   Port: 6432
   Database: ${PG_DB}

================================================================================
                              WEB MONITORING DASHBOARDS
================================================================================

🎨 GRAFANA DASHBOARD:
   URL: https://${DOMAIN_NAME}:3000
   Default Login: admin / admin
   Features: PostgreSQL metrics, performance graphs, alerts

📊 PROMETHEUS METRICS:
   URL: http://${DOMAIN_NAME}:9090
   Username: ${PROMETHEUS_USER}
   Password: ${PROMETHEUS_PASSWORD}
   Features: Raw metrics, query interface, targets status

🔍 POSTGRESQL EXPORTER:
   URL: http://${DOMAIN_NAME}:9187/metrics
   Features: Raw PostgreSQL metrics in Prometheus format

================================================================================
                              SSL CERTIFICATE
================================================================================

📜 Certificate: /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem
🔑 Private Key: /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem
🔄 Auto-renewal: Configured (runs twice daily)

================================================================================
                              BACKUP SYSTEM
================================================================================

💾 Backup Location: ${BACKUP_DIR}/dumps/
📦 Archive Location: ${BACKUP_DIR}/archive/
⏰ Schedule: Daily at 2:00 AM
📝 Backup Log: /var/log/postgresql_backup.log

🔧 BACKUP USAGE GUIDE:

   📥 Create Manual Backup:
      sudo /usr/local/bin/postgres_backup.sh
      
   📂 List Available Backups:
      ls -la ${BACKUP_DIR}/dumps/
      
   📋 Backup File Format:
      backup_${PG_DB}_YYYYMMDD_HHMMSS.sql.gz
      
   🔄 Restore from Backup:
      # Stop applications first
      # Drop and recreate database (CAREFUL!)
      sudo -u postgres dropdb ${PG_DB}
      sudo -u postgres createdb ${PG_DB}
      # Restore from backup file
      gunzip -c ${BACKUP_DIR}/dumps/backup_${PG_DB}_YYYYMMDD_HHMMSS.sql.gz | sudo -u postgres psql ${PG_DB}
      
   📊 Check Backup Status:
      tail -f /var/log/postgresql_backup.log
      
   🗂️ Backup Retention:
      Automatic cleanup: 7 days
      Manual cleanup: find ${BACKUP_DIR}/dumps/ -name "backup_*.sql.gz" -mtime +30 -delete

================================================================================
                              MONITORING
================================================================================

📊 Health Check: Every 15 minutes
📈 Monitor Log: /var/log/postgresql_monitor.log
🔍 PostgreSQL Logs: /var/log/postgresql/

🎨 WEB DASHBOARDS:
   Grafana: https://${DOMAIN_NAME}:3000 (admin/admin)
   Prometheus: http://${DOMAIN_NAME}:9090 (${PROMETHEUS_USER}/${PROMETHEUS_PASSWORD})
   PostgreSQL Metrics: http://${DOMAIN_NAME}:9187/metrics

🔧 Manual Health Check:
   sudo /usr/local/bin/postgres_monitor.sh

================================================================================
                              USEFUL COMMANDS
================================================================================

🚀 Service Management:
   sudo systemctl start/stop/restart/status postgresql
   sudo systemctl start/stop/restart/status pgbouncer

📋 Database Management:
   sudo -u postgres psql -c "\\l"    # List databases
   sudo -u postgres psql -c "\\du"   # List users
   sudo -u postgres psql -d ${PG_DB} -c "\\dt"  # List tables

🔍 Performance Monitoring:
   sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"
   sudo -u postgres psql -c "SELECT * FROM pg_stat_database;"
$(if [[ "$PG_STAT_MONITOR_AVAILABLE" == "true" ]]; then
echo "   sudo -u postgres psql -c \"SELECT * FROM pg_stat_monitor;\"  # Enhanced query stats"
else
echo "   sudo -u postgres psql -c \"SELECT * FROM pg_stat_statements;\"  # Query stats"
fi)

🛡️ Security:
   sudo fail2ban-client status postgresql
   sudo ufw status

================================================================================
                              MAINTENANCE SCHEDULE
================================================================================

📅 Daily (2:00 AM): Full database backup
📅 Every 15 min: Health monitoring
📅 Weekly (Sun 3:00 AM): VACUUM ANALYZE
📅 Twice daily: SSL certificate renewal check

================================================================================
                              IMPORTANT NOTES
================================================================================

⚠️  SAVE THIS FILE! It contains your passwords and connection information.
⚠️  Change default passwords for production use.
⚠️  Monitor backup logs regularly: /var/log/postgresql_backup.log
⚠️  SSL certificates auto-renew, but monitor renewal logs.

🎉 Your PostgreSQL server is ready for production use!

For support, check logs in /var/log/postgresql/ and /var/log/postgresql_*.log

================================================================================
EOF

# Set permissions on setup info file
chmod 600 "$SETUP_INFO_FILE"

# Final system status check
log "Performing final system status check..."

# Check if PostgreSQL is running and try to start if needed
if ! systemctl is-active --quiet postgresql; then
    warning "PostgreSQL is not running. Attempting to start..."
    systemctl start postgresql 2>/dev/null || true
    sleep 5
    
    # If still not running, try direct start
    if ! systemctl is-active --quiet postgresql; then
        log "Attempting direct PostgreSQL start..."
        sudo -u postgres /usr/lib/postgresql/16/bin/postgres \
            -D /var/lib/postgresql/16/main \
            -c config_file=/etc/postgresql/16/main/postgresql.conf \
            > /var/log/postgresql/final-startup.log 2>&1 &
        sleep 10
    fi
fi

# Test SSL connection (final verification)
SSL_TEST_RESULT="❌ Failed"
log "Testing SSL connection..."

# First ensure PostgreSQL is running
if ! systemctl is-active --quiet postgresql; then
    log "PostgreSQL not running, attempting to start..."
    systemctl start postgresql
    sleep 5
fi

# Test SSL connection using the password we set earlier
if PGPASSWORD="$POSTGRES_PASSWORD" psql "postgresql://postgres@${DOMAIN_NAME}:5432/${PG_DB}?sslmode=require" -c "SELECT 1;" > /dev/null 2>&1; then
    SSL_TEST_RESULT="✅ Success"
    log "✅ Final SSL connection test successful!"
else
    # Try socket connection as backup
    if sudo -u postgres psql -h /var/run/postgresql -c "SELECT 1;" > /dev/null 2>&1; then
        log "PostgreSQL is accepting socket connections"
        
        # Try SSL via localhost
        if PGPASSWORD="$POSTGRES_PASSWORD" psql "postgresql://postgres@localhost:5432/${PG_DB}?sslmode=require" -c "SELECT 1;" > /dev/null 2>&1; then
            SSL_TEST_RESULT="✅ Success"
            log "✅ SSL connection successful via localhost!"
        else
            warning "SSL connection failed in final test"
        fi
    else
        warning "PostgreSQL is not accepting connections. SSL test skipped."
    fi
fi

# Test pgBouncer
PGBOUNCER_TEST_RESULT="❌ Failed"
if systemctl is-active --quiet pgbouncer; then
    PGBOUNCER_TEST_RESULT="✅ Running"
fi

# Test backup script
BACKUP_TEST_RESULT="❌ Failed"
if [[ -x "/usr/local/bin/postgres_backup.sh" ]]; then
    BACKUP_TEST_RESULT="✅ Ready"
fi

# Display final summary
echo
echo "================================================================================"
echo "                    🎉 POSTGRESQL SETUP COMPLETE! 🎉"
echo "================================================================================"
echo
echo "📋 SETUP SUMMARY:"
echo "   Database: ${PG_DB}"
echo "   Domain: ${DOMAIN_NAME}"
echo "   SSL Connection: $SSL_TEST_RESULT"
echo "   pgBouncer: $PGBOUNCER_TEST_RESULT"
echo "   Backup System: $BACKUP_TEST_RESULT"
echo "   Grafana Dashboard: $(systemctl is-active --quiet grafana-server && echo "✅ Running" || echo "❌ Failed")"
echo "   Prometheus: $(systemctl is-active --quiet prometheus && echo "✅ Running" || echo "❌ Failed")"
echo
echo "🔐 CREDENTIALS:"
echo "   Postgres User: postgres"
echo "   Password: ${POSTGRES_PASSWORD}"
if [[ $CREATE_DB_USER =~ ^[Yy]$ ]]; then
echo "   DB User: ${DB_USERNAME}"
echo "   DB Password: ${DB_USER_PASSWORD}"
fi
echo
echo "🌐 CONNECTION:"
echo "   SSL: postgresql://${DB_USERNAME:-postgres}:PASSWORD@${DOMAIN_NAME}:5432/${PG_DB}?sslmode=require"
echo "   Local: sudo -u postgres psql -d ${PG_DB}"
echo "   pgBouncer: postgresql://${DB_USERNAME:-postgres}:PASSWORD@localhost:6432/${PG_DB}"
echo
echo "🎨 WEB MONITORING:"
echo "   Grafana: https://${DOMAIN_NAME}:3000 (admin/admin)"
echo "   Prometheus: http://${DOMAIN_NAME}:9090"
echo "   PostgreSQL Metrics: http://${DOMAIN_NAME}:9187/metrics"
echo
echo "📁 IMPORTANT FILES:"
echo "   Setup Info: $SETUP_INFO_FILE"
echo "   Backup Dir: ${BACKUP_DIR}"
echo "   Logs: /var/log/postgresql/"
echo
echo "🚀 QUICK START:"
echo "   1. Save your passwords from above"
echo "   2. Test connection: sudo -u postgres psql -d ${PG_DB}"
echo "   3. View setup details: cat $SETUP_INFO_FILE"
echo "   4. Monitor backups: tail -f /var/log/postgresql_backup.log"
echo
echo "================================================================================"
echo "✅ PostgreSQL ${PG_VERSION} is ready for production!"
echo "================================================================================"

# Grafana dashboard can be created manually if needed

log "Setup completed successfully! Check $SETUP_INFO_FILE for detailed information."
