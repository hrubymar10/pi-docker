#!/bin/sh
# Wrapper that keeps a supervising shell alive around pi so host-side cleanup
# can always deliver SIGHUP to a process group owned inside the container,
# including non-TTY callers such as aimebu/IDE wrappers.

PID_FILE=""
if [ -n "$PI_SESSION_ID" ]; then
    PID_FILE="/tmp/pi-session-${PI_SESSION_ID}.pid"
    echo $$ > "$PID_FILE"
fi

cleanup() {
    trap '' HUP TERM INT EXIT
    [ -n "$PID_FILE" ] && rm -f "$PID_FILE"
    kill -TERM 0 2>/dev/null
    sleep 2
    kill -KILL 0 2>/dev/null
}

trap cleanup HUP TERM INT EXIT

# Duplicate stdin before backgrounding so non-interactive callers keep a live
# input stream while this shell remains resident for signal handling.
exec 3<&0
pi "$@" <&3 &
PI_PID=$!
wait "$PI_PID" 2>/dev/null
EXIT_CODE=$?

trap - HUP TERM INT EXIT
exec 3<&-
[ -n "$PID_FILE" ] && rm -f "$PID_FILE"
exit "$EXIT_CODE"
