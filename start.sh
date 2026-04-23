#!/bin/bash

echo "🚀 Starting system..."

systemctl start icecast2

bash /root/generate_delays.sh

pkill liquidsoap 2>/dev/null || true
sleep 2

nohup liquidsoap /root/delay_48.liq > /root/liquid.log 2>&1 &

echo "✅ Running"
echo "🌐 http://$(curl -s ifconfig.me):8000"
