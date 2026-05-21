# 🚀 Hermis Agent - Quick Start Guide

**Get Hermis Agent running in 15 minutes**

---

## ⚡ Ultra-Quick Start (5 minutes)

### Step 1: Run the Installer

```bash
cd /home/prophet/HERMES

# Make scripts executable
chmod +x hermis-agent-installer.sh
chmod +x k3s-installer.sh
chmod +x backup-restore.sh
chmod +x model-manager.sh

# Run the installer as root
sudo ./hermis-agent-installer.sh
```

The installer will automatically:
✅ Check prerequisites  
✅ Harden the system  
✅ Install Docker  
✅ Deploy all services  
✅ Configure security  
✅ Set up monitoring  
✅ Start everything

### Step 2: Wait for Services

```bash
# Monitor services starting
cd /opt/hermis
docker compose ps

# Wait until all services show "healthy"
# This takes 2-3 minutes
watch docker compose ps
```

### Step 3: Access the Platform

Open your browser and navigate to:

| Service | URL | Credentials |
|---------|-----|-------------|
| **OpenWebUI** | http://localhost:8000 | (no login for local) |
| **Grafana** | http://grafana.localhost | admin / (see .env) |
| **Prometheus** | http://prometheus.localhost | (read-only) |
| **Portainer** | http://portainer.localhost | admin / (see .env) |

### Step 4: Pull AI Models

```bash
cd /opt/hermis

# Pull recommended models (takes 10-20 minutes)
./model-manager.sh pull-recommended

# Or pull specific models
./model-manager.sh pull mistral:7b
./model-manager.sh pull llama2:7b
./model-manager.sh pull nomic-embed-text

# Check model status
./model-manager.sh status
```

### Step 5: Start Chatting!

Go to http://localhost:8000 and start using the platform!

---

## 📋 Complete Installation Guide

### Prerequisites Check

```bash
# Check system specs
lscpu                    # CPU info
free -h                  # RAM
df -h                    # Disk space

# Required:
# - 4+ CPU cores
# - 20GB+ RAM
# - 500GB+ storage
# - Ubuntu 24.04 LTS (or similar Linux)
```

### Step-by-Step Installation

#### 1. Prepare System

```bash
# Update system
sudo apt update
sudo apt upgrade -y

# Create Hermis user (optional)
sudo useradd -m -s /bin/bash hermis
sudo usermod -aG docker hermis
```

#### 2. Download Hermis

```bash
# Clone or download
cd /home/prophet/HERMES

# Or download from GitHub
mkdir -p ~/hermis-agent
cd ~/hermis-agent
git clone https://github.com/hermis-ai/hermis-agent .
```

#### 3. Configure Environment

```bash
cd /opt/hermis

# Copy example config
cp .env.example .env

# Edit configuration
nano .env

# Required changes:
# - PORTAINER_PASSWORD=YourPassword
# - POSTGRES_PASSWORD=YourPassword
# - GRAFANA_ADMIN_PASSWORD=YourPassword
# - KEYCLOAK_ADMIN_PASSWORD=YourPassword
```

#### 4. Run Installer

```bash
sudo ./hermis-agent-installer.sh

# Wait for completion (15 minutes)
```

#### 5. Verify Installation

```bash
# Check all services
cd /opt/hermis
docker compose ps

# Test API
curl http://localhost:5000/health

# View logs
docker compose logs -f ollama
```

#### 6. Install AI Models

```bash
./model-manager.sh pull-recommended

# Monitor progress
./model-manager.sh monitor
```

#### 7. Access Services

```bash
# Open in browser
# http://localhost:8000  - OpenWebUI
# http://localhost:3000  - Grafana
```

---

## 🔧 Post-Installation Configuration

### 1. Change Default Passwords

```bash
nano /opt/hermis/.env

# Change:
# PORTAINER_PASSWORD
# POSTGRES_PASSWORD
# GRAFANA_ADMIN_PASSWORD
# KEYCLOAK_ADMIN_PASSWORD

# Restart services to apply
docker compose restart
```

### 2. Enable HTTPS (Optional)

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Get certificate
sudo certbot certonly --standalone -d yourdomain.com

# Update Traefik config
nano /opt/hermis/config/traefik/traefik.yml
```

### 3. Configure Firewall

```bash
# Enable UFW (if not already)
sudo ufw enable

# Allow SSH, HTTP, HTTPS
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# View rules
sudo ufw status
```

### 4. Set Up Backups

```bash
# Test backup
./backup-restore.sh backup

# Schedule daily at 2 AM
(crontab -l 2>/dev/null; echo "0 2 * * * /opt/hermis/backup-restore.sh backup") | sudo crontab -

# List backups
./backup-restore.sh list
```

### 5. Configure Alerts

```bash
# Login to Alertmanager
# (Configure notification channels - email, Slack, etc.)

# Or edit config
nano /opt/hermis/config/alertmanager/alertmanager.yml
```

---

## 📚 Using Hermis Agent

### Web Interface

1. **Go to http://localhost:8000**
2. **Select a model** (e.g., Mistral)
3. **Type your question**
4. **Get response** (streaming)

### API Usage

```bash
# Chat completion
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral",
    "messages": [{"role": "user", "content": "Hello!"}],
    "stream": false
  }' | jq .

# With streaming
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistral",
    "messages": [{"role": "user", "content": "Write a poem"}],
    "stream": true
  }'
```

### Python SDK

```python
from openai import OpenAI

client = OpenAI(
    api_key="sk-hermis",
    base_url="http://localhost:8000/v1"
)

# Simple message
response = client.chat.completions.create(
    model="mistral",
    messages=[{"role": "user", "content": "Hello!"}]
)
print(response.choices[0].message.content)

# With streaming
response = client.chat.completions.create(
    model="mistral",
    messages=[{"role": "user", "content": "Write a poem"}],
    stream=True
)
for chunk in response:
    print(chunk.choices[0].delta.content, end="", flush=True)
```

### Command-Line Tools

```bash
# Models
./model-manager.sh pull mistral:7b      # Install model
./model-manager.sh list                 # List models
./model-manager.sh status               # Show running
./model-manager.sh benchmark mistral:7b # Test speed

# Backups
./backup-restore.sh backup              # Create backup
./backup-restore.sh list                # List backups
./backup-restore.sh restore /path       # Restore

# Docker
docker compose ps                       # Services status
docker compose logs -f [service]        # View logs
docker compose restart [service]        # Restart service
docker compose down                     # Stop all
```

---

## 🔍 Monitoring

### Dashboards

**Grafana** (http://grafana.localhost):
- System resources
- Model performance
- API metrics
- Container stats

**Prometheus** (http://prometheus.localhost):
- Raw metrics
- PromQL queries
- Service discovery

**Portainer** (http://portainer.localhost):
- Container management
- Service logs
- Performance charts

### Health Checks

```bash
# API health
curl http://localhost:8000/health

# Services status
docker compose ps

# Database
docker compose exec postgres pg_isready

# Models
./model-manager.sh health
```

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f ollama
docker compose logs -f postgres

# System logs
tail -f /opt/hermis/logs/hermis-installer.log

# With grep
docker compose logs postgres | grep -i error
```

---

## 🚨 Troubleshooting

### Services Won't Start

```bash
# Check logs
docker compose logs

# Check disk space
df -h /opt/hermis

# Check RAM
free -h

# Restart Docker
sudo systemctl restart docker
```

### Model Inference Slow

```bash
# Check what's loaded
./model-manager.sh status

# Unload unused models
./model-manager.sh delete llama2:7b

# Check system resources
docker stats

# Benchmark model
./model-manager.sh benchmark mistral:7b
```

### Database Issues

```bash
# Check PostgreSQL
docker compose exec postgres psql -U hermis -d hermis -c "\dt"

# Check Redis
docker compose exec redis redis-cli ping

# Restart database
docker compose restart postgres
```

### Out of Disk Space

```bash
# Check what's using space
du -sh /opt/hermis/*

# Delete old backups
find /opt/hermis/backups -mtime +30 -exec rm -rf {} \;

# Prune Docker
docker system prune -a
```

---

## 🆚 Docker vs Kubernetes

### Use Docker Compose If:
✅ Testing/development  
✅ Single node  
✅ < 50 users  
✅ Simplicity important  
✅ < $100/month budget  

### Use Kubernetes If:
✅ Production  
✅ Multiple nodes  
✅ 50+ users  
✅ High availability  
✅ Auto-scaling needed  

### Switch to Kubernetes Later

```bash
# Install K3s on top of existing setup
sudo ./k3s-installer.sh

# Or migrate:
# 1. Backup with Docker
./backup-restore.sh backup

# 2. Install K3s cluster
# 3. Deploy with Helm
# 4. Restore data
./backup-restore.sh restore /path
```

---

## 📊 Next Steps

After successful installation:

1. **Customize Models**
   ```bash
   ./model-manager.sh create-config my-models.json
   ./model-manager.sh pull-custom my-models.json
   ```

2. **Upload Documents** (for RAG)
   - Via OpenWebUI web interface
   - Via API
   - Via batch upload

3. **Configure Authentication**
   - Set up Keycloak realms
   - Add users/teams
   - Configure OAuth

4. **Set Up Monitoring**
   - Create custom dashboards
   - Configure alerts
   - Set up log shipping

5. **Enable Backup to Cloud**
   ```bash
   # Edit to add S3 bucket
   ./backup-restore.sh upload-s3 /opt/hermis/backups/latest my-bucket
   ```

6. **Scale Up**
   - Upgrade to Kubernetes
   - Add more models
   - Increase resources

---

## 📞 Getting Help

**Still stuck?**

1. **Check the logs**
   ```bash
   tail -f /opt/hermis/logs/hermis-installer.log
   docker compose logs -f
   ```

2. **Read the documentation**
   - Architecture: `/home/prophet/HERMES/ARCHITECTURE.md`
   - Full README: `/home/prophet/HERMES/README.md`

3. **Try the community**
   - GitHub Issues: https://github.com/hermis-ai/hermis-agent/issues
   - Discord: https://discord.gg/hermis-ai

4. **Contact support**
   - Email: support@hermis.ai
   - Documentation: https://docs.hermis.ai

---

## ✅ Installation Checklist

After running the installer, verify:

- [ ] All services running: `docker compose ps`
- [ ] API responding: `curl http://localhost:8000/health`
- [ ] Models installed: `./model-manager.sh list`
- [ ] Grafana accessible: http://grafana.localhost
- [ ] Portainer accessible: http://portainer.localhost
- [ ] OpenWebUI working: http://localhost:8000
- [ ] Backup created: `./backup-restore.sh list`
- [ ] Passwords changed in .env
- [ ] Firewall configured (if needed)
- [ ] Daily backup scheduled (cron)

---

**🎉 Congratulations! You're ready to use Hermis Agent!**

Start building intelligent applications with local AI 🚀
