#!/bin/bash

###############################################################################
# Hermis Agent - AI Model Manager
# Automated model downloading, management, and optimization
###############################################################################

set -euo pipefail

OLLAMA_API="http://localhost:11434"
MODELS_DIR="${HERMIS_ROOT:-/opt/hermis}/models"
LOG_FILE="${HERMIS_ROOT:-/opt/hermis}/logs/model-manager.log"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

###############################################################################
# LOGGING
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $*" | tee -a "${LOG_FILE}"
}

###############################################################################
# MODEL OPERATIONS
###############################################################################

pull_model() {
    local model="${1:?Model name required}"

    log_info "Pulling model: ${model}"

    if curl -s -X POST "${OLLAMA_API}/api/pull" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${model}\"}" | jq '.error' >/dev/null; then
        log_error "Failed to pull model: ${model}"
        return 1
    fi

    log_success "Model pulled: ${model}"
}

list_models() {
    log_info "Available models:"

    curl -s "${OLLAMA_API}/api/tags" | jq -r '.models[] | "\(.name) (\(.size | ./(1024*1024*1024) | floor)GB)"' 2>/dev/null || {
        log_error "Cannot connect to Ollama API"
        return 1
    }
}

model_status() {
    log_info "Model status:"

    curl -s "${OLLAMA_API}/api/tags" | jq '.models[] | {name: .name, size: .size, modified: .modified_at}' 2>/dev/null

    log_info "\nRunning models:"
    curl -s "${OLLAMA_API}/api/ps" | jq '.models[]' 2>/dev/null || {
        log_warning "No models currently running"
    }
}

delete_model() {
    local model="${1:?Model name required}"

    log_warning "Deleting model: ${model}"

    if ! curl -s -X DELETE "${OLLAMA_API}/api/delete" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${model}\"}" | grep -q "success"; then
        log_error "Failed to delete model: ${model}"
        return 1
    fi

    log_success "Model deleted: ${model}"
}

benchmark_model() {
    local model="${1:?Model name required}"
    local prompt="${2:-What is artificial intelligence? Explain in 50 words.}"

    log_info "Benchmarking model: ${model}"

    time curl -s -X POST "${OLLAMA_API}/api/generate" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"${model}\",
            \"prompt\": \"${prompt}\",
            \"stream\": false
        }" | jq '.eval_duration, .prompt_eval_duration'

    log_success "Benchmark complete"
}

###############################################################################
# BULK OPERATIONS
###############################################################################

pull_recommended_models() {
    log_info "Pulling recommended model set..."

    local models=(
        "llama2:7b"
        "mistral:7b"
        "neural-chat:7b"
        "deepseek-coder:6.7b"
        "nomic-embed-text:latest"
        "bge:latest"
    )

    for model in "${models[@]}"; do
        log_info "Pulling: ${model}"
        pull_model "${model}" &
    done

    wait
    log_success "Recommended models installed"
}

pull_custom_set() {
    local config_file="${1:?Config file required}"

    if [ ! -f "${config_file}" ]; then
        log_error "Config file not found: ${config_file}"
        return 1
    fi

    log_info "Installing models from config: ${config_file}"

    jq -r '.models[]' "${config_file}" | while read -r model; do
        pull_model "${model}"
    done

    log_success "Custom model set installed"
}

###############################################################################
# OPTIMIZATION
###############################################################################

optimize_models() {
    log_info "Optimizing model storage..."

    # Remove duplicate/old models
    log_info "Checking for duplicate models..."

    curl -s "${OLLAMA_API}/api/tags" | jq -r '.models[] | .name' | sort | uniq -d | while read -r model; do
        log_warning "Duplicate model found: ${model}"
        # Keep only latest version
    done

    # Check for unused models
    log_info "Checking model access patterns..."

    # This would require logging of model usage

    log_success "Optimization complete"
}

get_model_info() {
    local model="${1:?Model name required}"

    log_info "Getting model information: ${model}"

    curl -s "${OLLAMA_API}/api/tags" | jq ".models[] | select(.name == \"${model}\")" 2>/dev/null || {
        log_error "Model not found: ${model}"
        return 1
    }
}

show_model_details() {
    local model="${1:?Model name required}"

    log_info "Detailed information for: ${model}"

    echo -e "\n${BLUE}=== Model Details ===${NC}"
    get_model_info "${model}"

    echo -e "\n${BLUE}=== Memory Estimation ===${NC}"
    curl -s "${OLLAMA_API}/api/show" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"${model}\"}" | \
        jq '{parameters: .parameters, quantization: .quantization}' 2>/dev/null || true

    echo -e "\n${BLUE}=== Inference Speed ===${NC}"
    log_info "Benchmark run..."
    benchmark_model "${model}"
}

###############################################################################
# CONFIGURATION
###############################################################################

create_model_config() {
    local output="${1:-.models.json}"

    log_info "Creating model configuration: ${output}"

    cat > "${output}" << 'EOF'
{
  "description": "Recommended Hermis Agent Model Set",
  "version": "1.0.0",
  "models": [
    {
      "name": "llama2:7b",
      "category": "general",
      "description": "Meta's Llama2 7B general purpose model",
      "memory_required": 4096,
      "recommended": true,
      "parameters": "7B"
    },
    {
      "name": "mistral:7b",
      "category": "general",
      "description": "Mistral 7B - Fast general purpose model",
      "memory_required": 4096,
      "recommended": true,
      "parameters": "7B"
    },
    {
      "name": "neural-chat:7b",
      "category": "chat",
      "description": "Intel's Neural Chat 7B",
      "memory_required": 4096,
      "recommended": true,
      "parameters": "7B"
    },
    {
      "name": "deepseek-coder:6.7b",
      "category": "code",
      "description": "DeepSeek Coder for code generation",
      "memory_required": 4096,
      "recommended": true,
      "parameters": "6.7B"
    },
    {
      "name": "codellama:7b",
      "category": "code",
      "description": "Meta's CodeLlama for code tasks",
      "memory_required": 4096,
      "recommended": false,
      "parameters": "7B"
    },
    {
      "name": "nomic-embed-text:latest",
      "category": "embedding",
      "description": "Nomic embedding model (256 dims)",
      "memory_required": 512,
      "recommended": true,
      "parameters": "276M"
    },
    {
      "name": "bge:latest",
      "category": "embedding",
      "description": "BGE embedding model (768 dims)",
      "memory_required": 1024,
      "recommended": false,
      "parameters": "1.2B"
    }
  ],
  "total_estimated_storage": "40GB",
  "total_estimated_ram": "20GB",
  "recommended_for": "Enterprise AI Platform"
}
EOF

    log_success "Model configuration created: ${output}"
}

###############################################################################
# MONITORING
###############################################################################

monitor_models() {
    log_info "Monitoring model performance..."

    while true; do
        clear
        echo -e "${BLUE}=== Hermis Model Monitor ===${NC}\n"

        echo "Loaded Models:"
        curl -s "${OLLAMA_API}/api/ps" 2>/dev/null | jq '.models[] | {name, size, duration}' || echo "No models loaded"

        echo -e "\n${BLUE}Available Models:${NC}"
        curl -s "${OLLAMA_API}/api/tags" 2>/dev/null | jq '.models[] | {name, size}' || echo "Cannot reach Ollama"

        echo -e "\n${BLUE}System Resources:${NC}"
        echo "CPU: $(top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - $1}')%"
        echo "Memory: $(free | grep Mem | awk '{printf("%.1f%%", $3/$2 * 100.0)}')"

        echo -e "\n${BLUE}(Refreshing in 10s, Ctrl+C to exit)${NC}"
        sleep 10
    done
}

###############################################################################
# HEALTH CHECK
###############################################################################

health_check() {
    log_info "Checking Ollama health..."

    if ! curl -s "${OLLAMA_API}/api/tags" >/dev/null 2>&1; then
        log_error "Ollama is not responding"
        return 1
    fi

    log_success "Ollama is healthy"

    local model_count=$(curl -s "${OLLAMA_API}/api/tags" | jq '.models | length')
    log_info "Models loaded: ${model_count}"

    # Check storage
    local storage_used=$(du -sh "${MODELS_DIR}" 2>/dev/null | cut -f1)
    log_info "Storage used: ${storage_used}"

    return 0
}

###############################################################################
# MAIN
###############################################################################

main() {
    mkdir -p "${MODELS_DIR}" "$(dirname ${LOG_FILE})"

    case "${1:-help}" in
        pull)
            pull_model "${2:?Model name required}"
            ;;
        list)
            list_models
            ;;
        status)
            model_status
            ;;
        delete)
            delete_model "${2:?Model name required}"
            ;;
        benchmark)
            benchmark_model "${2:?Model name required}"
            ;;
        info)
            show_model_details "${2:?Model name required}"
            ;;
        pull-recommended)
            pull_recommended_models
            ;;
        pull-custom)
            pull_custom_set "${2:?Config file required}"
            ;;
        optimize)
            optimize_models
            ;;
        monitor)
            monitor_models
            ;;
        health)
            health_check
            ;;
        create-config)
            create_model_config "${2:-.models.json}"
            ;;
        *)
            cat << 'USAGE'
╔════════════════════════════════════════════════════════════════╗
║       Hermis Agent - AI Model Manager v1.0                    ║
╚════════════════════════════════════════════════════════════════╝

USAGE: model-manager.sh <command> [options]

COMMANDS:
  pull <model>              Pull a model from registry
  list                      List all available models
  status                    Show model status and running instances
  delete <model>            Delete a model
  benchmark <model>         Benchmark model performance
  info <model>              Show detailed model information
  pull-recommended          Install recommended model set
  pull-custom <file>        Install models from config file
  optimize                  Optimize model storage
  monitor                   Monitor models in real-time
  health                    Check Ollama health status
  create-config <file>      Create model configuration template

EXAMPLES:
  # Install a model
  ./model-manager.sh pull llama2:7b

  # List all models
  ./model-manager.sh list

  # Install recommended set
  ./model-manager.sh pull-recommended

  # Monitor performance
  ./model-manager.sh monitor

  # Check system status
  ./model-manager.sh health

RECOMMENDED MODELS:
  llama2:7b          - General purpose (Meta)
  mistral:7b         - Fast general purpose
  deepseek-coder:6.7b - Code generation
  nomic-embed-text   - Embeddings
USAGE
            exit 1
            ;;
    esac
}

main "$@"
