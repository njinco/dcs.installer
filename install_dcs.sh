#!/usr/bin/env bash
set -e

echo "=== 📡 DCS - Device Check-in System Installer ==="

# Prompt user
read -rp "Enter your NocoDB API URL: " NC_URL
read -rp "Enter your NocoDB API Key: " NC_API_KEY

if [[ -z "$NC_URL" || -z "$NC_API_KEY" ]]; then
  echo "❌ URL or API key missing, aborting."
  exit 1
fi

INSTALL_DIR="/opt/heartbeat"
SERVICE_FILE="/etc/systemd/system/heartbeat-checkin.service"

sudo mkdir -p "$INSTALL_DIR"

# Write client_checkin.sh
sudo tee "$INSTALL_DIR/client_checkin.sh" >/dev/null <<EOF
#!/usr/bin/env bash

NC_URL="$NC_URL"
NC_API_KEY="$NC_API_KEY"
DEVICE_HOSTNAME="\${DEVICE_ID_OVERRIDE:-\$(hostname)}"
INTERVAL_SEC=300   # 5 minutes

get_public_ip() {
  for svc in \\
    "https://ifconfig.me" \\
    "https://api.ipify.org" \\
    "https://ipinfo.io/ip" \\
    "https://checkip.amazonaws.com" \\
    "https://icanhazip.com"; do
    ip="\$(curl -4 -s --max-time 5 "\$svc" | tr -d '[:space:]')"
    if [[ -n "\$ip" ]]; then
      echo "\$ip"
      return
    fi
  done
  # Fallback: local outward-facing IP
  ip route get 1.1.1.1 2>/dev/null | awk '{print \$7; exit}' || echo "unknown"
}

while true; do
  TS="\$(TZ='Asia/Manila' date +"%d-%m-%Y %H:%M")"
  PUBIP="\$(get_public_ip)"

  echo "[\$(date)] sending check-in: \$DEVICE_HOSTNAME at \$TS (\$PUBIP)"
  curl -s -X POST "\$NC_URL" \\
    -H "xc-token: \$NC_API_KEY" \\
    -H "Content-Type: application/json" \\
    -d "{
      \\\"hostname\\\":\\\"\$DEVICE_HOSTNAME\\\",
      \\\"last_seen\\\":\\\"\$TS\\\",
      \\\"ip\\\":\\\"\$PUBIP\\\"
    }" >/dev/null || true

  sleep "\$INTERVAL_SEC"
done
EOF

sudo chmod +x "$INSTALL_DIR/client_checkin.sh"

# Write systemd service
sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Heartbeat Check-in (DCS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env bash $INSTALL_DIR/client_checkin.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start service
sudo systemctl daemon-reload
sudo systemctl enable --now heartbeat-checkin.service

echo "✅ DCS client installed and running!"
echo "👉 Check logs with: journalctl -u heartbeat-checkin.service -f"
