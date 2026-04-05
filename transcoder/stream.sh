#!/bin/bash

CHANNEL=$(echo "$REQUEST_URI" | sed -E 's/^\///')
HDHRIP="HDHRIP_PLACEHOLDER"
ICECAST_PASS="ICECAST_PASS_PLACEHOLDER"
STREAMDIR="/tmp/radio-streams"

if [[ -z "$CHANNEL" || ! "$CHANNEL" =~ ^[0-9]+$ ]]; then
    printf "Status: 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nInvalid channel.\n"
    exit 1
fi

mkdir -p "$STREAMDIR"

icecast_has_mount() {
    curl -sf "http://localhost:8000/status-json.xsl" | python3 -c "
import sys,json
d=json.load(sys.stdin)
s=d.get('icestats',{}).get('source',[])
if isinstance(s,dict): s=[s]
sys.exit(0 if any(x.get('listenurl','').endswith('/$CHANNEL') for x in s) else 1)
"
}

(
    flock -x 9

    if ! icecast_has_mount; then
        [[ "$CHANNEL" -ge 700 ]] && BUFFER=24000 || BUFFER=48000

        ffmpeg -hide_banner -loglevel error \
            -probesize "$BUFFER" \
            -i "http://$HDHRIP:5004/auto/v$CHANNEL" \
            -vn -acodec libmp3lame -f mp3 \
            "icecast://source:$ICECAST_PASS@localhost:8000/$CHANNEL" \
            </dev/null >/dev/null 2>&1 &

        echo $! > "$STREAMDIR/$CHANNEL.pid"

        # Wait up to 10s for the mount to appear on Icecast
        for i in $(seq 1 20); do
            sleep 0.5
            icecast_has_mount && break
        done
    fi

) 9>"$STREAMDIR/$CHANNEL.lock"

HOST=$(echo "$HTTP_HOST" | cut -d: -f1)
printf "Status: 302 Found\r\nLocation: http://%s:5111/stream/%s\r\n\r\n" "$HOST" "$CHANNEL"
