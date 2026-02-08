# proxy

Installs shell helper functions to quickly toggle HTTP(S) proxy env vars and Git proxy settings.

## Usage

```bash
scripts/proxy/proxy.sh --help
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

