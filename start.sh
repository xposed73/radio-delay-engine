#!/bin/bash

echo "🚀 Starting system..."

systemctl restart icecast2
bash /root/generate_delays.sh

pkill liquidsoap 2>/dev/null || true
pkill ffmpeg 2>/dev/null || true

sleep 2

nohup bash /root/record.sh > /root/record.log 2>&1 &
nohup liquidsoap /root/delay_48.liq > /root/liquid.log 2>&1 &

sleep 3

ps aux | grep -E "liquidsoap|ffmpeg" | grep -v grep

echo "✅ Running"
echo "🌐 http://$(curl -s ifconfig.me):8000"
