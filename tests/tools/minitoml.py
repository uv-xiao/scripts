from __future__ import annotations

import dataclasses
import re
from typing import Any


class TomlError(ValueError):
    pass


_re_key = re.compile(r"^[A-Za-z0-9_-]+$")


def _strip_comment(line: str) -> str:
    in_dq = False
    in_sq = False
    esc = False
    out = []
    for ch in line:
        if esc:
            out.append(ch)
            esc = False
            continue
        if ch == "\\" and in_dq:
            out.append(ch)
            esc = True
            continue
        if ch == '"':
            if not in_sq:
                in_dq = not in_dq
            out.append(ch)
            continue
        if ch == "'":
            if not in_dq:
                in_sq = not in_sq
            out.append(ch)
            continue
        if ch == "#" and not in_dq and not in_sq:
            break
        out.append(ch)
    return "".join(out).rstrip()


def _parse_string(s: str) -> str:
    s = s.strip()
    if len(s) < 2:
        raise TomlError(f"invalid string: {s!r}")
    if s[0] == '"' and s[-1] == '"':
        inner = s[1:-1]
        # Minimal unescape for common sequences
        inner = inner.replace(r"\\", "\\").replace(r"\"", '"').replace(r"\n", "\n").replace(r"\t", "\t")
        return inner
    if s[0] == "'" and s[-1] == "'":
        return s[1:-1]
    raise TomlError(f"invalid string: {s!r}")


def _split_top_level_commas(s: str) -> list[str]:
    items: list[str] = []
    buf: list[str] = []
    in_dq = False
    in_sq = False
    esc = False
    for ch in s:
        if esc:
            buf.append(ch)
            esc = False
            continue
        if ch == "\\" and in_dq:
            buf.append(ch)
            esc = True
            continue
        if ch == '"':
            if not in_sq:
                in_dq = not in_dq
            buf.append(ch)
            continue
        if ch == "'":
            if not in_dq:
                in_sq = not in_sq
            buf.append(ch)
            continue
        if ch == "," and not in_dq and not in_sq:
            item = "".join(buf).strip()
            if item:
                items.append(item)
            buf = []
            continue
        buf.append(ch)
    last = "".join(buf).strip()
    if last:
        items.append(last)
    return items


def _parse_array_of_strings(s: str) -> list[str]:
    s = s.strip()
    if not (s.startswith("[") and s.endswith("]")):
        raise TomlError(f"invalid array: {s!r}")
    inner = s[1:-1].strip()
    if not inner:
        return []
    parts = _split_top_level_commas(inner)
    return [_parse_string(p) for p in parts]


def _set_path(root: dict[str, Any], path: list[str], value: Any) -> None:
    cur: Any = root
    for key in path[:-1]:
        if key not in cur or not isinstance(cur[key], dict):
            cur[key] = {}
        cur = cur[key]
    cur[path[-1]] = value


def _get_path(root: dict[str, Any], path: list[str]) -> Any:
    cur: Any = root
    for key in path:
        if not isinstance(cur, dict) or key not in cur:
            return None
        cur = cur[key]
    return cur


def loads(toml_text: str) -> dict[str, Any]:
    data: dict[str, Any] = {}
    current_table: dict[str, Any] = data
    lines = toml_text.splitlines()

    def is_complete_array(text: str) -> bool:
        depth = 0
        in_dq = False
        in_sq = False
        esc = False
        for ch in text:
            if esc:
                esc = False
                continue
            if ch == "\\" and in_dq:
                esc = True
                continue
            if ch == '"' and not in_sq:
                in_dq = not in_dq
                continue
            if ch == "'" and not in_dq:
                in_sq = not in_sq
                continue
            if in_dq or in_sq:
                continue
            if ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
                if depth == 0:
                    return True
        return False

    i = 0
    while i < len(lines):
        raw = lines[i]
        line = _strip_comment(raw).strip()
        if not line:
            i += 1
            continue

        if line.startswith("[[") and line.endswith("]]"):
            header = line[2:-2].strip()
            path = [p.strip() for p in header.split(".") if p.strip()]
            if not path:
                raise TomlError("empty array-of-tables header")
            if any(not _re_key.match(p) for p in path):
                raise TomlError(f"invalid header: {header!r}")

            parent_path = path[:-1]
            leaf = path[-1]
            parent = _get_path(data, parent_path)
            if parent is None:
                _set_path(data, parent_path, {})
                parent = _get_path(data, parent_path)
            if not isinstance(parent, dict):
                raise TomlError(f"invalid parent table for {header!r}")

            arr = parent.get(leaf)
            if arr is None:
                arr = []
                parent[leaf] = arr
            if not isinstance(arr, list):
                raise TomlError(f"expected array for {header!r}")

            new_item: dict[str, Any] = {}
            arr.append(new_item)
            current_table = new_item
            i += 1
            continue

        if line.startswith("[") and line.endswith("]"):
            header = line[1:-1].strip()
            path = [p.strip() for p in header.split(".") if p.strip()]
            if not path:
                raise TomlError("empty table header")
            if any(not _re_key.match(p) for p in path):
                raise TomlError(f"invalid header: {header!r}")

            table = _get_path(data, path)
            if table is None:
                _set_path(data, path, {})
                table = _get_path(data, path)
            if not isinstance(table, dict):
                raise TomlError(f"expected table for {header!r}")
            current_table = table
            i += 1
            continue

        if "=" not in line:
            raise TomlError(f"invalid line: {raw!r}")
        k, v = line.split("=", 1)
        key = k.strip()
        if not _re_key.match(key):
            raise TomlError(f"invalid key: {key!r}")
        val_str = v.strip()
        if val_str.startswith("[") and not is_complete_array(val_str):
            buf = val_str
            while True:
                i += 1
                if i >= len(lines):
                    raise TomlError(f"unterminated array for key {key!r}")
                nxt = _strip_comment(lines[i]).strip()
                if not nxt:
                    continue
                buf = buf + " " + nxt
                if is_complete_array(buf):
                    val_str = buf
                    break

        if val_str.startswith("["):
            value = _parse_array_of_strings(val_str)
        else:
            value = _parse_string(val_str)
        current_table[key] = value
        i += 1

    return data
