#!/usr/bin/env bash
set -euo pipefail

echo "=== 📡 DCS - Device Check-in System Installer ==="

# Prompt until non-empty
while [[ -z "${NC_URL:-}" ]]; do
  read -rp "Enter your NocoDB API URL: " NC_URL
done
while [[ -z "${NC_API_KEY:-}" ]]; do
  read -rp "Enter your NocoDB API Key: " NC_API_KEY
done

INSTALL_DIR="/opt/heartbeat"
SERVICE_FILE="/etc/systemd/system/heartbeat-checkin.service"

sudo mkdir -p "$INSTALL_DIR"

# Write client script with embedded values
sudo tee "$INSTALL_DIR/client_checkin.sh" >/dev/null <<EOF
#!/usr/bin/env bash

NC_URL="$NC_URL"
NC_API_KEY="$NC_API_KEY"
DEVICE_HOSTNAME="\${DEVICE_ID_OVERRIDE:-\$(hostname)}"
INTERVAL_SEC=300

get_public_ip() {
  for svc in "https://ifconfig.me" "https://api.ipify.org" "https://ipinfo.io/ip"; do
    ip="\$(curl -s --max-time 5 "\$svc")"
    if [[ "\$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ || "\$ip" =~ : ]]; then
      echo "\$ip"
      return
    fi
  done
  echo "unknown"
}

while true; do
  TS="\$(TZ='Asia/Manila' date +"%d-%m-%Y %H:%M")"
  PUBIP="\$(get_public_ip)"

  echo "[\$(date)] sending check-in: \$DEVICE_HOSTNAME at \$TS (\$PUBIP)"
  curl -s -X POST "\$NC_URL" \\
    -H "xc-token: \$NC_API_KEY" \\
    -H "Content-Type: application/json" \\
    -d "{\\"hostname\\":\\"\\$DEVICE_HOSTNAME\\",\\"last_seen\\":\\"\\$TS\\",\\"ip\\":\\"\\$PUBIP\\"}" >/dev/null || true

  sleep "\$INTERVAL_SEC"
done
EOF

sudo chmod +x "$INSTALL_DIR/client_checkin.sh"

# Write service
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

sudo systemctl daemon-reload
sudo systemctl enable --now heartbeat-checkin.service

echo "✅ Installed."
echo "👉 Check logs with: journalctl -u heartbeat-checkin.service -f"
