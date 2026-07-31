# pi-docker

Run [pi](https://pi.dev) inside an isolated Docker container instead of directly on your host. The container mirrors your host environment (same paths, UID, shell), so file references, sessions, `AGENTS.md`/`CLAUDE.md` discovery, and pi auth all keep working with minimal friction.

## Scope: what this is, what it isn't

This is an **opinionated** project tuned for the way I and my colleagues work day to day. The goal is to keep the daily pi flow feeling exactly like running `pi` on the host — same paths, same git, same `docker compose` against your project's stack — while putting a soft blanket between pi and the parts of your machine you'd rather it not touch by accident.

**This is a safety net for *bad prompts*, not *bad actors*.**

The threat model this project addresses is **AI mistakes** — the kind of footguns an LLM can stumble into when interpreting an ambiguous instruction, getting confused about state, or going overboard trying to be helpful. Concretely:

- You're checked out on `master` without realizing it and prompt *"do the changes and push them"*. pi tries `git push`, the wrapper refuses pushes to protected branches, and you (the human) decide whether to push from the host. No accidental force-push to `master` because pi didn't pause to ask.
- You write *"make REALLY sure that directory is gone"* and pi, in its enthusiasm, reaches for `sudo rm -rf /`. The container is the blast radius — only your mounted project dirs are reachable, the host is untouched. Worst case you lose what you mounted, not your home directory.
- A misread file path or runaway loop tries to write somewhere it shouldn't. The bind-mount allowlist confines damage to directories you explicitly opted in.

The threat model this project does **not** address is a deliberately adversarial pi — an LLM actively crafting multi-step attacks to break out of the sandbox, exfiltrate credentials via sibling containers, or otherwise behave like a hostile insider. If that's your threat model, this isn't the right tool: don't give pi the Docker socket at all, don't bind-mount your pi agent directory, and consider air-gapped execution.

The friction trade-off goes one way on purpose: **the sandbox must not get in our way**. Standard `docker compose up`, `docker compose exec`, debugger attach, language servers, and the rest of the daily-driver workflow all work without per-project allowlists or extra config. If a hardening proposal would block a legitimate developer flow, it's out of scope for this project — even if it would close a theoretical attack path.

In short: paranoia calibrated to "AI mental breakdown", not to "nation-state in your chat window".

## Siblings

`pi-docker` is one of several sibling projects that apply the same sandboxing model to different AI coding agents. They share the security philosophy (filtered Docker socket, path mirroring, git-push wrapper, scope above) and most of the implementation, but each is adapted to its agent's config and auth model.

| Project | Wraps |
| --- | --- |
| [`claude-docker`](https://github.com/hrubymar10/claude-docker) | [Claude Code](https://docs.anthropic.com/en/docs/claude-code) |
| [`codex-docker`](https://github.com/hrubymar10/codex-docker) | [OpenAI Codex CLI](https://github.com/openai/codex) |
| [`pi-docker`](https://github.com/hrubymar10/pi-docker) (this project) | [pi](https://pi.dev) |
| [`vibe-docker`](https://github.com/hrubymar10/vibe-docker) | [Mistral Vibe](https://mistral.ai/vibe) |

Pick by which agent you actually use day to day. Running more than one in parallel is fine — the containers are independent.

## Features

- **Isolated execution** — pi runs in an Alpine container instead of directly on your host
- **Docker socket proxy** — filtered Docker API access via `wollomatic/socket-proxy` plus an extra validation proxy
- **Path mirroring** — `~/project` inside the container is the same path as on the host
- **Host identity mirroring** — same username, UID, home path, and preferred shell
- **Shared pi state** — mounts your pi agent directory, so auth, settings, sessions, prompts, skills, packages, and model config are reused
- **Session teardown for terminal and IDE callers** — host watchdog plus in-container wrapper clean up orphaned pi processes even when the parent wrapper dies early
- **Git safety rails** — blocks pushes to protected branches from inside the container
- **AWS credentials proxy** — read-only AWS SSO credentials via the shared host-side [`aws-ai-proxy`](https://github.com/hrubymar10/aws-ai-proxy)
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

| Git push setting | Default | Purpose |
|------------------|---------|---------|
| `GIT_PROTECTED_BRANCHES` | `main master` | Branch names blocked by the in-container git wrapper. |
| `GIT_PROTECTED_BRANCH_EXEMPT_REPOS` | empty | Space-separated `host/org/repo` destinations allowed to receive protected branches; tag pushes remain blocked. |

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

## SSH Agent Forwarding

pi inside the container can use your host SSH agent for git pushes, `ssh` connections, etc. — no private keys are copied into the container.

If `SSH_AUTH_SOCK` is set on the host (i.e. an `ssh-agent` is running), `pi-docker-ctrl start` automatically launches a `socat` TCP relay on `127.0.0.1:19922` that bridges the host's Unix-domain agent socket. Inside the container, `SSH_AUTH_SOCK` is configured to point at the relay over `host.docker.internal`, and `~/.ssh/known_hosts` is bind-mounted in. Use `ssh-add -l` inside the container to confirm the agent is reachable.

### Setup

1. Install `socat` on the host. On macOS: `brew install socat`. On Linux: install via your package manager.
2. Make sure your SSH agent is running on the host — `echo "$SSH_AUTH_SOCK"` should print a path.
3. Add your key once: `ssh-add ~/.ssh/id_ed25519` (or whichever key).
4. Start (or restart) the container: `bin/pi-docker-ctrl start`.

The relay starts on `pi-docker-ctrl start` and stops on `pi-docker-ctrl stop`. If `socat` isn't available on the host, the relay is skipped with a warning and the rest of the container still starts normally.

## AWS Credentials (Optional)

pi inside the container can use read-only AWS credentials via an independently running [`aws-ai-proxy`](https://github.com/hrubymar10/aws-ai-proxy) service. No AWS credentials are stored in the container; every request is forwarded to the proxy, which uses its active host SSO session.

Configure and start [`aws-ai-proxy`](https://github.com/hrubymar10/aws-ai-proxy), then enable consumption in your shell or `config/.env`:

```bash
AWS_AI_PROXY_ENABLED=1
AWS_AI_PROXY_URL=http://host.docker.internal:9998
```

Log in on the host first:

```bash
aws sso login --profile my-readonly
```

Then start or restart the container:

```bash
bin/pi-docker-ctrl start
```

On start, the control script fetches enabled profiles from `$AWS_AI_PROXY_URL/profiles`. If the fetch fails, the container still starts and AWS proxy profiles are skipped with a warning. Inside the container, `~/.aws/config` is generated with `credential_process` entries that call `$AWS_AI_PROXY_URL/credentials/{profile}`.

### Upgrading from the legacy proxy

Older docker setups may still have `AWS_CRED_PROXY_PROFILES` or `AWS_CRED_PROXY_PORT` in the process environment or `config/.env`. Those variables are ignored by the current consumer-only model. During `start` and `rebuild`, `pi-docker-ctrl` detects active legacy variables when `AWS_AI_PROXY_ENABLED` is not already enabled. In a terminal it prompts to comment active legacy lines out of `config/.env`, show migration steps, or ignore once; in non-interactive IDE/automation runs it only prints the warning and continues.

## GitLab CLI (glab) (Optional)

The `glab` CLI is pre-installed, mirroring the bundled `gh` (GitHub CLI). The key thing to understand: the GitLab **API** — which is everything `glab` does (merge requests, pipelines, issues) — can only authenticate with a **token**, never an SSH key. SSH keys cover git transport only.

So there are two independent layers:

- **Git push/pull/clone** to GitLab — already works with **no token** via [SSH agent forwarding](#ssh-agent-forwarding). Nothing to configure beyond the agent.
- **The `glab` CLI** — needs a token. There's no SSH-key path to the GitLab API (same as `gh`).

### Setup

1. Authenticate `glab` once **on the host** (OAuth web flow — no manual PAT needed):

   ```bash
   glab auth login --hostname gitlab.com --web
   ```

   Alternatively, set `GITLAB_TOKEN` in `config/.env` to a Personal Access Token with the `api` scope.

2. Start (or rebuild) the container: `bin/pi-docker-ctrl start`. `pi-docker-ctrl` reads the host token via `glab config get token` and passes it into the container as `GITLAB_TOKEN`, where `glab` picks it up automatically.

Git transport is left on SSH — no `git@gitlab.com:` → HTTPS rewrite is applied, so existing remotes keep using the forwarded agent. A credential helper is still configured for `https://$GITLAB_HOST`, so HTTPS remotes work too when a token is present.

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GITLAB_TOKEN` | `$(glab config get token --host gitlab.com)` | Token for the `glab` CLI. Auto-detected from the host glab, or set explicitly. |
| `GITLAB_HOST` | `gitlab.com` | Set only for self-managed GitLab. |

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
- the in-container `git` wrapper blocks pushes to protected branches (`main`, `master` by default) and any `git push` that would publish tags (`--tags`, `--follow-tags`, `--mirror`, a `refs/tags/*` refspec, or the `<remote> tag <name>` shorthand)

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
