# openframe-radio

Streams radio from an [HDHomeRun](https://www.silicondust.com/) network tuner to an [OpenFrame](https://github.com/openframe) device. Two player modes are supported:

- **mpg123 via transcoder** — a Raspberry Pi pulls the stream from the HDHomeRun, transcodes it to MP3 via ffmpeg, and distributes it via Icecast. Multiple OpenFrames on the same channel share a single transcode and a single tuner. Streams start on demand and stop automatically when the last listener disconnects. Recommended for OpenFrame's Atom Z520, which can't easily demux MPEG-TS directly.
- **mplayer direct** — OpenFrame streams directly from the HDHomeRun using mplayer. Simpler setup, no Pi required.

```
mpg123 mode:  HDHomeRun → ffmpeg → Icecast ─┬→ OpenFrame
                                            ├→ OpenFrame
                                            └→ OpenFrame
mplayer mode: HDHomeRun → OpenFrame
```

## Requirements

**Raspberry Pi (transcoder, mpg123 mode only)**
- `nginx`
- `fcgiwrap`
- `ffmpeg`
- `icecast2`

**OpenFrame**
- `mpg123` (mpg123 mode) or `mplayer` (mplayer mode)
- `inotifywait` (from `inotify-tools`)
- `systemd`
- `shairport-sync` *(optional — AirPlay receiver; pauses/resumes radio automatically)*

Dependencies are installed automatically by the installer where possible.

## Installation

### Raspberry Pi (transcoder)

Run first. You will be prompted for your HDHomeRun's IP address.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/birdslikewires/openframe-radio/main/install.sh)" -- --transcoder
```

### OpenFrame

Run after the transcoder is up. You will be prompted for the Pi's IP address.

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/birdslikewires/openframe-radio/main/install.sh)"
```

## Usage

```bash
radio play             # Start or resume playback
radio pause            # Pause playback
radio 707              # Switch to channel 707
```

## Configuration

**OpenFrame** — edit `/opt/openframe-radio/radio.sh`:

| Variable   | Default              | Description                          |
|------------|----------------------|--------------------------------------|
| `mode`     | `mpg123`             | Player mode (`mpg123` or `mplayer`)  |
| `radioip`  | *(set by installer)* | Transcoder IP address (mpg123 mode)  |
| `hdhrip`   | *(set by installer)* | HDHomeRun IP address (mplayer mode)  |
| `channel`  | `707`                | Default channel on startup           |
| `volume`   | `50`                 | Playback volume (0–100)              |
| `tmploc`   | `/tmp/radio`         | Directory used for state files       |

**Transcoder** — edit `/var/www/radio/stream.sh`:

| Variable     | Default              | Description          |
|--------------|----------------------|----------------------|
| `HDHRIP`     | *(set by installer)* | HDHomeRun IP address |
| `ICECAST_PASS` | *(set by installer)* | Icecast source password |
