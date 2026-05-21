#!/bin/bash

echo "=== Docker Status ==="
systemctl status docker 2>&1 | grep -E "Active|running"

echo -e "\n=== Running Containers ==="
docker ps

echo -e "\n=== All Containers ==="
docker ps -a

echo -e "\n=== Docker Compose ==="
cd /opt/hermis 2>/dev/null && docker compose ps || echo "Can't access /opt/hermis"

echo -e "\n=== Docker Compose Logs ==="
docker compose logs --tail=30 2>/dev/null || echo "No compose running"

echo -e "\n=== Check /opt/hermis ==="
ls -la /opt/hermis/ 2>&1 | head -20

echo -e "\n=== Check docker-compose.yml ==="
[ -f /opt/hermis/docker-compose.yml ] && echo "✓ File exists" || echo "✗ File missing"
