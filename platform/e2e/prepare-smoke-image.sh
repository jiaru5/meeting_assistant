#!/usr/bin/env bash
set -euo pipefail

target_image="${MEETING_ASSISTANT_SMOKE_IMAGE:-meeting-assistant-smoke:local}"

if docker image inspect "$target_image" >/dev/null 2>&1; then
  echo "local smoke image available: $target_image"
  exit 0
fi

candidates=()
if [ -n "${MEETING_ASSISTANT_SMOKE_BASE_IMAGE:-}" ]; then
  candidates+=("$MEETING_ASSISTANT_SMOKE_BASE_IMAGE")
fi
candidates+=(
  "busybox:1.36.1"
  "node:22-alpine"
  "alpine:3.20"
  "postgres:16-alpine"
)

for candidate in "${candidates[@]}"; do
  if docker image inspect "$candidate" >/dev/null 2>&1; then
    docker image tag "$candidate" "$target_image"
    echo "local smoke image prepared: $target_image from cached $candidate"
    exit 0
  fi
done

cat >&2 <<EOF
prepare-smoke-image failed: no cached smoke base image is available.

Preload one allowed local image, or set MEETING_ASSISTANT_SMOKE_IMAGE to an
already available image that contains /bin/sh and sleep. This script does not
pull from external registries during E2E execution.
EOF
exit 1
