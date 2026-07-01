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

image_can_run_smoke_shell() {
  local image="$1"
  docker run --rm --pull=never --network none "$image" sh -c 'sleep 0' >/dev/null 2>&1
}

if ! command -v docker >/dev/null 2>&1; then
  cat >&2 <<EOF
prepare-smoke-image failed: docker executable was not found.

target image: $target_image
probe attempts: $image_probe_attempts
This script only uses cached/local images and does not auto pull from external registries.
EOF
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  cat >&2 <<EOF
prepare-smoke-image failed: Docker daemon is not reachable.

target image: $target_image
probe attempts: $image_probe_attempts
Start Docker locally, then rerun. This script only uses cached/local images and does not auto pull from external registries.
EOF
  exit 1
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

printf 'prepare-smoke-image: target image: %s\n' "$target_image"
printf 'prepare-smoke-image: base candidates: %s\n' "${candidates[*]}"
printf 'prepare-smoke-image: probe attempts: %s\n' "$image_probe_attempts"
printf 'prepare-smoke-image: pull policy: never; no automatic registry pull will be attempted.\n'

prepare_from_cached_image() {
  local candidate

  if image_exists_once "$target_image"; then
    if image_can_run_smoke_shell "$target_image"; then
      echo "local smoke image available and runnable: $target_image"
      return 0
    fi
    echo "prepare-smoke-image: target image exists but cannot run required sh/sleep probe: $target_image" >&2
  fi

  for candidate in "${candidates[@]}"; do
    if ! image_exists_once "$candidate"; then
      echo "prepare-smoke-image: cached candidate not found: $candidate"
      continue
    fi
    if ! image_can_run_smoke_shell "$candidate"; then
      echo "prepare-smoke-image: cached candidate cannot run required sh/sleep probe: $candidate" >&2
      continue
    fi
    if [ "$candidate" != "$target_image" ] && ! docker image tag "$candidate" "$target_image"; then
      echo "prepare-smoke-image: failed to tag cached candidate $candidate as $target_image" >&2
      continue
    fi
    if image_can_run_smoke_shell "$target_image"; then
      echo "local smoke image prepared and runnable: $target_image from cached $candidate"
      return 0
    fi
    echo "prepare-smoke-image: tagged target cannot run required sh/sleep probe: $target_image from $candidate" >&2
  done

  return 1
}

for ((attempt = 1; attempt <= image_probe_attempts; attempt += 1)); do
  printf 'prepare-smoke-image: probe attempt %s/%s\n' "$attempt" "$image_probe_attempts"
  if prepare_from_cached_image; then
    exit 0
  fi

  if ((attempt < image_probe_attempts)); then
    sleep 1
  fi
done

cat >&2 <<EOF
prepare-smoke-image failed: no cached smoke base image is available.

target image: $target_image
base candidates: ${candidates[*]}
probe attempts: $image_probe_attempts

Preload one allowed local image, or set MEETING_ASSISTANT_SMOKE_IMAGE to an
already available image that contains /bin/sh and sleep. This script verifies
images with docker run --pull=never --network none and does not auto pull from
external registries during E2E execution.
EOF
exit 1
