#!/bin/bash
# HERMIS AGENT - FAST DEPLOYMENT (Skip slow images)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

HERMIS_ROOT="/opt/hermis"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Must run with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  HERMIS AGENT - FAST DEPLOY${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""

# Clean
echo -e "${YELLOW}[1/4] Cleaning...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
echo -e "${GREEN}✓${NC}"
echo ""

# Directories
echo -e "${YELLOW}[2/4] Directories...${NC}"
mkdir -p $HERMIS_ROOT/{data,config,logs,scripts/backup}
chmod 777 $HERMIS_ROOT
echo -e "${GREEN}✓${NC}"
echo ""

# Quick images (small, fast)
echo -e "${YELLOW}[3/4] Pulling quick images (timeout 2 min each)...${NC}"

declare -a QUICK_IMAGES=(
    "traefik:latest"
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

for img in "${QUICK_IMAGES[@]}"; do
    echo -n "  $img ... "
    timeout 120 docker pull "$img" > /tmp/pull.log 2>&1 && echo -e "${GREEN}✓${NC}" || echo -e "${RED}SKIP${NC}"
done

echo ""
echo -e "${YELLOW}[Note] Large images (ollama, openwebui) can be pulled later:${NC}"
echo "  docker pull ollama/ollama:latest"
echo "  docker pull ghcr.io/open-webui/open-webui:latest"
echo ""

# Deploy
echo -e "${YELLOW}[4/4] Starting services...${NC}"
cp /home/cosmic/HERMES/docker-compose.yml $HERMIS_ROOT/ 2>/dev/null
cd $HERMIS_ROOT
docker compose up -d 2>&1 | grep -E "^Creating|^Starting|^Error" || true

sleep 20

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
docker compose ps 2>/dev/null | tail -10
echo -e "${GREEN}═══════════════════════════════════════${NC}"
