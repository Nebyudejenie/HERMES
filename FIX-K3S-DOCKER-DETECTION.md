# 🔧 Fix: K3s vs Docker Runtime Detection

**Status:** ✅ FIXED  
**Date:** 2026-05-21  
**Issue:** Docker daemon not available on K3s Kubernetes nodes  
**Solution:** Added intelligent runtime detection and dual deployment paths

---

## 🐛 The Problem

On K3s Kubernetes systems (like `cosmic@k8s-master`), Docker is not installed because K3s uses containerd as its container runtime. The installer was failing with:

```
Unit docker.service not found
```

This happened because the installer tried to:
1. Start Docker daemon on a system without Docker installed
2. Deploy Docker Compose services when Docker doesn't exist

---

## ✅ What Was Fixed

### Fix 1: Runtime Detection Function

**Added:** `detect_runtime()` function (lines ~360)

```bash
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
```

**Purpose:** Detects which container runtime is available:
- ✅ K3s Kubernetes
- ✅ Docker Engine
- ✅ Neither (error case)

---

### Fix 2: Robust Docker Setup

**Modified:** `setup_docker()` function (lines ~375-440)

**Key Changes:**

1. **K3s Detection:**
```bash
if command -v k3s &> /dev/null || [ -f /etc/systemd/system/k3s.service ] || [ -f /etc/systemd/system/k3s-agent.service ]; then
    log_warning "K3s Kubernetes detected - Docker installation skipped"
    return 0
fi
```

2. **Error Handling:**
```bash
# Installation failures are now non-fatal
DEBIAN_FRONTEND=noninteractive apt-get install -y ... 2>/dev/null || {
    log_warning "Docker installation failed - skipping Docker setup"
    return 0
}
```

3. **Service Startup Error Handling:**
```bash
systemctl restart docker 2>/dev/null || {
    log_warning "Failed to start Docker service - skipping Docker setup"
    return 0
}
```

---

### Fix 3: Smart Service Startup

**Modified:** `start_services()` function (lines ~1060-1110)

**Now Checks:**
1. ✅ Is Docker command available?
2. ✅ If not, is K3s available?
3. ✅ Provides clear guidance on next steps

**New Logic:**
```bash
# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_warning "Docker not found on this system"

    # Check if K3s is available
    if command -v k3s &> /dev/null || [ -f /etc/systemd/system/k3s.service ]; then
        log_warning "K3s Kubernetes detected"
        log_info "Use k3s-installer.sh for Kubernetes deployment:"
        log_info "  cd ${HERMIS_ROOT}"
        log_info "  sudo ./k3s-installer.sh"
        return 1
    fi
    
    log_error "Docker is not installed and K3s not found"
    return 1
fi
```

---

### Fix 4: Enhanced Validation

**Modified:** `validate_installation()` function (lines ~1175-1230)

**Now Detects Runtime and Validates Accordingly:**

```bash
local runtime=$(detect_runtime)

case "$runtime" in
    docker)
        # Validate Docker Compose services
        ;;
    k3s)
        log_success "K3s Kubernetes runtime detected"
        log_info "Use k3s-installer.sh to deploy on Kubernetes"
        ;;
    *)
        log_warning "No container runtime detected"
        ;;
esac
```

---

### Fix 5: K3s-Aware Post-Install

**Modified:** `configure_post_install()` function (lines ~1140-1160)

**Now Skips Docker-Specific Tasks on K3s:**

```bash
if ! command -v docker &> /dev/null; then
    log_warning "Docker not available - skipping Docker-based post-install configuration"
    return 0
fi
```

---

### Fix 6: Graceful Main Flow

**Modified:** `main()` function (lines ~1250-1270)

**Now Offers K3s Alternative if Docker Fails:**

```bash
if ! start_services; then
    if command -v k3s &> /dev/null || [ -f /etc/systemd/system/k3s.service ]; then
        log_warning "Docker services failed to start, but K3s is available"
        log_section "K3S KUBERNETES DEPLOYMENT PATH"
        log_info "Use k3s-installer.sh to deploy Hermis Agent on Kubernetes:"
        return 1
    else
        return 1
    fi
fi
```

---

## 🎯 Deployment Decision Tree

```
┌─ Run: sudo ./hermis-agent-installer.sh
│
├─ Docker available?
│  ├─ YES → Deploy via Docker Compose (16.5GB on 128GB server)
│  │        ✅ Services: 15 containers
│  │        ✅ Models: minimal set (4.5GB)
│  │        ✅ Storage: efficient
│  │
│  └─ NO → K3s available?
│     ├─ YES → Suggest: sudo ./k3s-installer.sh
│     │        ✅ Services: Kubernetes Deployments
│     │        ✅ Models: configurable count
│     │        ✅ Scalable
│     │
│     └─ NO → Error: Install Docker or K3s
└─ End
```

---

## 🚀 Usage

### Docker Systems

```bash
# Regular Ubuntu with Docker
ssh cosmic@192.168.1.28
cd /home/cosmic/HERMES

# Run Docker Compose installer
sudo ./hermis-agent-installer.sh

# Verify services
docker compose ps
```

### K3s Systems

```bash
# K3s Kubernetes node
ssh cosmic@k8s-master
cd /home/cosmic/HERMES

# Run Kubernetes installer
sudo ./k3s-installer.sh

# Verify services
kubectl get deployments -n hermis
kubectl get pods -n hermis
```

---

## 📋 Detection Logic

### Checking for K3s

```bash
# Method 1: K3s command available
command -v k3s &> /dev/null

# Method 2: K3s systemd service (server)
[ -f /etc/systemd/system/k3s.service ]

# Method 3: K3s systemd service (agent)
[ -f /etc/systemd/system/k3s-agent.service ]
```

### Checking for Docker

```bash
# Docker command available
command -v docker &> /dev/null

# Docker daemon running
docker ps > /dev/null 2>&1

# Docker service active
systemctl is-enabled docker > /dev/null 2>&1
```

---

## ✨ Benefits

✅ **Intelligent Detection** - Automatically detects K3s vs Docker  
✅ **Graceful Degradation** - Doesn't crash on missing runtimes  
✅ **Clear Guidance** - Shows exactly what to do next  
✅ **Idempotent** - Safe to run multiple times  
✅ **Flexible** - Works on both Docker and Kubernetes systems  
✅ **No Manual Intervention** - Detects and suggests automatically  

---

## 📊 System Compatibility

| System | Docker | K3s | Installer Behavior |
|--------|--------|-----|-------------------|
| **Ubuntu 24.04 (Docker)** | ✅ Installed | ❌ Not installed | Deploys via Docker Compose |
| **Ubuntu 24.04 (K3s)** | ❌ Not installed | ✅ Installed | Suggests K3s deployment |
| **K3s Master Node** | ❌ Not installed | ✅ Installed | Detects K3s, offers alternative |
| **Mixed Environment** | ✅ Installed | ✅ Installed | Uses Docker (primary path) |

---

## 🔍 Troubleshooting

### Docker Installation Failed

```bash
# Check error
sudo systemctl status docker

# View Docker logs
journalctl -u docker -n 50

# Try manual Docker installation
curl -fsSL https://get.docker.com | sh
```

### K3s Installation Issues

```bash
# Check K3s status
systemctl status k3s

# View K3s logs
journalctl -u k3s -n 50

# Check K3s installation
k3s --version
kubectl get nodes
```

### Detector Not Recognizing Runtime

```bash
# Check for K3s
command -v k3s
ls /etc/systemd/system/k3s*.service

# Check for Docker
command -v docker
docker --version

# Manual detection
docker ps 2>/dev/null && echo "Docker OK" || echo "No Docker"
```

---

## 🎉 Result

✅ **Automatic Runtime Detection** - No manual configuration needed  
✅ **Docker Compose Deployment** - Works on Docker systems  
✅ **Kubernetes Deployment** - Works on K3s systems  
✅ **Clear Error Messages** - Knows what to suggest  
✅ **Graceful Fallbacks** - Doesn't crash on missing runtimes  

---

## 🔄 Deployment Paths

### Path 1: Docker Compose (Recommended for Single Servers)
```bash
sudo ./hermis-agent-installer.sh
# → Docker Compose stack with 15 services
# → Minimal AI models (4.5GB)
# → Efficient for small deployments
```

### Path 2: Kubernetes (Recommended for Clusters)
```bash
sudo ./k3s-installer.sh
# → K3s Kubernetes stack
# → Configurable service replicas
# → Scalable to multiple nodes
```

---

**Ready to deploy!** 🚀

```bash
cd /home/cosmic/HERMES

# For Docker systems:
sudo ./hermis-agent-installer.sh

# For K3s systems:
sudo ./k3s-installer.sh
```

The installer will automatically detect your environment and guide you! ✨
