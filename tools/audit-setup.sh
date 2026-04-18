#!/usr/bin/env bash
# CkredBSD — AI Audit Pipeline Setup
# Configures Ollama + CodeQL for local security auditing

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFERRED_MODEL="${CKRED_AUDIT_MODEL:-}"

# Detect the local GPU so we can choose an appropriate Ollama model.
detect_gpu() {
    if ! command -v lspci &>/dev/null; then
        return 1
    fi

    GPU_INFO=$(lspci -nn | grep -E 'VGA|3D' | tr '[:upper:]' '[:lower:]' || true)
    if echo "${GPU_INFO}" | grep -q 'amd'; then
        echo amd
        return 0
    elif echo "${GPU_INFO}" | grep -q 'nvidia'; then
        echo nvidia
        return 0
    elif echo "${GPU_INFO}" | grep -q 'intel'; then
        echo intel
        return 0
    fi

    return 1
}

select_model_by_gpu() {
    local gpu="$1"
    case "${gpu}" in
        amd|nvidia)
            echo "qwen2.5-coder:14b"
            ;;
        intel)
            echo "qwen2.5-coder:7b"
            ;;
        *)
            echo "qwen2.5-coder:7b"
            ;;
    esac
}

echo "╔══════════════════════════════════════════╗"
echo "║   CkredBSD — AI Audit Pipeline Setup    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Check Ollama ──────────────────────────────────────────────────────────────
echo "[1/3] Checking Ollama..."
if ! command -v ollama &>/dev/null; then
    echo "      Ollama not found. Install from: https://ollama.com"
    echo "      For AMD RDNA4 (RX 9060 XT): use ollama-rocm from AUR"
    echo "      Then re-run this script."
    exit 1
fi

echo "      Ollama found: $(ollama --version 2>/dev/null || echo 'unknown version')"

# Check if GPU is being used
if ollama run --help 2>/dev/null | grep -q "gpu"; then
    echo "      GPU acceleration: available"
else
    echo "      WARNING: GPU acceleration may not be configured"
    echo "      For AMD cards, ensure ROCm is installed and HSA_OVERRIDE_GFX_VERSION is set"
fi

echo ""
echo "[2/3] Pulling audit model: ${PREFERRED_MODEL}..."
echo "      This may take a while on first run (~9GB download)"
echo ""
ollama pull "${PREFERRED_MODEL}" || {
    echo "      Failed to pull ${PREFERRED_MODEL}"
    echo "      Trying fallback: qwen2.5-coder:7b"
    ollama pull "qwen2.5-coder:7b"
    PREFERRED_MODEL="qwen2.5-coder:7b"
}

echo ""
echo "[3/3] Writing audit configuration..."

CONFIG_FILE="${REPO_ROOT}/audit/config.env"
cat > "${CONFIG_FILE}" << EOF
# CkredBSD Audit Pipeline Configuration
# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

CKRED_AUDIT_MODEL="${PREFERRED_MODEL}"
CKRED_OPENBSD_SRC="${REPO_ROOT}/src/openbsd"
CKRED_AUDIT_LOGS="${REPO_ROOT}/audit/logs"
CKRED_CHUNK_SIZE=400        # lines per chunk sent to AI
CKRED_PRIORITY_FIRST=true   # audit high-priority subsystems first
EOF

mkdir -p "${REPO_ROOT}/audit/logs"

echo "      Config written to audit/config.env"
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          Audit pipeline ready            ║"
echo "║                                          ║"
echo "║  Run: ./audit/run.sh --path sys/netinet  ║"
echo "╚══════════════════════════════════════════╝"
