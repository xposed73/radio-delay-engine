#!/bin/bash

echo "🚀 Starting system..."

systemctl restart icecast2

bash /root/generate_delays.sh

pkill liquidsoap 2>/dev/null || true
sleep 2

# recording process
nohup liquidsoap /root/record.liq > /root/record.log 2>&1 &

# streaming process
nohup liquidsoap /root/delay_48.liq > /root/liquid.log 2>&1 &

sleep 2

ps aux | grep liquidsoap | grep -v grep

echo "✅ Running"
echo "🌐 http://$(curl -s ifconfig.me):8000"
