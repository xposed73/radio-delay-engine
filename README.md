# Radio Delay Engine 🚀

A professional, 24-hour time-shifted radio broadcast system. It records a live stream in hourly blocks, stores them for 48 hours, and rebroadcasts them across 24 different time-delayed mount points (available in both MP3 and AAC).

## 📂 System Architecture
- **Location**: `/opt/radio-delay`
- **Engine**: Liquidsoap + Icecast2
- **Recorder**: FFmpeg (Hourly segmented recording)
- **Retention**: 48 hours (24h Delay + 24h Backup)

---

## 🛠 Management Commands

Use these commands from your terminal to manage the system:

| Command | Description |
| :--- | :--- |
| `sudo bash install.sh` | Install or update the system and mount points. |
| `bash start.sh` | Start all services (Recorder, Liquidsoap, Icecast). |
| `bash stop.sh` | Stop all services. |
| `bash status.sh` | Check health, storage usage, and public URLs. |
| `sudo bash /opt/radio-delay/repair.sh` | Restore a failed broadcast from yesterday's backup. |

---

## 🔧 How to Fix a Silent/Failed Broadcast
If there is a broadcast issue (e.g., silence from 7 AM to 10 AM today), you can overwrite today's failed recordings with the successful ones from yesterday.

**Syntax:**
```bash
sudo bash /opt/radio-delay/repair.sh YYYY-MM-DD START_HOUR END_HOUR
```

**Example:**
To repair today (April 26th) from 7 AM to 10 AM:
```bash
sudo bash /opt/radio-delay/repair.sh 2026-04-26 07 10
```
*The system will copy the files from April 25th (07, 08, 09, 10) and refresh the mount points automatically.*

---

## ⚙️ Configuration (`config.env`)
You can edit `/opt/radio-delay/config.env` to change:
- `SOURCE_URL`: The live stream to record.
- `ICECAST_PASSWORD`: The password for mount point authentication.
- `RETENTION_MINS`: How long to keep files (Default: 2880 mins / 48 hours).

*Note: After changing the config, run `sudo bash install.sh` to apply changes.*

---

## 🌐 Mount Point Naming
All streams follow a numeric naming convention for simplicity:

- **MP3 Streams**: `http://your-ip:8000/zeebrahradio-00.mp3` through `zeebrahradio-23.mp3`
- **AAC Streams**: `http://your-ip:8000/zeebrahradio-00.aac` through `zeebrahradio-23.aac`

---

## 📝 Logs & Monitoring
- **Real-time Logs**: `journalctl -u radio-liquidsoap -f`
- **Recorder Logs**: `journalctl -u radio-recorder -f`
- **Storage Check**: Run `bash status.sh` to see how many hourly files are on disk.

---

## 🕒 Troubleshooting
- **No Audio?** Check `bash status.sh` to ensure the Recorder is running and files are being created in `/opt/radio-delay/recordings`.
- **Mount points missing?** Ensure Liquidsoap is running and check `journalctl -u radio-liquidsoap -n 50`.
