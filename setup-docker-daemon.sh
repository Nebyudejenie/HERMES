#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[*] Setting up Docker daemon...${NC}"

# Check if docker-ce is installed (official Docker)
if ! dpkg -l | grep -q docker-ce; then
    echo -e "${YELLOW}[*] Installing Docker from official repository...${NC}"

    # Remove docker.io if installed (snap version)
    sudo apt-get remove -y docker.io docker-doc docker-compose 2>/dev/null || true

    # Install official Docker with proper systemd service
    sudo apt-get update -qq

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true

    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin 2>&1 | grep -v "^Get:"
else
    echo -e "${GREEN}[✓] Docker CE already installed${NC}"
fi

# Verify docker.service exists
if [ ! -f /etc/systemd/system/docker.service ]; then
    echo -e "${YELLOW}[*] Creating Docker systemd service file...${NC}"

    # Create docker service file if missing
    sudo tee /etc/systemd/system/docker.service > /dev/null << 'DOCKER_SERVICE'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service containerd.service
Wants=network-online.target containerd.service
Requires=docker.socket

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=mixed
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
DOCKER_SERVICE
fi

# Create docker.socket if missing
if [ ! -f /etc/systemd/system/docker.socket ]; then
    echo -e "${YELLOW}[*] Creating Docker socket systemd file...${NC}"

    sudo tee /etc/systemd/system/docker.socket > /dev/null << 'DOCKER_SOCKET'
[Unit]
Description=Docker Socket
Documentation=https://docs.docker.com

[Socket]
ListenStream=127.0.0.1:2375
ListenStream=/var/run/docker.sock
Accept=false

[Install]
WantedBy=sockets.target
DOCKER_SOCKET
fi

# Ensure Docker daemon directory exists
sudo mkdir -p /etc/docker

# Create daemon config if missing
if [ ! -f /etc/docker/daemon.json ]; then
    echo -e "${YELLOW}[*] Creating Docker daemon configuration...${NC}"

    sudo tee /etc/docker/daemon.json > /dev/null << 'DOCKER_CONFIG'
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
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc"
    }
  },
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
DOCKER_CONFIG
fi

# Reload systemd
echo -e "${YELLOW}[*] Reloading systemd daemon...${NC}"
sudo systemctl daemon-reload

# Enable docker service
echo -e "${YELLOW}[*] Enabling Docker service...${NC}"
sudo systemctl enable docker.service
sudo systemctl enable docker.socket

# Start Docker
echo -e "${YELLOW}[*] Starting Docker daemon...${NC}"
sudo systemctl start docker.socket || {
    echo -e "${RED}[✗] Failed to start docker.socket${NC}"
    exit 1
}

sudo systemctl start docker || {
    echo -e "${RED}[✗] Failed to start docker${NC}"
    systemctl status docker
    exit 1
}

# Wait for Docker to be ready
echo -e "${YELLOW}[*] Waiting for Docker to be ready...${NC}"
sleep 3

# Verify Docker is running
if ! docker ps > /dev/null 2>&1; then
    echo -e "${RED}[✗] Docker is not responding${NC}"
    systemctl status docker
    docker ps 2>&1
    exit 1
fi

echo -e "${GREEN}[✓] Docker daemon is running!${NC}"
docker --version
docker ps

# Create Docker networks
echo -e "${YELLOW}[*] Creating Docker networks...${NC}"
docker network create hermis-internal --driver bridge --subnet 172.19.0.0/16 2>/dev/null || true
docker network create hermis-ai --driver bridge --subnet 172.20.0.0/16 2>/dev/null || true

echo -e "${GREEN}[✓] Docker daemon setup complete!${NC}"
echo -e "${GREEN}[✓] Ready to run Hermis Agent installer${NC}"
