# PostgreSQL 16 プロダクション環境セットアップ 🚀

[![English](https://img.shields.io/badge/Language-English-blue)](README.md) [![中文](https://img.shields.io/badge/Language-中文-red)](README.zh.md) [![日本語](https://img.shields.io/badge/Language-日本語-green)](README.ja.md)

SSL 暗号化接続、Let's Encrypt 証明書、Prometheus/Grafana モニタリングスタック、自動化バックアップ/復旧システム、包括的なエンタープライズグレードセキュリティ機能を含むワンクリック PostgreSQL 16 プロダクション環境デプロイメント。

## 🚀 クイックスタート

### ワンライン インストール

```bash
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgresql_production_setup.sh -o postgresql_setup.sh && chmod +x postgresql_setup.sh && sudo ./postgresql_setup.sh
```

またはリポジトリをクローンして実行：

```bash
git clone https://github.com/astr0-g/postgresql-16-setup.git
cd postgresql-16-setup
sudo ./postgresql_production_setup.sh
```

## ✨ 主要機能

### 🔧 コア機能

- **PostgreSQL 16** 最新安定版のインストール
- **SSL/TLS 暗号化** Let's Encrypt 自動証明書
- **プロダクション設定** パフォーマンスとセキュリティの最適化
- **ユーザー管理** データベースユーザーの自動作成
- **セキュリティ強化** UFW ファイアウォールと fail2ban 保護

### 📊 モニタリングスタック

- **Prometheus** メトリクス収集と保存
- **Grafana** 可視化ダッシュボード（HTTPS）
- **PostgreSQL Exporter** データベースメトリクスエクスポート
- **pgBadger** ログ解析ツール
- **pg_stat_monitor** 拡張パフォーマンス監視

### 🔄 バックアップ＆リカバリ

- **自動バックアップ** 日次スケジュールバックアップタスク
- **手動バックアップ** 単一データベースとクラスターレベルのバックアップ
- **ワンクリック復旧** 簡素化されたデータ復元フロー
- **ログローテーション** 自動ログ管理

### 🛡️ セキュリティ機能

- **SSL 専用接続** すべてのクライアント接続を暗号化
- **証明書自動更新** Let's Encrypt 自動アップデート
- **アクセス制御** IP とユーザーベースの詳細権限
- **パスワードポリシー** 強力なパスワード生成と管理

## 📋 システム要件

- **オペレーティングシステム**: Ubuntu 24.04 LTS
- **権限**: sudo/root アクセス
- **ネットワーク**: パブリック IP とドメイン名（SSL 証明書用）
- **メモリ**: 最低 2GB RAM（4GB+推奨）
- **ストレージ**: 最低 20GB 利用可能容量

## 🔧 インストールオプション

### インタラクティブインストール（推奨）

```bash
sudo ./postgresql_production_setup.sh
```

スクリプトが以下の設定をガイドします：

- データベース名とパスワード設定
- ドメイン名とメール（SSL 証明書）
- データベースユーザー作成
- モニタリング設定

### サイレントインストール

無人インストール用の環境変数設定：

```bash
export PG_DB="myapp"
export PG_PASSWORD="your_secure_password"
export DOMAIN_NAME="db.yourdomain.com"
export EMAIL="admin@yourdomain.com"
export DB_USERNAME="appuser"
export DB_USER_PASSWORD="user_secure_password"

sudo -E ./postgresql_production_setup.sh
```

## 📁 プロジェクト構造

```
postgresql-16-setup/
├── postgresql_production_setup.sh    # メインインストールスクリプト
├── postgres_restore.sh              # 単一データベース復元スクリプト
├── postgres_cluster_backup_restore.sh # クラスターレベルバックアップ/復元スクリプト
├── README.md                         # 英語ドキュメント
├── README.zh.md                      # 中国語ドキュメント
└── README.ja.md                      # 日本語ドキュメント（このファイル）
```

## 🔍 スクリプト詳細

### メインインストールスクリプト (`postgresql_production_setup.sh`)

- システム環境チェックと準備
- PostgreSQL 16 インストールと設定
- SSL 証明書取得と設定
- モニタリングシステムデプロイメント
- セキュリティポリシー設定
- 自動バックアップ設定

### データベース復旧 (`postgres_restore.sh`)

```bash
# 復旧スクリプトのダウンロード
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_restore.sh -o postgres_restore.sh
chmod +x postgres_restore.sh

# 利用可能なバックアップのリスト
sudo ./postgres_restore.sh --list

# 特定のバックアップを復元
sudo ./postgres_restore.sh --restore backup_20241201_120000.sql

# カスタム場所から復元
sudo ./postgres_restore.sh --restore /path/to/backup.sql --database myapp
```

### クラスターバックアップ＆復旧 (`postgres_cluster_backup_restore.sh`)

```bash
# クラスターバックアップ/復旧スクリプトのダウンロード
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_cluster_backup_restore.sh -o postgres_cluster_backup_restore.sh
chmod +x postgres_cluster_backup_restore.sh

# 完全クラスターバックアップの作成
sudo ./postgres_cluster_backup_restore.sh --backup

# 完全クラスターの復元
sudo ./postgres_cluster_backup_restore.sh --restore cluster_backup_20241201.sql

# 利用可能なクラスターバックアップのリスト
sudo ./postgres_cluster_backup_restore.sh --list
```

## 🌐 サービスアクセス

インストール完了後、以下のサービスにアクセスできます：

### PostgreSQL データベース

```bash
# ローカル接続
psql -U postgres -d your_database

# リモート接続（SSL）
psql "host=your-domain.com port=5432 dbname=your_database user=your_user sslmode=require"
```

### モニタリングダッシュボード

- **Grafana**: `https://your-domain.com:3000`

  - ユーザー名: `admin`
  - パスワード: インストールログまたは設定情報ファイルを確認

- **Prometheus**: `https://your-domain.com:9090`
  - HTTP 基本認証が必要

### バックアップ管理

```bash
# バックアップステータスの確認
sudo systemctl status postgresql-backup.timer

# 手動バックアップのトリガー
sudo /usr/local/bin/postgres_backup.sh

# バックアップファイルの表示
ls -la /var/backups/postgresql/dumps/
```

## 📊 インストール概要

インストール完了後、詳細情報は `/root/postgresql_setup_info.txt` に保存されます。表示方法：

```bash
sudo cat /root/postgresql_setup_info.txt
```

このファイルには以下が含まれます：

- 🔐 **データベース認証情報**: PostgreSQL パスワードと接続詳細
- 🌐 **アクセス URL**: Grafana、Prometheus、データベースエンドポイント
- 📋 **設定パス**: 設定ファイルと証明書の場所
- 🔧 **サービスコマンド**: サービスの開始/停止/再起動方法
- 📊 **モニタリング設定**: ダッシュボードアクセスと認証詳細
- 🔄 **バックアップ情報**: バックアップスケジュールと復元コマンド

## 🔧 パフォーマンスチューニング

### 自動設定

スクリプトはシステムリソースに基づいて以下のパラメータを自動調整します：

- `shared_buffers`: システムメモリの 25%
- `work_mem`: 接続数とメモリに基づいて計算
- `maintenance_work_mem`: システムメモリの 10%
- `effective_cache_size`: システムメモリの 75%

### セキュリティ設定

- SSL 専用接続の強制
- パスワード認証 + 証明書検証
- IP ホワイトリストアクセス制御
- 定期的なパスワードローテーション通知

## 📊 モニタリングメトリクス

### Grafana ダッシュボードに含まれるもの

- データベース接続数とアクティブセッション
- クエリパフォーマンスとスロークエリ分析
- システムリソース使用率
- バックアップステータスとストレージ使用量
- SSL 証明書有効期限監視

### アラート設定

- データベース接続制限超過
- ディスク容量不足
- SSL 証明書期限切れ間近
- バックアップ失敗通知

## 🔄 日常メンテナンス

### バックアップ検証

```bash
# バックアップジョブステータスの確認
sudo systemctl status postgresql-backup.timer
sudo systemctl status postgresql-backup.service

# バックアップログの表示
sudo journalctl -u postgresql-backup.service -f
```

### 証明書管理

```bash
# 手動SSL証明書更新
sudo certbot renew --nginx

# 証明書ステータスの確認
sudo certbot certificates
```

### パフォーマンス監視

```bash
# PostgreSQLステータスの確認
sudo systemctl status postgresql

# 接続の表示
sudo -u postgres psql -c "SELECT * FROM pg_stat_activity;"

# データベースサイズの確認
sudo -u postgres psql -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) FROM pg_database;"
```

## 🚨 トラブルシューティング

### 一般的な問題

#### SSL 証明書リクエスト失敗

```bash
# ドメインDNS解決の確認
nslookup your-domain.com

# ファイアウォールルールの確認
sudo ufw status

# 手動証明書リクエスト
sudo certbot --nginx -d your-domain.com
```

#### PostgreSQL 接続失敗

```bash
# サービスステータスの確認
sudo systemctl status postgresql

# エラーログの表示
sudo tail -f /var/log/postgresql/postgresql-16-main.log

# 設定ファイルの確認
sudo -u postgres psql -c "SHOW config_file;"
```

#### モニタリングサービスの問題

```bash
# Prometheusの再起動
sudo systemctl restart prometheus

# Grafanaの再起動
sudo systemctl restart grafana-server

# ポート使用状況の確認
sudo netstat -tlnp | grep -E "(3000|9090|9187)"
```

## 📚 ドキュメント＆サポート

### 設定ファイルの場所

- PostgreSQL 設定: `/etc/postgresql/16/main/postgresql.conf`
- 接続設定: `/etc/postgresql/16/main/pg_hba.conf`
- SSL 証明書: `/etc/letsencrypt/live/your-domain.com/`
- バックアップディレクトリ: `/var/backups/postgresql/`
- ログファイル: `/var/log/postgresql/`

### インストール情報ファイル

インストール完了後、詳細情報は `/root/postgresql_setup_info.txt` に保存されます

### ヘルプの取得

```bash
# インストール概要の表示
sudo cat /root/postgresql_setup_info.txt

# PostgreSQLバージョンの確認
sudo -u postgres psql -c "SELECT version();"

# インストール済み拡張機能の表示
sudo -u postgres psql -c "SELECT * FROM pg_available_extensions WHERE installed_version IS NOT NULL;"
```

## 🤝 貢献

問題や改善提案を歓迎します！

## 📄 ライセンス

MIT License

---

## 🎯 クイックコマンドリファレンス

```bash
# ワンクリックデプロイメント
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgresql_production_setup.sh | sudo bash

# データベース接続
psql -U postgres -d your_database

# バックアップ作成
sudo /usr/local/bin/postgres_backup.sh

# データのダウンロードと復元
curl -fsSL https://raw.githubusercontent.com/astr0-g/postgresql-16-setup/main/postgres_restore.sh -o postgres_restore.sh && chmod +x postgres_restore.sh
sudo ./postgres_restore.sh --list
sudo ./postgres_restore.sh --restore backup_file.sql

# モニタリングの表示
# Grafana: https://your-domain.com:3000
# Prometheus: https://your-domain.com:9090

# サービスステータスの確認
sudo systemctl status postgresql prometheus grafana-server

# インストール詳細の表示
sudo cat /root/postgresql_setup_info.txt
```

**🎉 ワンラインのコードでエンタープライズグレードの PostgreSQL データベースをデプロイしよう！**
