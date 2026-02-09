#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import pathlib
import shlex
import sys
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from minitoml import TomlError, loads  # type: ignore  # noqa: E402


def q(word: str) -> str:
    return shlex.quote(word)


def arg_expr(arg: str) -> str:
    # Allow env-var expansion in args by emitting a double-quoted string when '$' is present.
    if "$" in arg:
        escaped = arg.replace("\\", "\\\\").replace('"', '\\"')
        return f"\"{escaped}\""
    return q(arg)


def emit_run_block(lines: list[str]) -> str:
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--toml", required=True)
    parser.add_argument("--mode", required=True, choices=["smoke", "integration"])
    parser.add_argument("--root", required=True)
    args = parser.parse_args()

    toml_path = pathlib.Path(args.toml).resolve()
    script_dir = toml_path.parent
    try:
        data: dict[str, Any] = loads(toml_path.read_text(encoding="utf-8"))
    except TomlError as e:
        print(f"echo {q('error: ' + str(e))} >&2; exit 2")
        return 0

    script_id = data.get("id")
    entry = data.get("entry")
    if not isinstance(script_id, str) or not script_id:
        print(f"echo {q('error: missing/invalid id in ' + str(toml_path))} >&2; exit 2")
        return 0
    if not isinstance(entry, str) or not entry:
        print(f"echo {q('error: missing/invalid entry in ' + str(toml_path))} >&2; exit 2")
        return 0

    entry_path = (script_dir / entry).resolve()

    tests = data.get("tests", {})
    steps = []
    if isinstance(tests, dict):
        steps = tests.get(args.mode, [])
    if not isinstance(steps, list):
        steps = []

    print("#!/usr/bin/env bash")
    print("set -euo pipefail")
    print(f"export REPO_ROOT={q(str(pathlib.Path(args.root).resolve()))}")
    print(f"export SCRIPT_ID={q(script_id)}")
    print(f"export SCRIPT_DIR={q(str(script_dir))}")
    print(f"export SCRIPT_ENTRY={q(str(entry_path))}")
    print("export SCRIPT_TMPDIR=\"$(mktemp -d)\"")
    print("trap 'rm -rf \"$SCRIPT_TMPDIR\"' EXIT")
    if args.mode == "integration":
        print("export SCRIPT_HOME=\"$SCRIPT_TMPDIR/home\"")
        print("mkdir -p \"$SCRIPT_HOME\"")
        print("export HOME=\"$SCRIPT_HOME\"")
        print("export XDG_CONFIG_HOME=\"$HOME/.config\"")
        print("export XDG_CACHE_HOME=\"$HOME/.cache\"")
        print("export XDG_DATA_HOME=\"$HOME/.local/share\"")
        print("unset ZSH ZSH_CUSTOM || true")
        print("unset MIHOMO_CONFIG MIHOMO_CONFIG_URL MIHOMO_SESSION MIHOMO_BIN || true")
    print("cd \"$SCRIPT_DIR\"")
    print("")

    if not steps:
        if args.mode == "integration":
            print("echo \"(no integration steps)\" >&2")
            print("exit 2")
        else:
            print("echo \"(no steps)\"")
        return 0

    for idx, step in enumerate(steps, start=1):
        if not isinstance(step, dict):
            print(f"echo {q(f'error: invalid step #{idx} (not a table)')} >&2; exit 2")
            continue

        kind = step.get("kind")
        if kind == "script":
            args_list = step.get("args", [])
            if not isinstance(args_list, list):
                print(f"echo {q(f'error: step #{idx} args must be an array')} >&2; exit 2")
                continue
            rendered_args = " ".join(arg_expr(str(a)) for a in args_list)
            print(f"echo {q(f'-- step {idx}: script')}")  # logging
            print(f"\"$SCRIPT_ENTRY\" {rendered_args}".rstrip())
            print("")
        elif kind == "bash":
            run = step.get("run", [])
            if isinstance(run, str):
                run_lines = [ln for ln in run.splitlines() if ln.strip()]
            elif isinstance(run, list) and all(isinstance(x, str) for x in run):
                run_lines = run
            else:
                print(f"echo {q(f'error: step #{idx} run must be a string or string array')} >&2; exit 2")
                continue
            print(f"echo {q(f'-- step {idx}: bash')}")
            print(emit_run_block(run_lines))
        else:
            print(f"echo {q(f'error: step #{idx} unknown kind: {kind!r}')} >&2; exit 2")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
