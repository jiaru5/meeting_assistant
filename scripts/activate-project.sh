#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "$#" -eq 0 ]; then
  cat >&2 <<'USAGE'
usage:
  ./scripts/activate-project.sh --confirmed-by "Name" --confirmation-text "I reviewed and approve project activation ..."

This command may only be run after explicit user approval. It switches docs/product-spec/PROJECT-STATUS.md to project mode after adoption activation checks pass.
USAGE
  exit 2
fi

exec python3 scripts/adoption-runtime.py activate "$@"
