# -------- 1) Composer/vendor stage (PHP 8.4 CLI with needed extensions) --------
FROM php:8.4-cli AS vendor
WORKDIR /app

# System deps
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libicu-dev libpng-dev libonig-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions (pcntl is required by the app; others are common Laravel reqs)
RUN docker-php-ext-install pcntl sockets intl zip bcmath pdo_mysql

# Optional but common for Laravel
RUN pecl install redis && docker-php-ext-enable redis

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

# Copy only composer files first for better caching, then install deps
COPY composer.json composer.lock ./
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction

# Copy the rest of the source so we can run artisan generators
COPY . /app

# Minimal env so artisan can bootstrap without touching a real DB
# (Wayfinder only scans routes/controllers)
ENV APP_ENV=production \
    APP_KEY=base64:WfH0leTempKeyDontUseInProd++++++++++++++= \
    DB_CONNECTION=sqlite \
    DB_DATABASE=/tmp/_build.sqlite \
    CACHE_STORE=file \
    QUEUE_CONNECTION=sync

# Create placeholder .env if missing, then generate Wayfinder TS before Vite build
RUN php -r "file_exists('.env') || copy('.env.example', '.env');" \
 && php artisan key:generate --ansi || true \
 && php artisan wayfinder:generate --ansi

# -------- 2) Node/Vite build stage --------
FROM node:22-alpine AS node_builder
WORKDIR /app

# Copy package manifests and install
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# Bring in resources (including the Wayfinder-generated TS from vendor stage)
COPY --from=vendor /app/resources /app/resources
# Vite/TS configs
COPY vite.config.ts tsconfig.json ./

# Build frontend assets
RUN npm run build

# -------- 3) Final PHP-FPM runtime image --------
FROM php:8.4-fpm AS app
WORKDIR /srv/app

# System deps
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libonig-dev libicu-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP runtime extensions (match vendor stage)
RUN docker-php-ext-install pcntl sockets pdo_mysql bcmath intl opcache zip \
 && pecl install redis \
 && docker-php-ext-enable redis

# Copy full source
COPY . /srv/app

# Copy vendor and built assets from previous stages
COPY --from=vendor /app/vendor /srv/app/vendor
COPY --from=node_builder /app/public/build /srv/app/public/build

# PHP config
RUN { \
  echo "memory_limit=512M"; \
  echo "upload_max_filesize=20M"; \
  echo "post_max_size=21M"; \
  echo "max_execution_time=120"; \
  echo "opcache.enable=1"; \
  echo "opcache.enable_cli=1"; \
} > /usr/local/etc/php/conf.d/99-custom.ini

# Entrypoint (migrate, storage:link, cache warmups)
COPY docker/app/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER www-data
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm", "-F"]
