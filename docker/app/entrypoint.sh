#!/usr/bin/env bash
set -euo pipefail

cd /srv/app

# Ensure storage is writable (volume may come in with root perms)
mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
chmod -R 775 storage bootstrap/cache || true

# Copy example env on first run if no .env present
if [ ! -f .env ]; then
  cp .env.example .env || true
fi

# Ensure APP_KEY exists
php artisan key:generate --force --no-interaction || true

# Cache config/routes/views for perf
php artisan config:cache || true
php artisan route:cache || true
php artisan view:cache || true

# Run database migrations (safe to run repeatedly)
php artisan migrate --force || true

# Ensure storage link
php artisan storage:link || true

exec "$@"
