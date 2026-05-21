#!/bin/bash

###############################################################################
# HERMIS AGENT - Kubernetes (K3s) Automated Installer
# Version: 1.0.0
# Purpose: Enterprise-grade Kubernetes deployment with GitOps
###############################################################################

set -euo pipefail

# Configuration
K3S_VERSION="v1.28.4+k3s1"
HELM_VERSION="3.13.0"
ARGOCD_VERSION="2.9.3"
HERMIS_ROOT="${HERMIS_ROOT:-/opt/hermis}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${HERMIS_ROOT}/logs"
LOG_FILE="${LOG_DIR}/k3s-installer.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

###############################################################################
# LOGGING
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

log_section() {
    echo -e "\n${PURPLE}==================${NC} $* ${PURPLE}==================${NC}\n" | tee -a "${LOG_FILE}"
}

###############################################################################
# PREREQUISITES
###############################################################################

check_prerequisites() {
    log_section "CHECKING PREREQUISITES"

    if [ "$EUID" -ne 0 ]; then
        log_error "Must run as root"
        exit 1
    fi
    log_success "Running as root"

    if ! command -v curl &> /dev/null; then
        log_error "curl is required"
        exit 1
    fi
    log_success "curl available"

    if ! command -v docker &> /dev/null; then
        log_error "Docker is required. Run docker installer first."
        exit 1
    fi
    log_success "Docker installed"
}

###############################################################################
# K3S INSTALLATION
###############################################################################

install_k3s() {
    log_section "INSTALLING K3S"

    log_info "Installing K3s version ${K3S_VERSION}..."
    curl -sfL https://get.k3s.io | \
        K3S_VERSION="${K3S_VERSION}" \
        K3S_KUBECONFIG_MODE=644 \
        K3S_KUBECONFIG_OUTPUT="${HERMIS_ROOT}/config/k3s-kubeconfig.yaml" \
        sh -

    log_success "K3s installed"

    # Wait for K3s to be ready
    log_info "Waiting for K3s to initialize..."
    sleep 10

    # Set up kubeconfig
    mkdir -p ~/.kube
    cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    chmod 600 ~/.kube/config

    log_success "Kubeconfig configured"
}

###############################################################################
# KUBECTL AND HELM INSTALLATION
###############################################################################

install_tools() {
    log_section "INSTALLING KUBERNETES TOOLS"

    # kubectl is included with K3s
    log_success "kubectl available"

    # Install Helm
    log_info "Installing Helm ${HELM_VERSION}..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    log_success "Helm installed"

    # Install additional tools
    apt-get install -y jq yq || true

    log_success "Tools installed"
}

###############################################################################
# KUBERNETES NAMESPACE SETUP
###############################################################################

setup_namespaces() {
    log_section "SETTING UP KUBERNETES NAMESPACES"

    log_info "Creating namespaces..."

    kubectl create namespace hermis-ai --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl create namespace hermis-monitoring --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl create namespace hermis-security --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl create namespace hermis-storage --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - || true

    log_success "Namespaces created"
}

###############################################################################
# STORAGE CLASS SETUP
###############################################################################

setup_storage() {
    log_section "SETTING UP STORAGE"

    log_info "Creating storage class..."

    cat << 'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-hermis
  namespace: hermis-storage
provisioner: rancher.io/local-path
parameters:
  nodePath: "/opt/hermis/data"
  helperPod.image: "rancher/local-path-provisioner:v0.0.26"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local-path
  namespace: hermis-storage
provisioner: rancher.io/local-path
parameters:
  nodePath: "/opt/hermis/data/fast"
  helperPod.image: "rancher/local-path-provisioner:v0.0.26"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
EOF

    log_success "Storage classes created"
}

###############################################################################
# NETWORK POLICIES
###############################################################################

setup_network_policies() {
    log_section "SETTING UP NETWORK POLICIES"

    log_info "Applying network policies..."

    cat << 'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: hermis-ai-network-policy
  namespace: hermis-ai
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: hermis-ai
        - namespaceSelector:
            matchLabels:
              name: hermis-monitoring
        - podSelector:
            matchLabels:
              app: api-gateway
  egress:
    - to:
        - namespaceSelector: {}
    - to:
        - podSelector: {}
      ports:
        - protocol: TCP
          port: 53
        - protocol: UDP
          port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: hermis-internal-deny-all
  namespace: hermis-ai
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: hermis-ai
EOF

    log_success "Network policies applied"
}

###############################################################################
# RBAC SETUP
###############################################################################

setup_rbac() {
    log_section "SETTING UP RBAC"

    log_info "Applying RBAC policies..."

    cat << 'EOF' | kubectl apply -f -
# Service account for Hermis AI
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hermis-ai-service-account
  namespace: hermis-ai
---
# Role for Hermis AI
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: hermis-ai-role
  namespace: hermis-ai
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
  - apiGroups: ["batch"]
    resources: ["jobs"]
    verbs: ["create", "get", "list", "watch"]
---
# RoleBinding for Hermis AI
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: hermis-ai-rolebinding
  namespace: hermis-ai
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: hermis-ai-role
subjects:
  - kind: ServiceAccount
    name: hermis-ai-service-account
    namespace: hermis-ai
EOF

    log_success "RBAC configured"
}

###############################################################################
# ARGOCD INSTALLATION
###############################################################################

install_argocd() {
    log_section "INSTALLING ARGOCD"

    log_info "Installing ArgoCD..."

    helm repo add argoproj https://argoproj.github.io/argo-helm || true
    helm repo update

    helm upgrade --install argocd argoproj/argo-cd \
        --namespace argocd \
        --version "6.1.13" \
        --set configs.secret.argocdServerAdminPassword="$(openssl rand -base64 16)" \
        --set "configs.repositories.hermis.url=file:///opt/hermis/config/gitops" \
        --set "configs.repositories.hermis.type=git" \
        --set "repoServer.replicas=2" \
        --set "server.replicas=2" \
        --set "controller.replicas=2"

    log_success "ArgoCD installed"

    # Expose ArgoCD API
    kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

    log_success "ArgoCD ready"
}

###############################################################################
# CERT-MANAGER INSTALLATION
###############################################################################

install_cert_manager() {
    log_section "INSTALLING CERT-MANAGER"

    log_info "Installing cert-manager..."

    helm repo add jetstack https://charts.jetstack.io || true
    helm repo update

    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version v1.13.2 \
        --set installCRDs=true

    log_success "Cert-manager installed"
}

###############################################################################
# TRAEFIK SETUP
###############################################################################

install_traefik() {
    log_section "INSTALLING TRAEFIK INGRESS"

    log_info "Installing Traefik..."

    helm repo add traefik https://traefik.github.io/charts || true
    helm repo update

    helm upgrade --install traefik traefik/traefik \
        --namespace kube-system \
        --set service.type=LoadBalancer \
        --set ingressClass.enabled=true \
        --set ingressClass.isDefaultClass=true

    log_success "Traefik installed"
}

###############################################################################
# PROMETHEUS OPERATOR INSTALLATION
###############################################################################

install_prometheus_stack() {
    log_section "INSTALLING PROMETHEUS STACK"

    log_info "Installing kube-prometheus-stack..."

    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    helm repo update

    helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace hermis-monitoring \
        --values - << 'EOF'
prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path-hermis
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

grafana:
  adminPassword: "changeme"
  persistence:
    enabled: true
    storageClassName: local-path-hermis
    size: 5Gi

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: local-path-hermis
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
EOF

    log_success "Prometheus stack installed"
}

###############################################################################
# LOKI STACK INSTALLATION
###############################################################################

install_loki_stack() {
    log_section "INSTALLING LOKI STACK"

    log_info "Installing Loki..."

    helm repo add grafana https://grafana.github.io/helm-charts || true
    helm repo update

    helm upgrade --install loki grafana/loki-stack \
        --namespace hermis-monitoring \
        --values - << 'EOF'
loki:
  enabled: true
  persistence:
    enabled: true
    storageClassName: local-path-hermis
    size: 20Gi

promtail:
  enabled: true
  config:
    clients:
      - url: http://loki:3100/loki/api/v1/push

grafana:
  enabled: false
EOF

    log_success "Loki stack installed"
}

###############################################################################
# OLLAMA HELM CHART
###############################################################################

install_ollama_chart() {
    log_section "INSTALLING OLLAMA HELM CHART"

    log_info "Creating Ollama Helm chart..."

    mkdir -p "${HERMIS_ROOT}"/config/helm/ollama

    cat > "${HERMIS_ROOT}"/config/helm/ollama/Chart.yaml << 'EOF'
apiVersion: v2
name: hermis-ollama
description: Ollama AI inference engine for Hermis
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

    cat > "${HERMIS_ROOT}"/config/helm/ollama/values.yaml << 'EOF'
replicaCount: 1

image:
  repository: ollama/ollama
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 11434

resources:
  requests:
    memory: "4Gi"
    cpu: "2"
  limits:
    memory: "8Gi"
    cpu: "4"

persistence:
  enabled: true
  storageClass: "local-path-hermis"
  size: 20Gi
  mountPath: /root/.ollama

env:
  OLLAMA_KEEP_ALIVE: "5m"
  OLLAMA_NUM_PARALLEL: "1"
  OLLAMA_NUM_THREAD: "4"

models:
  - llama2
  - mistral
  - neural-chat
EOF

    log_success "Ollama Helm chart created"
}

###############################################################################
# POSTGRESQL OPERATOR
###############################################################################

install_postgres_operator() {
    log_section "INSTALLING POSTGRESQL OPERATOR"

    log_info "Installing PostgreSQL operator..."

    helm repo add bitnami https://charts.bitnami.com/bitnami || true
    helm repo update

    helm upgrade --install postgresql bitnami/postgresql \
        --namespace hermis-ai \
        --values - << 'EOF'
auth:
  username: hermis
  password: hermis123
  database: hermis

primary:
  persistence:
    enabled: true
    storageClass: local-path-hermis
    size: 10Gi

replica:
  replicaCount: 0

metrics:
  enabled: true
EOF

    log_success "PostgreSQL installed"
}

###############################################################################
# REDIS OPERATOR
###############################################################################

install_redis() {
    log_section "INSTALLING REDIS"

    log_info "Installing Redis..."

    helm repo add bitnami https://charts.bitnami.com/bitnami || true
    helm repo update

    helm upgrade --install redis bitnami/redis \
        --namespace hermis-ai \
        --values - << 'EOF'
auth:
  enabled: true
  password: hermis123

master:
  persistence:
    enabled: true
    storageClass: local-path-hermis
    size: 5Gi

replica:
  replicaCount: 0

metrics:
  enabled: true
EOF

    log_success "Redis installed"
}

###############################################################################
# MAIN EXECUTION
###############################################################################

main() {
    log_section "HERMIS AGENT - KUBERNETES INSTALLATION"

    mkdir -p "${LOG_DIR}"

    check_prerequisites
    install_k3s
    install_tools
    setup_namespaces
    setup_storage
    setup_network_policies
    setup_rbac
    install_cert_manager
    install_traefik
    install_argocd
    install_prometheus_stack
    install_loki_stack
    install_ollama_chart
    install_postgres_operator
    install_redis

    log_section "KUBERNETES INSTALLATION COMPLETE"

    echo "
╔════════════════════════════════════════════════════════════════╗
║                   K3S INSTALLATION COMPLETE                    ║
╚════════════════════════════════════════════════════════════════╝

Kubernetes cluster is ready!

Access points:
- Kubeconfig: ${HERMIS_ROOT}/config/k3s-kubeconfig.yaml
- API: https://localhost:6443
- ArgoCD: Check kubectl port-forward in argocd namespace

Next steps:
1. Configure GitOps repositories in ArgoCD
2. Deploy AI models
3. Set up monitoring dashboards
4. Configure ingress routing
5. Enable auto-scaling

Logs available at: ${LOG_FILE}
    "

    log_success "Kubernetes installation complete!"
}

main "$@"
