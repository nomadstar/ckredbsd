#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

BASE_REF="${GITHUB_BASE_REF:-}"
EXCLUDE_PATHS=(".git" "node_modules" "IMMAC/cache" "IMMAC/artifacts")
REGEX='0x[a-fA-F0-9]{40}'

echo "Repository root: $REPO_ROOT"
if [ -n "$BASE_REF" ]; then
  echo "Base ref provided: $BASE_REF"
  git fetch origin "$BASE_REF" || true
  CHANGED_FILES=$(git diff --name-only "origin/$BASE_REF...HEAD" || true)
else
  echo "No base ref: scanning tracked files"
  CHANGED_FILES=$(git ls-files)
fi

if [ -z "$CHANGED_FILES" ]; then
  echo "No files to inspect."
  exit 0
fi

found=0
while IFS= read -r file; do
  # skip excluded paths
  skip=0
  for p in "${EXCLUDE_PATHS[@]}"; do
    if [[ "$file" == "$p"* ]]; then skip=1; break; fi
  done
  if [ "$skip" -eq 1 ]; then continue; fi
  if [ ! -f "$file" ]; then continue; fi

  # search for ethereum-style addresses
  while IFS=: read -r line content; do
    if [ -z "$line" ]; then continue; fi
    if [[ "$content" =~ $REGEX ]]; then
      ((found++))
      echo "---"
      echo "Found address in: $file:$line"
      echo "Line content: $content"
      echo "Blame (who/when/commit):"
      git blame -L "$line,$line" --line-porcelain -- "$file" | sed -n '1,5p'
      echo "Recent commits touching this file:"
      git --no-pager log -n5 --pretty=format:"%h %an %ad %s" --date=short -- "$file"
      echo "---"
    fi
  done < <(grep -nE "$REGEX" -- "$file" || true)
done <<< "$CHANGED_FILES"

if [ "$found" -gt 0 ]; then
  echo "Plaintext addresses detected: $found"
  if [ -n "${ALERT_WEBHOOK:-}" ]; then
    payload=$(jq -n --arg repo "$(basename $REPO_ROOT)" --argcount "$found" '{text: ("Plaintext addresses found in "+$repo+": "+$count)}' 2>/dev/null) || payload="{\"text\":\"Plaintext addresses found in repo\"}"
    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$ALERT_WEBHOOK" || true
  fi
  exit 1
fi

echo "No plaintext Ethereum addresses found."
