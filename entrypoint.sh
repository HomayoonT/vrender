#!/bin/bash
set -e

echo "Starting Xvfb on display :1..."
Xvfb :1 -screen 0 1024x768x16 &
export DISPLAY=:1
XVFB_PID=$!

sleep 2

echo "Starting the Xfce desktop environment..."
startxfce4 &
XFCE_PID=$!

sleep 5

# Check for VNC password
if [ -z "$VNC_PASSWORD" ]; then
  echo "Warning: VNC_PASSWORD not set, using default password 'secret'."
  VNC_PASSWORD="secret"
fi

echo "Setting up x11vnc..."
x11vnc -storepasswd "$VNC_PASSWORD" /tmp/passwd
x11vnc -forever -rfbauth /tmp/passwd -display :1 -shared -bg
X11VNC_PID=$!

sleep 1

# Check for ngrok auth token
if [ -z "$NGROK_AUTH_TOKEN" ]; then
  echo "Error: NGROK_AUTH_TOKEN is not set. Exiting."
  exit 1
fi

echo "Configuring ngrok tunnel..."
ngrok config add-authtoken "$NGROK_AUTH_TOKEN"
ngrok tcp 5900 --log=stdout > ngrok.log &
NGROK_PID=$!

sleep 3

echo "⏳ Waiting for ngrok tunnel to be established..."
NGROK_URL=""
for i in {1..20}; do
  NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url // empty')
  if [ -n "$NGROK_URL" ]; then
    echo "🔗 VNC Public URL: $NGROK_URL"
    break
  else
    echo "⌛ Still waiting..."
    sleep 2
  fi
done

if [ -z "$NGROK_URL" ]; then
  echo "❌ Failed to establish ngrok tunnel. Check logs below:"
  cat ngrok.log
fi

# Optional: start a tiny keepalive HTTP server if needed (uncomment to use)
# echo "Starting keepalive HTTP server on port 8080..."
# python3 -m http.server 8080 &

echo "🔧 Session ready. Connect your VNC client to the ngrok URL above."

# Keep-alive loop: ping ngrok's local API every 60 sec to avoid container idle timeout
while true; do
  echo "💓 Sending keepalive ping to ngrok local API..."
  curl -s http://127.0.0.1:4040/api/tunnels > /dev/null || true
  sleep 60
done
