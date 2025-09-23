#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/srv/app"
TARGET_DIR="${APP_COPY_TARGET:-/var/www/html}"

copy_if_empty() {
  if [ ! -f "$TARGET_DIR/.initialized" ]; then
    echo "[entrypoint] First run: populating app volume..."
    # Use rsync if available, else cp -a
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --delete "$APP_DIR/" "$TARGET_DIR/"
    else
      cp -a "$APP_DIR/." "$TARGET_DIR/"
    fi
    touch "$TARGET_DIR/.initialized"
  fi
}

artisan() {
  php "$TARGET_DIR/artisan" "$@"
}

main() {
  copy_if_empty

  # Storage link (idempotent)
  artisan storage:link || true

  # Generate APP_KEY if missing
  if ! grep -q '^APP_KEY=base64:' "$TARGET_DIR/.env" 2>/dev/null; then
    echo "[entrypoint] Generating APP_KEY..."
    artisan key:generate --force || true
  fi

  # Ensure database is migrated
  echo "[entrypoint] Running migrations (safe to re-run)..."
  artisan migrate --force || true

  echo "[entrypoint] Ready. Exec: $*"
  exec "$@"
}

main "$@"
