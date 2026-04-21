#!/usr/bin/env bash
# CkredBSD — AI Audit Pipeline Setup
# Configures Ollama + CodeQL for local security auditing

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFERRED_MODEL="${CKRED_AUDIT_MODEL:-}"
PREFERRED_GPU="${CKRED_OLLAMA_GPU:-}"

# Detect the local GPU so we can choose an appropriate Ollama model.
detect_gpu_type() {
    if ! command -v lspci &>/dev/null; then
        return 1
    fi

    GPU_INFO=$(lspci -nn | grep -E 'VGA|3D' | tr '[:upper:]' '[:lower:]' || true)
    if echo "${GPU_INFO}" | grep -q 'nvidia'; then
        echo nvidia
        return 0
    elif echo "${GPU_INFO}" | grep -q 'amd'; then
        echo amd
        return 0
    elif echo "${GPU_INFO}" | grep -q 'intel'; then
        echo intel
        return 0
    fi

    return 1
}

is_laptop() {
    if [ -d /sys/class/power_supply ]; then
        for f in /sys/class/power_supply/*; do
            [ -e "$f" ] || continue
            case "$(basename "$f")" in
                BAT*|*battery*)
                    return 0
                    ;;
            esac
        done
    fi
    if [ -r /sys/class/dmi/id/chassis_type ]; then
        case "$(cat /sys/class/dmi/id/chassis_type)" in
            8|9|10|14) return 0 ;; # Portable, laptop, notebook, subnotebook
        esac
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

select_gpu_backend() {
    local gpu="$1"
    case "${gpu}" in
        nvidia)
            echo "nvidia"
            ;;
        amd)
            echo "amd"
            ;;
        *)
            echo ""
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

# Choose model automatically when not explicitly set.
if [ -z "${PREFERRED_MODEL}" ]; then
    if GPU_TYPE=$(detect_gpu_type); then
        echo "      GPU detected: ${GPU_TYPE}"
        PREFERRED_MODEL=$(select_model_by_gpu "${GPU_TYPE}")
    else
        echo "      No compatible GPU detected or lspci missing. Using fallback model."
        PREFERRED_MODEL="qwen2.5-coder:7b"
    fi
fi

# Choose Ollama GPU backend when possible.
if [ -z "${PREFERRED_GPU}" ]; then
    if [ -z "${GPU_TYPE:-}" ]; then
        GPU_TYPE=$(detect_gpu_type) || true
    fi
    PREFERRED_GPU=$(select_gpu_backend "${GPU_TYPE}")
fi

if [ -n "${PREFERRED_GPU}" ]; then
    echo "      Selected GPU backend: ${PREFERRED_GPU}"
else
    echo "      No supported Ollama GPU backend selected; will run on CPU."
fi

echo "      Selected model: ${PREFERRED_MODEL}"

echo ""
# Check if GPU is being used
if ollama run --help 2>/dev/null | grep -q "--gpu"; then
    echo "      GPU acceleration: available (ollama supports --gpu)"
    OLLAMA_GPU_SUPPORTED=true
else
    echo "      WARNING: installed Ollama does not advertise --gpu support"
    OLLAMA_GPU_SUPPORTED=false
    if [ "${PREFERRED_GPU}" = "nvidia" ]; then
        echo "      Detected NVIDIA backend but Ollama does not report --gpu support."
        echo "      Make sure you are using an Ollama build with CUDA/NVIDIA support and that nvidia-smi works."
    elif [ "${PREFERRED_GPU}" = "amd" ]; then
        echo "      For AMD cards, make sure ROCm is installed and HSA_OVERRIDE_GFX_VERSION is set."
    else
        echo "      If your GPU is NVIDIA or AMD, install the appropriate Ollama backend."
    fi
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
CKRED_OLLAMA_GPU="${PREFERRED_GPU}"
CKRED_OPENBSD_SRC="${REPO_ROOT}/src/openbsd"
CKRED_AUDIT_LOGS="${REPO_ROOT}/audit/logs"
CKRED_CHUNK_SIZE=400        # lines per chunk sent to AI
CKRED_PRIORITY_FIRST=true   # audit high-priority subsystems first
CKRED_OLLAMA_GPU_SUPPORTED=${OLLAMA_GPU_SUPPORTED:-false}
EOF

mkdir -p "${REPO_ROOT}/audit/logs"

echo "      Config written to audit/config.env"
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          Audit pipeline ready            ║"
echo "║                                          ║"
echo "║  Run: ./audit/run.sh --path sys/netinet  ║"
echo "╚══════════════════════════════════════════╝"
