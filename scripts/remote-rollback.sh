#!/usr/bin/env bash
# Runs ON the Test server (piped over SSH by deploy.sh rollback).
# Re-points `current` at the Release just older than the live one.
set -euo pipefail

ROOT="$1"; APP="$2"; HEALTH_URL="$3"; APACHE="$4"

CURRENT="$(readlink -f "$ROOT/current")" || { echo "ERROR: no current Release." >&2; exit 1; }
CURRENT_ID="$(basename "$CURRENT")"
PREVIOUS_ID="$(ls -1 "$ROOT/releases" | sort | awk -v c="$CURRENT_ID" '$0 < c' | tail -1)"
[[ -n "$PREVIOUS_ID" ]] || { echo "ERROR: no older Release to roll back to." >&2; exit 1; }

echo "==> Rolling back $CURRENT_ID -> $PREVIOUS_ID"
ln -sfn "$ROOT/releases/$PREVIOUS_ID" "$ROOT/current.new"
mv -Tf "$ROOT/current.new" "$ROOT/current"
sudo -n systemctl restart "$APP"
sudo -n systemctl reload "$APACHE"

for _ in $(seq 1 10); do
  if curl -fsS -o /dev/null --max-time 5 "$HEALTH_URL"; then
    echo "==> Healthy on $PREVIOUS_ID. NOTE: database migrations are not reverted."
    exit 0
  fi
  sleep 3
done
echo "ERROR: health check failed after rollback." >&2
exit 1
