# Script Collection

Self-contained, no-root environment setup scripts.

This repo aims to make installing and managing common CLI tooling possible via a single command, without requiring `sudo` (where feasible).

## What this repo provides

- **Modular scripts** under `scripts/<id>/` with:
  - `scripts/<id>/<id>.sh` (entrypoint)
  - `scripts/<id>/README.md` (usage)
  - `scripts/<id>/script.toml` (registration + tests)
- **Script registry + tests** driven by TOML (no hard-coded script lists in the framework).
- **Containerized integration tests** (networked, non-interactive) and **GitHub CI**.

## Current modules

- `scripts/omz/omz.sh`: builds/installs `zsh` into `~/.local`, installs oh-my-zsh, and installs the `powerlevel10k` theme.
- `scripts/proxy/proxy.sh`: installs `proxy` helpers into your shell rc (`proxy on|off|status|toggle|set`).
- `scripts/mihomo/mihomo.sh`: installs `mihomo` into `~/.local/bin` and manages it in a tmux session (`start|stop|restart|status|attach`).

All scripts support `--help`.

## Install / usage

Each module has its own usage docs:

- `scripts/omz/README.md`
- `scripts/proxy/README.md`
- `scripts/mihomo/README.md`

You can also run scripts directly from GitHub via `curl`/`wget` (see each module README for the exact command).

## Testing

Smoke tests (runs each module’s `tests.smoke` from `script.toml`):

```bash
tests/run.sh
```

Networked integration tests (runs each module’s `tests.integration` from `script.toml`):

```bash
INTEGRATION=1 tests/run.sh
```

Container-based integration tests (used by CI):

```bash
tests/container/run.sh
```

## Architecture

**Module discovery**
- `tests/runner.sh` scans `scripts/*/script.toml`.

**Test model**
- Each `script.toml` declares `[[tests.smoke]]` and `[[tests.integration]]` steps.
- Steps run in a **single shared bash session per script** (env persists across steps).
- Two step types:
  - `kind="script"`: runs the module entrypoint with `args=[...]`
  - `kind="bash"`: runs a bash snippet (`run=[...]`) for assertions or multi-command flows

**Container + CI**
- `tests/container/run.sh` builds `tests/container/Dockerfile` and runs `INTEGRATION=1 tests/run.sh` inside the container.
- `.github/workflows/ci.yml` runs the same container test command.
