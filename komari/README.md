# Container-script

Container startup script with these built-in tasks:

- Nezha agent install and start
- Komari agent install and start
- Argosbx main script bootstrap
- Container port auto-detection
- Environment variable pass-through into argosbx.sh

## Remote install

Use curl:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

Use wget if curl is unavailable:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## Pass variables before startup

You can place environment variables in front of the remote command.

Example:

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

Those variables will:

- take effect for the current run
- be inherited by `argosbx.sh`
- be saved to `$HOME/.container-script.env`
- be restored again after reboot when autostart runs

## Argosbx pass-through

The script now supports this flow directly:

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

Internally it will continue with:

```bash
bash argosbx.sh rep
```

Because the environment is inherited, variables like `hypt` and `tupt` are passed into `argosbx.sh` automatically.

## Container port detection

The script checks these variables for a container port:

- `SERVER_PORT`
- `PORT`
- `PANEL_PORT`
- `LISTEN_PORT`
- `APP_PORT`
- `WEB_PORT`
- `CONTAINER_PORT`
- `INTERNAL_PORT`

If a valid port is found, it exports:

- `SERVER_PORT`
- `PORT`
- `CONTAINER_PORT`
- `INTERNAL_PORT`
- `PANEL_PORT`

If `hypt` was not set manually, the detected container port is also used as the default `hypt` value.

## Nezha usage

Supported inputs:

1. Paste the official Nezha command after the script starts.
2. Pass it with `NZ_CMD`.
3. Reuse an existing local `nezha.yml`.

Example:

```bash
NZ_CMD='NZ_SERVER=example.com:5555 NZ_CLIENT_SECRET=your-secret NZ_TLS=false' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## Komari usage

Supported inputs:

1. Paste the official Komari install command after the script starts.
2. Pass only arguments such as `-e https://example.com -t your-token`.
3. Pass it with `KOMARI_CMD`.
4. Reuse an existing local `komari-agent.args`.

Example:

```bash
KOMARI_CMD='-e https://example.com -t your-token' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## Common examples

Only Argosbx variables:

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

Argosbx variables plus Komari:

```bash
hypt="1" tupt="2" KOMARI_CMD='-e https://example.com -t your-token' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

Argosbx variables plus Nezha:

```bash
hypt="1" tupt="2" NZ_CMD='NZ_SERVER=example.com:5555 NZ_CLIENT_SECRET=your-secret NZ_TLS=false' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## Persistence

The script automatically:

- refreshes the remote `start.sh` into `$HOME/start.sh`
- saves the environment into `$HOME/.container-script.env`
- installs an `@reboot` task through `crontab` when available
