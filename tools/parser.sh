#!/usr/bin/env bash
# CkredBSD — OpenBSD source parser for Ollama
# Scans OpenBSD C source and produces CkredBSD migration/analysis notes.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/audit/config.env"

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Audit config not found. Run ./tools/audit-setup.sh first."
    exit 1
fi

# shellcheck source=../audit/config.env
# shellcheck disable=SC2129  # multiple separate append redirects are intentional for readability
source "${CONFIG_FILE}"

MODEL="${CKRED_AUDIT_MODEL:-qwen2.5-coder:14b}"
CHUNK_SIZE="${CKRED_CHUNK_SIZE:-300}"
OUTPUT_DIR="${REPO_ROOT}/src/ckredbsd/parser-output"

mkdir -p "${OUTPUT_DIR}"

AUDIT_PATH=""
DIFF_MODE=false
DIFF_RANGE=""
RUST_SCORE_MODE=false

usage() {
    cat <<USAGE
Usage: $0 [OPTIONS]

Options:
  --path <subsystem>   Parse a specific OpenBSD subsystem (e.g. sys/netinet)
  --diff <range>       Parse only changed files (e.g. HEAD~1..HEAD)
  --help               Show this help

Examples:
  $0 --path sys/netinet
  $0 --diff HEAD~1..HEAD
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) AUDIT_PATH="$2"; shift 2 ;; 
        --diff) DIFF_MODE=true; DIFF_RANGE="$2"; shift 2 ;; 
        --score) RUST_SCORE_MODE=true; shift ;; 
        --help) usage; exit 0 ;; 
        *) echo "Unknown option: $1"; usage; exit 1 ;;
    esac
 done

if [ -z "${AUDIT_PATH}" ] && [ "${DIFF_MODE}" = false ]; then
    echo "ERROR: specify --path or --diff"
    usage
    exit 1
fi

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_FILE="${OUTPUT_DIR}/parser-report-${TIMESTAMP}.md"

{
    echo "# CkredBSD OpenBSD Parser Report"
    echo ""
    echo "- Date: $(date -u)"
    echo "- Model: ${MODEL}"
    echo "- Target: ${AUDIT_PATH:-diff:${DIFF_RANGE}}"
    echo "- Chunk size: ${CHUNK_SIZE} lines"
    if [ "${RUST_SCORE_MODE}" = true ]; then
        echo "- Mode: Rust suitability scoring"
    fi
    echo ""
    echo "---"
    echo ""
} > "${REPORT_FILE}"

if [ "${DIFF_MODE}" = true ]; then
    echo "Mode: diff — ${DIFF_RANGE}"
    FILES=$(git -C "${CKRED_OPENBSD_SRC}" diff --name-only "${DIFF_RANGE}" 2>/dev/null | grep -E '\.(c|h)$' || true)
else
    echo "Mode: subsystem — ${AUDIT_PATH}"
    TARGET="${CKRED_OPENBSD_SRC}/${AUDIT_PATH}"
    if [ ! -d "${TARGET}" ]; then
        echo "ERROR: path not found: ${TARGET}"
        echo "Run ./tools/clone-openbsd.sh first."
        exit 1
    fi
    FILES=$(find "${TARGET}" \( -name '*.c' -o -name '*.h' \) | sed "s#^${CKRED_OPENBSD_SRC}/##" | sort)
fi

FILE_COUNT=$(echo "${FILES}" | grep -c . || echo 0)

echo "Files to parse: ${FILE_COUNT}"

echo "" >> "${REPORT_FILE}"

echo "## Summary" >> "${REPORT_FILE}"
echo "- Files parsed: ${FILE_COUNT}" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

FILE_NUM=0

while IFS= read -r file; do
    [ -z "${file}" ] && continue
    FILE_NUM=$((FILE_NUM + 1))

    FULL_PATH="${CKRED_OPENBSD_SRC}/${file}"
    [ ! -f "${FULL_PATH}" ] && FULL_PATH="${file}"
    [ ! -f "${FULL_PATH}" ] && continue

    echo -ne "\r[${FILE_NUM}/${FILE_COUNT}] $(basename "${FULL_PATH}")                    "

    TOTAL_LINES=$(wc -l < "${FULL_PATH}")
    CHUNK_START=1

    echo "### ${file}" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"

    while [ "${CHUNK_START}" -le "${TOTAL_LINES}" ]; do
        CHUNK_END=$((CHUNK_START + CHUNK_SIZE - 1))
        if [ "${CHUNK_END}" -gt "${TOTAL_LINES}" ]; then
            CHUNK_END=${TOTAL_LINES}
        fi

        CHUNK=$(sed -n "${CHUNK_START},${CHUNK_END}p" "${FULL_PATH}")

        SCORE_INSTRUCTION=""
        if [ "${RUST_SCORE_MODE}" = true ]; then
            SCORE_INSTRUCTION="- Rust suitability score: assign a value from 1 (poor) to 5 (excellent) and explain why."
        fi

        PROMPT=$(printf '%s\n' \
            "You are an AI engineer porting OpenBSD source to the CkredBSD project." \
            "Analyze the following C code chunk and produce a concise migration report." \
            "" \
            "For each chunk, answer in markdown with these sections:" \
            "- Summary: what the code does" \
            "- CkredBSD migration notes: what should change for CkredBSD" \
            "- Rust migration guidance: should this stay in C, be wrapped, or be replaced by Rust, and why" \
            "- Safety issues: any memory, concurrency, or design concerns" \
            "- Suggested next step: one concrete action for a developer" \
            "${SCORE_INSTRUCTION}" \
            "" \
            "Respond only in markdown." \
            "" \
            "File: ${file}" \
            "Lines: ${CHUNK_START}-${CHUNK_END}" \
            "" \
            '```c' \
            "${CHUNK}" \
            '```' \
        )

        RESPONSE=$(printf '%s' "${PROMPT}" | ollama run "${MODEL}" 2>/dev/null || echo "PARSER_ERROR")

        echo "#### Chunk ${CHUNK_START}-${CHUNK_END}" >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"
        echo '```' >> "${REPORT_FILE}"
        echo "${RESPONSE}" >> "${REPORT_FILE}"
        echo '```' >> "${REPORT_FILE}"
        echo "" >> "${REPORT_FILE}"

        CHUNK_START=$((CHUNK_END + 1))
    done

done <<< "${FILES}"

echo ""
echo "Parser output written to: ${REPORT_FILE}"

echo ""
echo "Finished ${FILE_NUM} files."
