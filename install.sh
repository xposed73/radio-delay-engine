#!/bin/bash
set -e
echo "🚀 Installing Production Radio Delay System..."

# =========================
# INSTALL DEPENDENCIES
# =========================
apt update -y
apt install -y icecast2 liquidsoap ffmpeg curl nano jq

# =========================
# ICECAST CONFIG
# =========================
ICECONF="/etc/icecast2/icecast.xml"

# Use a Python one-liner for safe single-occurrence XML edits
python3 - "$ICECONF" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Replace source-password only inside <authentication> block
content = re.sub(r'(<source-password>)[^<]*(</source-password>)', r'\1hackme\2', content, count=1)

# Set limits — these live in <limits>
content = re.sub(r'(<sources>)[^<]*(</sources>)', r'\1200\2', content, count=1)
content = re.sub(r'(<clients>)[^<]*(</clients>)', r'\12000\2', content, count=1)

# Ensure bind-address 0.0.0.0 inside listen-socket (only if not already present)
if '<bind-address>' not in content:
    content = content.replace('<listen-socket>', '<listen-socket>\n    <bind-address>0.0.0.0</bind-address>', 1)

with open(path, 'w') as f:
    f.write(content)

print("Icecast config updated.")
PYEOF

systemctl enable icecast2
systemctl restart icecast2

# =========================
# DIRECTORIES
# =========================
mkdir -p /root/recordings

# =========================
# RECORDING SCRIPT (FFMPEG)
# =========================
cat > /root/record.sh <<'EOF'
#!/bin/bash
mkdir -p /root/recordings
while true; do
  ffmpeg -loglevel error \
    -user_agent "Mozilla/5.0" \
    -i "https://a11.asurahosting.com:8970/radio.mp3" \
    -acodec libmp3lame -ab 64k \
    -f segment \
    -segment_time 3600 \
    -segment_atclocktime 1 \
    -reset_timestamps 1 \
    -strftime 1 \
    "/root/recordings/%Y-%m-%d_%H.mp3"
  sleep 2
done
EOF
chmod +x /root/record.sh

# =========================
# DELAY GENERATOR
# =========================
# FIX: use plain integers (no zero-padding) to match JSON stream IDs
# FIX: generate one file per delay hour, named current_0.txt .. current_23.txt
cat > /root/generate_delays.sh <<'EOF'
#!/bin/bash
DIR="/root/recordings"

# Find the most recent recording as fallback
LATEST=$(ls -t "$DIR"/*.mp3 2>/dev/null | head -n1)
if [ -z "$LATEST" ]; then
  LATEST=""
fi

for i in $(seq 0 23); do
  TARGET=$(date -d "$i hour ago" +"%Y-%m-%d_%H")
  FILE="$DIR/$TARGET.mp3"
  if [ -f "$FILE" ]; then
    echo "$FILE" > /root/current_${i}.txt
  elif [ -n "$LATEST" ]; then
    echo "$LATEST" > /root/current_${i}.txt
  else
    # No recordings at all yet — write empty so Liquidsoap falls back to live
    echo "" > /root/current_${i}.txt
  fi
done
EOF
chmod +x /root/generate_delays.sh
bash /root/generate_delays.sh

# =========================
# LIQUIDSOAP BASE CONFIG
# FIX: use file.contents (not file.read) for string result
# FIX: use request.dynamic.list for a looping single-file source
# FIX: define live once with buffer, reuse across all streams
# FIX: truncate file first (>) then append (>>) per stream
# =========================
cat > /root/delay_48.liq <<'EOF'
settings.init.allow_root.set(true)
settings.log.level.set(3)

# Live source — defined once, buffered for stability
live_raw = input.http(
  "https://a11.asurahosting.com:8970/radio.mp3",
  timeout=10.
)
live = buffer(buffer=5., max=10., live_raw)

# Silence fallback
silence = blank()

# Build a delayed stream for delay index i (string, e.g. "0", "3", "12")
def make_stream(i) =
  txt_path = "/root/current_" ^ i ^ ".txt"

  # request.dynamic.list: called each time a new track is needed
  # Returns a list with one request pointing to the current file
  def get_request() =
    raw = file.contents(txt_path)
    path = string.trim(raw)
    if path != "" and file.exists(path) then
      [request.create(path)]
    else
      []
    end
  end

  file_source = request.dynamic.list(
    conservative=true,
    get_request
  )

  # Fallback chain: delayed file → live → silence
  fallback(
    track_sensitive=false,
    [file_source, live, silence]
  )
end
EOF

# =========================
# GENERATE STREAMS FROM JSON
# =========================
JSON_FILE="./timezones.json"
if [ ! -f "$JSON_FILE" ]; then
  echo "❌ timezones.json missing"
  exit 1
fi

COUNT=$(jq '.streams | length' "$JSON_FILE")

for ((i=0; i<COUNT; i++)); do
  id=$(jq -r ".streams[$i].id" "$JSON_FILE")
  mp3=$(jq -r ".streams[$i].mp3" "$JSON_FILE")
  aac=$(jq -r ".streams[$i].aac" "$JSON_FILE")

  # Strip leading slash from mount names
  mp3_mount="${mp3#/}"
  aac_mount="${aac#/}"

  # FIX: id must match current_N.txt numbering — ensure JSON id is plain integer
  cat >> /root/delay_48.liq <<EOF

# --- Stream ID: $id ---
s${id} = make_stream("${id}")

output.icecast(%mp3(bitrate=48),
  host="127.0.0.1",
  port=8000,
  password="hackme",
  mount="${mp3_mount}",
  s${id})

output.icecast(%ffmpeg(format="adts", %audio(codec="aac", b="32k")),
  host="127.0.0.1",
  port=8000,
  password="hackme",
  mount="${aac_mount}",
  s${id})
EOF
done

# =========================
# START SCRIPT
# FIX: the install said "Run ./start.sh" but never created it
# =========================
cat > /root/start.sh <<'EOF'
#!/bin/bash
set -e
echo "▶ Starting recorder..."
nohup /root/record.sh > /var/log/radio_record.log 2>&1 &
echo $! > /tmp/record.pid

echo "▶ Starting Liquidsoap..."
nohup liquidsoap /root/delay_48.liq > /var/log/liquidsoap.log 2>&1 &
echo $! > /tmp/liquidsoap.pid

echo "✅ All services started."
echo "   Recorder PID : $(cat /tmp/record.pid)"
echo "   Liquidsoap PID: $(cat /tmp/liquidsoap.pid)"
echo "   Logs: /var/log/radio_record.log  /var/log/liquidsoap.log"
EOF
chmod +x /root/start.sh

# Create a stop script too
cat > /root/stop.sh <<'EOF'
#!/bin/bash
echo "⏹ Stopping services..."
[ -f /tmp/liquidsoap.pid ] && kill "$(cat /tmp/liquidsoap.pid)" 2>/dev/null && rm /tmp/liquidsoap.pid && echo "  Liquidsoap stopped."
[ -f /tmp/record.pid ]     && kill "$(cat /tmp/record.pid)"     2>/dev/null && rm /tmp/record.pid     && echo "  Recorder stopped."
echo "Done."
EOF
chmod +x /root/stop.sh

# =========================
# CRON JOBS
# FIX: avoid duplicate cron entries on re-run
# =========================
crontab -l 2>/dev/null | grep -v 'generate_delays\|radio_cleanup' | {
  cat
  echo "* * * * * /root/generate_delays.sh >> /var/log/generate_delays.log 2>&1"
  echo "5 * * * * find /root/recordings -type f -mmin +1440 -delete"
} | crontab -

echo ""
echo "✅ INSTALL COMPLETE"
echo "👉 Run: /root/start.sh"
echo ""
echo "Streams will be available at:"
jq -r '.streams[] | "  MP3: http://YOUR_IP:8000" + .mp3 + "\n  AAC: http://YOUR_IP:8000" + .aac' ./timezones.json 2>/dev/null || true
