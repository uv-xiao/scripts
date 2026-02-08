#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/scripts/hello"

cat >"$tmp/scripts/hello/hello.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --help|-h)
    echo "hello.sh"
    ;;
  touch)
    touch "$2"
    ;;
  *)
    echo "unknown" >&2
    exit 2
    ;;
esac
SH
chmod +x "$tmp/scripts/hello/hello.sh"

cat >"$tmp/scripts/hello/script.toml" <<'TOML'
id = "hello"
name = "Hello fixture"
entry = "hello.sh"
docs = "README.md"

[[tests.smoke]]
kind = "script"
args = ["--help"]

[[tests.integration]]
kind = "script"
args = ["touch", "$TMPFILE"]
TOML

cat >"$tmp/scripts/hello/README.md" <<'MD'
# hello
MD

out="$("$repo_root/tests/runner.sh" --root "$tmp" --mode smoke 2>&1 || true)"
grep -q "hello" <<<"$out"

tmpfile="$tmp/outfile"
export TMPFILE="$tmpfile"
"$repo_root/tests/runner.sh" --root "$tmp" --mode integration
test -f "$tmpfile"
