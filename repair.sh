#!/bin/bash
# Radio Delay Repair Tool
# Usage: ./repair.sh <date> <start_hour> <end_hour>
# Example: ./repair.sh 2026-04-26 07 10
# This will replace hours 07, 08, 09, 10 of 2026-04-26 with the same hours from the previous day.

set -e

# Load config
source /opt/radio-delay/config.env

TARGET_DATE=$1
START_HOUR=$2
END_HOUR=$3

if [ -z "$TARGET_DATE" ] || [ -z "$START_HOUR" ] || [ -z "$END_HOUR" ]; then
  echo "Usage: $0 <YYYY-MM-DD> <start_HH> <end_HH>"
  echo "Example: $0 $(date +%Y-%m-%d) 07 10"
  exit 1
fi

# Calculate Source Date (Yesterday relative to Target Date)
SOURCE_DATE=$(date -d "$TARGET_DATE -1 day" +%Y-%m-%d)

echo "🛠 Repairing broadcast for $TARGET_DATE (Hours: $START_HOUR to $END_HOUR)..."
echo "Source: $SOURCE_DATE | Destination: $TARGET_DATE"

for (( h=$((10#$START_HOUR)); h<=$((10#$END_HOUR)); h++ )); do
  HH=$(printf "%02d" $h)
  SRC_FILE="$RECORDINGS_DIR/${SOURCE_DATE}_${HH}.mp3"
  DEST_FILE="$RECORDINGS_DIR/${TARGET_DATE}_${HH}.mp3"
  
  if [ -f "$SRC_FILE" ]; then
    echo "📋 Copying $HH:00 from backup..."
    cp "$SRC_FILE" "$DEST_FILE"
  else
    echo "⚠️ Warning: Backup file for $HH:00 ($SOURCE_DATE) not found!"
  fi
done

echo "🔄 Refreshing delay maps..."
bash "$BASE_DIR/generate_delays.sh"

echo "✅ Repair complete. Mountpoints will update within 60 seconds."
