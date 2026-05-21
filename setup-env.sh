#!/bin/bash
# Setup .env file for docker-compose

set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Setting up .env file${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""

# Create /opt/hermis if doesn't exist
echo -e "${YELLOW}[1] Creating /opt/hermis...${NC}"
sudo mkdir -p /opt/hermis
sudo chown -R $(whoami) /opt/hermis 2>/dev/null || true
echo -e "${GREEN}✓${NC}"
echo ""

# Copy docker-compose.yml
echo -e "${YELLOW}[2] Setting up docker-compose.yml...${NC}"
sudo cp docker-compose.yml /opt/hermis/ 2>/dev/null || cp docker-compose.yml /opt/hermis/
echo -e "${GREEN}✓${NC}"
echo ""

# Create .env file
echo -e "${YELLOW}[3] Creating .env file...${NC}"
ENV_FILE="/opt/hermis/.env"

sudo tee $ENV_FILE > /dev/null << 'ENVEOF'
# Hermis Agent Environment Configuration

# Core
HERMIS_ROOT=/opt/hermis
HERMIS_VERSION=1.0.0

# PostgreSQL
POSTGRES_USER=hermis
POSTGRES_PASSWORD=hermis_secure_pass_2024
POSTGRES_DB=hermis

# Redis
REDIS_PASSWORD=redis_secure_pass_2024

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=grafana_secure_pass_2024
GRAFANA_SECRET_KEY=grafana_secret_key_2024

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=keycloak_secure_pass_2024

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minio_secure_pass_2024

# Vault
VAULT_DEV_ROOT_TOKEN_ID=vault_root_token_2024

# OpenWebUI
OPENWEBUI_API_KEY=openwebui_api_key_2024
OPENWEBUI_SECRET_KEY=openwebui_secret_key_2024

# Qdrant
QDRANT_API_KEY=qdrant_api_key_2024

# Portainer
PORTAINER_PASSWORD=portainer_password_2024

# Docker
DOCKER_BUILDKIT=1

# Timezone
TZ=UTC
ENVEOF

sudo chmod 644 $ENV_FILE
echo -e "${GREEN}✓${NC}"
echo ""

# Fix permissions
echo -e "${YELLOW}[4] Fixing permissions...${NC}"
sudo chmod 755 /opt/hermis
echo -e "${GREEN}✓${NC}"
echo ""

# Restart services
echo -e "${YELLOW}[5] Restarting services...${NC}"
cd /opt/hermis
docker compose down 2>/dev/null || true
sleep 2
docker compose up -d
echo -e "${GREEN}✓${NC}"
echo ""

# Wait and check
sleep 10
echo -e "${YELLOW}[6] Service status...${NC}"
docker compose ps
echo ""

echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Default Credentials:${NC}"
echo "  Grafana:     admin / grafana_secure_pass_2024"
echo "  Portainer:   admin / portainer_password_2024"
echo "  PostgreSQL:  hermis / hermis_secure_pass_2024"
echo "  MinIO:       minioadmin / minio_secure_pass_2024"
echo "  Keycloak:    admin / keycloak_secure_pass_2024"
echo ""
echo -e "${YELLOW}Next: Change these passwords in /opt/hermis/.env${NC}"
