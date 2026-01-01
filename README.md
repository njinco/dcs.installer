# DCS – Device Check-in System (Installer)

DCS is a lightweight heartbeat client that lets remote devices **check in** to a central NocoDB database every 5 minutes.  
Instead of pinging devices, you simply check when they last reported.

## Requirements

NocoDB table schema:

| Column     | Type             |
|------------|------------------|
| hostname   | Single Line Text |
| last_seen  | Single Line Text (format: `DD-MM-YYYY HH:mm`) |
| ip         | Single Line Text |

`last_seen` **must be text**, not date/time, to avoid format errors.

Platform requirements:
- Linux: `systemd`, `curl`
- Docker: Docker Engine + Docker Compose v2
- Windows: `curl`, PowerShell (preferred) or WMIC (fallback)

## Linux (systemd) Install

Run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/username/<your-repo>/main/install_dcs.sh | bash
```

You will be prompted for:
- **NocoDB API URL**  
  Example:  
  ```
  https://<your-nocodb-domain>/api/v1/db/data/v1/<project>/<table>
  ```
- **NocoDB API Key**

By default, API key input is hidden. To show it during install:
```bash
DCS_SHOW_KEY=1 curl -fsSL https://raw.githubusercontent.com/username/<your-repo>/main/install_dcs.sh | bash
```

Non-interactive install:
```bash
NC_URL="https://..." NC_API_KEY="..." \
  curl -fsSL https://raw.githubusercontent.com/username/<your-repo>/main/install_dcs.sh | bash
```

The installer will:
- Copy client → `/opt/heartbeat/client_checkin.sh`
- Create env file → `/etc/heartbeat/heartbeat.env` (root-only)
- Create systemd unit → `/etc/systemd/system/heartbeat-checkin.service`
- Create `dcs` system user
- Enable + start service

Quick verify:
1. `systemctl status heartbeat-checkin.service`
2. `journalctl -u heartbeat-checkin.service -f`

If you need to change the URL/key later, edit `/etc/heartbeat/heartbeat.env` and restart the service.

### Service Management

Check status:
```bash
systemctl status heartbeat-checkin.service
```

Restart service:
```bash
sudo systemctl restart heartbeat-checkin.service
```

Follow logs live (journald):
```bash
journalctl -u heartbeat-checkin.service -f
```

### Configuration

Edit `/etc/heartbeat/heartbeat.env` as root:

```bash
NC_URL="https://<your-nocodb-domain>/api/v1/db/data/v1/<project>/<table>"
NC_API_KEY="your_api_key"
# Optional overrides
# DEVICE_ID_OVERRIDE="custom-device-id"
# INTERVAL_SEC=300
```

After changes:
```bash
sudo systemctl restart heartbeat-checkin.service
```

### Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/username/<your-repo>/main/uninstall_dcs.sh | bash
```

This stops the service, disables it, and removes installed files. The `dcs` user is left in place.

## Docker

Build and run with Compose:
```bash
cat > .env <<'EOF'
NC_URL=https://<your-nocodb-domain>/api/v1/db/data/v1/<project>/<table>
NC_API_KEY=your_api_key
EOF

docker compose up -d --build
```

Or with `docker run`:
```bash
docker build -t dcs-checkin .
docker run -d --name dcs-checkin --restart unless-stopped \
  -e NC_URL="https://<your-nocodb-domain>/api/v1/db/data/v1/<project>/<table>" \
  -e NC_API_KEY="your_api_key" \
  dcs-checkin:latest
```

Optional environment variables for Docker:
- `DEVICE_ID_OVERRIDE`
- `INTERVAL_SEC`

Logs:
```bash
docker logs -f dcs-checkin
```

## Windows

Edit `client_checkin_windows.bat`:
```bat
set "NC_URL=https://<your-nocodb-domain>/api/v1/db/data/v1/<project>/<table>"
set "NC_API_KEY=<your_api_key>"
```

Then run the script:
```bat
client_checkin_windows.bat
```

PowerShell is used for GMT+8 time conversion; if PowerShell is unavailable, WMIC is used as a fallback (then local `%date% %time%` if WMIC is missing).
Last response log:
```
%TEMP%\dcs_last_response.log
```

## How It Works

- Every 5 minutes, the client posts JSON like:

```json
{
  "hostname": "<device-hostname>",
  "last_seen": "20-09-2025 10:45",
  "ip": "203.0.113.25"
}
```

- Time is always **GMT+8 (Asia/Manila)**.
- Public IP is fetched via multiple fallbacks (ifconfig.me, ipify.org, ipinfo.io, checkip.amazonaws.com, icanhazip.com) and finally the local route if all else fails.
- The systemd service waits 10s on boot to ensure networking is up.

## Debugging

- If no rows show up in NocoDB:
  1. Check logs:
     ```bash
     journalctl -u heartbeat-checkin.service -f
     ```
  2. Verify `NC_URL` is the correct API endpoint.
  3. Test with a one-shot debug run:
     ```bash
     sudo NC_URL="..." NC_API_KEY="..." bash /opt/heartbeat/client_checkin.sh
     ```

With this, you always know which devices are alive based on their **last_seen** field in NocoDB.
