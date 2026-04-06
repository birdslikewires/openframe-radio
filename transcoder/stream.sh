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

free_tuners() {
    curl -sf "http://$HDHRIP/tuners.html" | grep -c "not in use"
}

channel_name() {
    curl -sf "http://$HDHRIP/lineup.json" \
        | jq -r --arg ch "$CHANNEL" '.[] | select(.GuideNumber == $ch) | .GuideName' 2>/dev/null
}

icecast_has_mount() {
    curl -sf "http://localhost:8000/status-json.xsl" | python3 -c "
import sys,json
d=json.load(sys.stdin)
s=d.get('icestats',{}).get('source',[])
if isinstance(s,dict): s=[s]
sys.exit(0 if any(x.get('listenurl','').endswith('/$CHANNEL') for x in s) else 1)
"
}

# Fail fast if all tuners are busy and no mount exists for this channel
if ! icecast_has_mount && [ "$(free_tuners)" -eq 0 ]; then
    printf "Status: 503 Service Unavailable\r\nContent-Type: text/plain\r\n\r\nNo tuner available.\n"
    exit 1
fi

(
    flock -x 9

    if ! icecast_has_mount; then
        [[ "$CHANNEL" -ge 700 ]] && BUFFER=24000 || BUFFER=48000
        STREAM_NAME=$(channel_name)
        ICECAST_URL="icecast://source:$ICECAST_PASS@localhost:8000/$CHANNEL"
        [ -n "$STREAM_NAME" ] && ICECAST_URL+="?ice_name=${STREAM_NAME// /+}"

        ffmpeg -hide_banner -loglevel error \
            -probesize "$BUFFER" \
            -i "http://$HDHRIP:5004/auto/v$CHANNEL" \
            -vn -acodec libmp3lame -b:a 128k -f mp3 \
            "$ICECAST_URL" \
            </dev/null >/dev/null 2>&1 9>&- &

        echo $! > "$STREAMDIR/$CHANNEL.pid"

        # Wait up to 10s for the mount to appear on Icecast
        for i in $(seq 1 20); do
            sleep 0.5
            icecast_has_mount && break
        done
    fi

) 9>"$STREAMDIR/$CHANNEL.lock"

# If the mount still isn't up, ffmpeg failed (e.g. no tuner available)
if ! icecast_has_mount; then
    PID=$(cat "$STREAMDIR/$CHANNEL.pid" 2>/dev/null)
    [ -n "$PID" ] && kill "$PID" 2>/dev/null
    rm -f "$STREAMDIR/$CHANNEL.pid"
    printf "Status: 503 Service Unavailable\r\nContent-Type: text/plain\r\n\r\nNo tuner available.\n"
    exit 1
fi

HOST=$(echo "$HTTP_HOST" | cut -d: -f1)
printf "Status: 302 Found\r\nLocation: http://%s:5111/stream/%s\r\n\r\n" "$HOST" "$CHANNEL"
