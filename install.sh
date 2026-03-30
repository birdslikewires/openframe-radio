#!/usr/bin/env bash

## install.sh — installs radio.sh and radio.service for OpenFrame

set -e

REPO_RAW="https://raw.githubusercontent.com/birdslikewires/openframe-radio/main"
INSTALL_DIR="/opt/openframe-radio"
SERVICE_DIR="/etc/systemd/system"

# Prompt for HDHomeRun IP
read -rp "HDHomeRun IP address: " hdhrip

if [[ ! "$hdhrip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "Invalid IP address." >&2
    exit 1
fi

# Install radio.sh with the provided IP substituted in
echo "Installing radio.sh..."
mkdir -p "$INSTALL_DIR"
curl -fsSL "$REPO_RAW/radio.sh" \
    | sed "s/hdhrip=\"[^\"]*\"/hdhrip=\"$hdhrip\"/" \
    > "$INSTALL_DIR/radio.sh"
chmod +x "$INSTALL_DIR/radio.sh"

# Install radio.service with the updated ExecStart path
echo "Installing radio.service..."
curl -fsSL "$REPO_RAW/radio.service" \
    | sed "s|ExecStart=.*|ExecStart=$INSTALL_DIR/radio.sh|" \
    > "$SERVICE_DIR/radio.service"

# Enable and start
echo "Enabling and starting radio.service..."
systemctl daemon-reload
systemctl enable radio.service
systemctl start radio.service

echo "Done. Radio service is running."
