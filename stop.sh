#!/bin/bash
echo "🛑 Stopping Radio Delay System..."
systemctl stop radio-liquidsoap
systemctl stop radio-recorder
echo "✅ System stopped."
