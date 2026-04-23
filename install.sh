#!/bin/bash
set -e

# =========================
# CONFIGURATION
# =========================
APP_DIR="/opt/radio-delay"
CONFIG_FILE="./config.env"
TIMEZONES_FILE="./timezones.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Installing Radio Delay System...${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Please run as root (sudo bash install.sh)${NC}"
  exit 1
fi

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo -e "${RED}❌ config.env missing in current directory.${NC}"
    exit 1
fi

# =========================
# INSTALL DEPENDENCIES
# =========================
echo -e "${BLUE}📦 Installing dependencies...${NC}"
apt update -y
apt install -y icecast2 liquidsoap ffmpeg curl jq python3

# =========================
# ICECAST CONFIG
# =========================
echo -e "${BLUE}⚙️ Configuring Icecast...${NC}"
ICECONF="/etc/icecast2/icecast.xml"

python3 - "$ICECONF" "$ICECAST_PASSWORD" "$ICECAST_BIND_ADDRESS" <<'PYEOF'
import sys, re
path, password, bind_addr = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'r') as f:
    content = f.read()

# Update source-password
content = re.sub(r'(<source-password>)[^<]*(</source-password>)', f'\\g<1>{password}\\g<2>', content, count=1)
content = re.sub(r'(<relay-password>)[^<]*(</relay-password>)', f'\\g<1>{password}\\g<2>', content, count=1)
content = re.sub(r'(<admin-password>)[^<]*(</admin-password>)', f'\\g<1>{password}\\g<2>', content, count=1)

# Set limits
content = re.sub(r'(<sources>)[^<]*(</sources>)', r'\g<1>200\g<2>', content, count=1)
content = re.sub(r'(<clients>)[^<]*(</clients>)', r'\g<1>2000\g<2>', content, count=1)

# Set bind address
if '<bind-address>' not in content:
    content = content.replace('<listen-socket>', f'<listen-socket>\n    <bind-address>{bind_addr}</bind-address>', 1)
else:
    content = re.sub(r'(<bind-address>)[^<]*(</bind-address>)', f'\\g<1>{bind_addr}\\g<2>', content, count=1)

with open(path, 'w') as f:
    f.write(content)
PYEOF

systemctl enable icecast2
systemctl restart icecast2

# =========================
# DIRECTORIES
# =========================
echo -e "${BLUE}📁 Creating directories...${NC}"
mkdir -p "$APP_DIR"
mkdir -p "$RECORDINGS_DIR"
mkdir -p "$MAP_DIR"
cp "$CONFIG_FILE" "$APP_DIR/config.env"
cp "$TIMEZONES_FILE" "$APP_DIR/timezones.json"

# =========================
# RECORDING SCRIPT
# =========================
cat > "$APP_DIR/record.sh" <<EOF
#!/bin/bash
source "$APP_DIR/config.env"
mkdir -p "\$RECORDINGS_DIR"
echo "Starting ffmpeg recording from \$SOURCE_URL"
while true; do
  ffmpeg -loglevel error \\
    -user_agent "Mozilla/5.0" \\
    -i "\$SOURCE_URL" \\
    -acodec libmp3lame -ab 64k \\
    -f segment \\
    -segment_time \$SEGMENT_TIME \\
    -segment_atclocktime 1 \\
    -reset_timestamps 1 \\
    -strftime 1 \\
    "\$RECORDINGS_DIR/%Y-%m-%d_%H.mp3"
  sleep 5
done
EOF
chmod +x "$APP_DIR/record.sh"

# =========================
# DELAY GENERATOR
# =========================
cat > "$APP_DIR/generate_delays.sh" <<EOF
#!/bin/bash
source "$APP_DIR/config.env"
DIR="\$RECORDINGS_DIR"

# Find the most recent recording as fallback
LATEST=\$(ls -t "\$DIR"/*.mp3 2>/dev/null | head -n1)

for i in \$(seq 0 23); do
  # Format with zero padding to match JSON IDs (00, 01, ...)
  ID=\$(printf "%02d" \$i)
  TARGET=\$(date -d "\$i hour ago" +"%Y-%m-%d_%H")
  FILE="\$DIR/\$TARGET.mp3"
  
  if [ -f "\$FILE" ]; then
    echo "\$FILE" > "\$MAP_DIR/current_\${ID}.txt"
  elif [ -n "\$LATEST" ]; then
    echo "\$LATEST" > "\$MAP_DIR/current_\${ID}.txt"
  else
    echo "" > "\$MAP_DIR/current_\${ID}.txt"
  fi
done
EOF
chmod +x "$APP_DIR/generate_delays.sh"
bash "$APP_DIR/generate_delays.sh"

# =========================
# LIQUIDSOAP BASE CONFIG
# =========================
cat > "$APP_DIR/delay_engine.liq" <<EOF
settings.init.allow_root.set(true)
settings.log.level.set(3)

source_url = "$SOURCE_URL"

# Live source
live_raw = input.http(source_url, timeout=10.)
live = buffer(buffer=5., max=10., live_raw)
silence = blank()

def make_stream(i) =
  txt_path = "${MAP_DIR}/current_" ^ i ^ ".txt"
  def get_request() =
    raw = file.contents(txt_path)
    path = string.trim(raw)
    if path != "" and file.exists(path) then
      [request.create(path)]
    else
      []
    end
  end
  file_source = request.dynamic.list(get_request)
  fallback(track_sensitive=false, [file_source, live, silence])
end
EOF

# Append streams from JSON
COUNT=$(jq '.streams | length' "$TIMEZONES_FILE")
for ((i=0; i<COUNT; i++)); do
  id=$(jq -r ".streams[$i].id" "$TIMEZONES_FILE")
  mp3=$(jq -r ".streams[$i].mp3" "$TIMEZONES_FILE")
  aac=$(jq -r ".streams[$i].aac" "$TIMEZONES_FILE")
  mp3_mount="${mp3}"
  aac_mount="${aac}"

  cat >> "$APP_DIR/delay_engine.liq" <<EOF

# --- Stream ID: $id ---
s${id} = make_stream("${id}")
output.icecast(%mp3(bitrate=48), host="localhost", port=$ICECAST_PORT, password="$ICECAST_PASSWORD", mount="${mp3_mount}", s${id})
output.icecast(%ffmpeg(format="adts", %audio(codec="aac", b="32k")), host="localhost", port=$ICECAST_PORT, password="$ICECAST_PASSWORD", mount="${aac_mount}", s${id})
EOF
done

# =========================
# SYSTEMD UNITS
# =========================
echo -e "${BLUE}🛡️ Setting up systemd services...${NC}"

cat > /etc/systemd/system/radio-recorder.service <<EOF
[Unit]
Description=Radio Delay Recorder
After=network.target

[Service]
ExecStart=$APP_DIR/record.sh
Restart=always
User=root
WorkingDirectory=$APP_DIR

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/radio-liquidsoap.service <<EOF
[Unit]
Description=Radio Delay Liquidsoap Engine
After=network.target icecast2.service

[Service]
ExecStart=/usr/bin/liquidsoap $APP_DIR/delay_engine.liq
Restart=always
User=root
WorkingDirectory=$APP_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable radio-recorder
systemctl enable radio-liquidsoap

# =========================
# CRON JOBS
# =========================
echo -e "${BLUE}⏰ Setting up cron jobs...${NC}"
(crontab -l 2>/dev/null | grep -v 'generate_delays\|radio-delay') || true | {
  cat
  echo "* * * * * $APP_DIR/generate_delays.sh > /dev/null 2>&1"
  echo "5 * * * * find $RECORDINGS_DIR -type f -mmin +$RETENTION_MINS -delete"
} | crontab -

echo -e "\n${GREEN}✅ INSTALL COMPLETE${NC}"
echo -e "👉 Start services: ${BLUE}systemctl start radio-recorder radio-liquidsoap${NC}"
echo -e "👉 Check logs:    ${BLUE}journalctl -u radio-liquidsoap -f${NC}"
echo -e "👉 Icecast Admin: ${BLUE}http://$(curl -s ifconfig.me):$ICECAST_PORT${NC}"

