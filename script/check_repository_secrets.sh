#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PATTERNS=(
  '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
  'github_pat_[A-Za-z0-9_]{20,}'
  'gh[pousr]_[A-Za-z0-9_]{20,}'
  'sk-(proj-)?[A-Za-z0-9_-]{20,}'
  'AKIA[0-9A-Z]{16}'
)

FOUND=0
for pattern in "${PATTERNS[@]}"; do
  if matches="$(
    git grep --untracked -nEI \
      "$pattern" \
      -- \
      . \
      ':(exclude)script/check_repository_secrets.sh' \
      2>/dev/null
  )"; then
    printf '%s\n' "$matches"
    FOUND=1
  fi
done

if [[ "$FOUND" -ne 0 ]]; then
  echo "error: possible secret material was found in repository files" >&2
  exit 1
fi

echo "No common secret patterns found in repository files."
