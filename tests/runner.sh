#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
tests/runner.sh - Discover scripts via scripts/*/script.toml and run their tests.

Usage:
  tests/runner.sh --mode smoke|integration [--root PATH] [--only ID] [--list]

Options:
  --mode MODE   Which test set to run: smoke or integration (required)
  --root PATH   Repo root to scan (default: auto-detect from this file)
  --only ID     Run just one script id
  --list        List discovered scripts and exit
  -h, --help    Show help
EOF
}

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

mode=""
root=""
scan_root=""
only=""
do_list=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) mode="${2:-}"; shift 2 ;;
    --root) scan_root="${2:-}"; shift 2 ;;
    --only) only="${2:-}"; shift 2 ;;
    --list) do_list=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1 (use --help)" ;;
  esac
done

[[ -n "$mode" ]] || die "--mode is required"
[[ "$mode" == "smoke" || "$mode" == "integration" ]] || die "--mode must be smoke|integration"

if [[ -z "$root" ]]; then
  root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fi
tool_root="$root"
if [[ -n "$scan_root" ]]; then
  scan_root="$(cd -- "$scan_root" && pwd)"
else
  scan_root="$tool_root"
fi

need python3

discover_py='
import os, sys, glob
root = sys.argv[1]
paths = sorted(glob.glob(os.path.join(root, "scripts", "*", "script.toml")))
for p in paths:
    print(p)
'

tomls=()
while IFS= read -r line; do
  [[ -n "$line" ]] && tomls+=("$line")
done < <(python3 -c "$discover_py" "$scan_root")

if [[ "${#tomls[@]}" -eq 0 ]]; then
  die "no scripts found under $scan_root/scripts/*/script.toml"
fi

if [[ "$do_list" -eq 1 ]]; then
  python3 "$tool_root/tests/tools/list_scripts.py" "${tomls[@]}"
  exit 0
fi

failures=0
for toml in "${tomls[@]}"; do
  script_id="$(python3 "$tool_root/tests/tools/read_field.py" "$toml" id)"

  if [[ -n "$only" && "$script_id" != "$only" ]]; then
    continue
  fi

  echo "==> $script_id ($mode)"

  session_file="$(mktemp)"
  python3 "$tool_root/tests/tools/gen_session.py" \
    --toml "$toml" \
    --mode "$mode" \
    --root "$scan_root" \
    >"$session_file"
  chmod +x "$session_file"

  if "$session_file"; then
    echo "PASS: $script_id ($mode)"
  else
    echo "FAIL: $script_id ($mode)"
    failures=$((failures + 1))
  fi
  rm -f "$session_file"
  echo
done

if [[ "$failures" -gt 0 ]]; then
  echo "$failures script(s) failed"
  exit 1
fi
