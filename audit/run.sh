#!/usr/bin/env bash
# CkredBSD — AI Security Audit Runner
# Analyzes OpenBSD source for vulnerabilities using local AI

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/audit/config.env"
PARSER_LIB="${REPO_ROOT}/audit/lib/response_parser.sh"

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Audit not configured. Run ./tools/audit-setup.sh first."
    exit 1
fi

# shellcheck source=./config.env
# shellcheck disable=SC1091
source "${CONFIG_FILE}"
# shellcheck source=./lib/response_parser.sh
# shellcheck disable=SC1090,SC1091
source "${PARSER_LIB}"

if ! command -v ollama >/dev/null 2>&1; then
    echo "ERROR: ollama is not installed or not found in PATH."
    echo "Run ./tools/audit-setup.sh first and verify Ollama installation."
    exit 1
fi

AUDIT_PATH=""
DIFF_MODE=false
DIFF_RANGE=""
SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-medium}"
ALLOW_PARSE_ERRORS=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --path <subsystem>     Audit a specific subsystem (e.g. sys/netinet)"
    echo "  --diff <range>         Audit only changed files (e.g. HEAD~1..HEAD)"
    echo "  --severity <level>     Minimum severity to report (low|medium|high|critical)"
    echo "  --allow-parse-errors   Do not fail run when model output is unparseable"
    echo "  --help                 Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 --path sys/netinet"
    echo "  $0 --diff HEAD~1..HEAD"
    echo "  $0 --path sys/kern --severity high"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --path)     AUDIT_PATH="$2"; shift 2 ;;
        --diff)     DIFF_MODE=true; DIFF_RANGE="$2"; shift 2 ;;
        --severity) SEVERITY_THRESHOLD="$2"; shift 2 ;;
        --allow-parse-errors) ALLOW_PARSE_ERRORS=true; shift ;;
        --help)     usage; exit 0 ;;
        *)          echo "Unknown option: $1"; usage; exit 1 ;;
    esac
done

if [ -z "${AUDIT_PATH}" ] && [ "$DIFF_MODE" = false ]; then
    echo "ERROR: specify --path or --diff"
    usage
    exit 1
fi

# ── Setup ─────────────────────────────────────────────────────────────────────
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
LOG_FILE="${CKRED_AUDIT_LOGS}/audit-${TIMESTAMP}.log"
FINDINGS_FILE="${CKRED_AUDIT_LOGS}/findings-${TIMESTAMP}.md"

mkdir -p "${CKRED_AUDIT_LOGS}"
touch "${LOG_FILE}"

AUDIT_PROMPT='You are a kernel security auditor reviewing OpenBSD C source code.

Analyze the following code for security vulnerabilities. Focus on:
- Buffer overflows and out-of-bounds memory access
- Use-after-free and double-free
- Race conditions in concurrent or interrupt contexts
- Integer overflow in size calculations or pointer arithmetic
- Privilege escalation paths
- Input validation weaknesses on network data
- Interaction bugs between subsystems

For each finding, respond with:
SEVERITY: [CRITICAL|HIGH|MEDIUM|LOW]
LOCATION: [file:line]
TYPE: [vulnerability class]
DESCRIPTION: [clear explanation of the vulnerability]
EXPLOIT_SCENARIO: [how an attacker could use this]
SUGGESTED_FIX: [concrete remediation]
---

If no vulnerabilities are found, respond with: NO_FINDINGS

Code to analyze:'

echo "╔══════════════════════════════════════════╗"
echo "║      CkredBSD Security Audit Run        ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Model:     ${CKRED_AUDIT_MODEL}"
echo "Threshold: ${SEVERITY_THRESHOLD}"
echo "Log:       ${LOG_FILE}"
echo ""

# ── Get files to audit ────────────────────────────────────────────────────────
if [ "$DIFF_MODE" = true ]; then
    echo "Mode: diff — ${DIFF_RANGE}"
    FILES=$(git -C "${CKRED_OPENBSD_SRC}" diff --name-only "${DIFF_RANGE}" 2>/dev/null \
        | grep -E '\.(c|h)$' || true)
else
    echo "Mode: subsystem — ${AUDIT_PATH}"
    TARGET="${CKRED_OPENBSD_SRC}/${AUDIT_PATH}"
    if [ ! -d "${TARGET}" ]; then
        echo "ERROR: path not found: ${TARGET}"
        echo "Run ./tools/clone-openbsd.sh first."
        exit 1
    fi
    FILES=$(find "${TARGET}" \( -name "*.c" -o -name "*.h" \) | sort)
fi

FILE_COUNT=$(echo "${FILES}" | grep -c . || echo 0)
echo "Files to audit: ${FILE_COUNT}"
echo ""

{
    echo "# CkredBSD Security Audit Log"
    echo ""
    echo "- Date: $(date -u)"
    echo "- Model: ${CKRED_AUDIT_MODEL}"
    echo "- Target: ${AUDIT_PATH:-diff:${DIFF_RANGE}}"
    echo "- Files analyzed: ${FILE_COUNT}"
    echo ""
} > "${LOG_FILE}"

# ── Initialize findings report ────────────────────────────────────────────────
{
    echo "# CkredBSD Security Audit Report"
    echo ""
    echo "- **Date:** $(date -u)"
    echo "- **Model:** ${CKRED_AUDIT_MODEL}"
    echo "- **Target:** ${AUDIT_PATH:-diff:${DIFF_RANGE}}"
    echo "- **Files analyzed:** ${FILE_COUNT}"
    echo ""
    echo "---"
    echo ""
} > "${FINDINGS_FILE}"

FINDING_COUNT=0
ERROR_COUNT=0
FILE_NUM=0

# ── Audit each file ───────────────────────────────────────────────────────────
while IFS= read -r file; do
    [ -z "$file" ] && continue
    FILE_NUM=$((FILE_NUM + 1))

    FULL_PATH="${CKRED_OPENBSD_SRC}/${file}"
    [ ! -f "${FULL_PATH}" ] && FULL_PATH="${file}"
    [ ! -f "${FULL_PATH}" ] && continue

    echo -ne "\r[${FILE_NUM}/${FILE_COUNT}] $(basename "${FULL_PATH}")                    "

    # Split into chunks to fit context window
    TOTAL_LINES=$(wc -l < "${FULL_PATH}")
    CHUNK_START=1

    while [ "${CHUNK_START}" -le "${TOTAL_LINES}" ]; do
        CHUNK_END=$((CHUNK_START + CKRED_CHUNK_SIZE - 1))
        CHUNK=$(sed -n "${CHUNK_START},${CHUNK_END}p" "${FULL_PATH}")

        PROMPT="${AUDIT_PROMPT}

File: ${file} (lines ${CHUNK_START}-${CHUNK_END})

\`\`\`c
${CHUNK}
\`\`\`"

        OLLAMA_ARGS=()
        if [ -n "${CKRED_OLLAMA_GPU:-}" ]; then
            if ollama run --help 2>&1 | grep -q -- "--gpu"; then
                OLLAMA_ARGS+=(--gpu "${CKRED_OLLAMA_GPU}")
            else
                echo "Note: installed ollama does not support --gpu; skipping GPU flag" >> "${LOG_FILE}"
            fi
        fi

        RESPONSE_RAW=$(echo "${PROMPT}" | ollama run "${CKRED_AUDIT_MODEL}" "${OLLAMA_ARGS[@]}" 2>&1)
        RC=$?
        if [ ${RC} -ne 0 ]; then
            echo ""
            echo "ERROR: ollama run failed on ${file}:${CHUNK_START} (rc=${RC})."
            echo "See ${LOG_FILE} for the raw output."
            echo "${TIMESTAMP} | ${file}:${CHUNK_START} | OLLAMA_ERROR | rc=${RC}" >> "${LOG_FILE}"
            echo "${RESPONSE_RAW}" >> "${LOG_FILE}"
            exit 1
        fi

        RESPONSE="$(printf '%s' "${RESPONSE_RAW}" | ckred_normalize_response)"
        ckred_classify_response "${RESPONSE}"
        PARSE_KIND="${CKRED_PARSE_KIND}"
        PARSE_REASON="${CKRED_PARSE_REASON}"

        # Log every raw response so we can inspect what the model returned.
        {
            echo "---"
            echo "CHUNK: ${file}:${CHUNK_START}-${CHUNK_END}"
            echo "RESPONSE_RAW_START"
            echo "${RESPONSE_RAW}"
            echo "RESPONSE_RAW_END"
            echo "RESPONSE_NORMALIZED_START"
            echo "${RESPONSE}"
            echo "RESPONSE_NORMALIZED_END"
            echo "PARSE_KIND: ${PARSE_KIND}"
            [ -n "${PARSE_REASON}" ] && echo "PARSE_REASON: ${PARSE_REASON}"
        } >> "${LOG_FILE}"

        if [ "${PARSE_KIND}" = "finding" ]; then

            FINDING_COUNT=$((FINDING_COUNT + 1))

            {
                echo "## Finding #${FINDING_COUNT}"
                echo ""
                echo "\`\`\`"
                echo "${RESPONSE}"
                echo "\`\`\`"
                echo ""
            } >> "${FINDINGS_FILE}"

            echo "${TIMESTAMP} | ${file}:${CHUNK_START} | ${RESPONSE}" >> "${LOG_FILE}"
        elif [ "${PARSE_KIND}" = "parse_error" ]; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            echo "WARNING: unparseable model response for ${file}:${CHUNK_START}-${CHUNK_END}: ${PARSE_REASON}" >> "${LOG_FILE}"
        fi

        CHUNK_START=$((CHUNK_END + 1))
        # Brief pause between chunks to avoid saturating VRAM on large files
        sleep 0.3
    done

done <<< "${FILES}"

echo ""
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           Audit Complete                 ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Files analyzed:  ${FILE_NUM}"
echo "Findings:        ${FINDING_COUNT}"
echo "Errors:          ${ERROR_COUNT}"
echo "Report:          ${FINDINGS_FILE}"
echo ""

if [ "${FINDING_COUNT}" -eq 0 ]; then
    if [ "${ERROR_COUNT}" -eq 0 ]; then
        echo "No findings were detected."
    else
        echo "No verified findings due to parser errors."
        echo "Parse errors: ${ERROR_COUNT}"
        echo "Check ${LOG_FILE} for details."
    fi
fi

if [ "${FINDING_COUNT}" -gt 0 ]; then
    echo "Review findings and submit verified ones via SECURITY.md process."
    echo "Verified findings are eligible for IMMAC rewards."
fi

if [ "${FINDING_COUNT}" -eq 0 ] && [ "${ERROR_COUNT}" -eq 0 ]; then
    {
        echo "## No findings"
        echo ""
        echo "The AI audit did not identify any vulnerabilities in the analyzed files."
    } >> "${FINDINGS_FILE}"
fi

if [ "${ERROR_COUNT}" -gt 0 ]; then
    {
        echo "## Audit blocked by parse errors"
        echo ""
        echo "- Unparseable model responses: ${ERROR_COUNT}"
        echo "- Findings count may be incomplete."
        echo "- Inspect log for chunk-level details: ${LOG_FILE}"
    } >> "${FINDINGS_FILE}"

    if [ "${ALLOW_PARSE_ERRORS}" != true ]; then
        exit 2
    fi
fi
