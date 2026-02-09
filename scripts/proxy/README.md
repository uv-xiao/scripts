# proxy

Installs shell helper functions to quickly toggle HTTP(S) proxy env vars and Git proxy settings.

## Usage

```bash
scripts/proxy/proxy.sh --help
```

## Run via curl/wget

curl:

```bash
curl -fsSL https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/proxy/proxy.sh | bash -s -- --yes
```

wget:

```bash
wget -qO- https://raw.githubusercontent.com/uv-xiao/scripts/main/scripts/proxy/proxy.sh | bash -s -- --yes
```

Common:

```bash
scripts/proxy/proxy.sh --port 7890 --yes
```

Then in your shell:

```bash
proxy on 7890
proxy status
proxy off
```
