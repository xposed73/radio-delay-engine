#!/bin/bash
set -e

echo "🚀 Installing REAL 24h Delay Radio System..."

# =========================
# INSTALL DEPENDENCIES
# =========================
apt update -y
apt install -y icecast2 liquidsoap ffmpeg curl nano jq

# =========================
# CHECK JSON FILE
# =========================
JSON_FILE="./timezones.json"

if [ ! -f "$JSON_FILE" ]; then
  echo "❌ timezones.json not found"
  exit 1
fi

# =========================
# ICECAST CONFIG
# =========================
ICECONF="/etc/icecast2/icecast.xml"

sed -i 's|<source-password>.*</source-password>|<source-password>hackme</source-password>|g' $ICECONF
sed -i 's|<sources>.*</sources>|<sources>100</sources>|g' $ICECONF
sed -i 's|<clients>.*</clients>|<clients>1000</clients>|g' $ICECONF

systemctl enable icecast2
systemctl restart icecast2

# =========================
# DIRECTORIES
# =========================
mkdir -p /root/recordings

# =========================
# DELAY GENERATOR (REAL)
# =========================
cat > /root/generate_delays.sh <<'EOF'
#!/bin/bash

DIR="/root/recordings"

for i in $(seq -w 0 23); do

  TARGET=$(date -d "$i hour ago" +"%Y-%m-%d_%H")
  FILE="$DIR/$TARGET.mp3"

  if [ -f "$FILE" ]; then
    echo "$FILE" > /root/current_$i.txt
  else
    echo "" > /root/current_$i.txt
  fi

done
EOF

chmod +x /root/generate_delays.sh
bash /root/generate_delays.sh

# =========================
# LIQUIDSOAP CONFIG (REAL)
# =========================
cat > /root/delay_48.liq <<'EOF'
settings.init.allow_root.set(true)
settings.log.level.set(3)

# =========================
# LIVE SOURCE
# =========================
live = input.http("https://a11.asurahosting.com:8970/radio.mp3")

# =========================
# RECORD LIVE STREAM (HOURLY)
# =========================
output.file(
  %mp3(bitrate=96),
  "/root/recordings/%Y-%m-%d_%H.mp3",
  fallible=false,
  reopen_when={true},
  live
)

# =========================
# DELAY FUNCTION
# =========================
def make_stream(i) =
  def get_file() =
    f = file.read("/root/current_" ^ i ^ ".txt")
    string.trim(f())
  end

  def get_req() =
    request.create(get_file())
  end

  mksafe(fallback([request.dynamic(get_req), live]))
end
EOF

# =========================
# GENERATE STREAMS FROM JSON
# =========================
echo "⚙️ Generating streams..."

COUNT=$(jq '.streams | length' $JSON_FILE)

for ((i=0; i<$COUNT; i++)); do

  id=$(jq -r ".streams[$i].id" $JSON_FILE)
  mp3=$(jq -r ".streams[$i].mp3" $JSON_FILE)
  aac=$(jq -r ".streams[$i].aac" $JSON_FILE)

cat >> /root/delay_48.liq <<EOF

s$id = make_stream("$id")

# MP3
output.icecast(%mp3(bitrate=96),
  host="localhost", port=8000, password="hackme",
  mount="${mp3#/}",
  s$id)

# AAC
output.icecast(%ffmpeg(format="adts", %audio(codec="aac", b="64k")),
  host="localhost", port=8000, password="hackme",
  mount="${aac#/}",
  s$id)

EOF

done

# =========================
# CRON JOBS
# =========================

# update delay mapping every minute
(crontab -l 2>/dev/null; echo "* * * * * /root/generate_delays.sh") | crontab -

# delete files older than 24 hours
(crontab -l 2>/dev/null; echo "5 * * * * find /root/recordings -type f -mmin +1440 -delete") | crontab -

echo "✅ INSTALL COMPLETE"
echo "👉 Create start.sh and run it"
