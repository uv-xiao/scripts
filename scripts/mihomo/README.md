# mihomo

Installs the `mihomo` binary without root and provides tmux-managed start/stop helpers.

## Usage

```bash
scripts/mihomo/mihomo.sh --help
```

## Run via curl/wget

curl:

```bash
curl -fsSL https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/mihomo/mihomo.sh | bash -s -- install --yes
```

wget:

```bash
wget -qO- https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/mihomo/mihomo.sh | bash -s -- install --yes
```

Install:

```bash
scripts/mihomo/mihomo.sh install --yes
```

Start in tmux:

```bash
scripts/mihomo/mihomo.sh start --config ~/.config/mihomo/config.yaml
```
