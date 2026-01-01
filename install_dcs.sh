#!/usr/bin/env bash
set -euo pipefail

echo "=== 📡 DCS - Device Check-in System Installer ==="

INSTALL_DIR="/opt/heartbeat"
CONFIG_DIR="/etc/heartbeat"
ENV_FILE="$CONFIG_DIR/heartbeat.env"
SERVICE_FILE="/etc/systemd/system/heartbeat-checkin.service"
SERVICE_USER="dcs"

DOCKER_IMAGE="dcs-checkin:latest"
DOCKER_CONTAINER="dcs-checkin"

SUDO=""
if [[ "$EUID" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ sudo is required to install this service."
    exit 1
  fi
  SUDO="sudo"
fi

prompt_value() {
  local prompt="$1"
  local secret="$2"
  local value=""
  local show_key="${DCS_SHOW_KEY:-}"
  local show_secret="no"

  if [[ "$secret" == "yes" ]]; then
    case "$show_key" in
      1|yes|true|TRUE|Yes|YES) show_secret="yes" ;;
    esac
  fi

  if [[ -t 0 ]]; then
    if [[ "$secret" == "yes" && "$show_secret" != "yes" ]]; then
      read -rsp "$prompt" value
      echo
    else
      read -rp "$prompt" value
    fi
    printf '%s' "$value"
    return 0
  fi

  if [[ -r /dev/tty ]]; then
    if [[ "$secret" == "yes" && "$show_secret" != "yes" ]]; then
      read -rsp "$prompt" value </dev/tty
      echo >/dev/tty
    else
      read -rp "$prompt" value </dev/tty
    fi
    printf '%s' "$value"
    return 0
  fi

  return 1
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing dependency: $cmd"
    exit 1
  fi
}

escape_env() {
  local val="$1"
  val="${val//\\/\\\\}"
  val="${val//\"/\\\"}"
  printf '%s' "$val"
}

write_env_file() {
  local target="$1"
  local include_optional="${2:-no}"
  local sudo_cmd="${3:-$SUDO}"
  local tmp_env=""

  tmp_env="$(mktemp)"
  {
    printf 'NC_URL="%s"\n' "$(escape_env "$NC_URL")"
    printf 'NC_API_KEY="%s"\n' "$(escape_env "$NC_API_KEY")"
    if [[ "$include_optional" == "yes" ]]; then
      if [[ -n "${DEVICE_ID_OVERRIDE:-}" ]]; then
        printf 'DEVICE_ID_OVERRIDE="%s"\n' "$(escape_env "$DEVICE_ID_OVERRIDE")"
      fi
      if [[ -n "${INTERVAL_SEC:-}" ]]; then
        printf 'INTERVAL_SEC="%s"\n' "$(escape_env "$INTERVAL_SEC")"
      fi
    fi
  } >"$tmp_env"

  if [[ -n "$sudo_cmd" ]]; then
    $sudo_cmd install -m 600 "$tmp_env" "$target"
  else
    install -m 600 "$tmp_env" "$target"
  fi
  rm -f "$tmp_env"
}

write_client_script() {
  local target="$1"
  local sudo_cmd="${2:-$SUDO}"

  if [[ -n "$sudo_cmd" ]]; then
    $sudo_cmd tee "$target" >/dev/null <<'EOF'
#!/usr/bin/env bash

NC_URL="${NC_URL:-}"
NC_API_KEY="${NC_API_KEY:-}"
DEVICE_HOSTNAME="${DEVICE_ID_OVERRIDE:-$(hostname)}"
INTERVAL_SEC="${INTERVAL_SEC:-300}"   # 5 minutes

if [[ -z "$NC_URL" || -z "$NC_API_KEY" ]]; then
  echo "NC_URL or NC_API_KEY missing; set them in the environment."
  exit 1
fi

get_public_ip() {
  local ip
  local services=(
    "https://ifconfig.me"
    "https://api.ipify.org"
    "https://ipinfo.io/ip"
    "https://checkip.amazonaws.com"
    "https://icanhazip.com"
  )
  for svc in "${services[@]}"; do
    ip="$(curl -4 -sS --max-time 5 "$svc" | tr -d '[:space:]')"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
  done

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
  fi

  echo "unknown"
}

while true; do
  TS="$(TZ='Asia/Manila' date +"%d-%m-%Y %H:%M")"
  PUBIP="$(get_public_ip)"

  echo "[$(date)] sending check-in: $DEVICE_HOSTNAME at $TS ($PUBIP)"
  RESP="$(curl -sS --max-time 10 -w "\n%{http_code}" -X POST "$NC_URL" \
    -H "xc-token: $NC_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"hostname\":\"$DEVICE_HOSTNAME\",\"last_seen\":\"$TS\",\"ip\":\"$PUBIP\"}")"

  CURL_EXIT=$?
  HTTP_CODE="${RESP##*$'\n'}"
  BODY="${RESP%$'\n'*}"

  if [[ $CURL_EXIT -ne 0 ]]; then
    echo "➡️ curl failed with exit code: $CURL_EXIT"
  else
    if [[ "$HTTP_CODE" =~ ^[0-9]{3}$ && ( "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ) ]]; then
      echo "➡️ non-success HTTP code: $HTTP_CODE"
    else
      echo "➡️ response code: $HTTP_CODE"
    fi
    if [[ -n "$BODY" ]]; then
      echo "➡️ response body: $BODY"
    fi
  fi

  sleep "$INTERVAL_SEC"
done
EOF
    $sudo_cmd chmod +x "$target"
  else
    tee "$target" >/dev/null <<'EOF'
#!/usr/bin/env bash

NC_URL="${NC_URL:-}"
NC_API_KEY="${NC_API_KEY:-}"
DEVICE_HOSTNAME="${DEVICE_ID_OVERRIDE:-$(hostname)}"
INTERVAL_SEC="${INTERVAL_SEC:-300}"   # 5 minutes

if [[ -z "$NC_URL" || -z "$NC_API_KEY" ]]; then
  echo "NC_URL or NC_API_KEY missing; set them in the environment."
  exit 1
fi

get_public_ip() {
  local ip
  local services=(
    "https://ifconfig.me"
    "https://api.ipify.org"
    "https://ipinfo.io/ip"
    "https://checkip.amazonaws.com"
    "https://icanhazip.com"
  )
  for svc in "${services[@]}"; do
    ip="$(curl -4 -sS --max-time 5 "$svc" | tr -d '[:space:]')"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
  done

  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return
    fi
  fi

  echo "unknown"
}

while true; do
  TS="$(TZ='Asia/Manila' date +"%d-%m-%Y %H:%M")"
  PUBIP="$(get_public_ip)"

  echo "[$(date)] sending check-in: $DEVICE_HOSTNAME at $TS ($PUBIP)"
  RESP="$(curl -sS --max-time 10 -w "\n%{http_code}" -X POST "$NC_URL" \
    -H "xc-token: $NC_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"hostname\":\"$DEVICE_HOSTNAME\",\"last_seen\":\"$TS\",\"ip\":\"$PUBIP\"}")"

  CURL_EXIT=$?
  HTTP_CODE="${RESP##*$'\n'}"
  BODY="${RESP%$'\n'*}"

  if [[ $CURL_EXIT -ne 0 ]]; then
    echo "➡️ curl failed with exit code: $CURL_EXIT"
  else
    if [[ "$HTTP_CODE" =~ ^[0-9]{3}$ && ( "$HTTP_CODE" -lt 200 || "$HTTP_CODE" -ge 300 ) ]]; then
      echo "➡️ non-success HTTP code: $HTTP_CODE"
    else
      echo "➡️ response code: $HTTP_CODE"
    fi
    if [[ -n "$BODY" ]]; then
      echo "➡️ response body: $BODY"
    fi
  fi

  sleep "$INTERVAL_SEC"
done
EOF
    chmod +x "$target"
  fi
}

write_dockerfile() {
  local target="$1"
  local sudo_cmd="${2:-$SUDO}"

  if [[ -n "$sudo_cmd" ]]; then
    $sudo_cmd tee "$target" >/dev/null <<'EOF'
FROM alpine:3.20

RUN apk add --no-cache bash curl tzdata iproute2 ca-certificates \
  && addgroup -S dcs \
  && adduser -S -G dcs dcs

WORKDIR /app
COPY client_checkin.sh /app/client_checkin.sh
RUN chmod 755 /app/client_checkin.sh

USER dcs

ENTRYPOINT ["/app/client_checkin.sh"]
EOF
  else
    tee "$target" >/dev/null <<'EOF'
FROM alpine:3.20

RUN apk add --no-cache bash curl tzdata iproute2 ca-certificates \
  && addgroup -S dcs \
  && adduser -S -G dcs dcs

WORKDIR /app
COPY client_checkin.sh /app/client_checkin.sh
RUN chmod 755 /app/client_checkin.sh

USER dcs

ENTRYPOINT ["/app/client_checkin.sh"]
EOF
  fi
}

write_docker_compose() {
  local target="$1"
  local sudo_cmd="${2:-$SUDO}"

  if [[ -n "$sudo_cmd" ]]; then
    $sudo_cmd tee "$target" >/dev/null <<EOF
services:
  dcs-checkin:
    build: .
    image: $DOCKER_IMAGE
    container_name: $DOCKER_CONTAINER
    restart: unless-stopped
    env_file:
      - .env
EOF
  else
    tee "$target" >/dev/null <<EOF
services:
  dcs-checkin:
    build: .
    image: $DOCKER_IMAGE
    container_name: $DOCKER_CONTAINER
    restart: unless-stopped
    env_file:
      - .env
EOF
  fi
}

install_systemd() {
  require_cmd curl
  require_cmd systemctl

  if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
    $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
  fi

  $SUDO mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
  $SUDO chmod 700 "$CONFIG_DIR"

  write_env_file "$ENV_FILE" "no" "$SUDO"
  write_client_script "$INSTALL_DIR/client_checkin.sh" "$SUDO"

  $SUDO tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Heartbeat Check-in (DCS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $INSTALL_DIR/client_checkin.sh
User=$SERVICE_USER
Group=$SERVICE_USER
EnvironmentFile=$ENV_FILE
Restart=on-failure
RestartSec=10
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStartPre=/bin/sleep 10
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
SystemCallArchitectures=native
CapabilityBoundingSet=
AmbientCapabilities=
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK

[Install]
WantedBy=multi-user.target
EOF

  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now heartbeat-checkin.service

  echo "✅ DCS client installed and running (systemd)"
  echo "👉 Check logs with: journalctl -u heartbeat-checkin.service -f"
}

install_docker() {
  require_cmd docker

  local docker_cmd=()
  local compose_cmd=()
  local docker_dir=""
  local env_file=""
  local compose_file=""
  local file_sudo=""

  if docker info >/dev/null 2>&1; then
    docker_cmd=(docker)
  elif [[ -n "$SUDO" ]] && $SUDO docker info >/dev/null 2>&1; then
    docker_cmd=("$SUDO" docker)
  else
    echo "❌ docker is not accessible. Ensure Docker is running and you have permissions."
    exit 1
  fi

  if "${docker_cmd[@]}" compose version >/dev/null 2>&1; then
    compose_cmd=("${docker_cmd[@]}" compose)
  else
    echo "❌ docker compose (v2) is required."
    exit 1
  fi

  if [[ "${docker_cmd[0]}" == "docker" && "$EUID" -ne 0 ]]; then
    docker_dir="${HOME}/.dcs-checkin"
    file_sudo=""
  else
    docker_dir="/opt/heartbeat-docker"
    file_sudo="$SUDO"
  fi

  env_file="$docker_dir/.env"
  compose_file="$docker_dir/docker-compose.yml"

  if [[ -n "$file_sudo" ]]; then
    $file_sudo mkdir -p "$docker_dir"
    $file_sudo chmod 700 "$docker_dir"
  else
    mkdir -p "$docker_dir"
    chmod 700 "$docker_dir"
  fi

  write_client_script "$docker_dir/client_checkin.sh" "$file_sudo"
  write_dockerfile "$docker_dir/Dockerfile" "$file_sudo"
  write_docker_compose "$compose_file" "$file_sudo"
  write_env_file "$env_file" "yes" "$file_sudo"

  "${compose_cmd[@]}" -f "$compose_file" --project-directory "$docker_dir" up -d --build

  echo "✅ DCS container installed and running (docker)"
  echo "👉 Logs: ${docker_cmd[*]} logs -f $DOCKER_CONTAINER"
}

INSTALL_MODE="${INSTALL_MODE:-}"
if [[ -z "$INSTALL_MODE" ]]; then
  if ! INSTALL_MODE="$(prompt_value "Select install mode: [1] systemd [2] docker (default: 1): " "no")"; then
    echo "❌ No TTY available. Set INSTALL_MODE=systemd|docker."
    exit 1
  fi
fi

INSTALL_MODE="$(printf '%s' "$INSTALL_MODE" | tr '[:upper:]' '[:lower:]')"
if [[ -z "$INSTALL_MODE" || "$INSTALL_MODE" == "1" || "$INSTALL_MODE" == "systemd" ]]; then
  INSTALL_MODE="systemd"
elif [[ "$INSTALL_MODE" == "2" || "$INSTALL_MODE" == "docker" ]]; then
  INSTALL_MODE="docker"
else
  echo "❌ Invalid install mode: $INSTALL_MODE"
  exit 1
fi

NC_URL="${NC_URL:-}"
NC_API_KEY="${NC_API_KEY:-}"

if [[ -z "$NC_URL" ]]; then
  if ! NC_URL="$(prompt_value "Enter your NocoDB API URL: " "no")"; then
    echo "❌ No TTY available. Set NC_URL and NC_API_KEY in the environment."
    exit 1
  fi
fi
if [[ -z "$NC_API_KEY" ]]; then
  if ! NC_API_KEY="$(prompt_value "Enter your NocoDB API Key: " "yes")"; then
    echo "❌ No TTY available. Set NC_URL and NC_API_KEY in the environment."
    exit 1
  fi
fi

if [[ -z "$NC_URL" || -z "$NC_API_KEY" ]]; then
  echo "❌ URL or API key missing, aborting."
  exit 1
fi

if [[ "$INSTALL_MODE" == "systemd" ]]; then
  install_systemd
else
  install_docker
fi
