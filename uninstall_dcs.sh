#!/usr/bin/env bash
set -euo pipefail

echo "=== 🧹 DCS Uninstaller ==="

SERVICE_FILE="/etc/systemd/system/heartbeat-checkin.service"
INSTALL_DIR="/opt/heartbeat"
CONFIG_DIR="/etc/heartbeat"
ENV_FILE="$CONFIG_DIR/heartbeat.env"
SERVICE_USER="dcs"

DOCKER_IMAGE="dcs-checkin:latest"
DOCKER_CONTAINER="dcs-checkin"

SUDO=""
if [[ "$EUID" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ sudo is required to uninstall this service."
    exit 1
  fi
  SUDO="sudo"
fi

docker_cmd=()
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    docker_cmd=(docker)
  elif [[ -n "$SUDO" ]] && $SUDO docker info >/dev/null 2>&1; then
    docker_cmd=("$SUDO" docker)
  fi
fi

docker_dirs=("/opt/heartbeat-docker")
if [[ -n "${SUDO_USER:-}" ]]; then
  sudo_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  if [[ -n "$sudo_home" ]]; then
    docker_dirs+=("$sudo_home/.dcs-checkin")
  fi
fi
docker_dirs+=("$HOME/.dcs-checkin")

# Stop and disable systemd service if it exists
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

# Stop and remove Docker container/image if present
if [[ ${#docker_cmd[@]} -gt 0 ]]; then
  if "${docker_cmd[@]}" compose version >/dev/null 2>&1; then
    for dir in "${docker_dirs[@]}"; do
      if [ -f "$dir/docker-compose.yml" ]; then
        echo "Stopping Docker compose in $dir..."
        "${docker_cmd[@]}" compose -f "$dir/docker-compose.yml" --project-directory "$dir" \
          down --rmi local --remove-orphans || true
      fi
    done
  fi

  if "${docker_cmd[@]}" ps -a --format '{{.Names}}' | grep -qx "$DOCKER_CONTAINER"; then
    echo "Removing Docker container $DOCKER_CONTAINER..."
    "${docker_cmd[@]}" rm -f "$DOCKER_CONTAINER" || true
  fi

  "${docker_cmd[@]}" image rm -f "$DOCKER_IMAGE" >/dev/null 2>&1 || true
fi

# Remove Docker install directories
for dir in "${docker_dirs[@]}"; do
  if [ -d "$dir" ]; then
    echo "Removing Docker directory $dir..."
    $SUDO rm -rf "$dir"
  fi
done

# Reload systemd
if command -v systemctl >/dev/null 2>&1; then
  echo "Reloading systemd daemon..."
  $SUDO systemctl daemon-reload
fi

# Remove service user
if id -u "$SERVICE_USER" >/dev/null 2>&1; then
  echo "Removing user '$SERVICE_USER'..."
  $SUDO userdel -r "$SERVICE_USER" >/dev/null 2>&1 || true
fi

# Remove 'rpi' user (dangerous)
if id -u rpi >/dev/null 2>&1; then
  if [[ "${SUDO_USER:-$(id -un)}" == "rpi" ]]; then
    echo "WARNING: Removing user 'rpi' while logged in as rpi may interrupt your session."
  fi
  if [[ "$PWD" == "/home/rpi"* ]]; then
    cd /
  fi
  echo "Removing user 'rpi'..."
  if ! $SUDO userdel -r rpi >/dev/null 2>&1; then
    echo "WARNING: Failed to remove user 'rpi'. Ensure no active sessions and try again."
  fi
fi

echo "✅ DCS uninstall completed."
