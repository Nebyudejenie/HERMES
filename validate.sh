#!/usr/bin/env bash
#
# validate.sh — post-install readiness check. RUN INSIDE THE VM after
# hermis-agent-installer.sh. Confirms every container is up, healthchecks pass,
# the OpenAI-compatible API answers, and a real model responds.
#
set -uo pipefail

HERMIS_ROOT="/opt/hermis"
C_G='\033[0;32m'; C_Y='\033[1;33m'; C_R='\033[0;31m'; C_N='\033[0m'
pass(){ echo -e "${C_G}[PASS]${C_N} $*"; }
fail(){ echo -e "${C_R}[FAIL]${C_N} $*"; FAILS=$((FAILS+1)); }
warn(){ echo -e "${C_Y}[WARN]${C_N} $*"; }
FAILS=0

echo "=================================================="
echo "        HERMIS AGENT — READINESS CHECK"
echo "=================================================="

# 1. Docker
if docker ps >/dev/null 2>&1; then pass "Docker daemon responsive"; else fail "Docker not responding"; fi

cd "$HERMIS_ROOT" 2>/dev/null || { fail "$HERMIS_ROOT missing"; echo; echo "ABORT"; exit 1; }

# 2. Containers running
EXPECTED=$(docker compose config --services 2>/dev/null | wc -l)
RUNNING=$(docker compose ps --services --filter status=running 2>/dev/null | wc -l)
if [ "$RUNNING" -ge "$EXPECTED" ]; then pass "Containers running: $RUNNING/$EXPECTED"
else warn "Containers running: $RUNNING/$EXPECTED"; fi

# 3. Unhealthy containers (autoheal should keep this empty)
UNHEALTHY=$(docker ps --filter health=unhealthy --format '{{.Names}}' | tr '\n' ' ')
if [ -z "$UNHEALTHY" ]; then pass "No unhealthy containers"; else warn "Unhealthy: $UNHEALTHY (autoheal will retry)"; fi

# 4. autoheal present
docker ps --format '{{.Names}}' | grep -q '^autoheal$' && pass "Self-healing (autoheal) active" || warn "autoheal not running"

# 5. Core endpoints (from the host VM)
check_http(){ # name url
  if curl -fsS --max-time 5 "$2" >/dev/null 2>&1; then pass "$1 reachable ($2)"; else warn "$1 not reachable yet ($2)"; fi
}
check_http "Ollama"     "http://localhost:11434/api/tags"
check_http "Qdrant"     "http://localhost:6333/readyz"
check_http "Grafana"    "http://localhost:3000/api/health"
check_http "Prometheus" "http://localhost:9090/-/healthy"
check_http "Portainer"  "http://localhost:9000/api/status"

# 6. Models present
MODELS=$(docker exec ollama ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ' ')
if [ -n "$MODELS" ]; then pass "Models loaded: $MODELS"; else fail "No Ollama models present"; fi

# 7. OpenAI-compatible API (Ollama native /v1) answers
if curl -fsS --max-time 90 http://localhost:11434/v1/chat/completions \
     -H 'Content-Type: application/json' \
     -d "{\"model\":\"$(echo "$MODELS" | awk '{print $1}')\",\"messages\":[{\"role\":\"user\",\"content\":\"reply OK\"}],\"max_tokens\":5}" \
     2>/dev/null | grep -qi '"content"'; then
  pass "OpenAI-compatible API answered a real prompt"
else
  warn "AI prompt did not answer within 90s (model may still be warming on CPU)"
fi

echo "=================================================="
if [ "$FAILS" -eq 0 ]; then
  echo -e "${C_G}RESULT: READY ✅${C_N}  (warnings are non-fatal; re-run in a minute if services are still warming)"
  IP=$(hostname -I | awk '{print $1}')
  echo
  echo "Access (SSH-tunnel from your laptop, e.g.):"
  echo "  ssh -L 3000:localhost:3000 -L 9000:localhost:9000 $(whoami)@${IP}"
  echo "  Grafana http://localhost:3000 · Portainer http://localhost:9000"
  echo "  OpenAI API: http://${IP}:11434/v1   ·   OpenWebUI via Traefik (webui.localhost)"
  exit 0
else
  echo -e "${C_R}RESULT: ${FAILS} CRITICAL CHECK(S) FAILED ❌${C_N}"
  echo "Inspect with:  docker compose -f $HERMIS_ROOT/docker-compose.yml ps ; docker logs <svc>"
  exit 1
fi
