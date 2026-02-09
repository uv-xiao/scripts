# omz

Installs `zsh` (built from source into `~/.local` by default), then installs oh-my-zsh and the powerlevel10k theme.

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
