# -------- 1) Composer/vendor stage (PHP 8.4 CLI with needed extensions) --------
FROM php:8.4-cli AS vendor
WORKDIR /app

# System deps
RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libicu-dev libpng-dev libonig-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions (pcntl was the one that previously failed)
RUN docker-php-ext-install pcntl sockets intl zip bcmath pdo_mysql
RUN pecl install redis && docker-php-ext-enable redis

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
ENV COMPOSER_ALLOW_SUPERUSER=1

# ✅ Copy the whole app BEFORE running composer (artisan must exist)
COPY . /app

# ✅ Make sure Laravel cache paths exist for composer scripts & artisan
RUN mkdir -p storage/framework/{cache,sessions,views} bootstrap/cache

# Minimal env so composer scripts & artisan can boot safely during build
ENV APP_ENV=production \
    APP_KEY=base64:WfH0leTempKeyDontUseInProd++++++++++++++= \
    DB_CONNECTION=sqlite \
    DB_DATABASE=/tmp/_build.sqlite \
    CACHE_STORE=file \
    QUEUE_CONNECTION=sync \
    VIEW_COMPILED_PATH=/app/storage/framework/views

# Ensure a .env exists (some packages look for it)
RUN php -r "file_exists('.env') || copy('.env.example', '.env');" || true

# Install PHP deps (runs package:discover etc. now that paths exist)
RUN composer install --no-dev --prefer-dist --no-progress --no-interaction

# Generate Wayfinder TS modules (needed before Vite build)
RUN php artisan wayfinder:generate --ansi

# -------- 2) Node/Vite build stage --------
FROM node:22-alpine AS node_builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# Bring in resources (including Wayfinder output from vendor stage)
COPY --from=vendor /app/resources /app/resources
COPY vite.config.ts tsconfig.json ./
RUN npm run build

# -------- 3) Final PHP-FPM runtime --------
FROM php:8.4-fpm AS app
WORKDIR /srv/app

RUN apt-get update && apt-get install -y \
    git unzip libzip-dev libpng-dev libonig-dev libicu-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

RUN docker-php-ext-install pcntl sockets pdo_mysql bcmath intl opcache zip \
 && pecl install redis \
 && docker-php-ext-enable redis

# App source, vendor, built assets
COPY . /srv/app
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

# Entrypoint (migrate, storage:link, caches)
COPY docker/app/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER www-data
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm", "-F"]
