#!/bin/bash
set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}[*] Cleaning up previous failed installation...${NC}"

# Stop docker compose
echo -e "${YELLOW}[*] Stopping Docker Compose services...${NC}"
cd /opt/hermis 2>/dev/null && docker compose down -v 2>/dev/null || true
cd /opt/hermis 2>/dev/null && docker compose down 2>/dev/null || true

# Remove containers/volumes from failed install
echo -e "${YELLOW}[*] Removing orphaned containers...${NC}"
docker ps -a | grep -E "hermis|traefik|ollama|postgres|redis|qdrant|minio|keycloak|vault|prometheus|grafana" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

echo -e "${YELLOW}[*] Removing orphaned volumes...${NC}"
docker volume ls | grep -E "hermis|traefik|ollama|postgres|redis|qdrant|minio|keycloak|vault|prometheus|grafana" | awk '{print $2}' | xargs -r docker volume rm 2>/dev/null || true

# Clear image cache to force fresh pulls
echo -e "${YELLOW}[*] Clearing Docker build cache (optional, saves time if images cached)...${NC}"
docker builder prune -af 2>/dev/null || true

echo -e "${GREEN}[✓] Cleanup complete!${NC}"
echo ""
echo -e "${YELLOW}[*] Ready to retry installation${NC}"
echo "cd /home/cosmic/HERMES && sudo ./hermis-agent-installer.sh"
