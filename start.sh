#!/bin/bash
echo "🚀 Starting Radio Delay System..."
systemctl start icecast2
systemctl start radio-recorder
systemctl start radio-liquidsoap
systemctl start radio-metadata
echo "✅ System started."
systemctl status radio-recorder radio-liquidsoap radio-metadata --no-pager
