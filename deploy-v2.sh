#!/bin/bash
# HERMIS AGENT - DEPLOYMENT V2 (With live progress)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

HERMIS_ROOT="/opt/hermis"

echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  HERMIS AGENT DEPLOYMENT${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Must run with sudo${NC}"
    exit 1
fi

# Step 1: Clean
echo -e "${YELLOW}[1/5] Cleaning up...${NC}"
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm -f $(docker ps -aq) 2>/dev/null || true
echo -e "${GREEN}✓ Cleaned${NC}"
echo ""

# Step 2: Directories
echo -e "${YELLOW}[2/5] Setting up directories...${NC}"
mkdir -p $HERMIS_ROOT/{data,config,logs,scripts/backup}
chmod 777 $HERMIS_ROOT
echo -e "${GREEN}✓ Directories ready${NC}"
echo ""

# Step 3: Images with LIVE output
echo -e "${YELLOW}[3/5] Pulling Docker images...${NC}"
echo "(Showing live progress)"
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
    echo -e "${YELLOW}[$COUNT/${#IMAGES[@]}]${NC} Pulling $img"
    docker pull "$img" 2>&1 | tail -3
    echo ""
done

echo -e "${GREEN}✓ All images pulled${NC}"
echo ""

# Step 4: Copy compose file
echo -e "${YELLOW}[4/5] Setting up docker-compose...${NC}"
cp /home/cosmic/HERMES/docker-compose.yml $HERMIS_ROOT/ 2>/dev/null || {
    echo -e "${RED}✗ docker-compose.yml not found${NC}"
    exit 1
}
echo -e "${GREEN}✓ Ready${NC}"
echo ""

# Step 5: Start
echo -e "${YELLOW}[5/5] Starting services...${NC}"
cd $HERMIS_ROOT
echo "Running: docker compose up -d"
docker compose up -d

echo ""
sleep 30

echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}  CHECKING STATUS${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""

docker compose ps

echo ""
echo -e "${YELLOW}Next: docker compose logs -f${NC}"
