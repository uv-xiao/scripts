# Testing framework (TOML-driven)

The framework discovers modules via `scripts/*/script.toml` and runs either the `tests.smoke` or `tests.integration` step list defined in each file.

## Discovery

- `tests/runner.sh` glob-scans `scripts/*/script.toml`.
- The module `id` is read from TOML (`tests/tools/read_field.py`).
- For each module, `tests/tools/gen_session.py` generates a temporary executable bash script (a “session”) and runs it.

## TOML schema used in this repo

Top-level fields:

- `id` (string): unique module id; should match folder name
- `name` (string): display name
- `entry` (string): entrypoint filename (usually `<id>.sh`)
- `docs` (string): doc filename (usually `README.md`)

Tests:

- `[[tests.smoke]]` tables: ordered list of steps for smoke tests
- `[[tests.integration]]` tables: ordered list of steps for integration tests

Step table fields:

- `kind = "script"`:
  - `args = ["..."]` (array of strings): arguments to pass to the entrypoint
- `kind = "bash"`:
  - `run = ["...","..."]` (array of strings) or `run = "multi\nline\nstring"`: bash lines executed in order

The TOML loader is intentionally small (`tests/tools/minitoml.py`). Keep TOML constructs simple: strings, arrays-of-strings, `[table]` and `[[array.of.tables]]`.

## Execution model (important)

For each module, all steps run inside one generated bash script:

- This means **one shared bash session per module** (exports persist across steps).
- `kind="bash"` steps are printed as raw bash lines into that session script.
- `kind="script"` steps call `"$SCRIPT_ENTRY" ...` directly.

### Environment variables available to tests

Injected by `tests/tools/gen_session.py`:

- `REPO_ROOT`: repo root path
- `SCRIPT_ID`: module id
- `SCRIPT_DIR`: directory containing `script.toml`
- `SCRIPT_ENTRY`: full path to entrypoint
- `SCRIPT_TMPDIR`: per-module temporary directory (deleted after the session)

Integration-only safety:

- `HOME` is set to an isolated directory under `SCRIPT_TMPDIR` so integration tests do not modify the developer’s real `~/.bashrc`, `~/.zshrc`, etc.
- `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME` are set under that isolated home.

## Writing good integration tests

Goals:

- **Non-interactive**: pass `--yes` or `--no-shell` flags when supported.
- **Deterministic assertions**: verify files and binaries exist and basic commands run.
- **Idempotent**: safe to run twice (or explicitly clean up).

Patterns:

- Use `$SCRIPT_TMPDIR` for temporary config files.
- Prefer asserting on:
  - `test -x "$HOME/.local/bin/<tool>"`
  - `"<tool>" --version` / `-v` / `-t` config validation
  - `grep -q ... "$HOME/.zshrc"` for rc edits (in the isolated home)

## Running tests

From repo root:

- Smoke: `tests/run.sh`
- Integration: `INTEGRATION=1 tests/run.sh`
- Container (CI-style): `tests/container/run.sh --engine docker`

