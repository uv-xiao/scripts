#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
omz.sh - Install zsh (no root), oh-my-zsh, and powerlevel10k.

Usage:
  omz.sh [options]

Remote install (curl):
  curl -fsSL https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/omz/omz.sh | bash -s -- --yes --shell both
Remote install (wget):
  wget -qO- https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/omz/omz.sh | bash -s -- --yes --shell both

Options:
  --prefix DIR         Install prefix for zsh (default: ~/.local)
  --zsh-version VER    Zsh version to build (default: 5.9)
  --shell bash|zsh|both  Which shell rc to modify (default: auto)
  --rc PATH            Explicit rc file to modify (overrides --shell)
  --no-shell           Do not edit rc files
  --print              Print the rc snippet instead of editing files
  --yes                Do not prompt before editing files
  -h, --help           Show help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
is_tty() { [[ -t 0 && -t 1 ]]; }

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

run_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

git_clone_retry() {
  local url="$1"
  local dest="$2"
  local attempt=1
  while [[ "$attempt" -le 5 ]]; do
    rm -rf "$dest"
    if GIT_TERMINAL_PROMPT=0 run_timeout 120 git clone --depth=1 "$url" "$dest" >/dev/null 2>&1; then
      return 0
    fi
    sleep $((attempt * 2))
    attempt=$((attempt + 1))
  done
  return 1
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

upsert_block_append() {
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

upsert_block_before_pattern() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content="$4"
  local pattern="$5"

  mkdir -p "$(dirname -- "$file")"
  touch "$file"
  backup_file "$file"

  local tmp
  tmp="$(mktemp)"

  awk -v begin="$begin" -v end="$end" -v content="$content" -v pattern="$pattern" '
    function print_block() {
      print begin
      n = split(content, lines, "\n")
      for (i = 1; i <= n; i++) print lines[i]
      print end
    }
    $0 == begin { inblock=1; next }
    $0 == end   { inblock=0; next }
    inblock { next }
    !inserted && $0 ~ pattern {
      print_block()
      inserted=1
    }
    { print }
    END {
      if (!inserted) {
        if (NR > 0) print ""
        print_block()
        print ""
      }
    }
  ' "$file" >"$tmp"

  mv -f "$tmp" "$file"
}

jobs_count() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2
}

render_zsh_block() {
  local bin_dir="$1"
  cat <<EOF
export PATH="${bin_dir}":\$PATH
export ZSH="\${ZSH:-$HOME/.oh-my-zsh}"
ZSH_THEME="powerlevel10k/powerlevel10k"
POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
ZSH_DISABLE_COMPFIX=true
EOF
}

render_bash_block() {
  local bin_dir="$1"
  cat <<EOF
export PATH="${bin_dir}":\$PATH
EOF
}

prefix="$HOME/.local"
zsh_version="5.9"
shell_choice=""
rc_path=""
edit_shell=1
print_only=0
assume_yes=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) prefix="${2:-}"; shift 2 ;;
    --zsh-version) zsh_version="${2:-}"; shift 2 ;;
    --shell) shell_choice="${2:-}"; shift 2 ;;
    --rc) rc_path="${2:-}"; shift 2 ;;
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

need awk
need curl
need tar
need xz
need make
need gcc
need git

bin_dir="$prefix/bin"
mkdir -p "$bin_dir"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

zsh_url="https://www.zsh.org/pub/zsh-${zsh_version}.tar.xz"
curl_retry "$zsh_url" -o "$tmp/zsh.tar.xz"
tar -C "$tmp" -xf "$tmp/zsh.tar.xz"

src_dir="$(find "$tmp" -maxdepth 1 -type d -name "zsh-*" | head -n1)"
[[ -n "${src_dir:-}" ]] || die "failed to unpack zsh source"

(
  cd "$src_dir"
  ./configure --prefix="$prefix" --without-tcsetpgrp
  make -j"$(jobs_count)"
  make install
)

zsh_bin="$bin_dir/zsh"
[[ -x "$zsh_bin" ]] || die "zsh install failed: missing $zsh_bin"
echo "Installed $zsh_bin"

export PATH="$bin_dir:$PATH"

omz_dir="${ZSH:-$HOME/.oh-my-zsh}"
omz_dir="$(expand_home_path "$omz_dir")"

if [[ -d "$omz_dir/.git" ]]; then
  GIT_TERMINAL_PROMPT=0 run_timeout 60 git -C "$omz_dir" pull --ff-only >/dev/null || true
elif [[ -e "$omz_dir" ]]; then
  die "refusing to overwrite existing path: $omz_dir"
else
  git_clone_retry "https://github.com/ohmyzsh/ohmyzsh.git" "$omz_dir" \
    || die "failed to clone oh-my-zsh (network flake?)"
fi

p10k_dir="${ZSH_CUSTOM:-$omz_dir/custom}/themes/powerlevel10k"
p10k_dir="$(expand_home_path "$p10k_dir")"
if [[ -d "$p10k_dir/.git" ]]; then
  GIT_TERMINAL_PROMPT=0 run_timeout 60 git -C "$p10k_dir" pull --ff-only >/dev/null || true
else
  mkdir -p "$(dirname -- "$p10k_dir")"
  git_clone_retry "https://github.com/romkatv/powerlevel10k.git" "$p10k_dir" \
    || die "failed to clone powerlevel10k (network flake?)"
fi

zshrc="$HOME/.zshrc"
touch "$zshrc"

zsh_block_begin="# >>> scripts/omz >>>"
zsh_block_end="# <<< scripts/omz <<<"
zsh_block_content="$(render_zsh_block "$bin_dir")"
upsert_block_before_pattern "$zshrc" "$zsh_block_begin" "$zsh_block_end" "$zsh_block_content" '^[[:space:]]*source[[:space:]].*oh-my-zsh[.]sh'

if ! grep -q 'oh-my-zsh[.]sh' "$zshrc"; then
  source_begin="# >>> scripts/omz-source >>>"
  source_end="# <<< scripts/omz-source <<<"
  source_content=$'export ZSH="'"$omz_dir"$'"\nsource "'"$omz_dir"$'/oh-my-zsh.sh"'
  upsert_block_append "$zshrc" "$source_begin" "$source_end" "$source_content"
fi

if [[ "$edit_shell" -eq 0 ]]; then
  exit 0
fi

bash_block_begin="# >>> scripts/zsh-path >>>"
bash_block_end="# <<< scripts/zsh-path <<<"
bash_block_content="$(render_bash_block "$bin_dir")"

if [[ "$print_only" -eq 1 ]]; then
  echo "$bash_block_begin"
  printf '%s\n' "$bash_block_content"
  echo "$bash_block_end"
  echo
  echo "$zsh_block_begin"
  printf '%s\n' "$zsh_block_content"
  echo "$zsh_block_end"
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
  case "$f" in
    */.zshrc)
      # already updated above, but keep markers stable
      echo "Updated $f"
      ;;
    *)
      upsert_block_append "$f" "$bash_block_begin" "$bash_block_end" "$bash_block_content"
      echo "Updated $f"
      ;;
  esac
done
