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
is_root() { [[ "$(id -u)" -eq 0 ]]; }

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

os_id() {
  local id=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
  fi
  echo "${id:-unknown}"
}

try_compile_curses() {
  local cppflags="${1:-}"
  local ldflags="${2:-}"
  local libs
  local tmpdir
  tmpdir="$(mktemp -d)"
  cat >"$tmpdir/t.c" <<'C'
#include <curses.h>
int main(void) { initscr(); endwin(); return 0; }
C

  for libs in "-lncursesw -ltinfo" "-lncursesw" "-lncurses -ltinfo" "-lncurses" "-lcurses"; do
    if gcc $cppflags "$tmpdir/t.c" -o "$tmpdir/t" $ldflags $libs >/dev/null 2>&1; then
      rm -rf "$tmpdir"
      return 0
    fi
  done

  rm -rf "$tmpdir"
  return 1
}

install_system_ncurses_deps_if_root() {
  is_root || return 1

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null
    apt-get install -y --no-install-recommends libncurses5-dev libncursesw5-dev >/dev/null
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    dnf install -y ncurses-devel >/dev/null
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    yum install -y ncurses-devel >/dev/null
    return 0
  fi

  if command -v pacman >/dev/null 2>&1; then
    pacman -Sy --noconfirm ncurses >/dev/null
    return 0
  fi

  if command -v apk >/dev/null 2>&1; then
    apk add --no-cache ncurses-dev >/dev/null
    return 0
  fi

  return 1
}

build_ncurses_local() {
  local install_prefix="$1"
  local work_dir="$2"

  local ver="${NCURSES_VERSION:-6.5}"
  local url="https://ftp.gnu.org/gnu/ncurses/ncurses-${ver}.tar.gz"
  local tarball="$work_dir/ncurses.tar.gz"

  mkdir -p "$install_prefix"
  curl_retry "$url" -o "$tarball"
  tar -C "$work_dir" -xf "$tarball"

  local src
  src="$(find "$work_dir" -maxdepth 1 -type d -name "ncurses-*" | head -n1)"
  [[ -n "${src:-}" ]] || die "failed to unpack ncurses source"

  (
    cd "$src"
    ./configure \
      --prefix="$install_prefix" \
      --with-shared \
      --without-debug \
      --without-ada \
      --enable-widec \
      --with-termlib
    make -j"$(jobs_count)"
    make install
  )
}

ensure_terminal_lib() {
  local dep_prefix="$1"
  local work_dir="$2"

  if try_compile_curses "" ""; then
    return 0
  fi

  echo "note: system curses/ncurses headers not found; attempting to satisfy dependency automatically" >&2

  if install_system_ncurses_deps_if_root; then
    if try_compile_curses "" ""; then
      return 0
    fi
  fi

  echo "note: building ncurses locally under $dep_prefix (no root)" >&2
  build_ncurses_local "$dep_prefix" "$work_dir"

  if ! try_compile_curses "-I$dep_prefix/include" "-L$dep_prefix/lib -Wl,-rpath,$dep_prefix/lib"; then
    cat >&2 <<EOF
error: failed to satisfy terminal library dependency (curses/ncurses)
  OS: $(os_id)

If you prefer system packages, install a curses development package, e.g.:
  - Debian/Ubuntu: libncurses5-dev libncursesw5-dev
  - Fedora/RHEL/CentOS: ncurses-devel
  - Arch: ncurses
  - Alpine: ncurses-dev
EOF
    exit 1
  fi
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

deps_prefix="$prefix/.deps/ncurses"
ensure_terminal_lib "$deps_prefix" "$tmp"

zsh_url="https://www.zsh.org/pub/zsh-${zsh_version}.tar.xz"
curl_retry "$zsh_url" -o "$tmp/zsh.tar.xz"
tar -C "$tmp" -xf "$tmp/zsh.tar.xz"

src_dir="$(find "$tmp" -maxdepth 1 -type d -name "zsh-*" | head -n1)"
[[ -n "${src_dir:-}" ]] || die "failed to unpack zsh source"

zsh_cppflags=""
zsh_ldflags=""
if [[ -d "$deps_prefix/include" && -d "$deps_prefix/lib" ]]; then
  zsh_cppflags="-I$deps_prefix/include"
  zsh_ldflags="-L$deps_prefix/lib -Wl,-rpath,$deps_prefix/lib"
fi

(
  cd "$src_dir"
  CPPFLAGS="$zsh_cppflags" LDFLAGS="$zsh_ldflags" ./configure --prefix="$prefix" --without-tcsetpgrp
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
