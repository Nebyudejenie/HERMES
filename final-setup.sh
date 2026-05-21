#!/bin/bash
# Final setup - complete fix

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  HERMIS AGENT - FINAL SETUP            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Must run with sudo${NC}"
    exit 1
fi

HERMIS_ROOT="/opt/hermis"

# Step 1: Clean
echo -e "${YELLOW}[1] Cleaning...${NC}"
docker compose -f $HERMIS_ROOT/docker-compose.yml down 2>/dev/null || true
docker network rm hermis-internal 2>/dev/null || true
docker network prune -f > /dev/null 2>&1 || true
sleep 2
echo -e "${GREEN}✓${NC}"
echo ""

# Step 2: Setup directories
echo -e "${YELLOW}[2] Setting up directories...${NC}"
mkdir -p $HERMIS_ROOT/{data,config,logs,scripts/backup}
chmod 755 $HERMIS_ROOT
echo -e "${GREEN}✓${NC}"
echo ""

# Step 3: Copy simple docker-compose.yml
echo -e "${YELLOW}[3] Setting up docker-compose.yml...${NC}"
cp docker-compose.simple.yml $HERMIS_ROOT/docker-compose.yml
chmod 644 $HERMIS_ROOT/docker-compose.yml
echo -e "${GREEN}✓${NC}"
echo ""

# Step 4: Create .env file
echo -e "${YELLOW}[4] Creating .env file...${NC}"
cat > $HERMIS_ROOT/.env << 'ENVEOF'
# Hermis Agent Configuration

# Core
HERMIS_ROOT=/opt/hermis

# PostgreSQL
POSTGRES_USER=hermis
POSTGRES_PASSWORD=hermis_secure_password_123
POSTGRES_DB=hermis

# Redis
REDIS_PASSWORD=redis_secure_password_123

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=grafana_secure_password_123

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=keycloak_secure_password_123

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minio_secure_password_123

# Vault
VAULT_DEV_ROOT_TOKEN_ID=vault_root_token_123

# Qdrant
QDRANT_API_KEY=qdrant_api_key_123

# Docker
DOCKER_BUILDKIT=1

# Timezone
TZ=UTC
ENVEOF
chmod 644 $HERMIS_ROOT/.env
echo -e "${GREEN}✓${NC}"
echo ""

# Step 5: Start services
echo -e "${YELLOW}[5] Starting services...${NC}"
cd $HERMIS_ROOT
docker compose up -d 2>&1 | grep -E "^Creating|^Starting|done" || true
echo -e "${GREEN}✓${NC}"
echo ""

# Step 6: Wait and verify
echo -e "${YELLOW}[6] Waiting for services (30 seconds)...${NC}"
sleep 30
echo ""

echo -e "${YELLOW}[7] Service status...${NC}"
docker compose ps
echo ""

RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
TOTAL=$(docker compose config --services 2>/dev/null | wc -l)

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  HERMIS AGENT READY!                   ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Running: $RUNNING / $TOTAL services${NC}"
echo ""
echo -e "${YELLOW}Access URLs:${NC}"
echo "  • Traefik:    http://localhost:8080"
echo "  • Grafana:    http://localhost:3000"
echo "  • Portainer:  http://localhost:9000"
echo "  • Prometheus: http://localhost:9090"
echo "  • Qdrant:     http://localhost:6333"
echo ""
echo -e "${YELLOW}Default Credentials:${NC}"
echo "  • Grafana:    admin / grafana_secure_password_123"
echo "  • Portainer:  admin / portainer_password"
echo "  • MinIO:      minioadmin / minio_secure_password_123"
echo ""
echo -e "${YELLOW}Monitor:${NC}"
echo "  docker compose logs -f"
echo ""
echo -e "${YELLOW}Control:${NC}"
echo "  sudo bash up.sh        # Start"
echo "  sudo bash down.sh      # Stop"
echo "  bash hermis-control.sh status"
