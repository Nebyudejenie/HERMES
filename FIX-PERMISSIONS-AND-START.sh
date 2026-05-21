#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Must run with sudo${NC}"
    exit 1
fi

echo -e "${YELLOW}[*] Fixing permissions and starting services...${NC}"
echo ""

HERMIS_ROOT="/opt/hermis"

# Fix permissions
echo -e "${YELLOW}[1] Fixing directory permissions...${NC}"
chmod 755 $HERMIS_ROOT
chmod 644 $HERMIS_ROOT/.env
chmod 644 $HERMIS_ROOT/docker-compose.yml
chmod 755 $HERMIS_ROOT/{data,config,logs,scripts,models,monitoring,security,rag,apps,agents,ai}
echo -e "${GREEN}✓ Done${NC}"
echo ""

# Start compose
echo -e "${YELLOW}[2] Starting services...${NC}"
cd $HERMIS_ROOT
docker compose up -d

sleep 10

echo -e "${YELLOW}[3] Service status...${NC}"
docker compose ps

echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}SERVICES STARTING!${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Monitor with:${NC}"
echo "  docker compose logs -f"
echo ""
echo -e "${YELLOW}Access:${NC}"
echo "  http://localhost:8080  - Traefik"
echo "  http://localhost:3000  - Grafana"
echo "  http://localhost:9000  - Portainer"
