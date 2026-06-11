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

    # Read existing values if present
    existing_hdhrip=$(sed -n 's/^HDHRIP="\(.*\)"/\1/p' /var/www/radio/stream.sh 2>/dev/null)
    existing_icecast_pass=$(sed -n 's/^ICECAST_PASS="\(.*\)"/\1/p' /var/www/radio/stream.sh 2>/dev/null)
    existing_admin_pass=$(sed -n 's|.*<admin-password>\(.*\)</admin-password>.*|\1|p' /etc/icecast2/icecast.xml 2>/dev/null)

    # Prompt for HDHomeRun IP
    read -rp "HDHomeRun IP address${existing_hdhrip:+ [$existing_hdhrip]}: " input_hdhrip
    hdhrip="${input_hdhrip:-$existing_hdhrip}"

    if [[ ! "$hdhrip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "Invalid IP address." >&2
        exit 1
    fi

    # Keep existing passwords or generate new ones
    if [ -n "$existing_icecast_pass" ]; then
        ICECAST_PASS="$existing_icecast_pass"
        ICECAST_ADMIN_PASS="$existing_admin_pass"
    else
        ICECAST_PASS=$(openssl rand -hex 16)
        ICECAST_ADMIN_PASS=$(openssl rand -hex 16)
    fi

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
    curl -fsSL "$REPO_RAW/transcoder/radio-cleanup.sh" > /usr/local/bin/radio-cleanup.sh
    chmod +x /usr/local/bin/radio-cleanup.sh

    echo "Installing nginx config..."
    curl -fsSL "$REPO_RAW/transcoder/radio.nginx" > /etc/nginx/sites-available/radio
    ln -sf /etc/nginx/sites-available/radio /etc/nginx/sites-enabled/radio

    echo "Installing cleanup timer..."
    curl -fsSL "$REPO_RAW/transcoder/radio-cleanup.service" > "$SERVICE_DIR/radio-cleanup.service"
    curl -fsSL "$REPO_RAW/transcoder/radio-cleanup.timer" > "$SERVICE_DIR/radio-cleanup.timer"

    systemctl daemon-reload
    systemctl stop icecast2 2>/dev/null || true
    systemctl disable icecast2 2>/dev/null || true
    systemctl enable --now icecast2
    systemctl reload nginx
    systemctl stop radio-cleanup.timer 2>/dev/null || true
    systemctl disable radio-cleanup.timer 2>/dev/null || true
    systemctl enable --now radio-cleanup.timer

    echo "Done. Transcoder is running."

else

    # Read existing values if present
    existing_mode=$(sed -n 's/^mode="\(.*\)"/\1/p' "$INSTALL_DIR/radio.sh" 2>/dev/null)
    existing_radioip=$(sed -n 's/^radioip="\(.*\)"/\1/p' "$INSTALL_DIR/radio.sh" 2>/dev/null)
    existing_hdhrip=$(sed -n 's/^hdhrip="\(.*\)"/\1/p' "$INSTALL_DIR/radio.sh" 2>/dev/null)
    existing_device=$(sed -n 's/.*name = "\(.*\)";/\1/p' /etc/shairport-sync.conf 2>/dev/null | head -1)

    if [ "$existing_mode" = "mpg123" ]; then
        mode_default="1"
    elif [ "$existing_mode" = "mpv" ]; then
        mode_default="2"
    else
        mode_default=""
    fi

    read -rp "Player mode - (1) mpg123 via transcoder, (2) mpv direct${mode_default:+ [$mode_default]}: " input_mode
    mode_choice="${input_mode:-$mode_default}"

    if [ "$mode_choice" = "1" ]; then

        read -rp "Transcoder IP address${existing_radioip:+ [$existing_radioip]}: " input_radioip
        radioip="${input_radioip:-$existing_radioip}"

        if [[ ! "$radioip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "Invalid IP address." >&2
            exit 1
        fi

        apt-get update

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

        read -rp "HDHomeRun IP address${existing_hdhrip:+ [$existing_hdhrip]}: " input_hdhrip
        hdhrip="${input_hdhrip:-$existing_hdhrip}"

        if [[ ! "$hdhrip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "Invalid IP address." >&2
            exit 1
        fi

        if ! command -v mpv &>/dev/null; then
            echo "Installing mpv..."
            apt-get install -y mpv
        fi

        if ! command -v inotifywait &>/dev/null; then
            echo "Installing inotify-tools..."
            apt-get install -y inotify-tools
        fi

        SED_ARGS=(-e "s/mode=\"[^\"]*\"/mode=\"mpv\"/"
                  -e "s/hdhrip=\"[^\"]*\"/hdhrip=\"$hdhrip\"/")

    else
        echo "Invalid choice." >&2
        exit 1
    fi

    systemctl stop radio.service 2>/dev/null || true
    systemctl stop radio-watcher.service 2>/dev/null || true
    systemctl disable radio.service 2>/dev/null || true
    systemctl disable radio-watcher.service 2>/dev/null || true

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

    echo "Installing radio-watcher.service..."
    curl -fsSL "$REPO_RAW/openframe/radio-watcher.sh" > "$INSTALL_DIR/radio-watcher.sh"
    chmod +x "$INSTALL_DIR/radio-watcher.sh"
    curl -fsSL "$REPO_RAW/openframe/radio-watcher.service" \
        | sed "s|ExecStart=.*|ExecStart=$INSTALL_DIR/radio-watcher.sh|" \
        > "$SERVICE_DIR/radio-watcher.service"

    echo "Installing /usr/local/bin/radio..."
    ln -sf "$INSTALL_DIR/radio.sh" /usr/local/bin/radio

    echo "Enabling and starting services..."
    systemctl daemon-reload
    systemctl enable radio-watcher.service
    systemctl start radio-watcher.service
    systemctl enable radio.service
    systemctl start radio.service

    if [ -n "$existing_device" ]; then
        read -rp "Install shairport-sync (AirPlay)? [Y/n] " install_shairport
        install_shairport="${install_shairport:-y}"
    else
        read -rp "Install shairport-sync (AirPlay)? [y/N] " install_shairport
    fi

    if [[ "$install_shairport" =~ ^[Yy]$ ]]; then

        read -rp "AirPlay device name${existing_device:+ [$existing_device]}: " input_device
        device_name="${input_device:-$existing_device}"

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
