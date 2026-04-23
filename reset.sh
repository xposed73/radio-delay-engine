#!/bin/bash

echo "⚠️  WARNING: This will completely reset the radio system!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "❌ Cancelled"
  exit
fi

echo "🛑 Stopping services..."

# Stop processes
pkill liquidsoap 2>/dev/null || true
systemctl stop icecast2 2>/dev/null || true

# =========================
# REMOVE PACKAGES
# =========================

echo "🧹 Removing packages..."

apt remove --purge -y icecast2 liquidsoap ffmpeg
apt autoremove -y

# =========================
# DELETE FILES
# =========================

echo "🗑 Removing files..."

rm -rf /root/recordings
rm -f /root/delay_48.liq
rm -f /root/generate_delays.sh
rm -f /root/current_*.txt
rm -f /root/liquid.log

# =========================
# REMOVE ICECAST CONFIG
# =========================

rm -rf /etc/icecast2

# =========================
# REMOVE CRON
# =========================

echo "🧹 Cleaning cron..."

crontab -r 2>/dev/null || true

# =========================
# CLEAN CACHE
# =========================

apt clean

echo "✅ SYSTEM RESET COMPLETE"
echo "👉 You can now run install.sh again"
