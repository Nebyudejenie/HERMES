# 🚀 SIMPLE STEP-BY-STEP DEPLOYMENT

**Stop all previous attempts and run these commands manually:**

---

## **Step 1: Stop everything**
```bash
ssh cosmic@192.168.1.28

# Stop all Docker containers
sudo docker stop $(docker ps -aq) 2>/dev/null || true

# Remove all containers
sudo docker rm -f $(docker ps -aq) 2>/dev/null || true

# Clean up volumes
sudo docker volume prune -f 2>/dev/null || true
```

---

## **Step 2: Check if /opt/hermis exists**
```bash
# Check
ls -la /opt/hermis 2>&1 | head -5

# If it says "No such file", create it:
sudo mkdir -p /opt/hermis

# Set permissions
sudo chown -R $(whoami) /opt/hermis 2>/dev/null || sudo chmod 777 /opt/hermis
```

---

## **Step 3: Go to project directory**
```bash
cd /home/cosmic/HERMES
ls docker-compose.yml 2>&1
```

**If file NOT found**, copy it from installer:
```bash
sudo cp docker-compose.yml /opt/hermis/ 2>/dev/null || echo "Create docker-compose.yml manually"
```

---

## **Step 4: Pre-pull images ONE by ONE**
```bash
# This prevents hangs - takes 5-10 minutes

docker pull traefik:latest
docker pull ollama/ollama:latest
docker pull ghcr.io/open-webui/open-webui:latest
docker pull postgres:15
docker pull redis:7
docker pull qdrant/qdrant:latest
docker pull minio/minio:latest
docker pull quay.io/keycloak/keycloak:latest
docker pull hashicorp/vault:latest
docker pull prom/prometheus:latest
docker pull grafana/grafana:latest
docker pull grafana/loki:latest
docker pull grafana/promtail:latest
docker pull portainer/portainer-ce:latest
```

**Each should finish with:**
```
Status: Downloaded newer image for X
or
Status: Image is up to date for X
```

---

## **Step 5: Start Docker Compose**
```bash
# Navigate to hermis
cd /opt/hermis

# Check docker-compose.yml exists
ls docker-compose.yml

# Start services
docker compose up -d

# Check status
docker compose ps
```

---

## **Step 6: Wait and verify**
```bash
# Wait 30 seconds
sleep 30

# Check running services
docker compose ps

# View logs
docker compose logs --tail=20

# Check specific service
docker logs traefik
```

---

## **Expected Output:**
```
NAME                    STATUS
traefik                 running
ollama                  running
openwebui               running
postgres                running
redis                   running
qdrant                  running
minio                   running
keycloak                running
vault                   running
prometheus              running
grafana                 running
loki                    running
promtail                running
portainer               running
```

---

## **If any service fails:**
```bash
# Check logs
docker logs <service-name>

# Restart that service
docker restart <service-name>

# Check again
docker ps
```

---

## **Access URLs:**
```
http://localhost:8080    - Traefik
http://localhost:3000    - OpenWebUI / Grafana
http://localhost:9000    - Portainer
http://localhost:11434   - Ollama
http://localhost:5432    - PostgreSQL
```

---

## **Common Issues:**

### Images won't pull (network timeout)
```bash
# Try with longer timeout
timeout 600 docker pull <image>

# Or check network
ping 8.8.8.8
curl https://docker.io
```

### Port already in use
```bash
# See what's using the port
lsof -i :8080

# Kill it
kill -9 <PID>
```

### Docker compose file missing
```bash
# List what's in /opt/hermis
ls -la /opt/hermis/

# Copy from home if needed
cp /home/cosmic/HERMES/docker-compose.yml /opt/hermis/
```

---

**Run these commands one by one and show me if any fail!** 🚀
