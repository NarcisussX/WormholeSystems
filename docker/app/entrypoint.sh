#!/usr/bin/env bash
set -euo pipefail

cd /srv/app

# Ensure required dirs exist and are writable
mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache

# Own by www-data so all services (app/worker/scheduler/reverb) can use them
chown -R www-data:www-data storage bootstrap/cache
chmod -R ug+rwX storage bootstrap/cache || true

# Create .env on first run (safe if it already exists)
[ -f .env ] || cp .env.example .env || true

# Run artisan setup as www-data (DB will be ready thanks to compose healthcheck)
if command -v gosu >/dev/null 2>&1; then
  as_www="gosu www-data"
else
  as_www="su -s /bin/sh -c"
fi

$as_www "php artisan key:generate --force --no-interaction" || true
$as_www "php artisan storage:link" || true
$as_www "php artisan config:cache" || true
$as_www "php artisan route:cache" || true
$as_www "php artisan view:cache" || true
$as_www "php artisan migrate --force" || true

# If we're starting php-fpm, keep its default behavior (master root, workers www-data).
# For any other command (queue, schedule, reverb), drop to www-data.
if [ "${1:-}" = "php-fpm" ]; then
  exec "$@"
else
  exec gosu www-data "$@"
fi
