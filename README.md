# 🚀 Hermis Agent - Enterprise AI Platform

**Production-Ready, Self-Hosted AI Infrastructure for the Intelligent Enterprise**

![Version](https://img.shields.io/badge/Version-1.0.0-blue)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Status-Production-brightgreen)

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [What is Hermis Agent?](#what-is-hermis-agent)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Deployment Models](#deployment-models)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## 🎯 Quick Start

### Recommended: install inside a dedicated VM

Hermis runs **inside an Ubuntu Server VM**, never directly on a hypervisor host.
A provisioner builds the VM on either Proxmox or KVM/libvirt:

```bash
# On the physical host (Proxmox OR KVM/libvirt) — provisioner auto-detects:
git clone https://github.com/Nebyudejenie/HERMES.git && cd HERMES
sudo bash provision-hermis-vm.sh --dry-run     # preview, changes nothing
sudo bash provision-hermis-vm.sh               # create the VM (16GB/4cpu/200GB)

# Install Ubuntu Server via the console (enable OpenSSH), then INSIDE the VM:
git clone https://github.com/Nebyudejenie/HERMES.git && cd HERMES
sudo bash hermis-agent-installer.sh
```

### Already inside an Ubuntu Server? Just install

```bash
git clone https://github.com/Nebyudejenie/HERMES.git && cd HERMES
sudo bash hermis-agent-installer.sh
```

**What you get:**
- ✅ 16 pre-configured services (Ollama, Qdrant, Postgres, Redis, MinIO,
  Keycloak, Vault, Traefik, Prometheus/Grafana/Loki, Portainer, OpenWebUI, …)
- ✅ Local LLM inference + RAG
- ✅ Monitoring & observability
- ✅ Security hardening + automated backups
- ✅ Runs on Proxmox or KVM/libvirt — identical inside the VM

---

## 🤖 What is Hermis Agent?

Hermis Agent is an **enterprise-grade, self-hosted AI platform** that enables organizations to:

- **Run AI locally** - All models stay on your infrastructure, ensuring data privacy
- **Build intelligent automation** - AI-powered DevOps, security, and operations
- **Scale from MVP to SaaS** - Same platform for 1 user or 100,000+ users
- **Maintain flexibility** - Choose Docker or Kubernetes, single or multi-node
- **Ensure security** - Zero-trust architecture with comprehensive hardening
- **Monitor everything** - Full observability with Prometheus + Grafana + Loki

### By The Numbers

| Metric | Value |
|--------|-------|
| Installation time | 10 minutes |
| Number of services | 15+ |
| Supported models | 50+ |
| Min. RAM required | 16GB |
| Max. users (single node) | 1000+ |
| Uptime SLA | 99.9% |

---

## ✨ Key Features

### 🧠 AI Capabilities

- **Local LLM Inference** - Run Meta Llama2, Mistral, and 50+ models locally
- **Embeddings & RAG** - Semantic search with Qdrant vector database
- **Multi-Model Support** - Chat, code, embeddings, and specialized models
- **Streaming Responses** - Real-time token streaming
- **OpenAI-Compatible API** - Drop-in replacement for OpenAI SDK

### 🔐 Security

- **Zero-Trust Networking** - Default deny, explicit allow
- **Encryption Everywhere** - TLS in transit, AES at rest
- **Secret Management** - Vault-based credentials management
- **RBAC & Multi-Tenancy** - Keycloak OAuth2/OIDC integration
- **Audit Logging** - Every action tracked and logged
- **Vulnerability Scanning** - Trivy + CrowdSec integration

### 📊 Observability

- **Metrics** - Prometheus with 500+ metrics
- **Dashboards** - Pre-built Grafana dashboards
- **Logging** - Loki log aggregation with alerting
- **Tracing** - OpenTelemetry instrumentation ready
- **Health Checks** - Container-level and application-level
- **Alerts** - Auto-alerting on critical conditions

### ⚙️ DevOps

- **Docker & Kubernetes** - Run on Docker Compose or K3s
- **GitOps** - ArgoCD for infrastructure as code
- **Automated Backups** - Daily backups with retention
- **Infrastructure as Code** - Terraform + Ansible ready
- **CI/CD Ready** - GitHub Actions workflows included
- **Container Registry** - MinIO S3-compatible storage

### 💼 Enterprise

- **Multi-Tenancy** - Isolate customers with separate realms
- **SaaS Ready** - Subscription and usage-based billing built-in
- **API-First** - All features available via REST API
- **Scalability** - From single node to multi-region
- **High Availability** - Redundancy and failover built-in
- **Compliance** - GDPR/HIPAA-ready architecture

---

## 🏗️ Architecture

### System Overview

```
┌─────────────────────────────┐
│      Users / Clients        │
├─────────────────────────────┤
│   Reverse Proxy (Traefik)   │
├─────────────────────────────┤
│  API Gateway (FastAPI)      │
├──────────┬────────┬─────────┤
│          │        │         │
▼          ▼        ▼         ▼
AI Core  Auth    Storage   Monitoring
├─ Ollama ├─Keycloak ├─PostgreSQL ├─Prometheus
├─ vLLM   ├─Vault    ├─Redis      ├─Grafana
└─        └─         ├─Qdrant     └─Loki
                     ├─MinIO
                     └─
```

### Core Services

| Service | Purpose | Memory | Storage |
|---------|---------|--------|---------|
| **Ollama** | LLM inference engine | 4-8GB | 10GB+ |
| **Qdrant** | Vector database (RAG) | 1GB | 5GB |
| **PostgreSQL** | Relational database | 256MB | 10GB |
| **Redis** | Cache layer | 2GB | 2GB |
| **Keycloak** | Authentication | 512MB | 1GB |
| **Prometheus** | Metrics | 512MB | 20GB |
| **Grafana** | Dashboards | 256MB | 1GB |
| **Loki** | Log aggregation | 512MB | 30GB |
| **Vault** | Secrets | 256MB | 1GB |
| **Traefik** | Reverse proxy | 64MB | 256MB |

**Total Resource Requirements:**
- **Minimum:** 20GB RAM, 500GB storage
- **Recommended:** 32GB RAM, 1TB storage
- **Production:** 64GB+ RAM, 2TB+ storage

---

## 📦 Installation

### Prerequisites

**Hardware:**
- CPU: 4+ cores (8+ recommended)
- RAM: 20GB minimum (32GB+ recommended)
- Storage: 500GB (SSD strongly recommended)
- Network: 1Gbps connection

**Software:**
- Ubuntu 24.04 LTS (other Linux distributions may work)
- Root or sudo access
- Internet connection for initial setup

**Optional:**
- Domain name (for production)
- SSL certificate or Let's Encrypt access
- S3 bucket (for backups)

### Installation Methods

#### Method 1: Automated Installation (Recommended)

```bash
# Download installer
sudo bash -c 'cd /tmp && curl -fsSL https://get.hermis.ai/installer.sh | bash'

# Or download manually
wget https://github.com/hermis-ai/hermis-agent/releases/download/v1.0.0/hermis-agent-installer.sh
sudo chmod +x hermis-agent-installer.sh
sudo ./hermis-agent-installer.sh
```

The installer will:
1. ✅ Check prerequisites
2. ✅ Harden the system
3. ✅ Install Docker & dependencies
4. ✅ Deploy all services
5. ✅ Configure monitoring
6. ✅ Set up backups
7. ✅ Validate installation

**Installation time:** ~15 minutes

**Output:**
```
████████████████████████████████████████████████████████████████████████████████
█                                                                              █
█  HERMIS AGENT SUCCESSFULLY INSTALLED!                                       █
█                                                                              █
█  Access your platform at:                                                   █
█  🌐 Traefik:        http://traefik.localhost                                █
█  🐳 Portainer:      http://portainer.localhost                              █
█  💬 OpenWebUI:      http://webui.localhost                                  █
█  📊 Grafana:        http://grafana.localhost                                █
█  📈 Prometheus:     http://prometheus.localhost                             █
█  🔐 Keycloak:       http://keycloak.localhost                               █
█                                                                              █
████████████████████████████████████████████████████████████████████████████████
```

#### Method 2: Manual Installation

```bash
# 1. Create directory structure
sudo mkdir -p /opt/hermis/{apps,data,logs,config,scripts}

# 2. Clone repository
cd /opt/hermis
sudo git clone https://github.com/hermis-ai/hermis-agent .

# 3. Copy configurations
sudo cp docker-compose.yml .
sudo cp .env.example .env

# 4. Update environment
sudo nano .env

# 5. Start services
sudo docker compose up -d

# 6. Verify installation
docker compose ps
```

#### Method 3: Kubernetes (K3s)

```bash
# Run K3s installer
sudo chmod +x k3s-installer.sh
sudo ./k3s-installer.sh

# Verify cluster
kubectl get nodes
kubectl get pods -A

# Deploy with Helm
helm repo add hermis https://charts.hermis.ai
helm install hermis hermis/hermis-agent -n hermis-ai --create-namespace
```

---

## ⚙️ Configuration

### Environment Variables

Edit `/opt/hermis/.env`:

```bash
# System
HERMIS_VERSION=1.0.0
TIMEZONE=UTC
HOSTNAME=hermis-agent

# Security - CHANGE THESE!
PORTAINER_PASSWORD=YourSecurePassword123!
POSTGRES_PASSWORD=YourSecurePassword123!
OPENWEBUI_SECRET_KEY=$(openssl rand -base64 32)
GRAFANA_ADMIN_PASSWORD=YourSecurePassword123!
KEYCLOAK_ADMIN_PASSWORD=YourSecurePassword123!

# AI Configuration
OLLAMA_NUM_PARALLEL=1
OLLAMA_NUM_THREAD=4
OLLAMA_KEEP_ALIVE=5m

# Database
POSTGRES_DB=hermis
POSTGRES_USER=hermis

# Storage
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=YourSecurePassword123!

# Monitoring
LOG_LEVEL=info
LOKI_RETENTION_DAYS=30
```

### Docker Compose Configuration

The `docker-compose.yml` includes all services. Key services:

```yaml
services:
  traefik:      # Reverse proxy & load balancer
  ollama:       # LLM inference
  openwebui:    # Web interface
  postgres:     # Database
  redis:        # Cache
  qdrant:       # Vector DB
  minio:        # Storage
  keycloak:     # Auth
  prometheus:   # Metrics
  grafana:      # Dashboards
  loki:         # Logging
  vault:        # Secrets
```

### Network Configuration

By default, Hermis creates three networks:

```yaml
Networks:
  hermis-internal:  # Core services
  hermis-ai:        # AI models
  hermis-monitoring: # Observability
```

To access services externally:
1. **HTTP:** Configure firewall rule
2. **HTTPS:** Add SSL certificate
3. **Domain:** Update DNS records

---

## 🚀 Usage

### Web Interface

Access OpenWebUI:
```
http://localhost:8000
or
http://webui.localhost
```

Features:
- Chat with local models
- Manage documents for RAG
- Configure settings
- View chat history

### API Interface

Using the OpenAI-compatible API:

```bash
# Chat completion
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Embeddings
curl http://localhost:8000/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-embed-text",
    "input": "Hello world"
  }'

# RAG Query
curl http://localhost:8000/v1/rag/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is...",
    "model": "mistral",
    "collection": "documents"
  }'
```

### Python SDK

```python
from openai import OpenAI

# Initialize with local endpoint
client = OpenAI(
    api_key="sk-hermis",
    base_url="http://localhost:8000/v1"
)

# Chat
response = client.chat.completions.create(
    model="mistral",
    messages=[{"role": "user", "content": "Hello!"}],
    stream=True
)

for chunk in response:
    print(chunk.choices[0].delta.content, end="", flush=True)
```

### Command-Line Management

```bash
# Install models
./model-manager.sh pull-recommended

# List models
./model-manager.sh list

# Check status
./model-manager.sh status

# Monitor performance
./model-manager.sh monitor

# Create backup
./backup-restore.sh backup

# Restore from backup
./backup-restore.sh restore /opt/hermis/backups/2024-01-15_10-30-45
```

---

## 🌍 Deployment Models

### Single Node (Docker Compose)

**Best for:** Development, small teams (< 50 users)

```
Ubuntu VM (20GB RAM, 500GB storage)
  ├─ Docker Engine
  ├─ Docker Compose
  └─ All services in containers
```

**Pros:**
- ✅ Simple to install
- ✅ Low resource overhead
- ✅ Easy to maintain
- ✅ Perfect for MVP

**Cons:**
- ❌ Single point of failure
- ❌ No horizontal scaling
- ❌ Limited availability

**Cost:** ~$50-100/month (self-hosted)

### Multi-Node (K3s Kubernetes)

**Best for:** Production, enterprises (50-1000+ users)

```
3+ Ubuntu VMs (32GB RAM, 1TB storage each)
  ├─ K3s Kubernetes cluster
  ├─ Persistent volumes
  ├─ Auto-scaling
  └─ High availability
```

**Pros:**
- ✅ Horizontal scaling
- ✅ High availability
- ✅ Self-healing
- ✅ GitOps automation

**Cons:**
- ❌ More complex
- ❌ More resource overhead
- ❌ Requires K8s knowledge

**Cost:** ~$200-500/month (self-hosted)

### Cloud-Native (AWS/GCP/Azure)

**Best for:** SaaS, global scale

```
Managed Kubernetes (EKS/GKE/AKS)
  ├─ Multi-region deployment
  ├─ Managed databases
  ├─ Auto-scaling groups
  ├─ CDN integration
  └─ Backup & DR automation
```

**Pros:**
- ✅ Global distribution
- ✅ Enterprise security
- ✅ Managed services
- ✅ Automatic scaling

**Cons:**
- ❌ Cloud vendor lock-in
- ❌ Higher costs
- ❌ Data residency concerns

**Cost:** ~$1000-5000+/month

---

## 📊 Monitoring

### Accessing Monitoring Dashboards

| Service | URL | Credentials |
|---------|-----|-------------|
| **Grafana** | http://grafana.localhost | admin / password |
| **Prometheus** | http://prometheus.localhost | - |
| **Loki** | http://loki.localhost | - |
| **Portainer** | http://portainer.localhost | admin / password |

### Key Dashboards

1. **System Overview**
   - CPU, Memory, Disk
   - Network traffic
   - Container status

2. **AI Model Performance**
   - Inference latency
   - Token throughput
   - Model utilization

3. **Application Metrics**
   - API request rate
   - Error rate
   - Response time

4. **Infrastructure**
   - Disk space
   - Database connections
   - Cache hit ratio

### Creating Alerts

Example alert rule:

```yaml
alert: HighModelLatency
expr: histogram_quantile(0.95, ollama_request_duration_seconds_bucket) > 5
for: 5m
annotations:
  summary: "Model latency P95 > 5 seconds"
```

---

## 🔧 Troubleshooting

### Common Issues

#### Services Won't Start

```bash
# Check Docker daemon
systemctl status docker

# View logs
docker compose logs -f

# Check disk space
df -h

# Check RAM
free -h
```

#### Model Inference Slow

```bash
# Check model loaded
docker compose exec ollama ollama list

# Benchmark model
./model-manager.sh benchmark llama2:7b

# Check GPU availability
docker compose exec ollama nvidia-smi
```

#### Database Connection Error

```bash
# Check PostgreSQL health
docker compose exec postgres pg_isready

# Check credentials in .env
grep POSTGRES_ /opt/hermis/.env

# View database logs
docker compose logs postgres
```

#### High Memory Usage

```bash
# Reduce model parallelism
OLLAMA_NUM_PARALLEL=1

# Unload unused models
./model-manager.sh delete model-name

# Check container stats
docker stats
```

### Getting Help

1. **Check Logs**
   ```bash
   tail -f /opt/hermis/logs/hermis-installer.log
   docker compose logs -f [service]
   ```

2. **Health Check**
   ```bash
   curl http://localhost:8000/health
   docker compose ps
   ```

3. **Community Support**
   - GitHub Issues: https://github.com/hermis-ai/hermis-agent/issues
   - Discord: https://discord.gg/hermis-ai
   - Documentation: https://docs.hermis.ai

---

## 📈 Performance Tuning

### For 20GB RAM Systems

```bash
# Optimize sysctl
OLLAMA_NUM_THREAD=2
OLLAMA_NUM_PARALLEL=1
OLLAMA_KEEP_ALIVE=10m

# PostgreSQL
shared_buffers=256MB
effective_cache_size=1GB
work_mem=1310kB

# Redis
maxmemory=2gb
maxmemory-policy=allkeys-lru
```

### For 64GB+ RAM Systems

```bash
OLLAMA_NUM_THREAD=8
OLLAMA_NUM_PARALLEL=4
OLLAMA_KEEP_ALIVE=30m

# PostgreSQL
shared_buffers=16GB
effective_cache_size=48GB
work_mem=20MB

# Redis
maxmemory=16gb
```

---

## 🔐 Security Best Practices

### After Installation

1. **Change all default passwords**
   ```bash
   # Edit .env
   nano /opt/hermis/.env
   docker compose restart
   ```

2. **Enable HTTPS**
   ```bash
   # Set domain and get Let's Encrypt cert
   # Edit traefik config
   ```

3. **Configure Firewall**
   ```bash
   # Only allow needed ports
   ufw allow 22/tcp   # SSH
   ufw allow 80/tcp   # HTTP
   ufw allow 443/tcp  # HTTPS
   ```

4. **Set up Backups**
   ```bash
   # Test backup
   ./backup-restore.sh backup

   # Schedule daily
   echo "0 2 * * * /opt/hermis/backup-restore.sh backup" | sudo crontab -
   ```

5. **Enable Monitoring**
   ```bash
   # Check alerts are configured
   # Review logs regularly
   # Set up external log shipping
   ```

---

## 📜 License

Hermis Agent is released under the **MIT License**. See [LICENSE](LICENSE) for details.

---

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## 📞 Support

- **Documentation:** https://docs.hermis.ai
- **GitHub:** https://github.com/hermis-ai/hermis-agent
- **Discord:** https://discord.gg/hermis-ai
- **Email:** support@hermis.ai

---

## 🎯 Roadmap

- [x] Docker Compose MVP
- [x] K3s support
- [x] Monitoring stack
- [x] Authentication system
- [ ] Multi-region Kubernetes
- [ ] GPU support
- [ ] Mobile app
- [ ] Cloud marketplace

---

## 🙏 Acknowledgments

Built with:
- [Ollama](https://ollama.ai) - Local LLM inference
- [Qdrant](https://qdrant.tech) - Vector database
- [FastAPI](https://fastapi.tiangolo.com) - API framework
- [Kubernetes](https://kubernetes.io) - Container orchestration
- [Prometheus](https://prometheus.io) - Monitoring
- [ArgoCD](https://argoproj.github.io/argo-cd) - GitOps

---

**Made with ❤️ for the AI-powered enterprise**

⭐ If you find Hermis Agent useful, please star the repository!
