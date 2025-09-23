# ---------- Composer deps ----------
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction

# ---------- Node / Vite build ----------
FROM node:22-alpine AS node_builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
# Copy only what Vite needs to build
COPY resources ./resources
COPY vite.config.ts tsconfig.json ./
# Vite will emit to /app/public/build by default
RUN npm run build

# ---------- Final PHP-FPM runtime ----------
FROM php:8.4-fpm AS app
WORKDIR /srv/app

# System deps
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libonig-dev libicu-dev libxml2-dev \
    && docker-php-ext-install pdo_mysql bcmath intl opcache zip \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && rm -rf /var/lib/apt/lists/*

# Copy source code
COPY . /srv/app

# Bring in vendor and built assets
COPY --from=vendor /app/vendor /srv/app/vendor
COPY --from=node_builder /app/public/build /srv/app/public/build

# A persistent, shared volume where the running containers will keep the app
# code (so nginx and artisan share the same files).
# We copy into the volume on container start (see entrypoint).
RUN mkdir -p /var/www/html
ENV APP_COPY_TARGET=/var/www/html

# PHP config (prod-ish defaults)
RUN { \
  echo "memory_limit=512M"; \
  echo "upload_max_filesize=20M"; \
  echo "post_max_size=21M"; \
  echo "max_execution_time=120"; \
  echo "opcache.enable=1"; \
  echo "opcache.enable_cli=1"; \
  echo "opcache.preload_user=www-data"; \
} > /usr/local/etc/php/conf.d/99-custom.ini

# Entrypoint copies code to the shared volume if empty, runs first-time setup,
# then execs whatever command the service wants.
COPY docker/app/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER www-data
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm", "-F"]
