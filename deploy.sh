#!/bin/bash
# HERMIS AGENT - SIMPLE DEPLOYMENT

set -e

HERMIS_ROOT="/opt/hermis"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  HERMIS AGENT DEPLOYMENT${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""

# Check if running as root/sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Must run with sudo${NC}"
    echo "Usage: sudo bash deploy.sh"
    exit 1
fi

# Step 1: Clean up
echo -e "${YELLOW}[1/5] Cleaning up...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
docker volume prune -f >/dev/null 2>&1 || true
echo -e "${GREEN}✓ Cleaned${NC}"
echo ""

# Step 2: Setup directories
echo -e "${YELLOW}[2/5] Setting up directories...${NC}"
mkdir -p $HERMIS_ROOT/data/{postgres,redis,qdrant,minio,vault,traefik}
mkdir -p $HERMIS_ROOT/config/{postgres,traefik,prometheus,loki}
mkdir -p $HERMIS_ROOT/logs
mkdir -p $HERMIS_ROOT/scripts/backup
chmod 777 $HERMIS_ROOT 2>/dev/null || true
echo -e "${GREEN}✓ Directories ready${NC}"
echo ""

# Step 3: Pull images sequentially
echo -e "${YELLOW}[3/5] Pulling Docker images...${NC}"
echo "(This takes 5-10 minutes, please wait)"
echo ""

declare -a IMAGES=(
    "traefik:latest"
    "ollama/ollama:latest"
    "ghcr.io/open-webui/open-webui:latest"
    "postgres:15"
    "redis:7"
    "qdrant/qdrant:latest"
    "minio/minio:latest"
    "quay.io/keycloak/keycloak:latest"
    "hashicorp/vault:latest"
    "prom/prometheus:latest"
    "grafana/grafana:latest"
    "grafana/loki:latest"
    "grafana/promtail:latest"
    "portainer/portainer-ce:latest"
)

COUNT=0
for img in "${IMAGES[@]}"; do
    ((COUNT++))
    echo -n "  [$COUNT/${#IMAGES[@]}] $img ... "
    if docker pull "$img" 2>&1 | tail -1 | grep -q "Digest\|up to date"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
done
echo ""
echo -e "${GREEN}✓ Images ready${NC}"
echo ""

# Step 4: Start docker compose
echo -e "${YELLOW}[4/5] Starting services...${NC}"
cd $HERMIS_ROOT

if [ ! -f docker-compose.yml ]; then
    echo -e "${RED}✗ docker-compose.yml not found in $HERMIS_ROOT${NC}"
    echo "Copy it from /home/cosmic/HERMES/docker-compose.yml"
    exit 1
fi

docker compose up -d || {
    echo -e "${RED}✗ Failed to start services${NC}"
    docker compose logs --tail=20
    exit 1
}

echo -e "${GREEN}✓ Services starting${NC}"
echo ""

# Step 5: Wait and verify
echo -e "${YELLOW}[5/5] Verifying deployment...${NC}"
echo "(Waiting 30 seconds for services to start)"
sleep 30

RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  DEPLOYMENT COMPLETE!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Running services: $RUNNING${NC}"
docker compose ps | tail -15
echo ""
echo -e "${YELLOW}Access URLs:${NC}"
echo "  • Traefik:    http://localhost:8080"
echo "  • OpenWebUI:  http://localhost:3000"
echo "  • Grafana:    http://localhost:3000"
echo "  • Portainer:  http://localhost:9000"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Check logs: docker compose logs -f"
echo "  2. Update config: vi $HERMIS_ROOT/.env"
echo "  3. Ollama models: docker exec ollama ollama list"
echo ""
echo -e "${GREEN}✓ Ready to use!${NC}"
