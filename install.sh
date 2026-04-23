#!/bin/bash
set -e

echo "🚀 Installing 48-Stream Radio Delay System (JSON Powered)..."

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
  echo "❌ timezones.json not found in current directory"
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
# GENERATE BUFFER FILES
# =========================
echo "🎧 Generating buffer..."

for i in $(seq -w 0 23); do
  ffmpeg -loglevel quiet -f lavfi -i "sine=frequency=1000:duration=30" \
  -q:a 9 -acodec libmp3lame /root/recordings/$i.mp3
done

# =========================
# DELAY GENERATOR SCRIPT
# =========================
cat > /root/generate_delays.sh <<'EOF'
#!/bin/bash
DIR="/root/recordings"

for i in $(seq -w 0 23); do
  CURRENT=$(date +"%H")
  TARGET=$((10#$CURRENT - 10#$i))

  if [ $TARGET -lt 0 ]; then
    TARGET=$((24 + TARGET))
  fi

  TARGET=$(printf "%02d" $TARGET)

  echo "$DIR/$TARGET.mp3" > /root/current_$i.txt
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

# SOURCE STREAM
source = input.http("https://a11.asurahosting.com:8970/radio.mp3")

def make_stream(i) =
  def get_file() =
    f = file.read("/root/current_" ^ i ^ ".txt")
    string.trim(f())
  end

  def get_req() =
    request.create(get_file())
  end

  mksafe(fallback([request.dynamic(get_req), source]))
end
EOF

# =========================
# GENERATE STREAMS FROM JSON
# =========================
echo "⚙️ Generating streams from JSON..."

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
# CRON JOB
# =========================
(crontab -l 2>/dev/null; echo "* * * * * /root/generate_delays.sh") | crontab -

echo "✅ INSTALL COMPLETE"
echo "👉 Next step: create start.sh and run it"
