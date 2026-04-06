#!/usr/bin/env bash

## radio-watcher.sh
##  Watches the channel file and starts, stops or restarts radio.service.

tmploc="/tmp/radio"

mkdir -p "$tmploc"
[ -f "$tmploc/channel" ] || echo "707" > "$tmploc/channel"

while inotifywait -e close_write "$tmploc/channel" 2>/dev/null; do
	channel=$(cat "$tmploc/channel" 2>/dev/null)
	if [ "$channel" = "0" ]; then
		systemctl stop radio.service
	else
		systemctl restart radio.service
	fi
done
