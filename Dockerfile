# ---------- Composer/vendor stage (with PHP extensions available) ----------
FROM php:8.4-cli AS vendor
WORKDIR /app

# System deps required for common PHP extensions
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libicu-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions required by the project/platform checks
# (pcntl is the critical one from your error; sockets/intl/zip/bcmath/pdo_mysql are commonly required)
RUN docker-php-ext-install pcntl sockets intl zip bcmath pdo_mysql

# pecl redis is often required by Laravel stacks
RUN pecl install redis \
    && docker-php-ext-enable redis

# Bring in composer from the official image
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

# Install PHP deps
COPY composer.json composer.lock ./
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction

# ---------- Node / Vite build ----------
FROM node:22-alpine AS node_builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY resources ./resources
COPY vite.config.ts tsconfig.json ./
RUN npm run build

# ---------- Final PHP-FPM runtime ----------
FROM php:8.4-fpm AS app
WORKDIR /srv/app

# System deps
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libonig-dev libicu-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Runtime PHP extensions (match what we had in vendor to avoid surprises)
RUN docker-php-ext-install pcntl sockets pdo_mysql bcmath intl opcache zip \
    && pecl install redis \
    && docker-php-ext-enable redis

# App source
COPY . /srv/app

# Vendor + built assets
COPY --from=vendor /app/vendor /srv/app/vendor
COPY --from=node_builder /app/public/build /srv/app/public/build

# Shared volume target (for nginx, worker, scheduler, etc.)
RUN mkdir -p /var/www/html
ENV APP_COPY_TARGET=/var/www/html

# PHP runtime tweaks
RUN { \
  echo "memory_limit=512M"; \
  echo "upload_max_filesize=20M"; \
  echo "post_max_size=21M"; \
  echo "max_execution_time=120"; \
  echo "opcache.enable=1"; \
  echo "opcache.enable_cli=1"; \
  echo "opcache.preload_user=www-data"; \
} > /usr/local/etc/php/conf.d/99-custom.ini

# Entrypoint does first-run copy, key gen, storage link, migrate
COPY docker/app/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER www-data
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm", "-F"]
