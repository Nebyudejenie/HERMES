#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[*] EMERGENCY DOCKER FIX - REINSTALLING DAEMON${NC}"

# Stop any running Docker services
echo -e "${YELLOW}[*] Stopping Docker services...${NC}"
systemctl stop docker.service 2>/dev/null || true
systemctl stop docker.socket 2>/dev/null || true

# Remove broken docker-ce
echo -e "${YELLOW}[*] Removing incomplete docker-ce...${NC}"
apt-get remove --purge -y docker-ce 2>&1 | grep -v "^Get:" || true
apt-get clean

# Update package list
echo -e "${YELLOW}[*] Updating package list...${NC}"
apt-get update -qq

# Install docker-ce fresh
echo -e "${YELLOW}[*] Installing docker-ce (with daemon)...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce 2>&1 | tail -20 || {
    echo -e "${RED}[✗] Installation failed${NC}"
    exit 1
}

# Verify dockerd exists
if [ ! -f /usr/bin/dockerd ]; then
    echo -e "${RED}[✗] dockerd still missing after installation${NC}"
    echo "Trying alternative installation method..."
    apt-get install -y docker-ce-rootless-extras docker-buildx-plugin docker-compose-plugin
    exit 1
fi

echo -e "${GREEN}[✓] dockerd found: $(which dockerd)${NC}"

# Verify daemon.json
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
    echo -e "${YELLOW}[*] Creating daemon.json...${NC}"
    cat > /etc/docker/daemon.json << 'EOF'
{
  "debug": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "10",
    "labels": "hermis=true"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ],
  "insecure-registries": [],
  "registry-mirrors": [],
  "live-restore": true,
  "userland-proxy": true,
  "default-cgroupns-mode": "host",
  "icc": false,
  "ip-forward": true,
  "ip-masq": true,
  "default-address-pools": [
    {
      "base": "172.18.0.0/16",
      "size": 24
    }
  ],
  "max-concurrent-downloads": 5,
  "max-concurrent-uploads": 5,
  "metrics-addr": "127.0.0.1:9323",
  "experimental": false,
  "features": {
    "buildkit": true
  }
}
EOF
fi

# Reload systemd
echo -e "${YELLOW}[*] Reloading systemd...${NC}"
systemctl daemon-reload

# Enable services
echo -e "${YELLOW}[*] Enabling Docker services...${NC}"
systemctl enable docker.socket 2>/dev/null || true
systemctl enable docker.service 2>/dev/null || true

# Start services
echo -e "${YELLOW}[*] Starting Docker services...${NC}"
systemctl start docker.socket || {
    echo -e "${RED}[✗] Failed to start docker.socket${NC}"
    systemctl status docker.socket
    exit 1
}

systemctl start docker || {
    echo -e "${RED}[✗] Failed to start docker${NC}"
    systemctl status docker
    journalctl -u docker -n 20
    exit 1
}

# Wait for Docker
echo -e "${YELLOW}[*] Waiting for Docker to be ready...${NC}"
sleep 3

# Test Docker
if ! docker ps > /dev/null 2>&1; then
    echo -e "${RED}[✗] Docker test failed${NC}"
    docker ps 2>&1
    exit 1
fi

echo -e "${GREEN}[✓] Docker is running!${NC}"
docker --version
docker ps

# Create networks
echo -e "${YELLOW}[*] Creating Docker networks...${NC}"
docker network create hermis-internal --driver bridge --subnet 172.19.0.0/16 2>/dev/null || true
docker network create hermis-ai --driver bridge --subnet 172.20.0.0/16 2>/dev/null || true

echo -e "${GREEN}[✓✓✓ DOCKER FIXED! ✓✓✓${NC}"
echo -e "${GREEN}[✓] dockerd is installed and running${NC}"
echo -e "${GREEN}[✓] Ready for Hermis Agent installation${NC}"
echo ""
echo -e "${YELLOW}Now run:${NC}"
echo "cd /home/cosmic/HERMES && sudo ./hermis-agent-installer.sh"
