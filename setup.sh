#!/data/data/com.termux/files/usr/bin/bash
set -e

echo ""
echo "=== Pebble KDE Connect Bridge Setup ==="
echo ""

# Update and install dependencies
pkg update -y -o Dpkg::Options::="--force-confnew"
pkg install -y python kdeconnect

# Create the bridge server script
mkdir -p $HOME/.pebble-kde-bridge
cat > $HOME/.pebble-kde-bridge/server.py << 'PYEOF'
#!/usr/bin/env python3
import http.server
import subprocess
import urllib.parse
import json
import os

PORT = 1817

def run(cmd):
    try:
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=5
        )
        return result.stdout.strip()
    except Exception as e:
        return str(e)

def get_device_id():
    out = run("kdeconnect-cli -a --id-only")
    ids = [l.strip() for l in out.splitlines() if l.strip()]
    return ids[0] if ids else None

class BridgeHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # Suppress default logging

    def send_ok(self, body="OK"):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(body.encode())

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        task = params.get("task", [""])[0]

        device_id = get_device_id()
        if not device_id:
            self.send_ok("NO_DEVICE")
            return

        d = f'-d "{device_id}"'

        if task == "KDC_PlayPause":
            run(f'kdeconnect-cli {d} --send-mpris-action PlayPause')

        elif task == "KDC_Next":
            run(f'kdeconnect-cli {d} --send-mpris-action Next')

        elif task == "KDC_Prev":
            run(f'kdeconnect-cli {d} --send-mpris-action Previous')

        elif task == "KDC_VolUp":
            run(f'kdeconnect-cli {d} --send-mpris-volume-change 5')

        elif task == "KDC_VolDown":
            run(f'kdeconnect-cli {d} --send-mpris-volume-change -5')

        elif task == "KDC_Ring":
            run(f'kdeconnect-cli {d} --ring')

        elif task == "KDC_MouseClick":
            btn = params.get("btn", ["1"])[0]
            run(f'kdeconnect-cli {d} --send-mouse-click {btn}')

        elif task == "KDC_MouseMove":
            dx = params.get("dx", ["0"])[0]
            dy = params.get("dy", ["0"])[0]
            run(f'kdeconnect-cli {d} --send-mouse-delta {dx} {dy}')

        elif task == "KDC_GetMedia":
            out = run(f'kdeconnect-cli {d} --get-playing-media')
            # Expected format from kdeconnect-cli: "Title\nArtist"
            lines = out.splitlines()
            title  = lines[0] if len(lines) > 0 else ""
            artist = lines[1] if len(lines) > 1 else ""
            self.send_ok(f"{title}|{artist}")
            return

        elif task == "KDC_GetCommands":
            out = run(f'kdeconnect-cli {d} --list-commands')
            # Output format: "key: name\nkey: name\n..."
            names = []
            for line in out.splitlines():
                if ": " in line:
                    names.append(line.split(": ", 1)[1].strip())
            self.send_ok("|".join(names))
            return

        elif task == "KDC_RunCmd":
            cmdname = params.get("cmdname", [""])[0]
            # Get command list to find the key for this name
            out = run(f'kdeconnect-cli {d} --list-commands')
            for line in out.splitlines():
                if ": " in line:
                    key, name = line.split(": ", 1)
                    if name.strip() == cmdname:
                        run(f'kdeconnect-cli {d} --run-command "{key.strip()}"')
                        break

        self.send_ok()

if __name__ == "__main__":
    print(f"Pebble KDE Bridge running on port {PORT}")
    print("Keep this running while using your Pebble.")
    print("Press Ctrl+C to stop.")
    server = http.server.HTTPServer(("localhost", PORT), BridgeHandler)
    server.serve_forever()
PYEOF

chmod +x $HOME/.pebble-kde-bridge/server.py

# Create a convenient launch alias
echo 'alias pebble-kde="python $HOME/.pebble-kde-bridge/server.py"' >> $HOME/.bashrc

echo ""
echo "=== Setup complete! ==="
echo ""
echo "To start the bridge, run:"
echo "  pebble-kde"
echo ""
echo "Then open your Pebble KDE Connect app."
echo "You can minimize Termux — the bridge keeps running."
echo ""
