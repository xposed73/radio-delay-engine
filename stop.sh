#!/bin/bash

echo "🛑 Stopping system..."

pkill liquidsoap
systemctl stop icecast2

echo "✅ Stopped"
