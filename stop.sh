#!/bin/bash

echo "🛑 Stopping system..."

pkill liquidsoap
pkill ffmpeg
systemctl stop icecast2

echo "✅ Stopped"
