#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

HOST_HOME="$TMP_ROOT/home/tester"
PI_DIR="$HOST_HOME/.pi/agent"
GOPATH_DIR="$HOST_HOME/go"
mkdir -p "$PI_DIR" "$GOPATH_DIR/pkg"

OUT="$TMP_ROOT/compose-config.yml"

echo
echo "═══ docker compose config smoke test ═══"
HOST_UID=1000 \
HOST_USER=tester \
HOST_HOME="$HOST_HOME" \
GO_VERSION=go1.26.0 \
GOPATH="$GOPATH_DIR" \
PI_CODING_AGENT_DIR_HOST="$PI_DIR" \
ALLOWED_BIND_MOUNTS="$PI_DIR,$GOPATH_DIR/pkg" \
DOCKER_MEMORY_LIMIT=0 \
GITHUB_TOKEN=dummy \
GIT_USER_NAME= \
GIT_USER_EMAIL= \
GOPRIVATE= \
GONOSUMDB= \
docker compose -f docker-compose.yml config > "$OUT"

if grep -q '^  pi:$' "$OUT" && grep -q '^  filter-proxy:$' "$OUT" && grep -q '^  socket-proxy:$' "$OUT"; then
  ok "compose includes expected services"
else
  fail "compose missing expected services"
fi

if grep -q 'target: /usr/local/bin/pi-notifier' "$OUT"; then
  ok "compose mounts notifier hook"
else
  fail "compose missing notifier hook mount"
fi

if grep -q "source: $PI_DIR" "$OUT" && grep -q "target: $PI_DIR" "$OUT"; then
  ok "compose mounts pi agent dir"
else
  fail "compose missing pi agent dir mount"
fi

if grep -q 'container_name: pi-docker' "$OUT"; then
  ok "compose keeps expected container name"
else
  fail "compose missing pi-docker container name"
fi

echo
echo "═══════════════════════════════"
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "ALL TESTS PASSED" || { echo "SOME TESTS FAILED"; exit 1; }
