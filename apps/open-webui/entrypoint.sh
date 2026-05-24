#!/bin/bash
set -euo pipefail

# Start Open WebUI using its own startup script in the background.
cd /app/backend && bash start.sh &
WEBUI_PID=$!

echo "[entrypoint] Waiting for Open WebUI to be healthy..."
until curl -sf http://localhost:8080/health > /dev/null 2>&1; do
    if ! kill -0 "$WEBUI_PID" 2>/dev/null; then
        echo "[entrypoint] Open WebUI process exited unexpectedly" >&2
        exit 1
    fi
    sleep 3
done

echo "[entrypoint] Seeding knowledge base from ${HOMELAB_REPO}..."
python3 /seed.py || echo "[entrypoint] Warning: knowledge base seeding failed, continuing anyway" >&2

wait "$WEBUI_PID"
