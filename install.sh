#!/bin/bash
set -e

echo "🚀 Installing 48-Stream TimeShift Radio System..."

apt update -y
apt install -y icecast2 liquidsoap ffmpeg curl nano

# =========================
# ICECAST CONFIG
# =========================

sed -i 's/<source-password>.*<\/source-password>/<source-password>hackme<\/source-password>/g' /etc/icecast2/icecast.xml
sed -i 's/<sources>.*<\/sources>/<sources>100<\/sources>/g' /etc/icecast2/icecast.xml
sed -i 's/<clients>.*<\/clients>/<clients>1000<\/clients>/g' /etc/icecast2/icecast.xml

systemctl restart icecast2
systemctl enable icecast2

# =========================
# DIR
# =========================

mkdir -p /root/recordings

# =========================
# GENERATE 24 BUFFER FILES
# =========================

echo "🎧 Generating buffer..."

for i in $(seq -w 0 23); do
  ffmpeg -f lavfi -i "sine=frequency=1000:duration=60" \
  -q:a 9 -acodec libmp3lame /root/recordings/$i.mp3
done

# =========================
# DELAY GENERATOR
# =========================

cat > /root/generate_delays.sh <<'EOF'
#!/bin/bash

DIR="/root/recordings"

while read i; do
  CURRENT=$(date +"%H")
  TARGET=$((10#$CURRENT - i))

  if [ $TARGET -lt 0 ]; then
    TARGET=$((24 + TARGET))
  fi

  TARGET=$(printf "%02d" $TARGET)

  echo "$DIR/$TARGET.mp3" > /root/current_$i.txt

done < <(seq -w 0 23)
EOF

chmod +x /root/generate_delays.sh
bash /root/generate_delays.sh

# =========================
# LIQUIDSOAP CONFIG (48 STREAMS)
# =========================

cat > /root/delay_48.liq <<'EOF'
settings.init.allow_root.set(true)

# SOURCE STREAMS
aac_source = input.http("https://a11.asurahosting.com:8970/radio.aac")
mp3_source = input.http("https://a11.asurahosting.com:8970/radio.mp3")

def make_stream(i) =
  def get_file() =
    f = file.read("/root/current_" ^ i ^ ".txt")
    string.trim(f())
  end
  def get_req() = request.create(get_file()) end
  fallback([request.dynamic(get_req), aac_source])
end

# CREATE STREAMS
EOF

# Generate dynamic streams + outputs
for i in $(seq -w 0 23); do
cat >> /root/delay_48.liq <<EOF

s$i = make_stream("$i")

# AAC OUTPUT
output.icecast(
  %aac(bitrate=64),
  host="localhost", port=8000, password="hackme",
  mount="zeebrahradio-$i.aac",
  s$i
)

# MP3 OUTPUT
output.icecast(
  %mp3(bitrate=96),
  host="localhost", port=8000, password="hackme",
  mount="zeebrahradio-$i.mp3",
  s$i
)
EOF
done

# =========================
# CRON
# =========================

(crontab -l 2>/dev/null; echo "* * * * * /root/generate_delays.sh") | crontab -

# =========================
# START
# =========================

nohup liquidsoap /root/delay_48.liq > /root/liquid.log 2>&1 &

echo "✅ 48 STREAM SYSTEM READY"
echo "🌐 http://$(curl -s ifconfig.me):8000"
