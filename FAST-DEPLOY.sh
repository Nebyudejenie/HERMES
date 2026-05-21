#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HERMIS_ROOT="/opt/hermis"

log_progress() { echo -e "${YELLOW}[→]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  HERMIS AGENT - FAST DEPLOYMENT       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Clean up old setup
log_progress "Cleaning up previous failed attempts..."
cd $HERMIS_ROOT 2>/dev/null || {
    log_error "Directory $HERMIS_ROOT not found"
    exit 1
}

docker compose down -v 2>/dev/null || true
docker ps -a | grep -E "hermis|traefik|ollama|postgres|redis|qdrant|minio|keycloak|vault|prometheus|grafana" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

log_success "Cleanup done"
echo ""

# Pre-pull images sequentially (prevents hangs)
log_progress "Pre-pulling Docker images (sequential mode)..."
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

TOTAL=${#IMAGES[@]}
COUNT=0

for img in "${IMAGES[@]}"; do
    ((COUNT++))
    echo -n "  [$COUNT/$TOTAL] $img ... "

    if docker image inspect "$img" > /dev/null 2>&1; then
        echo -e "${GREEN}CACHED${NC}"
    else
        if timeout 300 docker pull "$img" 2>&1 | grep -E "^Digest:|Downloaded newer|Already exists|Pull complete" | tail -1; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${RED}TIMEOUT${NC}"
            log_error "Failed to pull $img - check network"
            exit 1
        fi
    fi
done

log_success "All images ready"
echo ""

# Start services
log_progress "Starting Docker Compose services..."
docker compose up -d || {
    log_error "Failed to start services"
    docker compose logs --tail=20
    exit 1
}

log_success "Services starting..."
echo ""

# Wait for services
log_progress "Waiting for services to initialize (30 seconds)..."
sleep 30

# Check status
log_progress "Checking service status..."
RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
TOTAL_SERVICES=$(docker compose config --services 2>/dev/null | wc -l)

echo "  Running: $RUNNING / $TOTAL_SERVICES services"
docker compose ps 2>/dev/null | tail -10

echo ""
if [ "$RUNNING" -ge "$((TOTAL_SERVICES - 2))" ]; then
    log_success "Services deployed successfully!"
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  HERMIS AGENT IS READY!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Access URLs:${NC}"
    echo "  Traefik:    http://localhost:8080"
    echo "  OpenWebUI:  http://localhost:3000"
    echo "  Grafana:    http://localhost:3000"
    echo "  Prometheus: http://localhost:9090"
    echo "  Portainer:  http://localhost:9000"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "  1. Check logs:   docker compose logs -f"
    echo "  2. Update .env:  sudo vi /opt/hermis/.env"
    echo "  3. Restart:      docker compose restart"
    echo ""
else
    log_error "Some services failed to start"
    docker compose logs --tail=50
    exit 1
fi
