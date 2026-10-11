#!/usr/bin/env bash
# Fails fast if a tool the job needs is missing on the (shared shell) runner.
set -euo pipefail

missing=0
for tool in "$@"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' is not installed on this runner ($(hostname))." >&2
    missing=1
  fi
done
exit "$missing"
