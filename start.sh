#!/bin/bash

echo "🚀 Starting Radio System..."

systemctl start icecast2

# run generator once
bash /root/generate_delays.sh

# start liquidsoap
pkill liquidsoap 2>/dev/null || true
nohup liquidsoap /root/delay_48.liq > /root/liquid.log 2>&1 &

echo "✅ System Started"
echo "🌐 http://$(curl -s ifconfig.me):8000"
