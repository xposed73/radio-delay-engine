#!/bin/bash
set -e

echo "🚀 Installing Full Radio Delay System..."

apt update -y
apt install -y icecast2 liquidsoap ffmpeg curl nano

# =========================
# ICECAST CONFIG
# =========================

sed -i 's/<source-password>.*<\/source-password>/<source-password>hackme<\/source-password>/g' /etc/icecast2/icecast.xml
sed -i 's/<sources>.*<\/sources>/<sources>100<\/sources>/g' /etc/icecast2/icecast.xml
sed -i 's/<clients>.*<\/clients>/<clients>500<\/clients>/g' /etc/icecast2/icecast.xml

systemctl restart icecast2
systemctl enable icecast2

# =========================
# DIRECTORIES
# =========================

mkdir -p /root/recordings

# =========================
# FAKE 24H BUFFER
# =========================

echo "🎧 Generating test audio..."

for i in $(seq -w 0 23); do
  ffmpeg -f lavfi -i "sine=frequency=1000:duration=30" \
  -q:a 9 -acodec libmp3lame /root/recordings/$i.mp3
done

# =========================
# TIMEZONE CONFIG (ALL 23)
# =========================

cat > /root/timezones.conf <<EOF
utc 0 utc.mp3
uk 0 uk.mp3
europe_central 1 eu_central.mp3
europe_east 2 eu_east.mp3
russia 3 russia.mp3
uae 4 uae.mp3
pakistan 5 pakistan.mp3
india 5 india.mp3
bangladesh 6 bangladesh.mp3
thailand 7 thailand.mp3
china 8 china.mp3
singapore 8 singapore.mp3
japan 9 japan.mp3
australia_west 8 australia_west.mp3
australia_central 9 australia_central.mp3
australia_east 10 australia_east.mp3
nz 12 nz.mp3
south_africa 2 south_africa.mp3
brazil 3 brazil.mp3
argentina 3 argentina.mp3
us_east 10 us_east.mp3
us_central 11 us_central.mp3
us_west 13 us_west.mp3
EOF

# =========================
# DELAY GENERATOR
# =========================

cat > /root/generate_delays.sh <<'EOF'
#!/bin/bash

DIR="/root/recordings"

while read name delay mount; do
  CURRENT_HOUR=$(date +"%H")
  TARGET=$((10#$CURRENT_HOUR - delay))

  if [ $TARGET -lt 0 ]; then
    TARGET=$((24 + TARGET))
  fi

  TARGET=$(printf "%02d" $TARGET)

  echo "$DIR/$TARGET.mp3" > /root/current_$name.txt

done < /root/timezones.conf
EOF

chmod +x /root/generate_delays.sh
bash /root/generate_delays.sh

# =========================
# LIQUIDSOAP CONFIG (ALL STREAMS)
# =========================

cat > /root/delay_all.liq <<'EOF'
settings.init.allow_root.set(true)

def make_stream(name) =
  def get_file() =
    f = file.read("/root/current_" ^ name ^ ".txt")
    string.trim(f())
  end

  def get_request() =
    request.create(get_file())
  end

  fallback([request.dynamic(get_request), blank()])
end

# Streams
utc = make_stream("utc")
uk = make_stream("uk")
europe_central = make_stream("europe_central")
europe_east = make_stream("europe_east")
russia = make_stream("russia")
uae = make_stream("uae")
pakistan = make_stream("pakistan")
india = make_stream("india")
bangladesh = make_stream("bangladesh")
thailand = make_stream("thailand")
china = make_stream("china")
singapore = make_stream("singapore")
japan = make_stream("japan")
australia_west = make_stream("australia_west")
australia_central = make_stream("australia_central")
australia_east = make_stream("australia_east")
nz = make_stream("nz")
south_africa = make_stream("south_africa")
brazil = make_stream("brazil")
argentina = make_stream("argentina")
us_east = make_stream("us_east")
us_central = make_stream("us_central")
us_west = make_stream("us_west")

# Outputs (ALL)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="utc.mp3", utc)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="uk.mp3", uk)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="eu_central.mp3", europe_central)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="eu_east.mp3", europe_east)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="russia.mp3", russia)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="uae.mp3", uae)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="pakistan.mp3", pakistan)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="india.mp3", india)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="bangladesh.mp3", bangladesh)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="thailand.mp3", thailand)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="china.mp3", china)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="singapore.mp3", singapore)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="japan.mp3", japan)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="australia_west.mp3", australia_west)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="australia_central.mp3", australia_central)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="australia_east.mp3", australia_east)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="nz.mp3", nz)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="south_africa.mp3", south_africa)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="brazil.mp3", brazil)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="argentina.mp3", argentina)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="us_east.mp3", us_east)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="us_central.mp3", us_central)
output.icecast(%mp3(bitrate=96), host="localhost", port=8000, password="hackme", mount="us_west.mp3", us_west)
EOF

# =========================
# CRON
# =========================

(crontab -l 2>/dev/null; echo "* * * * * /root/generate_delays.sh") | crontab -

# =========================
# START SERVICE
# =========================

nohup liquidsoap /root/delay_all.liq > /root/liquidsoap.log 2>&1 &

echo "✅ SYSTEM READY"
echo "🌐 Open: http://$(curl -s ifconfig.me):8000"
