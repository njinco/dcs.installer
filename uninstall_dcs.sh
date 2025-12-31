#!/usr/bin/env bash
set -euo pipefail

echo "=== 🧹 DCS Uninstaller ==="

SERVICE_FILE="/etc/systemd/system/heartbeat-checkin.service"
INSTALL_DIR="/opt/heartbeat"
CONFIG_DIR="/etc/heartbeat"
ENV_FILE="$CONFIG_DIR/heartbeat.env"
SERVICE_USER="dcs"

if [[ "$EUID" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ sudo is required to uninstall this service."
    exit 1
  fi
  SUDO="sudo"
else
  SUDO=""
fi

# Stop and disable service if it exists
if command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files | grep -q heartbeat-checkin.service; then
    echo "Stopping DCS service..."
    $SUDO systemctl stop heartbeat-checkin.service || true
    echo "Disabling DCS service..."
    $SUDO systemctl disable heartbeat-checkin.service || true
  fi
fi

# Remove service file
if [ -f "$SERVICE_FILE" ]; then
  echo "Removing service file..."
  $SUDO rm -f "$SERVICE_FILE"
fi

# Remove env file and config directory
if [ -f "$ENV_FILE" ]; then
  echo "Removing config..."
  $SUDO rm -f "$ENV_FILE"
fi
if [ -d "$CONFIG_DIR" ]; then
  $SUDO rmdir "$CONFIG_DIR" 2>/dev/null || $SUDO rm -rf "$CONFIG_DIR"
fi

# Remove client directory
if [ -d "$INSTALL_DIR" ]; then
  echo "Removing client directory..."
  $SUDO rm -rf "$INSTALL_DIR"
fi

# Reload systemd
if command -v systemctl >/dev/null 2>&1; then
  echo "Reloading systemd daemon..."
  $SUDO systemctl daemon-reload
fi

echo "✅ DCS client and service fully removed."
echo "👉 User '$SERVICE_USER' was not removed. Remove it manually if desired."
