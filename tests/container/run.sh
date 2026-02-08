#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
tests/container/run.sh - Run repo tests inside a container (docker or podman).

Usage:
  tests/container/run.sh [--engine auto|docker|podman] [--image TAG] [--no-build]

Notes:
  - Runs with network access and no TTY (no prompts).
  - Executes: INTEGRATION=1 tests/run.sh
EOF
}

die() { echo "error: $*" >&2; exit 1; }

engine="auto"
image="script-collection-test:local"
no_build=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) engine="${2:-}"; shift 2 ;;
    --image) image="${2:-}"; shift 2 ;;
    --no-build) no_build=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

pick_engine() {
  if [[ "$engine" == "docker" || "$engine" == "podman" ]]; then
    command -v "$engine" >/dev/null 2>&1 || die "$engine not found"
    echo "$engine"
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    echo "docker"
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    echo "podman"
    return 0
  fi
  die "neither docker nor podman found"
}

eng="$(pick_engine)"

if [[ "$no_build" -eq 0 ]]; then
  "$eng" build -f "$repo_root/tests/container/Dockerfile" -t "$image" "$repo_root"
fi

mount_suffix=""
if [[ "$eng" == "podman" ]]; then
  mount_suffix=":Z"
fi

"$eng" run --rm \
  -e CI=1 \
  -e TERM=xterm-256color \
  -e INTEGRATION=1 \
  -v "$repo_root:/repo${mount_suffix}" \
  -w /repo \
  "$image" \
  bash -lc 'tests/run.sh'

