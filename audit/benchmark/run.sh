#!/usr/bin/env bash
# CkredBSD benchmark runner for audit model quality.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/audit/config.env"
PARSER_LIB="${REPO_ROOT}/audit/lib/response_parser.sh"
MANIFEST_FILE="${REPO_ROOT}/audit/benchmark/manifest.tsv"
LOG_DIR="${REPO_ROOT}/audit/logs"

if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Audit not configured. Run ./tools/audit-setup.sh first."
    exit 1
fi

if ! command -v ollama >/dev/null 2>&1; then
    echo "ERROR: ollama is not installed or not found in PATH."
    exit 1
fi

# shellcheck source=../config.env
# shellcheck disable=SC1091
source "${CONFIG_FILE}"
# shellcheck source=../lib/response_parser.sh
# shellcheck disable=SC1090
source "${PARSER_LIB}"

if [ ! -f "${MANIFEST_FILE}" ]; then
    echo "ERROR: Manifest not found: ${MANIFEST_FILE}"
    exit 1
fi

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
REPORT_FILE="${LOG_DIR}/benchmark-${TIMESTAMP}.md"

mkdir -p "${LOG_DIR}"

tp=0
tn=0
fp=0
fn=0
parse_errors=0
total=0

safe_ratio() {
    local numerator="$1"
    local denominator="$2"
    if [ "${denominator}" -eq 0 ]; then
        echo "0.0000"
        return 0
    fi
    awk -v n="${numerator}" -v d="${denominator}" 'BEGIN { printf "%.4f", n / d }'
}

audit_prompt='You are a kernel security auditor reviewing C source code.

Analyze the following code for security vulnerabilities. Focus on:
- Buffer overflows and out-of-bounds memory access
- Use-after-free and double-free
- Race conditions in concurrent contexts
- Integer overflow in size calculations
- Privilege escalation paths
- Input validation weaknesses

Output format rules:
1) If no vulnerabilities are found, output exactly: NO_FINDINGS
2) If vulnerabilities are found, include all fields:
SEVERITY: ...
LOCATION: ...
TYPE: ...
DESCRIPTION: ...
EXPLOIT_SCENARIO: ...
SUGGESTED_FIX: ...'

{
    echo "# CkredBSD Audit Benchmark Report"
    echo ""
    echo "- **Date:** $(date -u)"
    echo "- **Model:** ${CKRED_AUDIT_MODEL}"
    echo "- **Dataset:** audit/benchmark/manifest.tsv"
    echo ""
    echo "---"
    echo ""
    echo "| Case | Expected | Predicted | Status |"
    echo "|------|----------|-----------|--------|"
} > "${REPORT_FILE}"

while IFS=$'\t' read -r id expected_label expected_type file_path; do
    [ -z "${id}" ] && continue
    [[ "${id}" =~ ^# ]] && continue

    case_file="${REPO_ROOT}/audit/benchmark/${file_path}"
    if [ ! -f "${case_file}" ]; then
        echo "ERROR: case file not found: ${case_file}"
        exit 1
    fi

    code=$(cat "${case_file}")
    prompt="${audit_prompt}

Ground-truth expected type (for context only, do not echo): ${expected_type}

File: ${file_path}
\`\`\`c
${code}
\`\`\`"

    raw_response=$(printf '%s' "${prompt}" | ollama run "${CKRED_AUDIT_MODEL}" 2>&1)
    normalized_response="$(printf '%s' "${raw_response}" | ckred_normalize_response)"
    ckred_classify_response "${normalized_response}"
    parse_kind="${CKRED_PARSE_KIND}"
    parse_reason="${CKRED_PARSE_REASON}"

    predicted_label="unknown"
    status="ok"

    if [ "${parse_kind}" = "finding" ]; then
        predicted_label="vulnerable"
    elif [ "${parse_kind}" = "no_findings" ]; then
        predicted_label="clean"
    else
        predicted_label="parse_error"
        status="parse_error"
        parse_errors=$((parse_errors + 1))
    fi

    if [ "${predicted_label}" = "vulnerable" ] && [ "${expected_label}" = "vulnerable" ]; then
        tp=$((tp + 1))
    elif [ "${predicted_label}" = "clean" ] && [ "${expected_label}" = "clean" ]; then
        tn=$((tn + 1))
    elif [ "${predicted_label}" = "vulnerable" ] && [ "${expected_label}" = "clean" ]; then
        fp=$((fp + 1))
    elif [ "${predicted_label}" = "clean" ] && [ "${expected_label}" = "vulnerable" ]; then
        fn=$((fn + 1))
    fi

    total=$((total + 1))

    {
        echo "| ${id} | ${expected_label} | ${predicted_label} | ${status} |"
        if [ "${status}" = "parse_error" ]; then
            echo ""
            echo "<details><summary>${id} parse error detail</summary>"
            echo ""
            echo "- Reason: ${parse_reason}"
            echo "- Raw model output excerpt:"
            echo ""
            echo '```'
            printf '%s\n' "${normalized_response}" | head -n 20
            echo '```'
            echo ""
            echo "</details>"
            echo ""
        fi
    } >> "${REPORT_FILE}"
done < "${MANIFEST_FILE}"

precision="$(safe_ratio "${tp}" "$((tp + fp))")"
recall="$(safe_ratio "${tp}" "$((tp + fn))")"
accuracy="$(safe_ratio "$((tp + tn))" "${total}")"
f1="$(awk -v p="${precision}" -v r="${recall}" 'BEGIN { if (p + r == 0) { printf "0.0000" } else { printf "%.4f", 2 * p * r / (p + r) } }')"

{
    echo ""
    echo "## Metrics"
    echo ""
    echo "- Total cases: ${total}"
    echo "- True positives: ${tp}"
    echo "- True negatives: ${tn}"
    echo "- False positives: ${fp}"
    echo "- False negatives: ${fn}"
    echo "- Parse errors: ${parse_errors}"
    echo "- Precision: ${precision}"
    echo "- Recall: ${recall}"
    echo "- F1 score: ${f1}"
    echo "- Accuracy: ${accuracy}"
} >> "${REPORT_FILE}"

echo "Benchmark report written to: ${REPORT_FILE}"
echo "Precision=${precision} Recall=${recall} F1=${f1} Accuracy=${accuracy} ParseErrors=${parse_errors}"

if [ "${parse_errors}" -gt 0 ]; then
    exit 2
fi
