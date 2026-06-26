#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "prod-config-check failed: $1" >&2
  exit 1
}

[ -f ".env.example" ] || fail "missing .env.example"
[ -f ".env.prod.example" ] || fail "missing .env.prod.example"

if grep -n -E 'PASSWORD=.+|SECRET=.+|TOKEN=.+' .env.prod.example; then
  fail ".env.prod.example must not contain concrete secret values"
fi

if grep -R -n -E 'SPRING_PROFILES_ACTIVE=.*dev|NODE_ENV=.*development|DEV_CURRENT|FIXED_NOW' \
  .env.prod.example docker-compose*.yml platform 2>/dev/null; then
  fail "production config surface contains dev-only settings"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pending_secret_like=""
  while IFS= read -r file; do
    case "$file" in
      .env|.env.*)
        if [ "$file" != ".env.example" ] && [ "$file" != ".env.prod.example" ]; then
          pending_secret_like+="${file}"$'\n'
        fi
        ;;
      *[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll][Ss]*|*[Ss][Ee][Cc][Rr][Ee][Tt]*|*.pem|*.key)
        pending_secret_like+="${file}"$'\n'
        ;;
    esac
  done < <(
    {
      git ls-files
      git ls-files --others --exclude-standard
    } | sort -u
  )
  if [ -n "$pending_secret_like" ]; then
    printf '%s\n' "$pending_secret_like" >&2
    fail "secret-like files are tracked or pending"
  fi
fi

echo "prod-config-check passed."
