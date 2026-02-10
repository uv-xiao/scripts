# Repo architecture (scripts/)

This repo is a collection of self-contained, no-root bash modules.

## Layout

- `scripts/<id>/`
  - `<id>.sh`: entrypoint (the thing `kind="script"` executes)
  - `README.md`: user-facing usage docs
  - `script.toml`: registration + tests for the framework
- `tests/`
  - `run.sh`: orchestrator (`shellcheck` if available, framework fixture test, then module tests)
  - `runner.sh`: discovers `scripts/*/script.toml` and runs smoke/integration sets
  - `tools/`
    - `minitoml.py`: minimal TOML loader (subset sufficient for this repo)
    - `read_field.py`: reads `id`, `entry`, etc
    - `gen_session.py`: generates one bash “session script” per module that runs all steps in order
  - `container/`
    - `Dockerfile`: container deps for integration tests
    - `run.sh`: builds + runs `INTEGRATION=1 tests/run.sh` inside docker/podman
- `.github/workflows/ci.yml`: runs container tests on push/PR

## Design intent

- **Modularity:** adding a new script should not require editing the test framework; just add `scripts/<id>/script.toml`.
- **Non-interactive tests:** CI runs without a TTY; scripts must support `--yes` and/or `--no-shell` patterns.
- **Networked integration:** integration tests may download releases / clone repos; add retries/backoff to reduce flakiness.
- **Safety:** integration tests run in an isolated `$HOME` (set by the framework) so they do not modify a developer’s real rc files.

## When to update the container

If a new script requires additional system packages to run (e.g., `jq`, `unzip`), add them to `tests/container/Dockerfile` so CI has them.

