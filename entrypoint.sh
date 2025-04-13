#!/bin/bash
set -e

echo "🔧 Starting Xvfb on display :1..."
Xvfb :1 -screen 0 1024x768x16 &
export DISPLAY=:1

sleep 2

echo "🔧 Starting the Xfce desktop environment..."
startxfce4 &
sleep 5

# Ensure VNC password is set
if [ -z "$VNC_PASSWORD" ]; then
  echo "⚠️  VNC_PASSWORD not set. Using default password 'secret'."
  VNC_PASSWORD="secret"
fi

echo "🔧 Setting up x11vnc server..."
x11vnc -storepasswd "$VNC_PASSWORD" /tmp/passwd
x11vnc -forever -rfbauth /tmp/passwd -display :1 -shared -bg

sleep 1

# Check ngrok auth token
if [ -z "$NGROK_AUTH_TOKEN" ]; then
  echo "❌ NGROK_AUTH_TOKEN not set. Exiting."
  exit 1
fi

echo "🔧 Configuring ngrok tunnel..."
ngrok config add-authtoken "$NGROK_AUTH_TOKEN"

# Start ngrok TCP tunnel for port 5900
ngrok tcp 5900 --log=stdout > ngrok.log &
sleep 3

echo "⏳ Waiting for ngrok tunnel to establish..."
NGROK_URL=""
for i in {1..20}; do
  NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url // empty')
  if [ -n "$NGROK_URL" ]; then
    echo "✅ VNC Public URL: $NGROK_URL"
    break
  else
    echo "⌛ Still waiting for ngrok tunnel..."
    sleep 2
  fi
done

if [ -z "$NGROK_URL" ]; then
  echo "❌ Failed to establish ngrok tunnel. Logs:"
  cat ngrok.log
fi

# Start a dummy TCP server on port 8000 for Koyeb health check
echo "🌐 Starting dummy TCP server on port 8000 to satisfy health check..."
cat << EOF > /tcp_server.py
import socket

server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_socket.bind(('0.0.0.0', 8000))
server_socket.listen(5)
print("TCP keepalive server running on port 8000...")
while True:
    client_socket, addr = server_socket.accept()
    client_socket.close()
EOF

python3 /tcp_server.py &
TCP_SERVER_PID=$!

# Final keep-alive
echo "✅ All services started. Container will stay alive."
tail -f /dev/null
