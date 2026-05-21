#!/bin/bash
set -euo pipefail

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}[*] Testing Docker Image Pulls${NC}"

# Test basic connectivity
echo -e "${YELLOW}[*] Testing registry connectivity...${NC}"
docker run --rm curlimages/curl curl -s https://registry-1.docker.io/v2/ | head -c 100 && echo "" || {
    echo -e "${RED}[!] Registry connectivity issue${NC}"
}

# List of images to test
images=(
    "vault:latest"
    "vault:1.15"
    "hashicorp/vault:latest"
    "ollama/ollama:latest"
    "traefik:latest"
    "postgres:15"
)

echo -e "${YELLOW}[*] Testing image availability...${NC}"
for img in "${images[@]}"; do
    echo -n "  Testing $img ... "
    if timeout 5 docker pull "$img" > /dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAIL${NC}"
    fi
done

echo -e "${YELLOW}[*] Checking Docker daemon logs for errors...${NC}"
journalctl -u docker -n 20 | grep -i "error\|fail" || echo "No errors in Docker logs"

echo -e "${YELLOW}[*] Alternative: Using pre-built images or offline deployment${NC}"
echo "If images don't pull, you can:"
echo "1. Check internet connectivity"
echo "2. Configure Docker to use mirror registries"
echo "3. Pre-download images on connected machine"
echo "4. Use K3s deployment instead (which might have cached images)"
