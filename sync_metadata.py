#!/usr/bin/env python3
"""
Radio Delay Metadata Synchronizer
Records live metadata history from AzuraCast / Icecast mount 00 into a local SQLite database,
and pushes corresponding time-delayed metadata to all delayed Icecast mounts (01 to 23).
"""
import os
import sys
import time
import json
import base64
import sqlite3
import urllib.request
import urllib.parse
from datetime import datetime

BASE_DIR = os.environ.get("BASE_DIR", "/opt/radio-delay")
CONFIG_PATH = os.path.join(BASE_DIR, "config.env")
DB_PATH = os.path.join(BASE_DIR, "metadata.db")

# Load config
config = {
    "ICECAST_PORT": "8000",
    "ICECAST_PASSWORD": "hackme",
    "AZURA_API_URL": "https://a11.asurahosting.com/api/nowplaying/535",
    "RETENTION_MINS": "2880",
}

if os.path.exists(CONFIG_PATH):
    try:
        with open(CONFIG_PATH, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    if "#" in v:
                        v = v.split("#", 1)[0]
                    config[k.strip()] = v.strip().strip('"').strip("'")
    except Exception as e:
        print(f"Error reading config: {e}", flush=True)

ICECAST_PORT = config.get("ICECAST_PORT", "8000")
ICECAST_PASSWORD = config.get("ICECAST_PASSWORD", "hackme")
AZURA_API_URL = config.get("AZURA_API_URL", "https://a11.asurahosting.com/api/nowplaying/535")

try:
    retention_val = config.get("RETENTION_MINS", "2880")
    if "#" in str(retention_val):
        retention_val = str(retention_val).split("#")[0].strip()
    RETENTION_SECS = int(retention_val) * 60
except Exception:
    RETENTION_SECS = 2880 * 60

# Precompute auth header
auth_str = f"admin:{ICECAST_PASSWORD}"
b64_auth = base64.b64encode(auth_str.encode()).decode()
AUTH_HEADERS = {
    "Authorization": f"Basic {b64_auth}",
    "User-Agent": "Mozilla/5.0 (RadioMetadataSync/1.0)",
}

def init_db():
    conn = sqlite3.connect(DB_PATH)
    with conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS song_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                song TEXT NOT NULL
            )
        """)
        conn.execute("CREATE INDEX IF NOT EXISTS idx_ts ON song_history(timestamp)")
    conn.close()

def fetch_live_song():
    # 1. Try AzuraCast API
    try:
        req = urllib.request.Request(AZURA_API_URL, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data and "now_playing" in data and "song" in data["now_playing"]:
                song_obj = data["now_playing"]["song"]
                text = song_obj.get("text") or f"{song_obj.get('artist', '')} - {song_obj.get('title', '')}".strip()
                if text and text != "-":
                    return text.strip()
    except Exception:
        pass

    # 2. Fallback to local Icecast mount 00
    try:
        url = f"http://127.0.0.1:{ICECAST_PORT}/status-json.xsl"
        with urllib.request.urlopen(url, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            sources = data.get("icestats", {}).get("source", [])
            if isinstance(sources, dict):
                sources = [sources]
            for s in sources:
                if "zeebrahradio-00" in s.get("listenurl", ""):
                    title = s.get("title", "").strip()
                    if title and title.lower() != "unknown":
                        return title
    except Exception:
        pass

    return None

def update_icecast_metadata(mount, song_title):
    try:
        params = urllib.parse.urlencode({
            "mount": mount,
            "mode": "updinfo",
            "song": song_title,
        })
        url = f"http://127.0.0.1:{ICECAST_PORT}/admin/metadata?{params}"
        req = urllib.request.Request(url, headers=AUTH_HEADERS)
        with urllib.request.urlopen(req, timeout=4) as resp:
            return resp.status == 200
    except Exception:
        return False

def main():
    print(f"Initializing Radio Delay Metadata Syncer (Port {ICECAST_PORT})...", flush=True)
    init_db()
    last_live_song = None
    last_delayed_songs = {}

    print("Metadata synchronizer started successfully.", flush=True)

    while True:
        try:
            now = int(time.time())
            live_song = fetch_live_song()

            # Record if live song changed
            if live_song and live_song != last_live_song:
                last_live_song = live_song
                conn = sqlite3.connect(DB_PATH)
                with conn:
                    conn.execute(
                        "INSERT INTO song_history (timestamp, song) VALUES (?, ?)",
                        (now, live_song),
                    )
                conn.close()
                print(f"[{datetime.now().strftime('%H:%M:%S')}] Live Song: {live_song}", flush=True)

            # Update delayed mounts (01 to 23)
            conn = sqlite3.connect(DB_PATH)
            for i in range(1, 24):
                mount_id = f"{i:02d}"
                target_ts = now - (i * 3600)

                cur = conn.cursor()
                cur.execute(
                    "SELECT song FROM song_history WHERE timestamp <= ? ORDER BY timestamp DESC LIMIT 1",
                    (target_ts,),
                )
                row = cur.fetchone()
                delayed_song = row[0] if row else "Zeebrah Radio"

                for ext in ["mp3", "aac"]:
                    mount = f"/zeebrahradio-{mount_id}.{ext}"
                    if last_delayed_songs.get(mount) != delayed_song:
                        if update_icecast_metadata(mount, delayed_song):
                            last_delayed_songs[mount] = delayed_song

            # Housekeeping: purge entries older than retention window once per hour
            if now % 3600 < 10:
                cutoff = now - RETENTION_SECS
                with conn:
                    conn.execute("DELETE FROM song_history WHERE timestamp < ?", (cutoff,))
            conn.close()

        except Exception as e:
            print(f"Error in sync loop: {e}", flush=True)

        time.sleep(10)

if __name__ == "__main__":
    main()
