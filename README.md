# pi-docker

Run [pi](https://shittycodingagent.ai) inside an isolated Docker container instead of directly on your host. The container mirrors your host environment (same paths, UID, shell), so file references, sessions, `AGENTS.md`/`CLAUDE.md` discovery, and pi auth all keep working with minimal friction.

This is the pi sibling of [`claude-docker`](https://github.com/hrubymar10/claude-docker): same general security model, same path-mirroring idea, but adapted to pi's config and auth model.

## Features

- **Isolated execution** — pi runs in an Alpine container instead of directly on your host
- **Docker socket proxy** — filtered Docker API access via `wollomatic/socket-proxy` plus an extra validation proxy
- **Path mirroring** — `~/project` inside the container is the same path as on the host
- **Host identity mirroring** — same username, UID, home path, and preferred shell
- **Shared pi state** — mounts your pi agent directory, so auth, settings, sessions, prompts, skills, packages, and model config are reused
- **Session teardown for terminal and IDE callers** — host watchdog plus in-container wrapper clean up orphaned pi processes even when the parent wrapper dies early
- **Git safety rails** — blocks pushes to protected branches from inside the container
- **Optional GPG import** — import signing keys into the container at startup
- **Optional notifier hook** — mount a custom `pi-notifier` script into the container for sound/desktop notifications
- **Optional beeper helper** — host-side HTTP helper for simple sound notifications

## How it maps to pi

pi stores its state under `~/.pi/agent/` by default:

- `auth.json`
- `settings.json`
- `models.json`
- sessions
- installed git packages
- prompts, skills, themes, extensions

`pi-docker` mounts that directory directly, so the same pi identity and configuration are visible inside the container.

If you use a custom config path, set `PI_CODING_AGENT_DIR` on the host before running `bin/pi-docker-ctrl start`.

## Prerequisites

- macOS or Linux
- Docker Desktop, OrbStack, or Docker Engine
- Node/npm on the container image build host is **not** required; the image installs pi itself

## Setup

### 1. Clone and enter the repo

```bash
git clone https://github.com/hrubymar10/pi-docker.git
cd pi-docker
```

### 2. Add `bin/` to your PATH

```bash
export PATH="/path/to/pi-docker/bin:$PATH"
```

This gives you:

- `pi-docker`
- `pi-docker-ctrl`

### 3. Prepare pi auth/config

You have two common options:

#### Option A: API keys

Export provider API keys on the host, for example:

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

#### Option B: pi `/login`

pi stores OAuth/subscription auth in `~/.pi/agent/auth.json`. Since that directory is mounted into the container, you can:

- authenticate on the host once with `pi` and `/login`, or
- authenticate inside the container after startup

See the pi docs for supported providers and auth flows.

### 4. Configure your project mounts

```bash
cp config/docker-compose.local.example.yml config/docker-compose.local.yml
```

Edit `config/docker-compose.local.yml` and add the directories you want pi to access:

```yaml
services:
  pi:
    volumes:
      - ${HOST_HOME}/projects:${HOST_HOME}/projects
      - ${HOST_HOME}/work:${HOST_HOME}/work
```

Paths are mirrored exactly.

### 5. Optional: customize environment

```bash
cp config/.env.example config/.env
```

You usually do not need this, but it is useful for:

- pinning `PI_VERSION`
- selecting extra Alpine packages
- overriding `PI_CODING_AGENT_DIR`
- setting protected branches

### 6. Start the container

```bash
bin/pi-docker-ctrl start
```

### 7. Use pi

From any mounted project directory:

```bash
cd ~/projects/my-app
pi-docker
```

Or:

```bash
bin/pi-docker-ctrl exec
```

Both run `pi` inside the container with the current working directory preserved.

## VS Code (`pi0.pi-vscode`)

The [pi-vscode](https://marketplace.visualstudio.com/items?itemName=pi0.pi-vscode) extension is terminal-based: it launches the configured `pi` binary inside an integrated terminal.

To make it use the Docker container instead of your host `pi`, point the extension at the wrapper in this repo.

1. Install the extension
2. Make sure the container is running
3. Set VS Code setting `pi-vscode.path` to:

```bash
/path/to/pi-docker/bin/pi-docker-vscode-wrapper
```

Example:

```json
{
  "pi-vscode.path": "/Users/you/xcode/pi-docker/bin/pi-docker-vscode-wrapper"
}
```

The wrapper forwards all CLI args to `pi-docker`, so commands like:

- `Pi: Open`
- `Pi: Open with File`
- `Pi: Send Selection`
- `@pi` chat forwarding

all run pi inside the container.

## Commands

```bash
bin/pi-docker-ctrl start    # build image, start container
bin/pi-docker-ctrl stop     # stop container
bin/pi-docker-ctrl status   # show status
bin/pi-docker-ctrl shell    # shell into the container
bin/pi-docker-ctrl exec     # run pi in the container
bin/pi-docker-ctrl rebuild       # rebuild image from scratch + restart
bin/pi-docker-ctrl beeper-start  # start host beeper server (default 127.0.0.1:9999)
bin/pi-docker-ctrl beeper-stop   # stop host beeper server

pi-docker                         # shortcut wrapper that runs pi in the container
```

Any pi arguments are forwarded:

```bash
pi-docker -p "summarize this repo"
pi-docker --model anthropic/claude-sonnet-4
pi-docker --mode rpc
```

## Beeper

Optional host-side HTTP server (`beeper/main.go`) that plays a sound when called. Started by `pi-docker-ctrl beeper-start`. Two env vars control access:

- `BEEPER_BIND` — `host:port` to listen on. Default `127.0.0.1:9999`. Host must be an IP literal (no hostnames). Set to `0.0.0.0:9999` to expose on all interfaces.
- `BEEPER_ALLOW` — comma-separated list of source IPs / CIDRs that may call the beeper. Default `127.0.0.0/8`. Bare IPs are normalised to `/32` (v4) / `/128` (v6). Requests from anywhere else get a `403`.

For container access via `host.docker.internal`, the defaults are sufficient on Docker Desktop / OrbStack (it forwards to host loopback). For VPN clients or other remote access, widen both:

```bash
export BEEPER_BIND=0.0.0.0:9999
export BEEPER_ALLOW=127.0.0.0/8,172.28.47.0/24
```

**Linux note:** on Linux Docker Engine, `host.docker.internal` resolves to the Docker bridge gateway (typically in `172.17.0.0/16` or `172.16.0.0/12`), not host loopback. The default `BEEPER_ALLOW=127.0.0.0/8` will block those requests. Add the bridge subnet to allow container→host beeper calls:

```bash
export BEEPER_BIND=0.0.0.0:9999
export BEEPER_ALLOW=127.0.0.0/8,172.17.0.0/16   # adjust to your bridge subnet
```

Note: `beeper/main.go` calls `afplay` (macOS only) — sound playback does not work on Linux, but the HTTP endpoint still responds.

`X-Forwarded-For` is intentionally not honoured — this is a direct-connection service.

## Custom models and proxies

pi already supports provider/model overrides through `~/.pi/agent/models.json`.

That means you usually do **not** need special wrapper binaries for alternate backends. Route built-in providers through proxies, or add custom providers/models there instead.

Example:

```json
{
  "providers": {
    "anthropic": {
      "baseUrl": "https://my-proxy.example.com/v1"
    }
  }
}
```

See pi docs:

- `docs/providers.md`
- `docs/models.md`
- `docs/custom-provider.md`

## Security

The container does **not** get direct access to `/var/run/docker.sock`.

Instead:

- Docker calls go through a filtering proxy
- dangerous container-create options are rejected
- Docker socket bind mounts are stripped from downstream create requests
- the in-container `docker` wrapper blocks dangerous subcommands like `run`, `build`, and `cp`
- the in-container `git` wrapper blocks pushes to protected branches (`main`, `master` by default)

See [SECURITY_ISSUES.md](SECURITY_ISSUES.md) for caveats.

## Testing

```bash
bash -n bin/pi-docker bin/pi-docker-ctrl bin/lib/session-cleanup.sh scripts/*.sh test/*.sh
make test
```

Current tests cover:

- mount boundary logic
- credential helper quoting
- session PID file naming
- wrapper behavior with mocked `docker`
- start-time preflight/override generation with mocked `docker`
- explicit compose project pinning
- `docker compose config` rendering smoke test
- VS Code wrapper forwarding (`pi-vscode.path`)

## Notes

- the notifier file is now `config/pi-notifier`, mounted as `/usr/local/bin/pi-notifier`
- a compatibility symlink also exposes `/usr/local/bin/claude-notifier` inside the container for older scripts
- pi loads both `AGENTS.md` and `CLAUDE.md`; `pi-docker-ctrl` auto-mounts your global copies if present
- if you use `~/.agents`, it is auto-mounted too so pi skills remain available
- if you use a custom `PI_PACKAGE_DIR`, set it before startup so the container mounts it as well
- `bin/pi-docker-ctrl` pins `COMPOSE_PROJECT_NAME=pi-docker` by default so resource names do not depend on the checkout directory name
- the `pi0.pi-vscode` extension can be pointed at `bin/pi-docker-vscode-wrapper` via `pi-vscode.path`
- pi's other integration story remains its terminal UI, JSON mode, RPC mode, and SDK

## License

MIT
