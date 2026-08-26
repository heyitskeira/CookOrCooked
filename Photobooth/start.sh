#!/usr/bin/env bash
# Cook or Cooked — Photobooth
#
# Browsers refuse camera access on file:// pages, so the booth needs to be
# served. localhost counts as a secure origin, which is all getUserMedia asks
# for — no certificate, no internet.
#
#   ./start.sh          → http://localhost:8080
#   ./start.sh 9000     → http://localhost:9000

set -euo pipefail
cd "$(dirname "$0")"

PORT="${1:-8080}"
URL="http://localhost:${PORT}"

echo "Cook or Cooked photobooth → ${URL}"
echo "Ctrl-C to close the kitchen."

( sleep 1; command -v open >/dev/null && open "$URL" ) &

python3 -m http.server "$PORT" --bind 127.0.0.1
