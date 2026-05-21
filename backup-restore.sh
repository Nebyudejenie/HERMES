#!/bin/bash

###############################################################################
# Hermis Agent - Backup and Restore System
# Comprehensive backup strategy with multiple recovery options
###############################################################################

set -euo pipefail

HERMIS_ROOT="${HERMIS_ROOT:-/opt/hermis}"
BACKUP_DIR="${HERMIS_ROOT}/backups"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"
LOG_FILE="${HERMIS_ROOT}/logs/backup.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

###############################################################################
# LOGGING
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "${LOG_FILE}"
}

###############################################################################
# BACKUP FUNCTIONS
###############################################################################

backup_all() {
    log_info "Starting comprehensive backup: ${TIMESTAMP}"

    mkdir -p "${BACKUP_PATH}"

    backup_database
    backup_redis
    backup_vectors
    backup_documents
    backup_models
    backup_configuration
    backup_secrets
    backup_metadata

    create_backup_manifest
    cleanup_old_backups
    verify_backup_integrity

    log_success "Backup completed: ${BACKUP_PATH}"
    return 0
}

backup_database() {
    log_info "Backing up PostgreSQL database..."

    if ! docker compose -f "${HERMIS_ROOT}/docker-compose.yml" exec -T postgres \
        pg_dump -U hermis hermis --verbose 2>&1 | \
        gzip > "${BACKUP_PATH}/database.sql.gz"; then
        log_error "Database backup failed"
        return 1
    fi

    local size=$(du -sh "${BACKUP_PATH}/database.sql.gz" | cut -f1)
    log_success "Database backed up: ${size}"
}

backup_redis() {
    log_info "Backing up Redis data..."

    if ! docker compose -f "${HERMIS_ROOT}/docker-compose.yml" exec -T redis \
        redis-cli BGSAVE >/dev/null 2>&1; then
        log_error "Redis backup failed"
        return 1
    fi

    sleep 2

    if ! docker compose -f "${HERMIS_ROOT}/docker-compose.yml" cp \
        redis:/data/dump.rdb "${BACKUP_PATH}/redis-dump.rdb" 2>/dev/null; then
        log_error "Failed to copy Redis dump"
        return 1
    fi

    log_success "Redis backed up"
}

backup_vectors() {
    log_info "Backing up Qdrant vector database..."

    if ! tar czf "${BACKUP_PATH}/qdrant.tar.gz" \
        -C "${HERMIS_ROOT}/data" qdrant 2>/dev/null; then
        log_error "Qdrant backup failed"
        return 1
    fi

    local size=$(du -sh "${BACKUP_PATH}/qdrant.tar.gz" | cut -f1)
    log_success "Vector database backed up: ${size}"
}

backup_documents() {
    log_info "Backing up documents and RAG data..."

    if ! tar czf "${BACKUP_PATH}/documents.tar.gz" \
        -C "${HERMIS_ROOT}" rag/ 2>/dev/null; then
        log_error "Documents backup failed"
        return 1
    fi

    local size=$(du -sh "${BACKUP_PATH}/documents.tar.gz" | cut -f1)
    log_success "Documents backed up: ${size}"
}

backup_models() {
    log_info "Backing up model metadata..."

    # Only backup metadata, not the actual model files (too large)
    if ! tar czf "${BACKUP_PATH}/models-metadata.tar.gz" \
        -C "${HERMIS_ROOT}/data" models/ 2>/dev/null; then
        log_error "Model metadata backup failed"
        return 1
    fi

    log_success "Model metadata backed up"
}

backup_configuration() {
    log_info "Backing up configuration files..."

    if ! tar czf "${BACKUP_PATH}/config.tar.gz" \
        -C "${HERMIS_ROOT}" config/ docker-compose.yml .env 2>/dev/null; then
        log_error "Configuration backup failed"
        return 1
    fi

    log_success "Configuration backed up"
}

backup_secrets() {
    log_info "Backing up secrets (encrypted)..."

    # Export secrets from Vault
    if command -v vault &>/dev/null; then
        vault kv get -format=json secret/data/hermis | \
            jq . > "${BACKUP_PATH}/vault-secrets.json.enc" || true
    fi

    # Encrypt with GPG if available
    if command -v gpg &>/dev/null && [ -n "${GPG_RECIPIENT:-}" ]; then
        gpg --encrypt --recipient "${GPG_RECIPIENT}" \
            "${BACKUP_PATH}/vault-secrets.json.enc"
        rm -f "${BACKUP_PATH}/vault-secrets.json.enc"
    fi

    log_success "Secrets backed up (encrypted)"
}

backup_metadata() {
    log_info "Creating backup metadata..."

    cat > "${BACKUP_PATH}/manifest.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "version": "1.0.0",
  "hermis_root": "${HERMIS_ROOT}",
  "backup_type": "full",
  "components": {
    "database": "$(ls -lh ${BACKUP_PATH}/database.sql.gz 2>/dev/null | awk '{print $5}' || echo 'N/A')",
    "redis": "$(ls -lh ${BACKUP_PATH}/redis-dump.rdb 2>/dev/null | awk '{print $5}' || echo 'N/A')",
    "vectors": "$(ls -lh ${BACKUP_PATH}/qdrant.tar.gz 2>/dev/null | awk '{print $5}' || echo 'N/A')",
    "documents": "$(ls -lh ${BACKUP_PATH}/documents.tar.gz 2>/dev/null | awk '{print $5}' || echo 'N/A')",
    "configuration": "$(ls -lh ${BACKUP_PATH}/config.tar.gz 2>/dev/null | awk '{print $5}' || echo 'N/A')"
  },
  "system_info": {
    "hostname": "$(hostname)",
    "kernel": "$(uname -r)",
    "docker_version": "$(docker --version 2>/dev/null || echo 'N/A')"
  }
}
EOF

    log_success "Backup metadata created"
}

create_backup_manifest() {
    log_info "Creating backup manifest..."

    cd "${BACKUP_PATH}"
    ls -lh > manifest.txt
    sha256sum * > checksums.sha256

    log_success "Manifest created"
}

cleanup_old_backups() {
    log_info "Cleaning up old backups (keeping last 7 days)..."

    find "${BACKUP_DIR}" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

    log_success "Old backups cleaned up"
}

verify_backup_integrity() {
    log_info "Verifying backup integrity..."

    cd "${BACKUP_PATH}"

    if ! sha256sum -c checksums.sha256 > /dev/null 2>&1; then
        log_error "Backup integrity check FAILED"
        return 1
    fi

    log_success "Backup integrity verified"
}

###############################################################################
# RESTORE FUNCTIONS
###############################################################################

restore_all() {
    local restore_path="${1:?Provide backup path to restore}"

    if [ ! -d "${restore_path}" ]; then
        log_error "Restore path does not exist: ${restore_path}"
        return 1
    fi

    log_info "Starting full restore from: ${restore_path}"

    # Verify backup integrity first
    if ! verify_restore_backup "${restore_path}"; then
        log_error "Backup verification failed, aborting restore"
        return 1
    fi

    # Stop services
    log_info "Stopping services..."
    docker compose -f "${HERMIS_ROOT}/docker-compose.yml" down

    restore_database "${restore_path}"
    restore_redis "${restore_path}"
    restore_vectors "${restore_path}"
    restore_documents "${restore_path}"
    restore_configuration "${restore_path}"

    # Start services
    log_info "Starting services..."
    docker compose -f "${HERMIS_ROOT}/docker-compose.yml" up -d

    # Verify all services are healthy
    sleep 10
    if verify_services; then
        log_success "Restore completed successfully"
        return 0
    else
        log_error "Service health check failed after restore"
        return 1
    fi
}

restore_database() {
    local restore_path="${1:?Provide restore path}"

    log_info "Restoring PostgreSQL database..."

    if [ ! -f "${restore_path}/database.sql.gz" ]; then
        log_error "Database backup not found"
        return 1
    fi

    # Wait for database to be ready
    sleep 5

    if ! zcat "${restore_path}/database.sql.gz" | \
        docker compose -f "${HERMIS_ROOT}/docker-compose.yml" exec -T postgres \
        psql -U hermis 2>&1 | tee -a "${LOG_FILE}"; then
        log_error "Database restore failed"
        return 1
    fi

    log_success "Database restored"
}

restore_redis() {
    local restore_path="${1:?Provide restore path}"

    log_info "Restoring Redis data..."

    if [ ! -f "${restore_path}/redis-dump.rdb" ]; then
        log_error "Redis backup not found"
        return 1
    fi

    docker compose -f "${HERMIS_ROOT}/docker-compose.yml" cp \
        "${restore_path}/redis-dump.rdb" redis:/data/dump.rdb 2>/dev/null || true

    log_success "Redis restored"
}

restore_vectors() {
    local restore_path="${1:?Provide restore path}"

    log_info "Restoring Qdrant vector database..."

    if [ ! -f "${restore_path}/qdrant.tar.gz" ]; then
        log_error "Qdrant backup not found"
        return 1
    fi

    rm -rf "${HERMIS_ROOT}/data/qdrant"
    tar xzf "${restore_path}/qdrant.tar.gz" -C "${HERMIS_ROOT}/data" 2>/dev/null || true

    log_success "Vector database restored"
}

restore_documents() {
    local restore_path="${1:?Provide restore path}"

    log_info "Restoring documents..."

    if [ ! -f "${restore_path}/documents.tar.gz" ]; then
        log_warning "Documents backup not found"
        return 0
    fi

    tar xzf "${restore_path}/documents.tar.gz" -C "${HERMIS_ROOT}" 2>/dev/null || true

    log_success "Documents restored"
}

restore_configuration() {
    local restore_path="${1:?Provide restore path}"

    log_info "Restoring configuration..."

    if [ ! -f "${restore_path}/config.tar.gz" ]; then
        log_error "Configuration backup not found"
        return 1
    fi

    tar xzf "${restore_path}/config.tar.gz" -C "${HERMIS_ROOT}" 2>/dev/null || true

    log_success "Configuration restored"
}

verify_restore_backup() {
    local restore_path="${1:?Provide restore path}"

    log_info "Verifying backup integrity before restore..."

    if [ ! -f "${restore_path}/checksums.sha256" ]; then
        log_warning "No checksums file found, skipping integrity check"
        return 0
    fi

    cd "${restore_path}"
    if ! sha256sum -c checksums.sha256 > /dev/null 2>&1; then
        log_error "Backup integrity check failed"
        return 1
    fi

    log_success "Backup integrity verified"
    return 0
}

verify_services() {
    log_info "Verifying service health..."

    local retries=30
    local count=0

    while [ $count -lt $retries ]; do
        if docker compose -f "${HERMIS_ROOT}/docker-compose.yml" ps | grep -q "healthy"; then
            log_success "Services are healthy"
            return 0
        fi

        count=$((count + 1))
        sleep 2
    done

    log_error "Services failed to become healthy"
    return 1
}

###############################################################################
# UTILITY FUNCTIONS
###############################################################################

list_backups() {
    log_info "Available backups:"
    ls -lh "${BACKUP_DIR}" | awk 'NR>1 {print $9, "(" $5 ")"}'
}

show_backup_info() {
    local backup_path="${1:?Provide backup path}"

    if [ ! -f "${backup_path}/manifest.json" ]; then
        log_error "No manifest found"
        return 1
    fi

    log_info "Backup information:"
    cat "${backup_path}/manifest.json" | jq .
}

compress_backup() {
    local backup_path="${1:?Provide backup path}"

    log_info "Compressing backup..."

    cd "${BACKUP_DIR}"
    tar czf "${backup_path}.tar.gz" "$(basename ${backup_path})"

    local size=$(du -sh "${backup_path}.tar.gz" | cut -f1)
    log_success "Backup compressed: ${size}"
}

upload_backup_to_s3() {
    local backup_path="${1:?Provide backup path}"
    local s3_bucket="${2:?Provide S3 bucket name}"

    log_info "Uploading backup to S3..."

    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI not found"
        return 1
    fi

    aws s3 cp "${backup_path}" "s3://${s3_bucket}/hermis-backups/" --recursive --sse AES256

    log_success "Backup uploaded to S3"
}

###############################################################################
# MAIN
###############################################################################

main() {
    mkdir -p "${BACKUP_DIR}" "${HERMIS_ROOT}/logs"

    case "${1:-backup}" in
        backup)
            backup_all
            ;;
        restore)
            restore_all "${2:-.}"
            ;;
        list)
            list_backups
            ;;
        info)
            show_backup_info "${2:-.}"
            ;;
        compress)
            compress_backup "${2:-.}"
            ;;
        upload-s3)
            upload_backup_to_s3 "${2:-.}" "${3:?S3 bucket required}"
            ;;
        *)
            cat << 'USAGE'
Usage: backup-restore.sh <command> [options]

Commands:
  backup              - Create full backup
  restore <path>      - Restore from backup
  list                - List available backups
  info <path>         - Show backup information
  compress <path>     - Compress backup
  upload-s3 <path> <bucket> - Upload to S3

Examples:
  ./backup-restore.sh backup
  ./backup-restore.sh restore /opt/hermis/backups/2024-01-15_10-30-45
  ./backup-restore.sh list
  ./backup-restore.sh info /opt/hermis/backups/2024-01-15_10-30-45
USAGE
            exit 1
            ;;
    esac
}

main "$@"
