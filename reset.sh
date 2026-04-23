#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo bash reset.sh)"
  exit 1
fi

echo "⚠️ This will DELETE everything (radio system and recordings)"
read -p "Type YES to continue: " confirm

if [ "$confirm" != "YES" ]; then
  echo "Cancelled"
  exit
fi

echo "⏹ Stopping and disabling services..."
systemctl stop radio-liquidsoap radio-recorder 2>/dev/null || true
systemctl disable radio-liquidsoap radio-recorder 2>/dev/null || true

echo "🗑 Removing systemd units..."
rm -f /etc/systemd/system/radio-liquidsoap.service
rm -f /etc/systemd/system/radio-recorder.service
systemctl daemon-reload

echo "🗑 Removing cron jobs..."
crontab -l 2>/dev/null | grep -v 'radio-delay\|generate_delays' | crontab - 2>/dev/null || true

echo "🗑 Removing application files..."
rm -rf /opt/radio-delay

echo "📦 Optional: Would you like to uninstall packages (icecast2, liquidsoap, ffmpeg)? [y/N]"
read -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    apt remove --purge -y icecast2 liquidsoap ffmpeg
    apt autoremove -y
fi

echo "✅ System fully reset"

