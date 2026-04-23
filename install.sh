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

sed -i 's|<source-password>.*</source-password>|<source-password>hackme</source-password>|g' $ICECONF
sed -i 's|<sources>.*</sources>|<sources>200</sources>|g' $ICECONF
sed -i 's|<clients>.*</clients>|<clients>2000</clients>|g' $ICECONF

# ensure ipv4 binding
sed -i 's|<listen-socket>|<listen-socket>\n    <bind-address>0.0.0.0</bind-address>|g' $ICECONF

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
cat > /root/generate_delays.sh <<'EOF'
#!/bin/bash

DIR="/root/recordings"
LATEST=$(ls -t $DIR/*.mp3 2>/dev/null | head -n1)

for i in $(seq -w 0 23); do
  TARGET=$(date -d "$i hour ago" +"%Y-%m-%d_%H")
  FILE="$DIR/$TARGET.mp3"

  if [ -f "$FILE" ]; then
    echo "$FILE" > /root/current_$i.txt
  else
    echo "$LATEST" > /root/current_$i.txt
  fi
done
EOF

chmod +x /root/generate_delays.sh
bash /root/generate_delays.sh

# =========================
# LIQUIDSOAP BASE CONFIG
# =========================
cat > /root/delay_48.liq <<'EOF'
settings.init.allow_root.set(true)
settings.log.level.set(3)

live = input.http(
  "https://a11.asurahosting.com:8970/radio.mp3",
  timeout=10.
)

def make_stream(i) =
  def get_file() =
    f = file.read("/root/current_" ^ i ^ ".txt")
    string.trim(f())
  end

  file_source = request.create(get_file())

  fallback(track_sensitive=false, [
    file_source,
    live,
    blank()
  ])
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

COUNT=$(jq '.streams | length' $JSON_FILE)

for ((i=0; i<$COUNT; i++)); do

  id=$(jq -r ".streams[$i].id" $JSON_FILE)
  mp3=$(jq -r ".streams[$i].mp3" $JSON_FILE)
  aac=$(jq -r ".streams[$i].aac" $JSON_FILE)

cat >> /root/delay_48.liq <<EOF

s$id = make_stream("$id")

output.icecast(%mp3(bitrate=48),
  host="127.0.0.1",
  port=8000,
  password="hackme",
  mount="${mp3#/}",
  s$id)

output.icecast(%ffmpeg(format="adts", %audio(codec="aac", b="32k")),
  host="127.0.0.1",
  port=8000,
  password="hackme",
  mount="${aac#/}",
  s$id)

EOF

done

# =========================
# CRON JOBS
# =========================
(crontab -l 2>/dev/null; echo "* * * * * /root/generate_delays.sh") | crontab -
(crontab -l 2>/dev/null; echo "5 * * * * find /root/recordings -type f -mmin +1440 -delete") | crontab -

echo "✅ INSTALL COMPLETE"
echo "👉 Run ./start.sh"
