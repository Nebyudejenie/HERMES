#!/bin/bash
# Hermis Agent Control - UP / DOWN / STATUS / RESTART

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

HERMIS_ROOT="/opt/hermis"
COMMAND="${1:-status}"

show_banner() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  HERMIS AGENT CONTROL                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

show_usage() {
    echo -e "${YELLOW}Usage:${NC}"
    echo "  sudo bash hermis-control.sh up       - Start services"
    echo "  sudo bash hermis-control.sh down     - Stop services (preserve data)"
    echo "  sudo bash hermis-control.sh restart  - Restart services"
    echo "  sudo bash hermis-control.sh status   - Show status"
    echo "  sudo bash hermis-control.sh logs     - Show logs"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}✗ Must run with sudo${NC}"
        exit 1
    fi
}

cmd_status() {
    echo -e "${YELLOW}[*] Checking Hermis Agent status...${NC}"
    echo ""

    cd $HERMIS_ROOT 2>/dev/null || {
        echo -e "${RED}✗ $HERMIS_ROOT not found${NC}"
        return 1
    }

    RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    TOTAL=$(docker compose config --services 2>/dev/null | wc -l)

    echo -e "${YELLOW}Services:${NC}"
    docker compose ps 2>/dev/null || echo "No services running"
    echo ""

    echo -e "${YELLOW}Summary:${NC}"
    echo "  Running: $RUNNING / $TOTAL"

    if [ "$RUNNING" -gt 0 ]; then
        echo -e "  Status: ${GREEN}✓ Online${NC}"
    else
        echo -e "  Status: ${RED}✗ Offline${NC}"
    fi
}

cmd_up() {
    echo -e "${YELLOW}[*] Starting Hermis Agent...${NC}"
    echo ""

    cd $HERMIS_ROOT || {
        echo -e "${RED}✗ $HERMIS_ROOT not found${NC}"
        exit 1
    }

    # Check if .env exists
    if [ ! -f .env ]; then
        echo -e "${RED}✗ .env file not found${NC}"
        echo "Run: sudo bash setup-env.sh"
        exit 1
    fi

    echo -e "${YELLOW}[1] Checking Docker...${NC}"
    if ! docker ps > /dev/null 2>&1; then
        echo -e "${RED}✗ Docker not running${NC}"
        systemctl start docker
        sleep 2
    fi

    # WSL fix: ensure Docker daemon has working DNS (containers can't reach
    # the WSL NAT resolver, which breaks image pulls and builds)
    if ! grep -q '"dns"' /etc/docker/daemon.json 2>/dev/null; then
        echo -e "${YELLOW}    Configuring Docker DNS (WSL fix)...${NC}"
        mkdir -p /etc/docker
        echo '{"dns": ["8.8.8.8", "1.1.1.1"]}' > /etc/docker/daemon.json
        systemctl restart docker
        sleep 3
    fi
    echo -e "${GREEN}✓ Docker ready${NC}"
    echo ""

    echo -e "${YELLOW}[2] Starting services...${NC}"
    docker compose up -d 2>&1 | grep -E "^Creating|^Starting|^Running|done" || true
    echo -e "${GREEN}✓ Services starting${NC}"
    echo ""

    echo -e "${YELLOW}[3] Waiting for initialization (20 seconds)...${NC}"
    sleep 20
    echo ""

    echo -e "${YELLOW}[4] Verifying services...${NC}"
    RUNNING=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    TOTAL=$(docker compose config --services 2>/dev/null | wc -l)

    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  HERMIS AGENT STARTED                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Running services: $RUNNING / $TOTAL${NC}"
    docker compose ps | tail -15
    echo ""
    echo -e "${YELLOW}Access:${NC}"
    echo "  • Grafana:    http://localhost:3000"
    echo "  • Portainer:  http://localhost:9000"
    echo "  • Traefik:    http://localhost:8080"
    echo ""
    echo -e "${YELLOW}Monitor:${NC}"
    echo "  docker compose logs -f"
}

cmd_down() {
    echo -e "${YELLOW}[*] Stopping Hermis Agent...${NC}"
    echo ""

    cd $HERMIS_ROOT || {
        echo -e "${RED}✗ $HERMIS_ROOT not found${NC}"
        exit 1
    }

    echo -e "${YELLOW}[1] Stopping services gracefully...${NC}"
    docker compose down 2>&1 | grep -E "^Stopping|down" || true
    echo -e "${GREEN}✓ Services stopped${NC}"
    echo ""

    echo -e "${YELLOW}[2] Verifying shutdown...${NC}"
    sleep 2
    RUNNING=$(docker ps -q 2>/dev/null | wc -l)

    if [ "$RUNNING" -eq 0 ]; then
        echo -e "${GREEN}✓ All services stopped${NC}"
    else
        echo -e "${YELLOW}[!] $RUNNING containers still running${NC}"
    fi
    echo ""

    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  HERMIS AGENT STOPPED                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Data preserved in:${NC}"
    echo "  $HERMIS_ROOT/data/"
    echo ""
    echo -e "${YELLOW}To start again:${NC}"
    echo "  sudo bash hermis-control.sh up"
}

cmd_restart() {
    echo -e "${YELLOW}[*] Restarting Hermis Agent...${NC}"
    echo ""

    cmd_down
    sleep 3
    cmd_up
}

cmd_logs() {
    cd $HERMIS_ROOT || {
        echo -e "${RED}✗ $HERMIS_ROOT not found${NC}"
        exit 1
    }

    echo -e "${YELLOW}[*] Showing logs (Ctrl+C to stop)...${NC}"
    echo ""
    docker compose logs -f
}

# Main
show_banner

case "$COMMAND" in
    up)
        check_root
        cmd_up
        ;;
    down)
        check_root
        cmd_down
        ;;
    restart)
        check_root
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    *)
        show_usage
        cmd_status
        ;;
esac
