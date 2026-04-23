#!/bin/bash
set -e

echo "🚀 Installing 48-Stream Radio Delay System..."

apt update -y
apt install -y icecast2 liquidsoap ffmpeg curl nano

# =========================
# ICECAST CONFIG
# =========================
ICECONF="/etc/icecast2/icecast.xml"

# set source password
sed -i 's|<source-password>.*</source-password>|<source-password>hackme</source-password>|g' $ICECONF

# increase limits
sed -i 's|<sources>.*</sources>|<sources>100</sources>|g' $ICECONF
sed -i 's|<clients>.*</clients>|<clients>1000</clients>|g' $ICECONF

systemctl enable icecast2
systemctl restart icecast2

# =========================
# DIRECTORIES
# =========================
mkdir -p /root/recordings

# =========================
# GENERATE 24 BUFFER FILES
# =========================
echo "🎧 Generating buffer..."
for i in $(seq -w 0 23); do
  ffmpeg -loglevel quiet -f lavfi -i "sine=frequency=1000:duration=30" \
  -q:a 9 -acodec libmp3lame /root/recordings/$i.mp3
done

# =========================
# DELAY GENERATOR
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
# LIQUIDSOAP CONFIG
# =========================
cat > /root/delay_48.liq <<'EOF'
settings.init.allow_root.set(true)
settings.log.level.set(3)

# SOURCE (fallback live stream)
source = input.http("https://a11.asurahosting.com:8970/radio.mp3")

def make_stream(i) =
  def get_file() =
    f = file.read("/root/current_" ^ i ^ ".txt")
    string.trim(f())
  end

  def get_req() =
    request.create(get_file())
  end

  # IMPORTANT: make infallible
  mksafe(fallback([request.dynamic(get_req), source]))
end
EOF

# append streams dynamically
for i in $(seq -w 0 23); do
cat >> /root/delay_48.liq <<EOF

s$i = make_stream("$i")

# MP3
output.icecast(%mp3(bitrate=96),
  host="localhost", port=8000, password="hackme",
  mount="zeebrahradio-$i.mp3",
  s$i)

# AAC (via ffmpeg)
output.icecast(%ffmpeg(format="adts", %audio(codec="aac", b="64k")),
  host="localhost", port=8000, password="hackme",
  mount="zeebrahradio-$i.aac",
  s$i)

EOF
done

# =========================
# CRON (update every minute)
# =========================
(crontab -l 2>/dev/null; echo "* * * * * /root/generate_delays.sh") | crontab -

echo "✅ INSTALL COMPLETE"
echo "👉 Run ./start.sh to start system"
