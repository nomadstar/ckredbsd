#!/usr/bin/env bash

# Shared helpers for normalizing and classifying LLM audit output.

ckred_strip_ansi() {
    perl -pe 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\e\][^\a]*(?:\a|\e\\)//g; s/\r/\n/g'
}

ckred_normalize_response() {
    ckred_strip_ansi \
        | LC_ALL=C tr -cd '\11\12\15\40-\176' \
        | sed 's/[[:space:]]\+$//' \
        | awk 'NF { print }'
}

ckred_classify_response() {
    local response="$1"
    local required_fields=(
        "SEVERITY"
        "LOCATION"
        "TYPE"
        "DESCRIPTION"
        "EXPLOIT_SCENARIO"
        "SUGGESTED_FIX"
    )

    # These variables are populated for callers (sourced scripts).
    # shellcheck disable=SC2034
    CKRED_PARSE_KIND=""
    CKRED_PARSE_REASON=""

    if echo "${response}" | grep -Eq 'SEVERITY[[:space:]]*:'; then
        local missing=()
        local field
        for field in "${required_fields[@]}"; do
            if ! echo "${response}" | grep -Eq "${field}[[:space:]]*:"; then
                missing+=("${field}")
            fi
        done

        if [ "${#missing[@]}" -eq 0 ]; then
            CKRED_PARSE_KIND="finding"
            return 0
        fi

        CKRED_PARSE_REASON="missing required fields: ${missing[*]}"
        CKRED_PARSE_KIND="parse_error"
        return 0
    fi

    if echo "${response}" | grep -Eq '(^|[^A-Z_])NO_FINDINGS([^A-Z_]|$)'; then
        CKRED_PARSE_KIND="no_findings"
        return 0
    fi

    CKRED_PARSE_REASON="response did not contain NO_FINDINGS or structured finding fields"
    CKRED_PARSE_KIND="parse_error"
}

# Export these globals so callers (scripts that `source` this file) receive them
# and to make intent explicit for static analyzers like ShellCheck.
export CKRED_PARSE_KIND CKRED_PARSE_REASON
