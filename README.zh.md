# PostgreSQL 16 生产环境部署 🚀

[![English](https://img.shields.io/badge/Language-English-blue)](README.md) [![中文](https://img.shields.io/badge/Language-中文-red)](README.zh.md) [![日本語](https://img.shields.io/badge/Language-日本語-green)](README.ja.md)

一键式 PostgreSQL 16 生产环境部署脚本，包含 SSL 加密连接、Let's Encrypt 自动证书、Prometheus/Grafana 监控堆栈、自动化备份恢复系统以及全面的企业级安全功能。

## 🚀 快速开始

### 一行代码部署

```bash
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgresql_production_setup.sh | sudo bash
```

或者克隆仓库后运行：

```bash
git clone https://github.com/astr0-g/postgresql-16-setup.git
cd postgresql-16-setup
sudo ./postgresql_production_setup.sh
```

## ✨ 主要特性

### 🔧 核心功能

- **PostgreSQL 16** 最新稳定版本安装
- **SSL/TLS 加密** 使用 Let's Encrypt 自动证书
- **生产级配置** 针对性能和安全性优化
- **用户管理** 自动创建数据库用户和权限设置
- **防火墙配置** UFW 和 fail2ban 安全防护

### 📊 监控系统

- **Prometheus** 指标收集和存储
- **Grafana** 可视化仪表板 (HTTPS)
- **PostgreSQL Exporter** 数据库指标导出
- **pgBadger** 日志分析工具
- **pg_stat_monitor** 增强性能监控

### 🔄 备份与恢复

- **自动备份** 每日定时备份任务
- **手动备份** 单数据库和集群级备份
- **一键恢复** 简化的数据恢复流程
- **日志轮转** 自动日志管理

### 🛡️ 安全特性

- **SSL 强制连接** 所有客户端连接加密
- **证书自动续期** Let's Encrypt 自动更新
- **访问控制** 基于 IP 和用户的精细权限
- **密码策略** 强密码生成和管理

## 📋 系统要求

- **操作系统**: Ubuntu 24.04 LTS
- **权限**: sudo/root 访问权限
- **网络**: 公网 IP 和域名（SSL 证书需要）
- **内存**: 最低 2GB RAM（推荐 4GB+）
- **存储**: 最低 20GB 可用空间

## 🔧 安装选项

### 交互式安装（推荐）

```bash
sudo ./postgresql_production_setup.sh
```

脚本会引导你完成以下配置：

- 数据库名称和密码
- 域名和邮箱（SSL 证书）
- 数据库用户创建
- 监控配置

### 静默安装

设置环境变量进行无人值守安装：

```bash
export PG_DB="myapp"
export PG_PASSWORD="your_secure_password"
export DOMAIN_NAME="db.yourdomain.com"
export EMAIL="admin@yourdomain.com"
export DB_USERNAME="appuser"
export DB_USER_PASSWORD="user_secure_password"

sudo -E ./postgresql_production_setup.sh
```

## 📁 项目结构

```
postgresql-16-setup/
├── postgresql_production_setup.sh    # 主安装脚本
├── postgres_restore.sh              # 单数据库恢复脚本
├── postgres_cluster_backup_restore.sh # 集群级备份恢复脚本
├── README.md                         # 英文文档
├── README.zh.md                      # 中文文档（本文件）
└── README.ja.md                      # 日文文档
```

## 🔍 脚本功能详解

### 主安装脚本 (`postgresql_production_setup.sh`)

- 系统环境检查和准备
- PostgreSQL 16 安装和配置
- SSL 证书申请和配置
- 监控系统部署
- 安全策略配置
- 自动备份设置

### 数据库恢复 (`postgres_restore.sh`)

```bash
# 下载恢复脚本
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_restore.sh -o postgres_restore.sh
chmod +x postgres_restore.sh

# 列出可用备份
sudo ./postgres_restore.sh --list

# 恢复指定备份
sudo ./postgres_restore.sh --restore backup_20241201_120000.sql

# 从自定义位置恢复
sudo ./postgres_restore.sh --restore /path/to/backup.sql --database myapp
```

### 集群备份恢复 (`postgres_cluster_backup_restore.sh`)

```bash
# 下载集群备份恢复脚本
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_cluster_backup_restore.sh -o postgres_cluster_backup_restore.sh
chmod +x postgres_cluster_backup_restore.sh

# 创建完整集群备份
sudo ./postgres_cluster_backup_restore.sh --backup

# 恢复完整集群
sudo ./postgres_cluster_backup_restore.sh --restore cluster_backup_20241201.sql

# 列出可用集群备份
sudo ./postgres_cluster_backup_restore.sh --list
```

## 🌐 访问服务

安装完成后，你可以访问以下服务：

### PostgreSQL 数据库

```bash
# 本地连接
psql -U postgres -d your_database

# 远程连接 (SSL)
psql "host=your-domain.com port=5432 dbname=your_database user=your_user sslmode=require"
```

### 监控面板

- **Grafana**: `https://your-domain.com:3000`

  - 用户名: `admin`
  - 密码: 查看安装日志或配置信息文件

- **Prometheus**: `https://your-domain.com:9090`
  - 需要 HTTP 基础认证

### 备份管理

```bash
# 查看备份状态
sudo systemctl status postgresql-backup.timer

# 手动触发备份
sudo /usr/local/bin/postgres_backup.sh

# 查看备份文件
ls -la /var/backups/postgresql/dumps/
```

## 📊 安装摘要

安装完成后，详细信息保存在 `/root/postgresql_setup_info.txt`。查看方法：

```bash
sudo cat /root/postgresql_setup_info.txt
```

该文件包含：

- 🔐 **数据库凭据**: PostgreSQL 密码和连接详情
- 🌐 **访问地址**: Grafana、Prometheus 和数据库端点
- 📋 **配置路径**: 配置文件和证书位置
- 🔧 **服务命令**: 如何启动/停止/重启服务
- 📊 **监控设置**: 仪表板访问和认证详情
- 🔄 **备份信息**: 备份计划和恢复命令

## 🔧 配置调优

### 性能配置

脚本会根据系统资源自动调整以下参数：

- `shared_buffers`: 系统内存的 25%
- `work_mem`: 根据连接数和内存自动计算
- `maintenance_work_mem`: 系统内存的 10%
- `effective_cache_size`: 系统内存的 75%

### 安全配置

- 仅允许 SSL 连接
- 密码认证 + 证书验证
- IP 白名单访问控制
- 定期密码轮换提醒

## 📊 监控指标

### Grafana 仪表板包含

- 数据库连接数和活跃会话
- 查询性能和慢查询分析
- 系统资源使用情况
- 备份状态和存储使用量
- SSL 证书有效期监控

### 告警配置

- 数据库连接数超限
- 磁盘空间不足
- SSL 证书即将过期
- 备份失败通知

## 🔄 日常维护

### 备份检查

```bash
# 检查备份任务状态
sudo systemctl status postgresql-backup.timer
sudo systemctl status postgresql-backup.service

# 查看备份日志
sudo journalctl -u postgresql-backup.service -f
```

### 证书更新

```bash
# 手动更新SSL证书
sudo certbot renew --nginx

# 检查证书状态
sudo certbot certificates
```

### 性能监控

```bash
# 查看PostgreSQL状态
sudo systemctl status postgresql

# 查看连接情况
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"

# 查看数据库大小
sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;"
```

## 🚨 故障排除

### 常见问题

#### SSL 证书申请失败

```bash
# 检查域名DNS解析
nslookup your-domain.com

# 检查防火墙规则
sudo ufw status

# 手动申请证书
sudo certbot --nginx -d your-domain.com
```

#### PostgreSQL 连接失败

```bash
# 检查服务状态
sudo systemctl status postgresql

# 查看错误日志
sudo tail -f /var/log/postgresql/postgresql-16-main.log

# 检查配置文件
sudo -u postgres psql -c "SHOW config_file;"
```

#### 监控服务异常

```bash
# 重启Prometheus
sudo systemctl restart prometheus

# 重启Grafana
sudo systemctl restart grafana-server

# 检查端口占用
sudo netstat -tlnp | grep -E "(3000|9090|9187)"
```

## 📚 文档和支持

### 配置文件位置

- PostgreSQL 配置: `/etc/postgresql/16/main/postgresql.conf`
- 连接配置: `/etc/postgresql/16/main/pg_hba.conf`
- SSL 证书: `/etc/letsencrypt/live/your-domain.com/`
- 备份目录: `/var/backups/postgresql/`
- 日志文件: `/var/log/postgresql/`

### 安装信息文件

安装完成后，详细信息保存在 `/root/postgresql_setup_info.txt`

### 获取帮助

```bash
# 查看安装摘要
sudo cat /root/postgresql_setup_info.txt

# 查看PostgreSQL版本
sudo -u postgres psql -c "SELECT version();"

# 查看已安装扩展
sudo -u postgres psql -c "SELECT * FROM pg_available_extensions WHERE installed_version IS NOT NULL;"
```

## 🤝 贡献

欢迎提交问题和改进建议！

## 📄 许可证

MIT License

---

## 🎯 快速命令参考

```bash
# 一键部署
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgresql_production_setup.sh | sudo bash

# 数据库连接
psql -U postgres -d your_database

# 创建备份
sudo /usr/local/bin/postgres_backup.sh

# 下载并恢复数据
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_restore.sh -o postgres_restore.sh && chmod +x postgres_restore.sh
sudo ./postgres_restore.sh --list
sudo ./postgres_restore.sh --restore backup_file.sql

# 查看监控
# Grafana: https://your-domain.com:3000
# Prometheus: https://your-domain.com:9090

# 检查服务状态
sudo systemctl status postgresql prometheus grafana-server

# 查看安装详情
sudo cat /root/postgresql_setup_info.txt
```

**🎉 现在你可以用一行代码部署企业级 PostgreSQL 数据库了！**
