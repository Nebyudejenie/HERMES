#!/bin/bash
set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}[*] PRE-PULLING DOCKER IMAGES (Sequential)${NC}"
echo -e "${YELLOW}[*] This prevents hangs during docker compose up${NC}"
echo ""

# Array of images needed for Hermis Agent
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

echo -e "${YELLOW}[*] Images to pull: ${#IMAGES[@]}${NC}"
echo ""

PULLED=0
FAILED=0
SKIPPED=0

for img in "${IMAGES[@]}"; do
    echo -n "  [${PULLED}/${#IMAGES[@]}] Pulling $img ... "

    # Check if image already exists
    if docker image inspect "$img" > /dev/null 2>&1; then
        echo -e "${GREEN}CACHED${NC}"
        ((SKIPPED++))
    else
        # Pull with timeout
        if timeout 300 docker pull "$img" > /tmp/docker-pull.log 2>&1; then
            echo -e "${GREEN}OK${NC}"
            ((PULLED++))
        else
            echo -e "${RED}FAILED (timeout or error)${NC}"
            tail -5 /tmp/docker-pull.log | sed 's/^/    /'
            ((FAILED++))
        fi
    fi
done

echo ""
echo -e "${YELLOW}[*] Summary:${NC}"
echo "  Pulled: $PULLED images"
echo "  Cached: $SKIPPED images"
echo "  Failed: $FAILED images"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}[✓] All images ready!${NC}"
    echo ""
    echo -e "${YELLOW}[*] Now run:${NC}"
    echo "  cd /opt/hermis && docker compose up -d"
    exit 0
else
    echo -e "${RED}[✗] Some images failed to pull${NC}"
    echo -e "${YELLOW}[*] Check network connectivity and try again${NC}"
    exit 1
fi
