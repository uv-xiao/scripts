#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from minitoml import TomlError, loads  # type: ignore  # noqa: E402


def main(argv: list[str]) -> int:
    for p in argv:
        try:
            data = loads(pathlib.Path(p).read_text(encoding="utf-8"))
        except TomlError as e:
            print(f"error: {e}", file=sys.stderr)
            return 2
        script_id = data.get("id", "")
        name = data.get("name", "")
        print(f"{script_id}\t{name}\t{p}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
