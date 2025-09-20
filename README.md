# 📡 DCS Client Installer
Device Check-in System (DCS) client for Linux.  
Each device runs a small heartbeat script that checks in to a central **NocoDB** table every 5 minutes.  
This lets you track whether devices are UP or DOWN without running constant pings.

---

## 📦 Requirements
- Linux system with `systemd` (Ubuntu, Debian, Debian-based, CentOS, etc.)
- `curl` installed
- Access to a NocoDB instance with a table like:

| hostname | last_seen           | ip    |
|----------|---------------------|-------|
| text     | single line text    | text  |

> ⚠️ `last_seen` column must be **Single Line Text**.  
> Format: `DD-MM-YYYY HH:mm` (example: `21-09-2025 14:45`).

---

## 🚀 Install

Run this command on the device:

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/<your-repo>/main/install_dcs.sh | bash
```

You will be prompted for:
- **NocoDB API URL**  
  Example:  
  `https://api-website/api/v1/db/data/v1/DCS/device_checkins`
- **NocoDB API Key**  

The installer will:
- Copy client script → `/opt/heartbeat/client_checkin.sh`
- Create systemd unit → `/etc/systemd/system/heartbeat-checkin.service`
- Enable + start the service

---

## ⏱ Timezone
- The script records time in **GMT+8 (Asia/Manila)**  
- Stored format: `DD-MM-YYYY HH:mm`  
- Example: `21-09-2025 14:45`

---

## 🔄 Service Management

Check status:
```bash
systemctl status heartbeat-checkin.service
```

Follow logs live:
```bash
journalctl -u heartbeat-checkin.service -f
```

Restart service:
```bash
sudo systemctl restart heartbeat-checkin.service
```

Stop service:
```bash
sudo systemctl stop heartbeat-checkin.service
```

Enable at boot:
```bash
sudo systemctl enable heartbeat-checkin.service
```

Disable autostart:
```bash
sudo systemctl disable heartbeat-checkin.service
```

---

## ✅ Verification

After ~5 minutes, confirm in NocoDB:
- **hostname** = device’s hostname
- **last_seen** = current time in GMT+8
- **ip** = public IP (detected via `ifconfig.me` / `ipify.org` / `ipinfo.io`)

Manual run (once only, for testing):
```bash
bash /opt/heartbeat/client_checkin.sh
```

---

## ❌ Uninstall

To fully remove the client:

```bash
sudo systemctl stop heartbeat-checkin.service
sudo systemctl disable heartbeat-checkin.service
sudo rm -f /etc/systemd/system/heartbeat-checkin.service
sudo rm -rf /opt/heartbeat
sudo systemctl daemon-reload
```

---

## 🛠 Future Notes

- If you redeploy and want to **update the script**, edit:
  ```bash
  sudo nano /opt/heartbeat/client_checkin.sh
  sudo systemctl restart heartbeat-checkin.service
  ```
- By default, the client runs forever in a loop every 5 minutes.  
- It is safe to re-run the install script; it will overwrite the client and reset the service.  
- Logs are always available with:
  ```bash
  journalctl -u heartbeat-checkin.service -f
  ```

---

## 🌐 Architecture Overview

- Each remote device runs this **DCS client** (heartbeat script).  
- Client posts JSON to NocoDB table:  
  ```json
  {
    "hostname": "my-device",
    "last_seen": "21-09-2025 14:45",
    "ip": "123.45.67.89"
  }
  ```
- Netlify dashboard + functions query NocoDB to display:  
  - Device status (UP/DOWN, based on last_seen age)  
  - History logs  
  - Charts (activity, uptime)  
