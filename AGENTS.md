# AGENTS.md

## Project

`pi-docker` runs [pi](https://pi.dev) inside a Docker container with host path mirroring, Docker socket filtering, and a few safety rails.

## Goals

- Keep pi isolated from the host except for explicitly mounted paths
- Preserve the same host paths, UID, username, and shell inside the container
- Reuse the host pi state directory (`~/.pi/agent` by default)
- Keep the implementation simple shell/compose/go where possible

## Important files

- `README.md` — user-facing setup and usage
- `Dockerfile` — container image, pi installation, tooling
- `docker-compose.yml` — main services and mounts
- `bin/pi-docker-ctrl` — lifecycle management (`start`, `stop`, `status`, `shell`, `exec`, `rebuild`)
- `bin/pi-docker` — convenience wrapper to run `pi` in the container
- `bin/pi-docker-vscode-wrapper` — wrapper for the `pi-vscode` VS Code extension
- `scripts/entrypoint.sh` — runtime setup inside the container
- `beeper/` — optional host-side HTTP beep server; a sample `config/pi-notifier` can call it to play sounds from inside the container
- `../aws-ai-proxy/` - optional independently running AWS credential proxy consumed when `AWS_AI_PROXY_ENABLED` is true (https://github.com/hrubymar10/aws-ai-proxy)
- `scripts/pi-session.sh` — session wrapper/cleanup
- `scripts/git-wrapper.sh` — blocks pushes to protected branches
- `scripts/docker-wrapper.sh` — blocks dangerous Docker subcommands in-container
- `docker-filter-proxy/` — extra validation layer in front of socket proxy
- `config/docker-compose.local.example.yml` — local mount template
- `test/test-pi-docker.sh` — lightweight host-side wrapper tests
- `test/test-vscode-wrapper.sh` — VS Code wrapper forwarding test
- `test/test-wrappers-mock.sh` — mocked `docker` tests for `pi-docker` and `pi-docker-ctrl`
- `test/test-preflight-overrides.sh` — preflight/override generation tests
- `test/test-compose-config.sh` — compose rendering smoke test

## Common commands

```bash
make test
bash -n bin/pi-docker bin/pi-docker-ctrl bin/lib/session-cleanup.sh scripts/*.sh test/*.sh
bin/pi-docker-ctrl start
bin/pi-docker-ctrl status
bin/pi-docker-ctrl shell
bin/pi-docker-ctrl exec
bin/pi-docker-ctrl beeper-start
bin/pi-docker-ctrl beeper-stop
```

## Conventions

- Prefer small, direct shell scripts over heavy abstractions
- Keep pi-specific behavior in pi-specific files
- Backward compatibility is okay, but prefer pi-first names (`pi-notifier`, `PI_*` env vars, etc.)
- Keep `COMPOSE_PROJECT_NAME` pinned so docker resource names do not depend on the checkout directory name
- Docker repos are AWS proxy consumers only. Use `AWS_AI_PROXY_ENABLED` and `AWS_AI_PROXY_URL`; do not add proxy lifecycle management here.
- Legacy `AWS_CRED_PROXY_PROFILES` / `AWS_CRED_PROXY_PORT` values are ignored. `bin/pi-docker-ctrl start` and `rebuild` detect them when `AWS_AI_PROXY_ENABLED` is not truthy, prompt only on a TTY, and warn without blocking non-interactive runs.
- Update `README.md` when behavior changes
- Preserve exact host path mirroring semantics
- Preserve security defaults unless explicitly changing them

## Guardrails

- Do not add or update dependencies unless explicitly requested
- Do not weaken Docker/socket/git safety checks casually
- Do not mount more host paths by default than necessary
- If changing wrapper behavior, keep non-interactive/TTY behavior in mind

## Testing expectations

At minimum after meaningful changes:

```bash
bash -n bin/pi-docker bin/pi-docker-ctrl bin/lib/session-cleanup.sh scripts/*.sh test/*.sh
make test
```

If changing compose/build logic, also verify:

```bash
docker compose -f docker-compose.yml config
```
