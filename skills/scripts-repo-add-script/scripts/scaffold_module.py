#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import re


def die(msg: str) -> None:
    raise SystemExit(f"error: {msg}")


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: pathlib.Path, content: str, executable: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    if executable:
        mode = path.stat().st_mode
        path.chmod(mode | 0o111)


def apply_template(tmpl: str, *, script_id: str, name: str, one_line: str) -> str:
    return (
        tmpl.replace("{{id}}", script_id)
        .replace("{{name}}", name)
        .replace("{{one_line}}", one_line)
    )


def is_valid_id(script_id: str) -> bool:
    return bool(re.fullmatch(r"[a-z0-9][a-z0-9-]*", script_id))


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Scaffold a new module under scripts/<id>/ from skill templates."
    )
    parser.add_argument("id", help="module id (lowercase letters/digits/hyphens)")
    parser.add_argument("--name", default="", help="human-readable module name")
    parser.add_argument("--one-line", default="", help="one-line description for docs/help")
    parser.add_argument(
        "--repo-root",
        default=".",
        help="repo root (default: current directory)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite existing files",
    )
    args = parser.parse_args()

    script_id = args.id.strip()
    if not is_valid_id(script_id):
        die("id must match: [a-z0-9][a-z0-9-]*")

    repo_root = pathlib.Path(args.repo_root).resolve()
    scripts_dir = repo_root / "scripts" / script_id

    name = args.name.strip() or script_id
    one_line = args.one_line.strip() or f"{name} module (TODO: describe)"

    skill_dir = pathlib.Path(__file__).resolve().parent.parent
    tmpl_dir = skill_dir / "assets" / "templates"

    sh_tmpl = read_text(tmpl_dir / "module.sh.tmpl")
    readme_tmpl = read_text(tmpl_dir / "README.md.tmpl")
    toml_tmpl = read_text(tmpl_dir / "script.toml.tmpl")

    out_sh = scripts_dir / f"{script_id}.sh"
    out_readme = scripts_dir / "README.md"
    out_toml = scripts_dir / "script.toml"

    for p in (out_sh, out_readme, out_toml):
        if p.exists() and not args.force:
            die(f"refusing to overwrite existing file: {p} (use --force)")

    write_text(
        out_sh,
        apply_template(sh_tmpl, script_id=script_id, name=name, one_line=one_line),
        executable=True,
    )
    write_text(
        out_readme,
        apply_template(readme_tmpl, script_id=script_id, name=name, one_line=one_line),
    )
    write_text(
        out_toml,
        apply_template(toml_tmpl, script_id=script_id, name=name, one_line=one_line),
    )

    print(f"[OK] Created {out_sh}")
    print(f"[OK] Created {out_readme}")
    print(f"[OK] Created {out_toml}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

