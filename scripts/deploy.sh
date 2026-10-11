#!/usr/bin/env bash
# Runner-side entry point: `deploy.sh deploy` or `deploy.sh rollback`.
# Ships files to the Test server over SSH, then runs the matching remote-*.sh there.
set -euo pipefail

MODE="${1:-}"
[[ "$MODE" == "deploy" || "$MODE" == "rollback" ]] || { echo "usage: $0 deploy|rollback" >&2; exit 2; }

for v in TEST_HOST TEST_USER DEPLOY_ROOT APP_NAME SSH_PRIVATE_KEY SSH_KNOWN_HOSTS; do
  [[ -n "${!v:-}" ]] || { echo "ERROR: CI/CD variable $v is not set." >&2; exit 1; }
done
bash "$(dirname "$0")/check-tools.sh" ssh rsync

HEALTH_URL="${HEALTH_URL:-http://127.0.0.1/}"
KEEP_RELEASES="${KEEP_RELEASES:-5}"
MIGRATE_CMD="${MIGRATE_CMD:-}"
APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
FRONTEND_BUILD_DIR="${FRONTEND_BUILD_DIR:-dist}"

chmod 600 "$SSH_PRIVATE_KEY"
SSH_OPTS=(-i "$SSH_PRIVATE_KEY" -o "UserKnownHostsFile=$SSH_KNOWN_HOSTS"
          -o StrictHostKeyChecking=yes -o BatchMode=yes -o IdentitiesOnly=yes)
REMOTE="$TEST_USER@$TEST_HOST"

# Run a local script on the Test server, with arguments safely quoted.
remote_script() {
  local script="$1"; shift
  local args; printf -v args '%q ' "$@"
  ssh "${SSH_OPTS[@]}" "$REMOTE" "bash -s -- $args" < "$script"
}

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"

if [[ "$MODE" == "rollback" ]]; then
  remote_script "$SCRIPTS/remote-rollback.sh" \
    "$DEPLOY_ROOT" "$APP_NAME" "$HEALTH_URL" "$APACHE_SERVICE"
  exit 0
fi

[[ -d "frontend/$FRONTEND_BUILD_DIR" ]] || {
  echo "ERROR: frontend/$FRONTEND_BUILD_DIR not found (did build:frontend run?)." >&2; exit 1; }

RELEASE_ID="$(date -u +%Y%m%d%H%M%S)-${CI_COMMIT_SHORT_SHA:-local}"
RELEASE_DIR="$DEPLOY_ROOT/releases/$RELEASE_ID"
RSYNC_SSH="ssh ${SSH_OPTS[*]}"

echo "==> Uploading Release $RELEASE_ID to $TEST_HOST"
ssh "${SSH_OPTS[@]}" "$REMOTE" "mkdir -p '$RELEASE_DIR/backend' '$RELEASE_DIR/frontend'"
rsync -az --delete --exclude='__pycache__' --exclude='*.pyc' --exclude='.venv' \
  -e "$RSYNC_SSH" backend/ "$REMOTE:$RELEASE_DIR/backend/"
rsync -az --delete -e "$RSYNC_SSH" "frontend/$FRONTEND_BUILD_DIR/" "$REMOTE:$RELEASE_DIR/frontend/"

echo "==> Activating Release $RELEASE_ID"
remote_script "$SCRIPTS/remote-activate.sh" \
  "$DEPLOY_ROOT" "$APP_NAME" "$RELEASE_ID" "$HEALTH_URL" "$KEEP_RELEASES" "$MIGRATE_CMD" "$APACHE_SERVICE"
