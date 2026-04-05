#!/usr/bin/env bash

## install.sh — installs openframe-radio on OpenFrame or Raspberry Pi transcoder

set -e

REPO_RAW="https://raw.githubusercontent.com/birdslikewires/openframe-radio/main"
INSTALL_DIR="/opt/openframe-radio"
SERVICE_DIR="/etc/systemd/system"
TRANSCODER=false

for arg in "$@"; do
    case $arg in
        --transcoder) TRANSCODER=true ;;
    esac
done

if [ "$TRANSCODER" = true ]; then

    # Prompt for HDHomeRun IP
    read -rp "HDHomeRun IP address: " hdhrip

    if [[ ! "$hdhrip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Invalid IP address." >&2
        exit 1
    fi

    ICECAST_PASS=$(openssl rand -hex 16)
    ICECAST_ADMIN_PASS=$(openssl rand -hex 16)

    echo "Installing dependencies..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y nginx fcgiwrap ffmpeg icecast2

    echo "Installing Icecast config..."
    curl -fsSL "$REPO_RAW/transcoder/icecast.xml" \
        | sed -e "s/ICECAST_SOURCE_PASS/$ICECAST_PASS/g" \
              -e "s/ICECAST_ADMIN_PASS/$ICECAST_ADMIN_PASS/g" \
        > /etc/icecast2/icecast.xml

    echo "Installing stream.sh..."
    mkdir -p /var/www/radio
    curl -fsSL "$REPO_RAW/transcoder/stream.sh" \
        | sed -e "s/HDHRIP_PLACEHOLDER/$hdhrip/" \
              -e "s/ICECAST_PASS_PLACEHOLDER/$ICECAST_PASS/" \
        > /var/www/radio/stream.sh
    chmod +x /var/www/radio/stream.sh

    echo "Installing cleanup script..."
    curl -fsSL "$REPO_RAW/transcoder/cleanup.sh" > /usr/local/bin/radio-cleanup.sh
    chmod +x /usr/local/bin/radio-cleanup.sh

    echo "Installing nginx config..."
    curl -fsSL "$REPO_RAW/transcoder/radio" > /etc/nginx/sites-available/radio
    ln -sf /etc/nginx/sites-available/radio /etc/nginx/sites-enabled/radio

    echo "Installing cleanup timer..."
    curl -fsSL "$REPO_RAW/transcoder/radio-cleanup.service" > "$SERVICE_DIR/radio-cleanup.service"
    curl -fsSL "$REPO_RAW/transcoder/radio-cleanup.timer" > "$SERVICE_DIR/radio-cleanup.timer"

    systemctl daemon-reload
    systemctl enable --now icecast2
    systemctl reload nginx
    systemctl enable --now radio-cleanup.timer

    echo "Done. Transcoder is running."

else

    read -rp "Player mode - (1) mpg123 via transcoder, (2) mplayer direct: " mode_choice

    if [ "$mode_choice" = "1" ]; then

        read -rp "Transcoder IP address: " radioip

        if [[ ! "$radioip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "Invalid IP address." >&2
            exit 1
        fi

        if ! command -v mpg123 &>/dev/null; then
            echo "Installing mpg123..."
            apt-get install -y mpg123
        fi

        if ! command -v inotifywait &>/dev/null; then
            echo "Installing inotify-tools..."
            apt-get install -y inotify-tools
        fi

        SED_ARGS=(-e "s/mode=\"[^\"]*\"/mode=\"mpg123\"/"
                  -e "s/radioip=\"[^\"]*\"/radioip=\"$radioip\"/")

    elif [ "$mode_choice" = "2" ]; then

        read -rp "HDHomeRun IP address: " hdhrip

        if [[ ! "$hdhrip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "Invalid IP address." >&2
            exit 1
        fi

        if ! command -v mplayer &>/dev/null; then
            echo "Installing mplayer..."
            of-install mplayer
        fi

        if ! command -v inotifywait &>/dev/null; then
            echo "Installing inotify-tools..."
            apt-get install -y inotify-tools
        fi

        SED_ARGS=(-e "s/mode=\"[^\"]*\"/mode=\"mplayer\"/"
                  -e "s/hdhrip=\"[^\"]*\"/hdhrip=\"$hdhrip\"/")

    else
        echo "Invalid choice." >&2
        exit 1
    fi

    echo "Installing radio.sh..."
    mkdir -p "$INSTALL_DIR"
    curl -fsSL "$REPO_RAW/openframe/radio.sh" \
        | sed "${SED_ARGS[@]}" \
        > "$INSTALL_DIR/radio.sh"
    chmod +x "$INSTALL_DIR/radio.sh"

    echo "Installing radio.service..."
    curl -fsSL "$REPO_RAW/openframe/radio.service" \
        | sed "s|ExecStart=.*|ExecStart=$INSTALL_DIR/radio.sh|" \
        > "$SERVICE_DIR/radio.service"

    echo "Installing /usr/local/bin/radio..."
    ln -sf "$INSTALL_DIR/radio.sh" /usr/local/bin/radio

    echo "Enabling and starting radio.service..."
    systemctl daemon-reload
    systemctl enable radio.service
    systemctl start radio.service

    read -rp "Install shairport-sync (AirPlay)? [y/N] " install_shairport
    if [[ "$install_shairport" =~ ^[Yy]$ ]]; then

        read -rp "AirPlay device name: " device_name

        if ! command -v shairport-sync &>/dev/null; then
            echo "Installing shairport-sync..."
            apt-get install -y shairport-sync
        fi

        echo "Configuring shairport-sync..."
        cat > /etc/shairport-sync.conf << EOF
general =
{
        name = "$device_name";
        ignore_volume_control = "yes";
};

sessioncontrol =
{
        run_this_before_entering_active_state = "/usr/local/bin/radio pause";
        run_this_after_exiting_active_state = "/usr/local/bin/radio play";
        active_state_timeout = 10.0;
};
EOF

        systemctl enable shairport-sync
        systemctl restart shairport-sync

    fi

    echo "Done. Radio service is running."

fi
