#!/usr/bin/env bash
# CkredBSD — OpenBSD source integration script
# Clones the OpenBSD source tree and sets up the audit environment

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENBSD_MIRROR="${OPENBSD_MIRROR:-https://github.com/openbsd/src.git}"
SRC_DIR="${REPO_ROOT}/src/openbsd"
AUDIT_PRIORITY_SUBSYSTEMS=(
    "sys/netinet"    # IPv4 stack — highest attack surface
    "sys/netinet6"   # IPv6 stack
    "sys/kern"       # Core syscalls
    "sys/security"   # MAC, audit
    "sys/net"        # Network core
    "lib/libssl"     # TLS
    "lib/libcrypto"  # Cryptography
)

echo "╔══════════════════════════════════════════╗"
echo "║     CkredBSD — OpenBSD Source Setup      ║"
echo "║         Immaculated till the end         ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Check dependencies ────────────────────────────────────────────────────────
check_dep() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: $1 is required but not installed."
        exit 1
    fi
}

check_dep git
check_dep clang

echo "[1/4] Cloning OpenBSD source..."
echo "      Mirror: ${OPENBSD_MIRROR}"
echo "      Target: ${SRC_DIR}"
echo ""

if [ -d "${SRC_DIR}" ]; then
    echo "      Source directory already exists. Pulling latest..."
    cd "${SRC_DIR}" && git pull --ff-only
else
    # Sparse clone — only the subsystems we need for initial audit
    git clone \
        --filter=blob:none \
        --sparse \
        --depth=1 \
        "${OPENBSD_MIRROR}" \
        "${SRC_DIR}"

    cd "${SRC_DIR}"

    echo "[2/4] Setting up sparse checkout for priority subsystems..."
    git sparse-checkout set \
        sys/netinet \
        sys/netinet6 \
        sys/kern \
        sys/security \
        sys/net \
        sys/sys \
        lib/libssl \
        lib/libcrypto \
        usr.sbin \
        usr.bin

    echo "      Priority subsystems checked out."
fi

echo ""
echo "[3/4] Generating subsystem index for audit pipeline..."

INDEX_FILE="${REPO_ROOT}/audit/openbsd-index.txt"
mkdir -p "${REPO_ROOT}/audit"

{
    echo "# CkredBSD — OpenBSD subsystem audit index"
    echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Priority order: highest attack surface first"
    echo ""
    for subsystem in "${AUDIT_PRIORITY_SUBSYSTEMS[@]}"; do
        if [ -d "${SRC_DIR}/${subsystem}" ]; then
            count=$(find "${SRC_DIR}/${subsystem}" -name "*.c" -o -name "*.h" | wc -l)
            echo "${subsystem} (${count} files)"
        fi
    done
} > "${INDEX_FILE}"

echo "      Index written to audit/openbsd-index.txt"

echo ""
echo "[4/4] Summary"
echo ""

TOTAL_C=$(find "${SRC_DIR}" -name "*.c" 2>/dev/null | wc -l)
TOTAL_H=$(find "${SRC_DIR}" -name "*.h" 2>/dev/null | wc -l)
TOTAL_LINES=$(find "${SRC_DIR}" -name "*.c" -o -name "*.h" 2>/dev/null | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')

echo "      C source files:  ${TOTAL_C}"
echo "      Header files:    ${TOTAL_H}"
echo "      Total lines:     ${TOTAL_LINES}"
echo ""
echo "Priority subsystems ready for audit:"
for subsystem in "${AUDIT_PRIORITY_SUBSYSTEMS[@]}"; do
    if [ -d "${SRC_DIR}/${subsystem}" ]; then
        count=$(find "${SRC_DIR}/${subsystem}" -name "*.c" | wc -l)
        echo "    ✓  ${subsystem} (${count} .c files)"
    else
        echo "    ✗  ${subsystem} (not found)"
    fi
done

echo ""
echo "Next step: run ./tools/audit-setup.sh to configure the AI pipeline"
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║              Setup complete              ║"
echo "╚══════════════════════════════════════════╝"
