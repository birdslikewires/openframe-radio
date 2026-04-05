#!/bin/bash

STREAMDIR="/tmp/radio-streams"

[ -d "$STREAMDIR" ] || exit 0
STATUS=$(curl -sf "http://localhost:8000/status-json.xsl") || exit 0

for pidfile in "$STREAMDIR"/*.pid; do
    [ -f "$pidfile" ] || continue

    CHANNEL=$(basename "$pidfile" .pid)
    PID=$(cat "$pidfile")

    # Clean up stale PID files
    if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$pidfile"
        continue
    fi

    # Stop the stream if nobody is listening
    LISTENERS=$(echo "$STATUS" | python3 -c "
import sys,json
d=json.load(sys.stdin)
s=d.get('icestats',{}).get('source',[])
if isinstance(s,dict): s=[s]
ch='/$CHANNEL'
print(next((x.get('listeners',0) for x in s if x.get('listenurl','').endswith(ch)),0))
")

    if [ "${LISTENERS:-0}" -eq 0 ]; then
        kill "$PID" 2>/dev/null
        rm -f "$pidfile"
    fi
done
