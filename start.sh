#!/bin/bash

echo "🚀 Starting Radio System..."

systemctl start icecast2

# update delay mapping
bash /root/generate_delays.sh

# kill old
pkill liquidsoap 2>/dev/null || true
sleep 2

# start liquidsoap
nohup liquidsoap /root/delay_48.liq > /root/liquid.log 2>&1 &

sleep 2

ps aux | grep liquidsoap | grep -v grep

echo "✅ System Started"
echo "🌐 http://$(curl -s ifconfig.me):8000"
