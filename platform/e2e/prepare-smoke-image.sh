#!/usr/bin/env bash
set -euo pipefail

target_image="${MEETING_ASSISTANT_SMOKE_IMAGE:-meeting-assistant-smoke:local}"
image_probe_attempts="${MEETING_ASSISTANT_SMOKE_IMAGE_PROBE_ATTEMPTS:-90}"

case "$image_probe_attempts" in
  *[!0-9]*|"")
    echo "prepare-smoke-image failed: MEETING_ASSISTANT_SMOKE_IMAGE_PROBE_ATTEMPTS must be a positive integer." >&2
    exit 2
    ;;
  0)
    echo "prepare-smoke-image failed: MEETING_ASSISTANT_SMOKE_IMAGE_PROBE_ATTEMPTS must be greater than zero." >&2
    exit 2
    ;;
esac

image_exists_once() {
  local image="$1"
  docker image inspect "$image" >/dev/null 2>&1
}

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

prepare_from_cached_image() {
  local candidate

  if image_exists_once "$target_image"; then
    echo "local smoke image available: $target_image"
    return 0
  fi

  for candidate in "${candidates[@]}"; do
    if image_exists_once "$candidate" && docker image tag "$candidate" "$target_image"; then
      echo "local smoke image prepared: $target_image from cached $candidate"
      return 0
    fi
  done

  return 1
}

for ((attempt = 1; attempt <= image_probe_attempts; attempt += 1)); do
  if prepare_from_cached_image; then
    exit 0
  fi

  if ((attempt < image_probe_attempts)); then
    sleep 1
  fi
done

cat >&2 <<EOF
prepare-smoke-image failed: no cached smoke base image is available.

Preload one allowed local image, or set MEETING_ASSISTANT_SMOKE_IMAGE to an
already available image that contains /bin/sh and sleep. This script does not
pull from external registries during E2E execution.
EOF
exit 1
