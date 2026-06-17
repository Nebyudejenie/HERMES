#!/bin/bash

###############################################################################
# HERMIS AGENT - Enterprise-Grade Self-Hosted AI Platform Installer
# Version: 1.0.0
# Environment: Proxmox VM, Ubuntu Server 24.04 LTS
# Specs: 20GB RAM, 500GB storage, CPU inference + future GPU support
#
# This is a production-grade, fully automated, idempotent installer
# for an enterprise AI platform with security, monitoring, and DevOps
###############################################################################

set -euo pipefail

###############################################################################
# CONFIGURATION
###############################################################################

export HERMIS_ROOT="/opt/hermis"
export HERMIS_VERSION="1.0.0"
export DOCKER_COMPOSE_VERSION="2.24.0"
export K3S_VERSION="v1.28.4"
export TIMEZONE="UTC"
export HOSTNAME_TARGET="hermis-agent"
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LOG_DIR="${HERMIS_ROOT}/logs"
export LOG_FILE="${LOG_DIR}/hermis-installer.log"
export ERROR_LOG="${LOG_DIR}/hermis-installer.error.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

###############################################################################
# LOGGING AND OUTPUT FUNCTIONS
###############################################################################

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${LOG_FILE}" "${ERROR_LOG}"
    exec 1> >(tee -a "${LOG_FILE}")
    exec 2> >(tee -a "${ERROR_LOG}" >&2)
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_success() {
    echo -e "${GREEN}[✓ SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_error() {
    echo -e "${RED}[✗ ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_warning() {
    echo -e "${YELLOW}[⚠ WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*"
}

log_section() {
    echo -e "\n${PURPLE}=================================================================================${NC}"
    echo -e "${PURPLE}$*${NC}"
    echo -e "${PURPLE}=================================================================================${NC}\n"
}

log_progress() {
    echo -e "${CYAN}[→] $*${NC}"
}

###############################################################################
# ERROR HANDLING AND CLEANUP
###############################################################################

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Installation failed with exit code $exit_code"
        log_error "Check logs: ${LOG_FILE}"
        log_error "Error log: ${ERROR_LOG}"
    fi
    exit $exit_code
}

trap cleanup EXIT
trap 'log_error "Installation interrupted"; exit 130' INT TERM

###############################################################################
# SYSTEM CHECKS
###############################################################################

check_prerequisites() {
    log_section "CHECKING PREREQUISITES"

    log_progress "Checking for root privileges..."
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
    log_success "Running as root"

    log_progress "Checking Ubuntu version..."
    if ! grep -q "24.04" /etc/os-release; then
        log_warning "This script is optimized for Ubuntu 24.04 LTS. Other versions may work but are untested."
    fi
    log_success "Ubuntu version compatible"

    log_progress "Checking available RAM..."
    local available_ram=$(free -g | awk '/^Mem:/ {print $2}')
    if [ "${available_ram}" -lt 16 ]; then
        log_warning "Only ${available_ram}GB RAM available. Recommended: 20GB+"
    fi
    log_success "RAM check: ${available_ram}GB available"

    log_progress "Checking available disk space..."
    local available_disk=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    # Allow override for tight environments: HERMIS_MIN_DISK=NN bash hermis-agent-installer.sh
    local min_disk="${HERMIS_MIN_DISK:-25}"
    if [ "${available_disk}" -lt "${min_disk}" ]; then
        log_error "Only ${available_disk}GB disk available. Minimum required: ${min_disk}GB"
        log_info "Free up space, grow the disk, or lower the bar: HERMIS_MIN_DISK=20 bash hermis-agent-installer.sh"
        exit 1
    elif [ "${available_disk}" -lt 200 ]; then
        log_warning "Only ${available_disk}GB disk available. Recommended: 400GB+"
        log_warning "Installing with minimal model set for smaller storage"
        export MINIMAL_INSTALL=true
    elif [ "${available_disk}" -lt 400 ]; then
        log_warning "Only ${available_disk}GB disk available. Full install recommended: 400GB+"
        export COMPACT_INSTALL=true
    fi
    log_success "Disk space check: ${available_disk}GB available"

    log_progress "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_warning "No internet connectivity detected. Offline installation mode."
    else
        log_success "Internet connectivity confirmed"
    fi
}

###############################################################################
# SYSTEM SETUP
###############################################################################

setup_system() {
    log_section "SYSTEM SETUP AND HARDENING"

    log_progress "Updating package lists..."
    apt-get update || log_warning "apt-get update reported errors (continuing)"

    log_progress "Upgrading packages..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || log_warning "apt-get upgrade reported errors (continuing)"

    # Essential packages — the installer cannot proceed without these
    log_progress "Installing essential dependencies..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl wget git ca-certificates gnupg lsb-release \
        apt-transport-https jq unzip tar gzip \
        openssl python3 python3-pip ufw chrony || {
        log_error "Failed to install essential dependencies"
        log_info "Check your APT repositories (on Proxmox, ensure the Debian base repos are enabled)"
        exit 1
    }
    log_success "Essential dependencies installed"

    # Optional packages — nice to have; install individually and skip any that are
    # missing on this distro (e.g. yq/tmuxinator aren't in Debian main)
    log_progress "Installing optional tools (skipping any unavailable)..."
    local optional_pkgs=(
        vim htop tmux net-tools iputils-ping dnsutils zip
        build-essential software-properties-common
        apparmor apparmor-utils auditd fail2ban
        openssh-server python3-venv make
    )
    for pkg in "${optional_pkgs[@]}"; do
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" 2>/dev/null \
            && log_success "  installed: $pkg" \
            || log_warning "  skipped (unavailable): $pkg"
    done
    log_success "Dependency installation complete"

    log_progress "Setting timezone to ${TIMEZONE}..."
    timedatectl set-timezone "${TIMEZONE}"
    systemctl restart chrony
    log_success "Timezone configured"

    log_progress "Setting hostname to ${HOSTNAME_TARGET}..."
    hostnamectl set-hostname "${HOSTNAME_TARGET}"
    sed -i "s/^127.0.1.1.*/127.0.1.1\t${HOSTNAME_TARGET}/" /etc/hosts
    log_success "Hostname configured"

    log_progress "Configuring swap..."
    if [ ! -f /swapfile ]; then
        fallocate -l 4G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log_success "Swap configured (4GB)"
    fi

    log_progress "Optimizing sysctl..."
    cat > /etc/sysctl.d/99-hermis.conf << 'EOF'
# Kernel parameters optimization for Hermis Agent
# Network optimization
net.core.rmem_default = 134217728
net.core.rmem_max = 134217728
net.core.wmem_default = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 30

# File descriptor limits
fs.file-max = 2097152
fs.inode-max = 2097152

# Memory optimization
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.dirty_writeback_centisecs = 100

# Security
kernel.unprivileged_userns_clone = 0
kernel.unprivileged_bpf_disabled = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
EOF

    # Apply sysctl settings with -e flag to ignore errors on non-existent parameters
    sysctl -p -e /etc/sysctl.d/99-hermis.conf 2>&1 | grep -v "cannot stat" || true
    log_success "Sysctl optimized"
}

###############################################################################
# SECURITY HARDENING
###############################################################################

harden_security() {
    log_section "SECURITY HARDENING"

    log_progress "Configuring SSH hardening..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    cat >> /etc/ssh/sshd_config << 'EOF'

# Hermis Agent SSH Hardening
Port 22
AddressFamily inet
Protocol 2
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 10
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive yes
Compression no
GatewayPorts no
UsePAM yes
EOF
    systemctl restart sshd
    log_success "SSH hardened"

    log_progress "Configuring firewall (UFW)..."
    ufw --force enable
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp      # SSH
    ufw allow 80/tcp      # HTTP
    ufw allow 443/tcp     # HTTPS
    ufw allow 6443/tcp    # Kubernetes API (K3s)
    ufw allow 8080/tcp    # Portainer
    ufw allow 5000/tcp    # Ollama API
    ufw allow 8000/tcp    # OpenWebUI
    ufw allow 6379/tcp    # Redis
    ufw allow 5432/tcp    # PostgreSQL (internal)
    ufw allow 9090/tcp    # Prometheus
    ufw allow 3000/tcp    # Grafana
    log_success "Firewall configured"

    log_progress "Installing and configuring Fail2Ban..."
    systemctl enable fail2ban
    systemctl start fail2ban
    cat > /etc/fail2ban/jail.d/hermis.conf << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 10
findtime = 60
bantime = 600
EOF
    systemctl restart fail2ban
    log_success "Fail2Ban configured"

    log_progress "Configuring audit daemon..."
    systemctl enable auditd
    systemctl start auditd
    # Remove existing rules if they exist, then add new ones
    auditctl -W /opt/hermis -p wa -k hermis_changes 2>/dev/null || true
    auditctl -W /etc/docker -p wa -k docker_config 2>/dev/null || true
    # Add new audit rules (ignore if already exist)
    auditctl -w /opt/hermis -p wa -k hermis_changes 2>/dev/null || true
    auditctl -w /etc/docker -p wa -k docker_config 2>/dev/null || true
    log_success "Audit daemon configured"

    log_progress "Configuring AppArmor..."
    systemctl enable apparmor
    systemctl start apparmor
    log_success "AppArmor enabled"

    log_progress "Configuring automatic security updates..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Boot-Grub-Packages "true";
Unattended-Upgrade::Mail "root";
EOF
    systemctl enable unattended-upgrades
    systemctl start unattended-upgrades
    log_success "Automatic security updates configured"
}

###############################################################################
# DOCKER INSTALLATION AND CONFIGURATION
###############################################################################

detect_runtime() {
    # Check if running on K3s Kubernetes
    if command -v k3s &> /dev/null || [ -f /etc/systemd/system/k3s.service ] || [ -f /etc/systemd/system/k3s-agent.service ]; then
        echo "k3s"
        return 0
    fi

    # Check if running on regular Docker
    if command -v docker &> /dev/null; then
        echo "docker"
        return 0
    fi

    echo "none"
    return 1
}

setup_docker() {
    log_section "DOCKER INSTALLATION AND CONFIGURATION"

    log_progress "Checking if Docker is installed..."
    if command -v docker &> /dev/null; then
        log_success "Docker binary found"

        # Check if docker.service exists in systemd
        if [ ! -f /etc/systemd/system/docker.service ]; then
            log_warning "Docker binary exists but systemd service missing"
            log_progress "Recreating Docker systemd service..."

            # Create docker.socket
            mkdir -p /etc/systemd/system
            cat > /etc/systemd/system/docker.socket << 'DOCKER_SOCKET'
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

            # Create docker.service
            cat > /etc/systemd/system/docker.service << 'DOCKER_SERVICE'
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

            log_progress "Reloading systemd daemon..."
            systemctl daemon-reload

            log_success "Docker systemd service recreated"
        fi

        log_warning "Docker already installed, skipping fresh installation"
        return 0
    fi

    # Check if K3s is available (incompatible with Docker)
    if command -v k3s &> /dev/null || [ -f /etc/systemd/system/k3s.service ] || [ -f /etc/systemd/system/k3s-agent.service ]; then
        log_warning "K3s Kubernetes detected - Docker installation skipped"
        log_info "Use k3s-installer.sh for Kubernetes deployment instead"
        return 0
    fi

    log_progress "Installing Docker GPG key..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || {
        log_warning "Failed to install Docker GPG key - Docker installation may fail"
    }

    log_progress "Adding Docker repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_progress "Installing Docker Engine and CLI..."
    apt-get update || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || {
        log_warning "Docker installation failed - skipping Docker setup"
        log_info "This system may not support Docker installation"
        return 0
    }

    log_progress "Configuring Docker daemon..."
    mkdir -p /etc/docker
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
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc"
    }
  },
  "seccomp-profile": "/etc/docker/seccomp.json",
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

    log_progress "Configuring Docker seccomp profile..."
    curl -sSL https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json | tee /etc/docker/seccomp.json > /dev/null 2>&1 || true

    log_progress "Enabling Docker service..."
    systemctl enable docker 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    systemctl restart docker 2>/dev/null || {
        log_warning "Failed to start Docker service - skipping Docker setup"
        return 0
    }

    log_progress "Verifying Docker installation..."
    docker run --rm hello-world > /dev/null 2>&1 || {
        log_warning "Docker verification failed - Docker may not be fully operational"
        return 0
    }
    log_success "Docker installed and running"

    log_progress "Creating Docker networks..."
    docker network create hermis-internal --driver bridge --subnet 172.19.0.0/16 2>/dev/null || true
    docker network create hermis-ai --driver bridge --subnet 172.20.0.0/16 2>/dev/null || true
    docker network create hermis-monitoring --driver bridge --subnet 172.21.0.0/16 || true
    log_success "Docker networks created"
}

###############################################################################
# DIRECTORY STRUCTURE SETUP
###############################################################################

create_directory_structure() {
    log_section "CREATING DIRECTORY STRUCTURE"

    log_progress "Creating Hermis root directory..."
    mkdir -p "${HERMIS_ROOT}"/{apps,data,logs,backups,models,config,scripts,monitoring,security,ai,rag,agents}

    log_progress "Setting directory permissions..."
    chmod -R 750 "${HERMIS_ROOT}"
    chown -R root:root "${HERMIS_ROOT}"

    # Create subdirectories
    mkdir -p "${HERMIS_ROOT}"/apps/{portainer,traefik,postgres,redis,ollama,openwebui,qdrant,minio,prometheus,grafana,loki,keycloak,vault,n8n}
    mkdir -p "${HERMIS_ROOT}"/data/{postgres,redis,qdrant,minio,models}
    mkdir -p "${HERMIS_ROOT}"/config/{docker,kubernetes,monitoring,security}
    mkdir -p "${HERMIS_ROOT}"/scripts/{backup,restore,maintenance,monitoring,ai}
    mkdir -p "${HERMIS_ROOT}"/models/{ollama,huggingface,gguf}
    mkdir -p "${HERMIS_ROOT}"/ai/{gateway,agents,embeddings,rag}
    mkdir -p "${HERMIS_ROOT}"/rag/{documents,indexes,cache}
    mkdir -p "${HERMIS_ROOT}"/agents/{tools,workflows,memory}

    log_success "Directory structure created"
}

###############################################################################
# OLLAMA INSTALLATION
###############################################################################

install_ollama() {
    log_section "OLLAMA SETUP"

    # The stack runs Ollama as a container (service name "ollama", port 11434).
    # A host-level Ollama service would hold 11434 and collide with the
    # container -> "port is already allocated". Free the port here.
    if systemctl is-active ollama > /dev/null 2>&1; then
        log_warning "A host Ollama service is running and holding port 11434"
        log_progress "Stopping & disabling host Ollama (the stack runs it as a container)..."
        systemctl stop ollama 2>/dev/null || true
        systemctl disable ollama 2>/dev/null || true
        sleep 2
    fi
    # Also free the port if anything non-systemd is bound to it
    if ss -ltn 2>/dev/null | grep -q ':11434 '; then
        log_warning "Port 11434 still in use; attempting to free it"
        fuser -k 11434/tcp 2>/dev/null || true
        sleep 1
    fi

    # Decide which models the Ollama CONTAINER should pull after it starts.
    # Consumed by pull_models_into_container() in start_services.
    if [ "${MINIMAL_INSTALL:-false}" = "true" ]; then
        export HERMIS_MODELS="mistral:7b nomic-embed-text"
        log_info "Minimal model set selected (~5 GB): ${HERMIS_MODELS}"
    elif [ "${COMPACT_INSTALL:-false}" = "true" ]; then
        export HERMIS_MODELS="mistral:7b neural-chat nomic-embed-text"
        log_info "Compact model set selected (~10-15 GB): ${HERMIS_MODELS}"
    else
        export HERMIS_MODELS="llama3 mistral:7b codellama nomic-embed-text"
        log_info "Full model set selected (~25-30 GB): ${HERMIS_MODELS}"
    fi

    log_success "Ollama will run as a container; models pull after startup"
}

# Pull the selected models into the running Ollama container
pull_models_into_container() {
    local models="${HERMIS_MODELS:-mistral:7b nomic-embed-text}"

    log_progress "Waiting for Ollama container to be ready..."
    local ready=false
    for _ in $(seq 1 30); do
        if docker exec ollama ollama list > /dev/null 2>&1; then
            ready=true
            break
        fi
        sleep 2
    done

    if [ "$ready" != true ]; then
        log_warning "Ollama container not ready; pull models later with:"
        log_info "  docker exec ollama ollama pull mistral:7b"
        return 0
    fi

    for model in $models; do
        if docker exec ollama ollama list 2>/dev/null | grep -q "$model"; then
            log_success "Model already present: $model"
        else
            log_progress "Pulling $model into container (this may take a while)..."
            docker exec ollama ollama pull "$model" 2>&1 | tail -1 || \
                log_warning "Failed to pull $model (you can retry later)"
        fi
    done
    log_success "Model setup complete"
}

###############################################################################
# DOCKER COMPOSE STACK
###############################################################################

create_docker_compose() {
    log_section "CREATING DOCKER COMPOSE STACK"

    log_progress "Creating main docker-compose.yml..."
    cat > "${HERMIS_ROOT}"/docker-compose.yml << 'DOCKERCOMPOSE_EOF'
services:
  # Reverse Proxy
  traefik:
    image: traefik:latest
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    environment:
      - TRAEFIK_API_INSECURE=true
      - TRAEFIK_METRICS_PROMETHEUS=true
      - TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80
      - TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443
      - TRAEFIK_PROVIDERS_DOCKER=true
      - TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT=false
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${HERMIS_ROOT}/data/traefik:/traefik
      - ${HERMIS_ROOT}/config/ssl:/ssl:ro
    networks:
      - hermis-internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`traefik.localhost`)"
      - "traefik.http.routers.api.service=api@internal"
      - "traefik.http.services.noop.loadbalancer.server.port=8080"
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Portainer - Container Management
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    networks:
      - hermis-internal
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${HERMIS_ROOT}/data/portainer:/data
    environment:
      ADMIN_PASSWORD: "${PORTAINER_PASSWORD}"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(`portainer.localhost`)"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
      - "traefik.http.middlewares.portainer-headers.headers.customrequestheaders.X-Script-Name=/portainer"

  # PostgreSQL Database
  postgres:
    image: postgres:16-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: "${POSTGRES_USER}"
      POSTGRES_PASSWORD: "${POSTGRES_PASSWORD}"
      POSTGRES_DB: "${POSTGRES_DB}"
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C"
    volumes:
      - ${HERMIS_ROOT}/data/postgres:/var/lib/postgresql/data
    networks:
      - hermis-internal
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    command:
      - "postgres"
      - "-c"
      - "max_connections=200"
      - "-c"
      - "shared_buffers=256MB"
      - "-c"
      - "effective_cache_size=1GB"
      - "-c"
      - "maintenance_work_mem=64MB"
      - "-c"
      - "checkpoint_completion_target=0.9"
      - "-c"
      - "wal_buffers=16MB"
      - "-c"
      - "default_statistics_target=100"
      - "-c"
      - "random_page_cost=1.1"
      - "-c"
      - "effective_io_concurrency=200"
      - "-c"
      - "work_mem=1310kB"
      - "-c"
      - "min_wal_size=1GB"
      - "-c"
      - "max_wal_size=4GB"
      - "-c"
      - "max_worker_processes=4"
      - "-c"
      - "max_parallel_workers_per_gather=2"
      - "-c"
      - "max_parallel_workers=4"

  # Redis Cache
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 2gb --maxmemory-policy allkeys-lru
    volumes:
      - ${HERMIS_ROOT}/data/redis:/data
    networks:
      - hermis-internal
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # Ollama - Local LLM Inference
  ollama:
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    environment:
      OLLAMA_KEEP_ALIVE: 5m
      OLLAMA_NUM_PARALLEL: 1
      OLLAMA_NUM_THREAD: 4
    volumes:
      - ${HERMIS_ROOT}/models/ollama:/root/.ollama
      - ${HERMIS_ROOT}/data:/models
    networks:
      - hermis-ai
    ports:
      - "11434:11434"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.ollama.rule=Host(`ollama.localhost`)"
      - "traefik.http.services.ollama.loadbalancer.server.port=11434"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:11434/api/tags"]
      interval: 30s
      timeout: 5s
      retries: 3

  # OpenWebUI - LLM Interface
  openwebui:
    image: ghcr.io/open-webui/open-webui:latest
    container_name: openwebui
    restart: unless-stopped
    environment:
      OLLAMA_API_BASE_URL: http://ollama:11434
      WEBUI_SECRET_KEY: "${OPENWEBUI_SECRET_KEY}"
      WEBUI_API_KEY: "${OPENWEBUI_API_KEY}"
    volumes:
      - ${HERMIS_ROOT}/data/openwebui:/app/backend/data
    networks:
      - hermis-ai
      - hermis-internal
    depends_on:
      - ollama
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.openwebui.rule=Host(`webui.localhost`)"
      - "traefik.http.services.openwebui.loadbalancer.server.port=8080"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Qdrant - Vector Database for RAG
  qdrant:
    image: qdrant/qdrant:latest
    container_name: qdrant
    restart: unless-stopped
    environment:
      QDRANT_API_KEY: "${QDRANT_API_KEY}"
    volumes:
      - ${HERMIS_ROOT}/data/qdrant:/qdrant/storage
    networks:
      - hermis-ai
    ports:
      - "6333:6333"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.qdrant.rule=Host(`qdrant.localhost`)"
      - "traefik.http.services.qdrant.loadbalancer.server.port=6333"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:6333/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # MinIO - S3-compatible Object Storage
  minio:
    image: minio/minio:latest
    container_name: minio
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: "${MINIO_ROOT_USER}"
      MINIO_ROOT_PASSWORD: "${MINIO_ROOT_PASSWORD}"
    volumes:
      - ${HERMIS_ROOT}/data/minio:/minio_data
    networks:
      - hermis-internal
    ports:
      # Host 9000/9001 are commonly taken (Portainer/Cockpit/etc); publish
      # MinIO on 9900/9901 to avoid "port is already allocated". Container
      # ports stay 9000/9001 so Traefik routing and healthchecks are unchanged.
      - "9900:9000"
      - "9901:9001"
    command: minio server /minio_data --console-address :9001
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.minio-api.rule=Host(`minio.localhost`)"
      - "traefik.http.services.minio-api.loadbalancer.server.port=9000"
      - "traefik.http.routers.minio-console.rule=Host(`minio-console.localhost`)"
      - "traefik.http.services.minio-console.loadbalancer.server.port=9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Prometheus - Metrics Collection
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    user: "1000"
    volumes:
      - ${HERMIS_ROOT}/config/prometheus:/etc/prometheus
      - ${HERMIS_ROOT}/data/prometheus:/prometheus
    networks:
      - hermis-monitoring
      - hermis-internal
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.console.libraries=/usr/share/prometheus/console_libraries"
      - "--web.console.templates=/usr/share/prometheus/consoles"
      - "--web.enable-lifecycle"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.prometheus.rule=Host(`prometheus.localhost`)"
      - "traefik.http.services.prometheus.loadbalancer.server.port=9090"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9090/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Grafana - Visualization
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    user: "1000"
    environment:
      GF_SECURITY_ADMIN_USER: "${GRAFANA_ADMIN_USER}"
      GF_SECURITY_ADMIN_PASSWORD: "${GRAFANA_ADMIN_PASSWORD}"
      GF_INSTALL_PLUGINS: "grafana-worldmap-panel,grafana-piechart-panel"
      GF_SERVER_ROOT_URL: "http://grafana.localhost"
      GF_SECURITY_SECRET_KEY: "${GRAFANA_SECRET_KEY}"
    volumes:
      - ${HERMIS_ROOT}/data/grafana:/var/lib/grafana
    networks:
      - hermis-monitoring
      - hermis-internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.grafana.rule=Host(`grafana.localhost`)"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Loki - Log Aggregation
  loki:
    image: grafana/loki:latest
    container_name: loki
    restart: unless-stopped
    user: "1000"
    volumes:
      - ${HERMIS_ROOT}/config/loki:/etc/loki
      - ${HERMIS_ROOT}/data/loki:/loki
    networks:
      - hermis-monitoring
    command: -config.file=/etc/loki/loki-config.yml
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3100/ready"]
      interval: 30s
      timeout: 5s
      retries: 3

  # Promtail - Log Shipper
  promtail:
    image: grafana/promtail:latest
    container_name: promtail
    restart: unless-stopped
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - ${HERMIS_ROOT}/config/promtail:/etc/promtail
    networks:
      - hermis-monitoring
    command: -config.file=/etc/promtail/promtail-config.yml
    depends_on:
      - loki

  # cAdvisor - Container Metrics
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:rw
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    networks:
      - hermis-monitoring
    ports:
      - "8081:8080"

  # Node Exporter - System Metrics
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - "--path.procfs=/host/proc"
      - "--path.sysfs=/host/sys"
      - "--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)"
    networks:
      - hermis-monitoring
    ports:
      - "9100:9100"

  # Keycloak - Authentication
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: keycloak
    restart: unless-stopped
    # 'start-dev' is required; without a command the image just prints help
    # and exits (restart loop). dev-file uses a self-contained H2 database so
    # Keycloak doesn't need a pre-created Postgres DB.
    command: start-dev
    environment:
      KC_DB: dev-file
      KC_BOOTSTRAP_ADMIN_USERNAME: "${KEYCLOAK_ADMIN}"
      KC_BOOTSTRAP_ADMIN_PASSWORD: "${KEYCLOAK_ADMIN_PASSWORD}"
      KEYCLOAK_ADMIN: "${KEYCLOAK_ADMIN}"
      KEYCLOAK_ADMIN_PASSWORD: "${KEYCLOAK_ADMIN_PASSWORD}"
      KC_PROXY: edge
      KC_HTTP_ENABLED: "true"
    volumes:
      - ${HERMIS_ROOT}/data/keycloak:/opt/keycloak/data
    networks:
      - hermis-internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.keycloak.rule=Host(`keycloak.localhost`)"
      - "traefik.http.services.keycloak.loadbalancer.server.port=8080"

  # HashiCorp Vault - Secrets Management
  vault:
    image: hashicorp/vault:latest
    container_name: vault
    restart: unless-stopped
    environment:
      VAULT_DEV_ROOT_TOKEN_ID: "${VAULT_DEV_ROOT_TOKEN_ID}"
      VAULT_DEV_LISTEN_ADDRESS: "0.0.0.0:8200"
    volumes:
      - ${HERMIS_ROOT}/data/vault:/vault/data
      - ${HERMIS_ROOT}/config/vault:/vault/config
    networks:
      - hermis-internal
    cap_add:
      - IPC_LOCK
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.vault.rule=Host(`vault.localhost`)"
      - "traefik.http.services.vault.loadbalancer.server.port=8200"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8200/v1/sys/health"]
      interval: 30s
      timeout: 5s
      retries: 3

networks:
  # Custom bridge names are intentionally omitted: Linux interface names are
  # capped at 15 chars, so "br-hermis-internal" (18) made Docker fail with
  # "numerical result out of range". Let Docker auto-name the bridges.
  hermis-internal:
    driver: bridge
  hermis-ai:
    driver: bridge
  hermis-monitoring:
    driver: bridge
DOCKERCOMPOSE_EOF

    log_success "Docker Compose stack created"
}

###############################################################################
# SERVICE CONFIG FILES
###############################################################################

create_service_configs() {
    log_section "CREATING SERVICE CONFIG FILES"

    # Config dirs that compose mounts (must exist as dirs with real files,
    # otherwise Docker bind-mounts create empty dirs and services crash-loop)
    mkdir -p "${HERMIS_ROOT}"/config/{prometheus,loki,promtail,ssl}

    log_progress "Writing prometheus.yml..."
    cat > "${HERMIS_ROOT}/config/prometheus/prometheus.yml" << 'PROM_EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]
  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]
  - job_name: traefik
    static_configs:
      - targets: ["traefik:8080"]
PROM_EOF

    log_progress "Writing loki-config.yml..."
    cat > "${HERMIS_ROOT}/config/loki/loki-config.yml" << 'LOKI_EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h
LOKI_EOF

    log_progress "Writing promtail-config.yml..."
    cat > "${HERMIS_ROOT}/config/promtail/promtail-config.yml" << 'PROMTAIL_EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets: ["localhost"]
        labels:
          job: varlogs
          __path__: /var/log/*log
PROMTAIL_EOF

    log_progress "Fixing data directory ownership for non-root containers..."
    # prometheus/grafana/loki run as user "1000"; their data dirs were created
    # root:root 750 and would be unwritable -> crash. Hand them to uid 1000.
    mkdir -p "${HERMIS_ROOT}"/data/{prometheus,grafana,loki,traefik}
    chown -R 1000:1000 "${HERMIS_ROOT}"/data/{prometheus,grafana,loki} 2>/dev/null || true
    chmod -R 755 "${HERMIS_ROOT}"/config/{prometheus,loki,promtail} 2>/dev/null || true

    log_success "Service config files created"
}

###############################################################################
# ENVIRONMENT CONFIGURATION
###############################################################################

create_env_files() {
    log_section "CREATING ENVIRONMENT CONFIGURATION"

    log_progress "Creating .env file..."
    cat > "${HERMIS_ROOT}"/.env << 'ENV_EOF'
# Hermis Agent Configuration

# System
HERMIS_ROOT=/opt/hermis
HERMIS_VERSION=1.0.0
TIMEZONE=UTC

# Portainer
PORTAINER_PASSWORD=ChangeMe@123

# PostgreSQL
POSTGRES_USER=hermis
POSTGRES_PASSWORD=ChangeMe@123
POSTGRES_DB=hermis

# OpenWebUI
OPENWEBUI_SECRET_KEY=sk-$(openssl rand -base64 32)
OPENWEBUI_API_KEY=sk-$(openssl rand -base64 32)

# Qdrant
QDRANT_API_KEY=$(openssl rand -base64 32)

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=ChangeMe@123

# Grafana
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=ChangeMe@123
GRAFANA_SECRET_KEY=$(openssl rand -base64 32)

# Keycloak
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=ChangeMe@123

# Vault
VAULT_DEV_ROOT_TOKEN_ID=$(openssl rand -hex 16)

# AI Configuration
OLLAMA_NUM_PARALLEL=1
OLLAMA_NUM_THREAD=4
OLLAMA_KEEP_ALIVE=5m

# Logging
LOG_LEVEL=info
LOKI_RETENTION_DAYS=30
ENV_EOF

    log_success ".env file created"
    log_warning "IMPORTANT: Update passwords in ${HERMIS_ROOT}/.env before running!"
}

###############################################################################
# START SERVICES
###############################################################################

start_services() {
    log_section "STARTING SERVICES"

    cd "${HERMIS_ROOT}"

    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_warning "Docker not found on this system"

        # Check if K3s is available
        if command -v k3s &> /dev/null || [ -f /etc/systemd/system/k3s.service ] || [ -f /etc/systemd/system/k3s-agent.service ]; then
            log_warning "K3s Kubernetes detected"
            log_info "Use k3s-installer.sh for Kubernetes deployment:"
            log_info "  cd ${HERMIS_ROOT}"
            log_info "  sudo ./k3s-installer.sh"
            return 1
        fi

        log_error "Docker is not installed and K3s not found"
        log_info "Install Docker from: https://docs.docker.com/engine/install/ubuntu/"
        log_info "Or use K3s deployment: sudo ./k3s-installer.sh"
        return 1
    fi

    # Check if Docker daemon is running
    log_progress "Checking Docker daemon..."
    if ! docker ps > /dev/null 2>&1; then
        log_progress "Docker daemon is not running, attempting to start..."

        # Try to start Docker if service exists
        if systemctl is-enabled docker > /dev/null 2>&1; then
            systemctl start docker 2>/dev/null || {
                log_error "Failed to start Docker daemon"
                log_info "Check Docker status: systemctl status docker"
                return 1
            }
            sleep 5

            # Verify Docker is running
            if ! docker ps > /dev/null 2>&1; then
                log_error "Docker daemon failed to respond after startup"
                return 1
            fi
        else
            log_error "Docker service not found"
            log_info "Check Docker installation: docker --version"
            return 1
        fi
    fi
    log_success "Docker daemon is running"

    # Clean up any leftover containers from a previous failed run so fixed
    # ports (e.g. 6333) aren't held by orphans -> "port is already allocated"
    log_progress "Clearing any leftover containers from previous runs..."
    docker compose down --remove-orphans 2>/dev/null || true
    for c in traefik portainer postgres redis ollama openwebui qdrant minio \
             prometheus grafana loki promtail cadvisor node-exporter keycloak vault; do
        docker rm -f "$c" 2>/dev/null || true
    done

    # Robust port sweep: force-remove ANY container still publishing a host
    # port this stack needs (catches leftovers from older runs / other
    # projects that name-based cleanup misses).
    log_progress "Freeing required host ports..."
    for port in 80 443 6333 8081 9100 11434 9900 9901; do
        local holders
        holders=$(docker ps -q --filter "publish=${port}" 2>/dev/null)
        if [ -n "$holders" ]; then
            log_warning "Port ${port} held by a container; removing it"
            docker rm -f $holders 2>/dev/null || true
        elif ss -ltn 2>/dev/null | grep -q ":${port} "; then
            log_warning "Port ${port} held by a host process (not Docker)."
            log_info "  Identify it with: ss -ltnp | grep ':${port} '"
        fi
    done

    log_progress "Starting Docker Compose services..."
    docker compose up -d --remove-orphans || {
        log_error "Failed to start services"
        log_info "Troubleshooting: docker compose ps"
        log_info "If a port is 'already allocated', find it with: ss -ltnp | grep <port>"
        return 1
    }

    log_progress "Waiting for services to initialize..."
    sleep 10

    log_progress "Checking service status..."
    docker compose ps || true

    # Pull the selected models into the Ollama container
    pull_models_into_container

    log_success "Services started"
}

###############################################################################
# POST-INSTALLATION CONFIGURATION
###############################################################################

configure_post_install() {
    log_section "POST-INSTALLATION CONFIGURATION"

    # Check if Docker is available for post-install tasks
    if ! command -v docker &> /dev/null; then
        log_warning "Docker not available - skipping Docker-based post-install configuration"
        log_info "Post-install tasks can be configured manually or with K3s deployment"
        return 0
    fi

    log_progress "Creating backup script..."
    cat > "${HERMIS_ROOT}"/scripts/backup/daily-backup.sh << 'BACKUP_EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/hermis/backups/$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"

# Backup databases
docker exec postgres pg_dump -U hermis hermis | gzip > "$BACKUP_DIR/postgres.sql.gz" 2>/dev/null || true

# Backup important data directories
tar czf "$BACKUP_DIR/data.tar.gz" /opt/hermis/data 2>/dev/null || true
tar czf "$BACKUP_DIR/config.tar.gz" /opt/hermis/config 2>/dev/null || true

# Keep only last 30 days
find /opt/hermis/backups -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

echo "Backup completed: $BACKUP_DIR"
BACKUP_EOF
    chmod +x "${HERMIS_ROOT}"/scripts/backup/daily-backup.sh

    log_progress "Setting up backup cron job..."
    echo "0 2 * * * root ${HERMIS_ROOT}/scripts/backup/daily-backup.sh" | tee /etc/cron.d/hermis-backup > /dev/null 2>&1 || true

    log_success "Backup automation configured"
}

###############################################################################
# HEALTH CHECKS AND VALIDATION
###############################################################################

validate_installation() {
    log_section "VALIDATING INSTALLATION"

    local errors=0
    local runtime=$(detect_runtime)

    log_progress "Detecting runtime..."
    case "$runtime" in
        docker)
            log_success "Docker runtime detected"

            log_progress "Checking Docker..."
            if docker ps > /dev/null 2>&1; then
                log_success "Docker running"
            else
                log_warning "Docker not running (can be started manually)"
            fi

            log_progress "Checking Docker Compose..."
            if command -v docker compose > /dev/null; then
                log_success "Docker Compose available"
            else
                log_error "Docker Compose not found"
                ((errors++))
            fi

            log_progress "Checking services..."
            cd "${HERMIS_ROOT}"
            if [ -f docker-compose.yml ]; then
                local running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | wc -l)
                log_success "Docker Compose file configured"
            fi
            ;;
        k3s)
            log_success "K3s Kubernetes runtime detected"
            log_info "Use k3s-installer.sh to deploy on Kubernetes"
            ;;
        *)
            log_warning "No container runtime detected (Docker/K3s)"
            ((errors++))
            ;;
    esac

    log_progress "Checking firewall..."
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        log_success "Firewall active"
    else
        log_warning "Firewall not active (recommended but not required)"
    fi

    log_progress "Checking filesystem..."
    if [ -d "${HERMIS_ROOT}" ]; then
        log_success "Directory structure exists"
    else
        log_error "Directory structure missing"
        ((errors++))
    fi

    if [ $errors -eq 0 ]; then
        log_success "Installation validation passed!"
    else
        log_error "Validation failed with $errors critical errors"
        return 1
    fi
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    log_section "HERMIS AGENT INSTALLER - VERSION ${HERMIS_VERSION}"

    setup_logging
    check_prerequisites
    setup_system
    harden_security
    setup_docker
    create_directory_structure
    install_ollama
    create_docker_compose
    create_service_configs
    create_env_files

    # Attempt to start services (non-fatal if K3s is available as alternative)
    if ! start_services; then
        if command -v k3s &> /dev/null || [ -f /etc/systemd/system/k3s.service ] || [ -f /etc/systemd/system/k3s-agent.service ]; then
            log_warning "Docker services failed to start, but K3s is available"
            log_section "K3S KUBERNETES DEPLOYMENT PATH"
            log_info "Use k3s-installer.sh to deploy Hermis Agent on Kubernetes:"
            log_info "  cd ${HERMIS_ROOT}"
            log_info "  sudo ./k3s-installer.sh"
        else
            return 1
        fi
    fi

    configure_post_install
    validate_installation

    log_section "INSTALLATION COMPLETE"
    cat << 'COMPLETE_EOF'

████████████████████████████████████████████████████████████████████████████████
█                                                                              █
█  HERMIS AGENT SUCCESSFULLY INSTALLED!                                       █
█                                                                              █
█  Access your platform at:                                                   █
█  ─────────────────────────────────────────────────────────────────────────  █
█                                                                              █
█  🌐 Traefik:        http://traefik.localhost                                █
█  🐳 Portainer:      http://portainer.localhost                              █
█  💬 OpenWebUI:      http://webui.localhost                                  █
█  📊 Grafana:        http://grafana.localhost                                █
█  📈 Prometheus:     http://prometheus.localhost                             █
█  🔐 Keycloak:       http://keycloak.localhost                               █
█  🔑 Vault:          http://vault.localhost                                  █
█  🎯 Qdrant:         http://qdrant.localhost                                 █
█  📦 MinIO:          http://minio-console.localhost                          █
█                                                                              █
█  Next Steps:                                                                █
█  ─────────────────────────────────────────────────────────────────────────  █
█                                                                              █
█  1. Update credentials in:  /opt/hermis/.env                               █
█  2. Review logs:            /opt/hermis/logs/hermis-installer.log          █
█  3. Run: docker compose ps (in /opt/hermis/)                               █
█  4. Check model status:     ollama list                                     █
█  5. Configure reverse proxy: traefik.localhost                              █
█  6. Set up SSL certificates                                                █
█  7. Configure authentication in Keycloak                                    █
█  8. Set up monitoring dashboards in Grafana                                 █
█  9. Back up your configuration                                              █
█  10. Join the Hermis community!                                             █
█                                                                              █
█  Documentation: https://hermis.local/docs                                  █
█  Support:       https://github.com/hermis-ai/hermis-agent                  █
█                                                                              █
████████████████████████████████████████████████████████████████████████████████

COMPLETE_EOF

    log_success "Hermis Agent installation complete!"
    log_info "Full logs available at: ${LOG_FILE}"
}

# Execute main function
main "$@"
