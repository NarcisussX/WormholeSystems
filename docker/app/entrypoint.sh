#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/srv/app"           # code baked into the image
WEBROOT="/var/www/html"      # shared volume for nginx + app

copy_tree() { rsync -a --delete "$1/" "$2/" 2>/dev/null || cp -a "$1/." "$2/"; }
as_www() { if command -v gosu >/dev/null 2>&1; then gosu www-data "$@"; else su -s /bin/sh -c "$*"; fi; }

# 1) Seed the shared webroot once from the image
if [ ! -e "$WEBROOT/.initialized" ]; then
  echo "[entrypoint] Populating webroot volume from image..."
  mkdir -p "$WEBROOT"
  copy_tree "$APP_DIR" "$WEBROOT"
  touch "$WEBROOT/.initialized"
fi

cd "$WEBROOT"

# 2) Ensure Laravel dirs + perms
mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache

# public can be ro in worker/reverb — do not fail
chmod u+w public 2>/dev/null || true

# never fail on chown when bind/ro
chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true
chown -R www-data:www-data public 2>/dev/null || true
chmod -R ug+rwX storage bootstrap/cache 2>/dev/null || true


# 3) Ensure .env exists and is writable for key:generate
[ -f .env ] || cp .env.example .env || true
chown www-data:www-data .env || true
chmod 660 .env || true

# 4) Create the "public/storage" link (idempotent)
if [ ! -L public/storage ]; then
  ln -s storage/app/public public/storage || true
fi

# 5) Generate APP_KEY if missing, clear & warm caches
as_www php artisan key:generate --force --no-interaction || true
as_www php artisan config:clear || true
as_www php artisan cache:clear  || true
as_www php artisan route:clear  || true
as_www php artisan view:clear   || true
as_www php artisan config:cache || true
as_www php artisan route:cache  || true
as_www php artisan view:cache   || true

# 6) Wait for DB and run migrations (tolerant)
DB_HOST="${DB_HOST:-db}"; DB_PORT="${DB_PORT:-3306}"
for i in $(seq 1 30); do
  php -r '[$h,$p]=[getenv("DB_HOST")?: "db", (int)(getenv("DB_PORT")?:3306)];
          $f=@fsockopen($h,$p,$e,$s,2); if($f){fclose($f); exit(0);} exit(1);' && {
    as_www php artisan migrate --force && break || true
  }
  echo "[entrypoint] DB not ready ($i/30); sleeping 3s..."
  sleep 3
done

# 7) Launch the requested process
# php-fpm should stay root; other commands can drop privs if gosu is present
if [ "${1:-}" = "php-fpm" ]; then
  exec "$@"
else
  if command -v gosu >/dev/null 2>&1; then
    exec gosu www-data "$@"
  else
    echo "[entrypoint] gosu not found; running '$*' as root" >&2
    exec "$@"
  fi
fi
