#!/bin/bash

echo "⚠️ This will DELETE everything (radio system)"
read -p "Type YES to continue: " confirm

if [ "$confirm" != "YES" ]; then
  echo "Cancelled"
  exit
fi

pkill liquidsoap 2>/dev/null || true
systemctl stop icecast2 2>/dev/null || true

apt remove --purge -y icecast2 liquidsoap ffmpeg
apt autoremove -y

rm -rf /root/recordings
rm -f /root/delay_48.liq
rm -f /root/generate_delays.sh
rm -f /root/current_*.txt
rm -f /root/liquid.log

crontab -r 2>/dev/null || true

echo "✅ System fully reset"
