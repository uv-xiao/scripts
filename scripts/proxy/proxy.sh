#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
proxy.sh - Install shell proxy helper functions into bash/zsh rc files.

Usage:
  proxy.sh [--port PORT] [--shell bash|zsh|both] [--rc PATH] [--print] [--yes]

Options:
  --port PORT     Default proxy port to embed (default: 7890)
  --shell SHELL   Which shell rc to modify when --rc not provided (default: auto)
  --rc PATH       Explicit rc file to modify (overrides --shell)
  --print         Print the snippet instead of editing files
  --yes           Do not prompt before editing files
  -h, --help      Show help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

is_tty() { [[ -t 0 && -t 1 ]]; }

backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local ts
  ts="$(date +%Y%m%d%H%M%S)"
  cp -p "$file" "$file.bak.$ts"
}

upsert_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content="$4"

  mkdir -p "$(dirname -- "$file")"
  touch "$file"
  backup_file "$file"

  local tmp
  tmp="$(mktemp)"

  awk -v begin="$begin" -v end="$end" '
    $0 == begin { inblock=1; next }
    $0 == end   { inblock=0; next }
    !inblock { print }
  ' "$file" >"$tmp"

  {
    cat "$tmp"
    [[ -s "$tmp" ]] && echo
    echo "$begin"
    printf '%s\n' "$content"
    echo "$end"
    echo
  } >"$file"

  rm -f "$tmp"
}

render_snippet() {
  local port="$1"
  cat <<EOF
# Proxy helpers (installed by scripts/proxy/proxy.sh)
PROXY_PORT="${port}"
PROXY_HOST="http://127.0.0.1:\${PROXY_PORT}"

proxy_set_port() {
  if [ -z "\${1:-}" ]; then
    echo "Usage: proxy set <port>" >&2
    return 1
  fi
  PROXY_PORT="\$1"
  PROXY_HOST="http://127.0.0.1:\${PROXY_PORT}"
}

proxy_on() {
  local port="\${1:-\${PROXY_PORT}}"
  proxy_set_port "\$port" >/dev/null

  export http_proxy="\$PROXY_HOST"
  export https_proxy="\$PROXY_HOST"
  export all_proxy="\$PROXY_HOST"
  export HTTP_PROXY="\$PROXY_HOST"
  export HTTPS_PROXY="\$PROXY_HOST"
  export ALL_PROXY="\$PROXY_HOST"

  git config --global http.proxy "\$PROXY_HOST" 2>/dev/null || true
  git config --global https.proxy "\$PROXY_HOST" 2>/dev/null || true

  echo "Proxy ON: \$PROXY_HOST"
}

proxy_off() {
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
  git config --global --unset http.proxy 2>/dev/null || true
  git config --global --unset https.proxy 2>/dev/null || true
  echo "Proxy OFF"
}

proxy_status() {
  echo "Network:"
  echo "  http_proxy: \${http_proxy:-Not set}"
  echo "  https_proxy: \${https_proxy:-Not set}"
  echo "Git:"
  echo "  http.proxy: \$(git config --global --get http.proxy 2>/dev/null || echo 'Not set')"
  echo "  https.proxy: \$(git config --global --get https.proxy 2>/dev/null || echo 'Not set')"
}

proxy() {
  case "\${1:-}" in
    on|enable)   proxy_on "\${2:-}";;
    off|disable) proxy_off;;
    status|check) proxy_status;;
    set)         proxy_set_port "\${2:-}";;
    toggle|switch)
      if [ -n "\${http_proxy:-}" ]; then proxy_off; else proxy_on "\${2:-}"; fi
      ;;
    *)
      cat <<USAGE
Usage:
  proxy on [port]      Turn proxy on
  proxy off            Turn proxy off
  proxy status         Show proxy status
  proxy toggle [port]  Toggle proxy on/off
  proxy set <port>     Set default port
USAGE
      proxy_status
      return 1
      ;;
  esac
}
EOF
}

detect_shell() {
  case "${SHELL:-}" in
    */zsh) echo "zsh" ;;
    */bash) echo "bash" ;;
    *) echo "both" ;;
  esac
}

port="7890"
shell_choice=""
rc_path=""
print_only=0
assume_yes=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) port="${2:-}"; shift 2 ;;
    --shell) shell_choice="${2:-}"; shift 2 ;;
    --rc) rc_path="${2:-}"; shift 2 ;;
    --print) print_only=1; shift ;;
    --yes) assume_yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ "$port" =~ ^[0-9]+$ ]] || die "--port must be a number"

need awk
need git

snippet="$(render_snippet "$port")"
begin="# >>> scripts/proxy >>>"
end="# <<< scripts/proxy <<<"

if [[ "$print_only" -eq 1 ]]; then
  echo "$begin"
  printf '%s\n' "$snippet"
  echo "$end"
  exit 0
fi

targets=()
if [[ -n "$rc_path" ]]; then
  targets+=("$rc_path")
else
  choice="${shell_choice:-$(detect_shell)}"
  case "$choice" in
    bash) targets+=("$HOME/.bashrc") ;;
    zsh) targets+=("$HOME/.zshrc") ;;
    both) targets+=("$HOME/.bashrc" "$HOME/.zshrc") ;;
    *) die "--shell must be bash|zsh|both" ;;
  esac
fi

if [[ "$assume_yes" -eq 0 ]] && is_tty; then
  echo "This will edit:"
  printf '  - %s\n' "${targets[@]}"
  read -r -p "Proceed? [y/N] " ans
  [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]] || exit 1
fi

for f in "${targets[@]}"; do
  upsert_block "$f" "$begin" "$end" "$snippet"
  echo "Updated $f"
done
