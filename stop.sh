#!/bin/bash

echo "🛑 Stopping Radio System..."

pkill liquidsoap 2>/dev/null || true
systemctl stop icecast2

echo "✅ System Stopped"
