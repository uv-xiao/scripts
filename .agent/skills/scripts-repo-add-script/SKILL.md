---
name: scripts-repo-add-script
description: Add a new script module to this repo (scripts/ID/) with a bash entrypoint, usage docs, and a per-script script.toml that registers smoke/integration tests for the TOML-driven test runner. Use when creating or modifying modules, extending the container/CI test environment, or debugging how tests are discovered and executed in one shared bash session per script.
---

# Scripts Repo Add Script

## Workflow

Add a new module by creating `scripts/<id>/` containing:

- `scripts/<id>/<id>.sh` (entrypoint; executable; supports `--help`; non-interactive flags for CI)
- `scripts/<id>/README.md` (user-facing usage)
- `scripts/<id>/script.toml` (registration + `[[tests.smoke]]` + `[[tests.integration]]`)

Then run:

- `tests/run.sh` (smoke)
- `INTEGRATION=1 tests/run.sh` (integration; networked; non-interactive; isolated `$HOME`)

Use `skills/scripts-repo-add-script/scripts/scaffold_module.py` to generate the skeleton.

## Module conventions

- Scripts should be safe to run in CI: avoid prompts by supporting `--yes` and/or `--no-shell` and defaulting to non-destructive operations unless explicitly requested.
- Prefer `~/.local` by default (no root).
- Any network fetch should use retries/backoff to reduce flakiness.
- Support “download-and-run” installs in docs (and in `--help` output) using GitHub raw URLs:
  - `curl -fsSL <raw-url> | bash -s -- ...`
  - `wget -qO- <raw-url> | bash -s -- ...`

Examples in this repo:

- `scripts/omz/omz.sh` + `scripts/omz/script.toml`
- `scripts/proxy/proxy.sh` + `scripts/proxy/script.toml`
- `scripts/mihomo/mihomo.sh` + `scripts/mihomo/script.toml`

## Testing model (TOML-driven)

Each module declares tests in `scripts/<id>/script.toml`:

- `[[tests.smoke]]`: fast checks (usually `--help`).
- `[[tests.integration]]`: networked / full install / assertions.

Supported step kinds:

- `kind="script"`: runs the module entrypoint (`"$SCRIPT_ENTRY" ...`).
- `kind="bash"`: runs a bash snippet for assertions or multi-command flows.

Execution details:

- Tests for a given module run in a single shared bash process (env persists across steps).
- Integration sessions run with an isolated `$HOME` under `$SCRIPT_TMPDIR` to avoid touching the developer machine.

Read these references when needed:

- `skills/scripts-repo-add-script/references/repo-architecture.md` (repo layout + CI)
- `skills/scripts-repo-add-script/references/testing-framework.md` (runner + env vars + TOML schema)

## Templates

Use the templates in `skills/scripts-repo-add-script/assets/templates/` (or run the scaffold script):

- `module.sh.tmpl`
- `README.md.tmpl`
- `script.toml.tmpl`
