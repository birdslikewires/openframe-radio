# openframe-radio

Streams radio from an [HDHomeRun](https://www.silicondust.com/) network tuner and keeps it running reliably as a systemd service. Designed for use with [OpenFrame](https://github.com/openframe).

## How it works

`radio.sh` connects to an HDHomeRun device and streams a channel via `mplayer`. It monitors the systemd journal for common failure conditions (cache empty, network errors, soundcard resets) and automatically restarts the service if anything goes wrong.

Channel changes are handled via `inotifywait` — writing a new channel number to `/tmp/radio/channel` triggers a seamless service restart with the updated channel.

## Requirements

- `mplayer`
- `inotifywait` (from `inotify-tools`)
- `systemd`
- An HDHomeRun network tuner on your LAN

## Installation

Run the installer as root. It will prompt for your HDHomeRun's IP address, then download, configure, and start the service automatically:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/birdslikewires/openframe-radio/main/install.sh)"
```

## Usage

```bash
radio.sh play          # Start or resume playback
radio.sh pause         # Pause playback
radio.sh 707           # Switch to channel 707
```

## Configuration

To change defaults, edit `/opt/openframe-radio/radio.sh`:

| Variable  | Default      | Description                      |
|-----------|--------------|----------------------------------|
| `hdhrip`  | *(set by installer)* | HDHomeRun IP address    |
| `channel` | `707`        | Default channel on startup       |
| `tmploc`  | `/tmp/radio` | Directory used for state files   |
