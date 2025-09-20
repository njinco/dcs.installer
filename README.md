# 📡 DCS – Device Check-in System (Installer)

DCS is a lightweight heartbeat client that lets remote devices **check in** to a central NocoDB database every 5 minutes.  
Instead of pinging devices, you simply check when they last reported.

---

## 🔹 Requirements
- Linux system with `systemd`
- `curl` installed
- NocoDB instance with a table like:

| Column     | Type             |
|------------|------------------|
| hostname   | Single Line Text |
| last_seen  | Single Line Text (format: `DD-MM-YYYY HH:mm`) |
| ip         | Single Line Text |

⚠️ `last_seen` **must be text**, not date/time, to avoid format errors.

---

## 🔹 Install

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

The installer will:

- Copy client → `/opt/heartbeat/client_checkin.sh`
- Create systemd unit → `/etc/systemd/system/heartbeat-checkin.service`
- Enable + start service

---

## 🔹 Service Management

Check status:
```bash
systemctl status heartbeat-checkin.service
```

Restart service:
```bash
sudo systemctl restart heartbeat-checkin.service
```

Follow logs live:
```bash
journalctl -u heartbeat-checkin.service -f
```

Last API response:
```bash
cat /tmp/dcs_last_response.log
```

---

## 🔹 Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/username/<your-repo>/main/uninstall_dcs.sh | bash
```

This stops the service, disables it, and removes all installed files.

---

## 🔹 How It Works

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
- Service waits 10s on boot to ensure networking is up.

---

## 🔹 Debugging

- If no rows show up in NocoDB:
  1. Check `/tmp/dcs_last_response.log` for error messages.  
  2. Verify `NC_URL` is the correct API endpoint.  
  3. Test with a one-shot debug run:
     ```bash
     bash /opt/heartbeat/client_checkin.sh
     ```

---

✅ With this, you always know which devices are alive based on their **last_seen** field in NocoDB.
