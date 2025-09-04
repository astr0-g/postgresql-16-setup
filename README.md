# PostgreSQL 16 Production Setup 🚀

[![English](https://img.shields.io/badge/Language-English-blue)](README.md) [![中文](https://img.shields.io/badge/Language-中文-red)](README.zh.md) [![日本語](https://img.shields.io/badge/Language-日本語-green)](README.ja.md)

One-click PostgreSQL 16 production deployment with SSL-encrypted connections, Let's Encrypt certificates, Prometheus/Grafana monitoring stack, automated backup/restore system, and comprehensive enterprise-grade security features.

## 🚀 Quick Start

### One-Line Installation

```bash
# Download and run interactively
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgresql_production_setup.sh -o postgresql_setup.sh && chmod +x postgresql_setup.sh && sudo ./postgresql_setup.sh
```

Or clone and run locally:

```bash
git clone https://github.com/astr0-g/postgresql-16-setup.git
cd postgresql-16-setup
sudo ./postgresql_production_setup.sh
```

## ✨ Key Features

### 🔧 Core Features

- **PostgreSQL 16** Latest stable version
- **SSL/TLS Encryption** Automatic Let's Encrypt certificates
- **Production Configuration** Performance and security optimized
- **User Management** Automated database user creation
- **Security Hardening** UFW firewall and fail2ban protection

### 📊 Monitoring Stack

- **Prometheus** Metrics collection and storage
- **Grafana** Visualization dashboards (HTTPS)
- **PostgreSQL Exporter** Database metrics export
- **pgBadger** Log analysis tool
- **pg_stat_monitor** Enhanced performance monitoring

### 🔄 Backup & Recovery

- **Automated Backups** Daily scheduled backup tasks
- **Manual Backups** Single database and cluster-level backups
- **One-Click Recovery** Simplified data restoration
- **Log Rotation** Automated log management

### 🛡️ Security Features

- **SSL-Only Connections** All client connections encrypted
- **Auto Certificate Renewal** Let's Encrypt automatic updates
- **Access Control** IP and user-based permissions
- **Password Policies** Strong password generation and management

## 📋 System Requirements

- **Operating System**: Ubuntu 24.04 LTS
- **Privileges**: sudo/root access
- **Network**: Public IP and domain name (for SSL certificates)
- **Memory**: Minimum 2GB RAM (4GB+ recommended)
- **Storage**: Minimum 20GB available space

## 🔧 Installation Options

### Interactive Installation (Recommended)

```bash
sudo ./postgresql_production_setup.sh
```

The script will guide you through:

- Database name and password configuration
- Domain name and email (SSL certificates)
- Database user creation
- Monitoring setup

### Silent Installation

Set environment variables for unattended installation:

```bash
export PG_DB="myapp"
export PG_PASSWORD="your_secure_password"
export DOMAIN_NAME="db.yourdomain.com"
export EMAIL="admin@yourdomain.com"
export DB_USERNAME="appuser"
export DB_USER_PASSWORD="user_secure_password"

sudo -E ./postgresql_production_setup.sh
```

## 📁 Project Structure

```
postgresql-16-setup/
├── postgresql_production_setup.sh    # Main installation script
├── postgres_restore.sh              # Single database restore script
├── postgres_cluster_backup_restore.sh # Cluster-level backup/restore script
├── README.md                         # This document (English)
├── README.zh.md                      # Chinese documentation
└── README.ja.md                      # Japanese documentation
```

## 🔍 Script Details

### Main Installation Script (`postgresql_production_setup.sh`)

- System environment check and preparation
- PostgreSQL 16 installation and configuration
- SSL certificate acquisition and setup
- Monitoring system deployment
- Security policy configuration
- Automated backup setup

### Database Recovery (`postgres_restore.sh`)

```bash
# Download restore script
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_restore.sh -o postgres_restore.sh
chmod +x postgres_restore.sh

# List available backups
sudo ./postgres_restore.sh --list

# Restore specific backup
sudo ./postgres_restore.sh --restore backup_20241201_120000.sql

# Restore from custom location
sudo ./postgres_restore.sh --restore /path/to/backup.sql --database myapp
```

### Cluster Backup & Recovery (`postgres_cluster_backup_restore.sh`)

```bash
# Download cluster backup/restore script
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_cluster_backup_restore.sh -o postgres_cluster_backup_restore.sh
chmod +x postgres_cluster_backup_restore.sh

# Create full cluster backup
sudo ./postgres_cluster_backup_restore.sh --backup

# Restore full cluster
sudo ./postgres_cluster_backup_restore.sh --restore cluster_backup_20241201.sql

# List available cluster backups
sudo ./postgres_cluster_backup_restore.sh --list
```

## 🌐 Access Services

After installation, you can access the following services:

### PostgreSQL Database

```bash
# Local connection
psql -U postgres -d your_database

# Remote connection (SSL)
psql "host=your-domain.com port=5432 dbname=your_database user=your_user sslmode=require"
```

### Monitoring Dashboards

- **Grafana**: `https://your-domain.com:3000`

  - Username: `admin`
  - Password: Check installation logs or setup info file

- **Prometheus**: `https://your-domain.com:9090`
  - Requires HTTP basic authentication

### Backup Management

```bash
# Check backup status
sudo systemctl status postgresql-backup.timer

# Trigger manual backup
sudo /usr/local/bin/postgres_backup.sh

# View backup files
ls -la /var/backups/postgresql/dumps/
```

## 📊 Installation Summary

After installation completes, detailed information is saved to `/root/postgresql_setup_info.txt`. View it with:

```bash
sudo cat /root/postgresql_setup_info.txt
```

This file contains:

- 🔐 **Database Credentials**: PostgreSQL passwords and connection details
- 🌐 **Access URLs**: Grafana, Prometheus, and database endpoints
- 📋 **Configuration Paths**: Location of config files and certificates
- 🔧 **Service Commands**: How to start/stop/restart services
- 📊 **Monitoring Setup**: Dashboard access and authentication details
- 🔄 **Backup Information**: Backup schedules and restoration commands

## 🔧 Performance Tuning

### Automatic Configuration

The script automatically adjusts these parameters based on system resources:

- `shared_buffers`: 25% of system memory
- `work_mem`: Calculated based on connections and memory
- `maintenance_work_mem`: 10% of system memory
- `effective_cache_size`: 75% of system memory

### Security Configuration

- SSL-only connections enforced
- Password authentication + certificate verification
- IP whitelist access control
- Regular password rotation reminders

## 📊 Monitoring Metrics

### Grafana Dashboards Include

- Database connections and active sessions
- Query performance and slow query analysis
- System resource utilization
- Backup status and storage usage
- SSL certificate expiration monitoring

### Alert Configuration

- Database connection limit exceeded
- Insufficient disk space
- SSL certificate expiring soon
- Backup failure notifications

## 🔄 Daily Maintenance

### Backup Verification

```bash
# Check backup job status
sudo systemctl status postgresql-backup.timer
sudo systemctl status postgresql-backup.service

# View backup logs
sudo journalctl -u postgresql-backup.service -f
```

### Certificate Management

```bash
# Manual SSL certificate renewal
sudo certbot renew --nginx

# Check certificate status
sudo certbot certificates
```

### Performance Monitoring

```bash
# Check PostgreSQL status
sudo systemctl status postgresql

# View connections
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"

# Check database sizes
sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;"
```

## 🚨 Troubleshooting

### Common Issues

#### SSL Certificate Request Failed

```bash
# Check domain DNS resolution
nslookup your-domain.com

# Check firewall rules
sudo ufw status

# Manual certificate request
sudo certbot --nginx -d your-domain.com
```

#### PostgreSQL Connection Failed

```bash
# Check service status
sudo systemctl status postgresql

# View error logs
sudo tail -f /var/log/postgresql/postgresql-16-main.log

# Check configuration file
sudo -u postgres psql -c "SHOW config_file;"
```

#### Monitoring Services Issues

```bash
# Restart Prometheus
sudo systemctl restart prometheus

# Restart Grafana
sudo systemctl restart grafana-server

# Check port usage
sudo netstat -tlnp | grep -E "(3000|9090|9187)"
```

## 📚 Documentation & Support

### Configuration File Locations

- PostgreSQL config: `/etc/postgresql/16/main/postgresql.conf`
- Connection config: `/etc/postgresql/16/main/pg_hba.conf`
- SSL certificates: `/etc/letsencrypt/live/your-domain.com/`
- Backup directory: `/var/backups/postgresql/`
- Log files: `/var/log/postgresql/`

### Installation Information File

After installation, detailed information is saved to `/root/postgresql_setup_info.txt`

### Getting Help

```bash
# View installation summary
sudo cat /root/postgresql_setup_info.txt

# Check PostgreSQL version
sudo -u postgres psql -c "SELECT version();"

# View installed extensions
sudo -u postgres psql -c "SELECT * FROM pg_available_extensions WHERE installed_version IS NOT NULL;"
```

## 🤝 Contributing

Issues and improvement suggestions are welcome!

## 📄 License

MIT License

---

## 🎯 Quick Command Reference

```bash
# One-click deployment
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgresql_production_setup.sh | sudo bash

# Database connection
psql -U postgres -d your_database

# Create backup
sudo /usr/local/bin/postgres_backup.sh

# Download and restore data
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_restore.sh -o postgres_restore.sh && chmod +x postgres_restore.sh
sudo ./postgres_restore.sh --list
sudo ./postgres_restore.sh --restore backup_file.sql

# View monitoring
# Grafana: https://your-domain.com:3000
# Prometheus: https://your-domain.com:9090

# Check service status
sudo systemctl status postgresql prometheus grafana-server

# View installation details
sudo cat /root/postgresql_setup_info.txt
```

**🎉 Deploy enterprise-grade PostgreSQL database with one line of code!**
