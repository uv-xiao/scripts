#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
mihomo.sh - Install mihomo (no root) and manage it in a tmux session.

Usage:
  mihomo.sh install [options]
  mihomo.sh shell-snippet [options]
  mihomo.sh <start|stop|restart|status|attach> [options]

Remote install (curl):
  curl -fsSL https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/mihomo/mihomo.sh | bash -s -- install --yes
Remote install (wget):
  wget -qO- https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/mihomo/mihomo.sh | bash -s -- install --yes

Back-compat:
  mihomo.sh [install options...]   (treated as `install`)

Install options:
  --prefix DIR        Install prefix (default: ~/.local)
  --version TAG       Release tag to install (default: latest)
  --shell bash|zsh|both  Which shell rc to modify (default: auto)
  --rc PATH           Explicit rc file to modify (overrides --shell)
  --config PATH       Default config path for helpers (default: ~/.config/mihomo/config.yaml)
  --config-url URL    Default config URL to download when missing (optional)
  --self-url URL      URL to download this script for installing mihomoctl (optional)
  --no-shell          Do not edit rc files
  --print             Print the rc snippet instead of editing files
  --yes               Do not prompt before editing files

TMUX options:
  --session NAME      tmux session name (default: mihomo-proxy)
  --mihomo-bin PATH   mihomo binary path (default: mihomo, resolved via PATH)
  --config PATH       config file path (default: $MIHOMO_CONFIG or ~/.config/mihomo/config.yaml)
  --config-url URL    if config path doesn't exist, download from URL

General:
  -h, --help          Show help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
is_tty() { [[ -t 0 && -t 1 ]]; }

default_self_url() {
  if [[ -n "${SCRIPTS_RAW_BASE:-}" ]]; then
    echo "${SCRIPTS_RAW_BASE%/}/scripts/mihomo/mihomo.sh"
    return 0
  fi
  echo "https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/mihomo/mihomo.sh"
}

expand_home_path() {
  local p="${1:-}"
  p="${p/#\~/$HOME}"
  p="${p//\$HOME/$HOME}"
  printf '%s' "$p"
}

curl_retry() {
  curl --fail --location --silent --show-error \
    --retry 8 --retry-delay 2 --retry-connrefused --retry-all-errors \
    --connect-timeout 30 --max-time 1200 \
    "$@"
}

install_mihomoctl() {
  local dest="$1"
  local self_url="$2"

  local src="${BASH_SOURCE[0]:-}"
  if [[ -n "$src" && -f "$src" ]] && grep -q "mihomo.sh - Install mihomo" "$src" 2>/dev/null; then
    cp -f "$src" "$dest"
    return 0
  fi

  curl_retry "$self_url" -o "$dest"
}

detect_shell() {
  case "${SHELL:-}" in
    */zsh) echo "zsh" ;;
    */bash) echo "bash" ;;
    *) echo "both" ;;
  esac
}

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

platform_os() {
  case "$(uname -s | tr '[:upper:]' '[:lower:]')" in
    linux) echo "linux" ;;
    darwin) echo "darwin" ;;
    *) die "unsupported OS: $(uname -s)" ;;
  esac
}

platform_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported arch: $(uname -m)" ;;
  esac
}

github_latest_tag() {
  curl_retry -H "User-Agent: scripts/mihomo/mihomo.sh" \
    "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n1
}

render_shell_snippet() {
  local ctl="$1"
  local cfg="$2"
  local cfg_url="$3"

  cat <<EOF
# Mihomo helpers (installed by scripts/mihomo/mihomo.sh)
export MIHOMO_CONFIG="${cfg}"
${cfg_url:+export MIHOMO_CONFIG_URL="${cfg_url}"}
export MIHOMO_SESSION="\${MIHOMO_SESSION:-mihomo-proxy}"

mihomorun() {
  local ctl="${ctl}"
  if [[ ! -x "\$ctl" ]]; then
    echo "[mihomo] control script not found or not executable: \$ctl" >&2
    return 1
  fi

  case "\${1:-}" in
    start|stop|restart|status|attach)
      "\$ctl" "\$1" --session "\${MIHOMO_SESSION}" --config "\${MIHOMO_CONFIG}" ${cfg_url:+--config-url "\${MIHOMO_CONFIG_URL}"} "\${@:2}"
      ;;
    *)
      cat <<USAGE
Usage:
  mihomorun start|stop|restart|status|attach
USAGE
      return 1
      ;;
  esac
}
EOF
}

tmux_is_running() {
  local session="$1"
  tmux has-session -t "$session" 2>/dev/null
}

tmux_ensure_config() {
  local config_path="$1"
  local config_url="$2"
  if [[ -f "$config_path" ]]; then
    return 0
  fi
  [[ -n "$config_url" ]] || die "config not found: $config_path (set --config-url or create it)"
  mkdir -p "$(dirname -- "$config_path")"
  curl_retry "$config_url" -o "$config_path"
}

cmd_tmux() {
  local action="$1"
  shift

  local session="${MIHOMO_SESSION:-mihomo-proxy}"
  local mihomo_bin="${MIHOMO_BIN:-mihomo}"
  local config_path="${MIHOMO_CONFIG:-$HOME/.config/mihomo/config.yaml}"
  local config_url="${MIHOMO_CONFIG_URL:-}"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --session) session="${2:-}"; shift 2 ;;
      --mihomo-bin) mihomo_bin="${2:-}"; shift 2 ;;
      --config) config_path="${2:-}"; shift 2 ;;
      --config-url) config_url="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1 (use --help)" ;;
    esac
  done

  need tmux
  need curl

  case "$action" in
    start)
      tmux_ensure_config "$config_path" "$config_url"
      if tmux_is_running "$session"; then
        echo "[mihomo] tmux session '$session' already running"
        return 0
      fi
      tmux new-session -d -s "$session" "$mihomo_bin" -f "$config_path"
      echo "[mihomo] started in tmux session '$session'"
      ;;
    stop)
      if ! tmux_is_running "$session"; then
        echo "[mihomo] tmux session '$session' not running"
        return 0
      fi
      tmux kill-session -t "$session"
      echo "[mihomo] stopped tmux session '$session'"
      ;;
    restart)
      cmd_tmux stop --session "$session" --mihomo-bin "$mihomo_bin" --config "$config_path" ${config_url:+--config-url "$config_url"}
      cmd_tmux start --session "$session" --mihomo-bin "$mihomo_bin" --config "$config_path" ${config_url:+--config-url "$config_url"}
      ;;
    status)
      if tmux_is_running "$session"; then
        echo "[mihomo] running (tmux session: $session)"
      else
        echo "[mihomo] not running"
      fi
      ;;
    attach)
      tmux attach -t "$session"
      ;;
    *)
      die "unknown action: $action"
      ;;
  esac
}

cmd_shell_snippet() {
  local prefix="$HOME/.local"
  local config_path="$HOME/.config/mihomo/config.yaml"
  local config_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix) prefix="${2:-}"; shift 2 ;;
      --config) config_path="${2:-}"; shift 2 ;;
      --config-url) config_url="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1 (use --help)" ;;
    esac
  done

  local ctl="$prefix/bin/mihomoctl"
  render_shell_snippet "$ctl" "$config_path" "$config_url"
}

cmd_install() {
  local prefix="$HOME/.local"
  local version="latest"
  local shell_choice=""
  local rc_path=""
  local config_path="$HOME/.config/mihomo/config.yaml"
  local config_url=""
  local self_url=""
  local edit_shell=1
  local print_only=0
  local assume_yes=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --prefix) prefix="${2:-}"; shift 2 ;;
      --version) version="${2:-}"; shift 2 ;;
      --shell) shell_choice="${2:-}"; shift 2 ;;
      --rc) rc_path="${2:-}"; shift 2 ;;
      --config) config_path="${2:-}"; shift 2 ;;
      --config-url) config_url="${2:-}"; shift 2 ;;
      --self-url) self_url="${2:-}"; shift 2 ;;
      --no-shell) edit_shell=0; shift ;;
      --print) print_only=1; shift ;;
      --yes) assume_yes=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1 (use --help)" ;;
    esac
  done

  prefix="$(expand_home_path "$prefix")"
  if [[ -n "$rc_path" ]]; then
    rc_path="$(expand_home_path "$rc_path")"
  fi
  config_path="$(expand_home_path "$config_path")"
  if [[ -z "$self_url" ]]; then
    self_url="$(default_self_url)"
  fi

  need awk
  need curl
  need gzip

  os="$(platform_os)"
  arch="$(platform_arch)"

  tag="$version"
  if [[ -z "$tag" || "$tag" == "latest" ]]; then
    tag="$(github_latest_tag)"
    [[ -n "$tag" ]] || die "failed to detect latest mihomo release tag"
  fi

  asset_name="mihomo-${os}-${arch}-${tag}.gz"
  url="https://github.com/MetaCubeX/mihomo/releases/download/${tag}/${asset_name}"

  bin_dir="$prefix/bin"
  mkdir -p "$bin_dir"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  dest="$bin_dir/mihomo"
  curl_retry "$url" -o "$tmp/mihomo.gz"
  gzip -dc "$tmp/mihomo.gz" >"$tmp/mihomo"
  chmod +x "$tmp/mihomo"
  mv -f "$tmp/mihomo" "$dest"
  echo "Installed $dest ($tag)"

  ctl_dest="$bin_dir/mihomoctl"
  install_mihomoctl "$ctl_dest" "$self_url"
  chmod +x "$ctl_dest"
  echo "Installed $ctl_dest"

  begin="# >>> scripts/mihomo >>>"
  end="# <<< scripts/mihomo <<<"
  snippet="$(render_shell_snippet "$ctl_dest" "$config_path" "$config_url")"

  if [[ "$edit_shell" -eq 0 ]]; then
    return 0
  fi

  if [[ "$print_only" -eq 1 ]]; then
    echo "$begin"
    printf '%s\n' "$snippet"
    echo "$end"
    return 0
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
    [[ "${ans:-}" == "y" || "${ans:-}" == "Y" ]] || return 1
  fi

  for f in "${targets[@]}"; do
    upsert_block "$f" "$begin" "$end" "$snippet"
    echo "Updated $f"
  done
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -eq 0 ]]; then
    usage
    exit 0
  fi

  case "${1:-}" in
    install)
      shift
      cmd_install "$@"
      ;;
    shell-snippet)
      shift
      cmd_shell_snippet "$@"
      ;;
    start|stop|restart|status|attach)
      cmd_tmux "$@"
      ;;
    --*)
      # Back-compat: treat flags-only invocation as install.
      cmd_install "$@"
      ;;
    *)
      die "unknown command: $1 (use --help)"
      ;;
  esac
}

main "$@"
