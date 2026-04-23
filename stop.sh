#!/bin/bash

echo "🛑 Stopping system..."

pkill liquidsoap 2>/dev/null || true
systemctl stop icecast2

echo "✅ Stopped"
