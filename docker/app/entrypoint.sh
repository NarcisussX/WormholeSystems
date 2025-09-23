#!/usr/bin/env bash
set -euo pipefail
APP_DIR="/srv/app"             # code baked into the image
WEBROOT="/var/www/html"        # shared volume for nginx + app

# 1) Populate shared webroot once (copy full app, including public/build)
if [ ! -e "$WEBROOT/.initialized" ]; then
  echo "[entrypoint] Populating webroot volume from image..."
  mkdir -p "$WEBROOT"
  rsync -a --delete "$APP_DIR/" "$WEBROOT/" || cp -a "$APP_DIR/." "$WEBROOT/"
  touch "$WEBROOT/.initialized"
fi

cd "$WEBROOT"

# 2) Ensure writable dirs
mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
chown -R www-data:www-data storage bootstrap/cache
chmod -R ug+rwX storage bootstrap/cache || true

# 3) .env + key
[ -f .env ] || cp .env.example .env || true

run_as_www() {
  if command -v gosu >/dev/null 2>&1; then gosu www-data "$@"; else su -s /bin/sh -c "$*"; fi
}

run_as_www php artisan key:generate --force --no-interaction || true
run_as_www php artisan storage:link || true
run_as_www php artisan config:cache || true
run_as_www php artisan route:cache || true
run_as_www php artisan view:cache || true
run_as_www php artisan migrate --force || true

# 4) If we're launching php-fpm, keep it as default; else drop to www-data
if [ "${1:-}" = "php-fpm" ]; then
  exec "$@"
else
  exec gosu www-data "$@"
fi
