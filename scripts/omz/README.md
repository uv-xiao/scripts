# omz

Installs `zsh` (built from source into `~/.local` by default), then installs oh-my-zsh and the powerlevel10k theme.

## Dependencies

`omz.sh` builds `zsh` from source, which needs a terminal handling library (**curses/ncurses**).

- On full distros this is usually already available.
- On minimal images/VMs you may need a `*-dev` package (e.g. `libncursesw5-dev` / `ncurses-devel`).
- `omz.sh` will try to satisfy this automatically (install system package if running as root, otherwise build `ncurses` locally under `~/.local/.deps/ncurses`).

## Usage

```bash
scripts/omz/omz.sh --help
```

## Run via curl/wget

curl:

```bash
curl -fsSL https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/omz/omz.sh | bash -s -- --yes --shell both
```

wget:

```bash
wget -qO- https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/omz/omz.sh | bash -s -- --yes --shell both
```

Non-interactive install:

```bash
scripts/omz/omz.sh --yes --shell both
```
