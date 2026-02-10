#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
tests/container/run.sh - Run repo tests inside a container (docker or podman).

Usage:
  tests/container/run.sh [--engine auto|docker|podman] [--image TAG] [--no-build] [--network auto|bridge|host]

Notes:
  - Runs with network access and no TTY (no prompts).
  - Executes: INTEGRATION=1 tests/run.sh
  - If your host requires a local proxy (e.g. HTTP(S)_PROXY points to 127.0.0.1),
    use --network host (or keep --network auto) so the container can reach it.
EOF
}

die() { echo "error: $*" >&2; exit 1; }

engine="auto"
image="script-collection-test:local"
no_build=0
network_mode="auto"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) engine="${2:-}"; shift 2 ;;
    --image) image="${2:-}"; shift 2 ;;
    --no-build) no_build=1; shift ;;
    --network) network_mode="${2:-}"; shift 2 ;;
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

is_loopback_proxy() {
  local val="${1:-}"
  [[ -n "$val" ]] || return 1
  [[ "$val" == *"127.0.0.1"* || "$val" == *"localhost"* ]]
}

has_loopback_proxy=0
for k in HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy; do
  if is_loopback_proxy "${!k-}"; then
    has_loopback_proxy=1
    break
  fi
done

case "$network_mode" in
  auto)
    network_mode="bridge"
    ;;
  bridge|host) ;;
  *) die "invalid --network value: $network_mode (expected auto|bridge|host)" ;;
esac

run_args=(run --rm)

if [[ "$network_mode" == "host" ]]; then
  run_args+=(--network host)
fi

add_env_if_set() {
  local name="$1"
  local val="${!name-}"
  [[ -n "$val" ]] || return 0
  run_args+=(-e "$name=$val")
}

proxy_forward_pid=""
proxy_tmpdir=""
proxy_configured=0

cleanup_proxy_forwarder() {
  if [[ -n "${proxy_forward_pid:-}" ]]; then
    kill "$proxy_forward_pid" >/dev/null 2>&1 || true
    wait "$proxy_forward_pid" >/dev/null 2>&1 || true
  fi
  if [[ -n "${proxy_tmpdir:-}" ]]; then
    rm -rf "$proxy_tmpdir" >/dev/null 2>&1 || true
  fi
}

trap cleanup_proxy_forwarder EXIT

pick_loopback_proxy_url() {
  local v
  for v in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy; do
    if is_loopback_proxy "${!v-}"; then
      echo "${!v}"
      return 0
    fi
  done
  return 1
}

rewrite_proxy_url() {
  local url="$1"
  local host_alias="$2"
  local port="$3"

  local scheme rest hostport auth=""
  scheme="${url%%://*}"
  rest="${url#*://}"
  hostport="${rest%%/*}"
  if [[ "$hostport" == *"@"* ]]; then
    auth="${hostport%%@*}@"
    hostport="${hostport#*@}"
  fi
  echo "${scheme}://${auth}${host_alias}:${port}"
}

docker_daemon_proxy_url() {
  [[ "$eng" == "docker" ]] || return 1
  local p
  p="$("$eng" info 2>/dev/null | awk -F': ' '/^ *HTTP Proxy: /{print $2; exit}')"
  [[ -n "$p" && "$p" != "<nil>" ]] || return 1
  echo "$p"
}

set_container_proxy_envs() {
  local url="$1"
  proxy_configured=1
  run_args+=(-e "HTTP_PROXY=$url" -e "http_proxy=$url")
  run_args+=(-e "HTTPS_PROXY=$url" -e "https_proxy=$url")
  run_args+=(-e "ALL_PROXY=$url" -e "all_proxy=$url")
  add_env_if_set NO_PROXY
  add_env_if_set no_proxy
}

start_proxy_forwarder_if_needed() {
  [[ "$has_loopback_proxy" -eq 1 ]] || return 0
  [[ "$network_mode" != "host" ]] || return 0

  # Rootless docker often can't reach host loopback, but the daemon may already
  # have an outbound proxy configured that containers can use.
  local daemon_proxy
  daemon_proxy="$(docker_daemon_proxy_url || true)"
  if [[ -n "$daemon_proxy" ]]; then
    set_container_proxy_envs "$daemon_proxy"
    echo "note: using docker-daemon proxy for container tests ($daemon_proxy)" >&2
    return 0
  fi

  local proxy_url target_port
  proxy_url="$(pick_loopback_proxy_url)" || return 0
  target_port="${proxy_url##*:}"
  if [[ -z "$target_port" || "$target_port" == "$proxy_url" ]]; then
    die "could not parse proxy port from: $proxy_url"
  fi

  proxy_tmpdir="$(mktemp -d)"
  : >"$proxy_tmpdir/forward.out"
  : >"$proxy_tmpdir/forward.err"

  python3 "$repo_root/tests/tools/tcp_forward.py" \
    --listen-host 0.0.0.0 \
    --listen-port 0 \
    --target-host 127.0.0.1 \
    --target-port "$target_port" \
    >"$proxy_tmpdir/forward.out" \
    2>"$proxy_tmpdir/forward.err" &
  proxy_forward_pid="$!"

  local forward_port=""
  for _ in {1..50}; do
    forward_port="$(head -n 1 "$proxy_tmpdir/forward.out" 2>/dev/null || true)"
    if [[ "$forward_port" =~ ^[0-9]+$ ]]; then
      break
    fi
    sleep 0.1
  done
  [[ "$forward_port" =~ ^[0-9]+$ ]] || die "proxy forwarder failed to start: $(cat "$proxy_tmpdir/forward.err" 2>/dev/null || true)"

  local host_alias
  if [[ "$eng" == "podman" ]]; then
    host_alias="host.containers.internal"
  else
    host_alias="host.docker.internal"
    run_args+=(--add-host=host.docker.internal:host-gateway)
  fi

  local rewritten
  rewritten="$(rewrite_proxy_url "$proxy_url" "$host_alias" "$forward_port")"

  set_container_proxy_envs "$rewritten"

  echo "note: using proxy forwarder for container tests ($proxy_url -> $rewritten)" >&2
}

start_proxy_forwarder_if_needed

if [[ "$proxy_configured" -eq 0 && -z "${proxy_forward_pid:-}" ]]; then
  # Plain proxy pass-through for environments where outbound traffic requires it.
  for k in HTTP_PROXY http_proxy HTTPS_PROXY https_proxy ALL_PROXY all_proxy NO_PROXY no_proxy; do
    add_env_if_set "$k"
  done
fi

"$eng" "${run_args[@]}" \
  -e CI=1 \
  -e TERM=xterm-256color \
  -e INTEGRATION=1 \
  -v "$repo_root:/repo${mount_suffix}" \
  -w /repo \
  "$image" \
  bash -lc 'tests/run.sh'
