#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ "$#" -lt 3 ]; then
  echo "usage: $0 <scope> <step-name> <command> [args...]" >&2
  exit 2
fi

scope="$1"
step_name="$2"
shift 2

case "$scope" in
  *[!A-Za-z0-9._-]*|"")
    echo "invalid evidence scope: $scope" >&2
    exit 2
    ;;
esac
case "$step_name" in
  *[!A-Za-z0-9._-]*|"")
    echo "invalid evidence step name: $step_name" >&2
    exit 2
    ;;
esac

evidence_dir="${HARNESS_EVIDENCE_DIR:-.harness/evidence}/$scope"
mkdir -p "$evidence_dir"
log_file="$evidence_dir/$step_name.log"
meta_file="$evidence_dir/$step_name.meta"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
commit_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
worktree_fingerprint="$(python3 scripts/worktree-fingerprint.py)"
command_text="$(printf '%q ' "$@")"

set +e
"$@" 2>&1 | tee "$log_file"
exit_code="${PIPESTATUS[0]}"
set -e

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  echo "step=$step_name"
  echo "command=$command_text"
  echo "commit=$commit_sha"
  echo "worktree_fingerprint=$worktree_fingerprint"
  echo "started_at=$started_at"
  echo "finished_at=$finished_at"
  echo "exit_code=$exit_code"
  echo "log=$log_file"
} > "$meta_file"

exit "$exit_code"
