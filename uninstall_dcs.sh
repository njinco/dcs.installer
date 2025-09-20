#!/usr/bin/env bash
set -e

echo "=== 🧹 DCS Uninstaller ==="

SERVICE_FILE="/etc/systemd/system/heartbeat-checkin.service"
INSTALL_DIR="/opt/heartbeat"

# Stop and disable service if it exists
if systemctl list-unit-files | grep -q heartbeat-checkin.service; then
  echo "Stopping DCS service..."
  sudo systemctl stop heartbeat-checkin.service || true
  echo "Disabling DCS service..."
  sudo systemctl disable heartbeat-checkin.service || true
fi

# Remove service file
if [ -f "$SERVICE_FILE" ]; then
  echo "Removing service file..."
  sudo rm -f "$SERVICE_FILE"
fi

# Remove client directory
if [ -d "$INSTALL_DIR" ]; then
  echo "Removing client directory..."
  sudo rm -rf "$INSTALL_DIR"
fi

# Reload systemd
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload

echo "✅ DCS client and service fully removed."

