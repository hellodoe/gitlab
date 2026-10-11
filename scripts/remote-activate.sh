#!/usr/bin/env bash
# Runs ON the Test server (piped over SSH by deploy.sh).
# Prepares the venv, migrates, switches `current`, restarts, health-checks,
# and re-points to the previous Release if the health check fails.
set -euo pipefail

ROOT="$1"; APP="$2"; RELEASE_ID="$3"; HEALTH_URL="$4"; KEEP="$5"; MIGRATE_CMD="$6"; APACHE="$7"

RELEASE="$ROOT/releases/$RELEASE_ID"
ENV_FILE="$ROOT/shared/app.env"

die() { echo "ERROR: $*" >&2; exit 1; }

restart() {
  sudo -n systemctl restart "$APP"
  sudo -n systemctl reload "$APACHE"
}

point_current_at() {
  ln -sfn "$1" "$ROOT/current.new"
  mv -Tf "$ROOT/current.new" "$ROOT/current"   # atomic switch
}

healthy() {
  for _ in $(seq 1 10); do
    if curl -fsS -o /dev/null --max-time 5 "$HEALTH_URL"; then return 0; fi
    sleep 3
  done
  return 1
}

[[ -d "$RELEASE/backend" ]] || die "Release folder $RELEASE is missing."
[[ -f "$ENV_FILE" ]] || die "$ENV_FILE not found; see the runbook."

# Virtualenv is keyed by the hash of requirements.txt, so it is rebuilt only when that changes.
if [[ -f "$RELEASE/backend/requirements.txt" ]]; then
  VENV="$ROOT/venvs/$(sha256sum "$RELEASE/backend/requirements.txt" | cut -c1-16)"
  if [[ ! -x "$VENV/bin/python" ]]; then
    echo "==> Building virtualenv $VENV"
    mkdir -p "$ROOT/venvs"
    if ! { python3 -m venv "$VENV" && "$VENV/bin/pip" install --quiet -r "$RELEASE/backend/requirements.txt"; }; then
      rm -rf "$VENV"
      die "pip install failed."
    fi
  fi
  ln -sfn "$VENV" "$RELEASE/venv"
fi

if [[ -n "$MIGRATE_CMD" ]]; then
  echo "==> Running migrations: $MIGRATE_CMD"
  (
    cd "$RELEASE/backend"
    set -a; . "$ENV_FILE"; set +a
    export PATH="$RELEASE/venv/bin:$PATH"
    bash -c "$MIGRATE_CMD"
  )
fi

PREVIOUS="$(readlink -f "$ROOT/current" 2>/dev/null || true)"

echo "==> Switching current -> $RELEASE_ID"
point_current_at "$RELEASE"
restart

if ! healthy; then
  echo "ERROR: health check failed for $HEALTH_URL" >&2
  if [[ -n "$PREVIOUS" && -d "$PREVIOUS" ]]; then
    echo "==> Rolling back to $(basename "$PREVIOUS")" >&2
    point_current_at "$PREVIOUS"
    restart
    echo "NOTE: database migrations are not reverted." >&2
  else
    echo "No previous Release to roll back to." >&2
  fi
  exit 1
fi

echo "==> Healthy. Pruning old Releases (keeping $KEEP)"
LIVE="$(readlink -f "$ROOT/current")"
ls -1 "$ROOT/releases" | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do
  [[ "$ROOT/releases/$old" == "$LIVE" ]] || rm -rf -- "${ROOT:?}/releases/$old"
done
echo "==> Deployed $RELEASE_ID"
