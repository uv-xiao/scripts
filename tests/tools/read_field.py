#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from minitoml import TomlError, loads  # type: ignore  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("toml_path")
    parser.add_argument("field")
    args = parser.parse_args()

    try:
        data = loads(pathlib.Path(args.toml_path).read_text(encoding="utf-8"))
    except TomlError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    value = data.get(args.field)
    if value is None:
        print(f"error: missing field '{args.field}' in {args.toml_path}", file=sys.stderr)
        return 2
    if not isinstance(value, str):
        print(f"error: field '{args.field}' must be a string", file=sys.stderr)
        return 2
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
