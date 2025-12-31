#!/usr/bin/env bash
set -euo pipefail

echo "=== 📡 DCS - Device Check-in System Installer ==="

# Prompt user if env vars aren't provided
NC_URL="${NC_URL:-}"
NC_API_KEY="${NC_API_KEY:-}"

if [[ -z "$NC_URL" ]]; then
  read -rp "Enter your NocoDB API URL: " NC_URL
fi
if [[ -z "$NC_API_KEY" ]]; then
  read -rsp "Enter your NocoDB API Key: " NC_API_KEY
  echo
fi

if [[ -z "$NC_URL" || -z "$NC_API_KEY" ]]; then
  echo "❌ URL or API key missing, aborting."
  exit 1
fi

INSTALL_DIR="/opt/heartbeat"
CONFIG_DIR="/etc/heartbeat"
ENV_FILE="$CONFIG_DIR/heartbeat.env"
SERVICE_FILE="/etc/systemd/system/heartbeat-checkin.service"
SERVICE_USER="dcs"

if [[ "$EUID" -ne 0 ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "❌ sudo is required to install this service."
    exit 1
  fi
  SUDO="sudo"
else
  SUDO=""
fi

for cmd in curl systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing dependency: $cmd"
    exit 1
  fi
done

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
fi

$SUDO mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
$SUDO chmod 700 "$CONFIG_DIR"

escape_env() {
  local val="$1"
  val="${val//\\/\\\\}"
  val="${val//\"/\\\"}"
  printf '%s' "$val"
}

tmp_env="$(mktemp)"
{
  printf 'NC_URL="%s"\n' "$(escape_env "$NC_URL")"
  printf 'NC_API_KEY="%s"\n' "$(escape_env "$NC_API_KEY")"
} >"$tmp_env"
$SUDO install -m 600 "$tmp_env" "$ENV_FILE"
rm -f "$tmp_env"

# Write client_checkin.sh
$SUDO tee "$INSTALL_DIR/client_checkin.sh" >/dev/null <<'EOF'
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

  # Fallback: local outward-facing IP
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

$SUDO chmod +x "$INSTALL_DIR/client_checkin.sh"

# Write systemd service
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

# Reload systemd and start service
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now heartbeat-checkin.service

echo "✅ DCS client installed and running!"
echo "👉 Check logs with: journalctl -u heartbeat-checkin.service -f"
