#!/usr/bin/env bash

## radio.sh v1.14 (6th April 2026)
##  Streams radio to OpenFrame and restarts if there's a problem.
##  Use the accompanying radio.service and radio-watcher.service files.

mode="mpg123"
radioip=""
hdhrip=""
channel="707"
volume="50"
tmploc="/tmp/radio"

# Set up our temporary location with access for any audio group member.
if [ ! -d "$tmploc" ]; then
	mkdir -p "$tmploc"
	chown :audio "$tmploc"
	chmod 777 "$tmploc"
	chmod g+s "$tmploc"
	umask 002
fi

# Handle play, pause and channel selection.
if [ "$1" == "pause" ]; then
	[ -f "$tmploc/channel" ] && cp "$tmploc/channel" "$tmploc/paused"
	echo 0 > "$tmploc/channel"
	exit 0
elif [ "$1" == "play" ]; then
	if [ -f "$tmploc/paused" ]; then
		cp "$tmploc/paused" "$tmploc/channel"
		rm "$tmploc/paused"
	else
		echo "$channel" > "$tmploc/channel"
	fi
	exit 0
elif [[ "$1" =~ ^[+-]?[0-9]+$ ]]; then
	echo "$1" > "$tmploc/channel"
	exit 0
elif [ "$1" != "" ]; then
	exit 1
fi

# Keep an eye on our restart count.
if [ -f "$tmploc/restarts" ]; then
	restarts=$(cat "$tmploc/restarts")
	(( restarts++ ))
	echo "$restarts" > "$tmploc/restarts"
else
	echo 0 > "$tmploc/restarts"
fi

# Set the channel from the file if present.
if [ -f "$tmploc/channel" ]; then
	channel=$(cat "$tmploc/channel")
else
	echo "$channel" > "$tmploc/channel"
fi

if [ "$mode" = "mpg123" ]; then
	exec env DISPLAY= mpg123 -q --buffer 1024 -f $(( 32768 * volume / 100 )) "http://$radioip:5111/$channel"
else
	exec mplayer -novideo -cache 512 -cache-min 80 -softvol -volume "$volume" "http://$hdhrip:5004/auto/v$channel"
fi
