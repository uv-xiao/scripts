#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0

run_test() {
  local name="$1"
  shift

  echo "==> $name"
  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    failures=$((failures + 1))
  fi
  echo
}

if command -v shellcheck >/dev/null 2>&1; then
  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$repo_root/scripts" "$repo_root/tests" -type f -name '*.sh' -print0)

  run_test "shellcheck" shellcheck -S warning -x "${files[@]}"
fi

run_test "registry-framework" bash "$repo_root/tests/framework_registry_test.sh"
run_test "modules-smoke" bash "$repo_root/tests/runner.sh" --root "$repo_root" --mode smoke

if [[ "${INTEGRATION:-0}" == "1" ]]; then
  run_test "modules-integration" bash "$repo_root/tests/runner.sh" --root "$repo_root" --mode integration
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi

echo "All tests passed"
