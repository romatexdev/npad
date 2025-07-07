# этап установки Composer
FROM composer:2.8 AS project
WORKDIR /app
COPY rootfs/var/www/html ./
RUN composer install --no-dev --optimize-autoloader --no-interaction --no-progress --no-scripts \
    && rm -rf /var/cache/apk/

COPY . .

# установка npm ресурсов
FROM node:lts-alpine3.21 AS frontend
WORKDIR /app
COPY rootfs/var/www/html/package*.json ./
COPY --from=project /app ./
RUN npm install
RUN npm audit fix
RUN npm run build \
    && rm -rf /var/cache/apk/

COPY . .

# syntax=docker/dockerfile:1
FROM alpine:3.21

LABEL org.opencontainers.image.authors="Vitalii Mikhnevych <blackrooty#gmail.com>"
LABEL org.opencontainers.image.source="https://github.com/rooty/nginx-php84-alpine"
LABEL org.opencontainers.image.description="Lightweight container with Nginx & PHP-FPM 8.4 based on Alpine Linux."
LABEL org.opencontainers.image.licenses=MIT

# Install packages
RUN apk --no-cache add \
        php84 \
        php84-ctype \
        php84-curl \
        php84-dom \
        php84-exif \
        php84-fileinfo \
        php84-fpm \
        php84-gd \
        php84-iconv \
        php84-intl \
        php84-json \
        php84-mbstring \
        #php84-mysqli \
        php84-pdo_sqlite \
        php84-opcache \
        php84-openssl \
        php84-pecl-apcu \
        php84-pdo \
        php84-pdo_mysql \
        php84-pgsql \
        php84-phar \
        php84-session \
        php84-simplexml \
        php84-soap \
        php84-sodium \
        php84-tokenizer \
        php84-xml \
        php84-xmlreader \
        php84-zip \
        php84-zlib \
        nginx \
        runit \
        curl \
# Bring in gettext so we can get `envsubst`, then throw
# the rest away. To do this, we need to install `gettext`
# then move `envsubst` out of the way so `gettext` can
# be deleted completely, then move `envsubst` back.
    && apk add --no-cache --virtual .gettext gettext \
    && mv /usr/bin/envsubst /tmp/ \
    && runDeps="$( \
        scanelf --needed --nobanner /tmp/envsubst \
            | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
            | sort -u \
            | xargs -r apk info --installed \
            | sort -u \
    )" \
    && apk add --no-cache $runDeps \
    && apk del .gettext \
    && mv /tmp/envsubst /usr/local/bin/ \
# Remove alpine cache
    && rm -rf /var/cache/apk/* \
# Remove default server definition
    && rm /etc/nginx/http.d/default.conf \
# Make sure files/folders needed by the processes are accessable when they run under the nobody user
    && mkdir -p /run /var/lib/nginx /var/www/html /var/log/nginx \
    && chown -R nobody:nobody /run /var/lib/nginx /var/log/nginx
RUN ln -s /usr/bin/php84 /usr/bin/php
# Add configuration files
COPY --chown=nobody rootfs/ /
# Копирование подготовленных ресурсов
COPY --from=project /app /var/www/html
COPY --from=frontend /app/public/build /var/www/html/public/build
RUN chown -R nobody:nobody /var/www/html
# Инифиализируем entrypoint скрипт
RUN ["chmod", "+x", "/bin/docker-entrypoint.sh"]


# Switch to use a non-root user from here on
USER nobody

# Add application
WORKDIR /var/www/html

# Expose the port nginx is reachable on
EXPOSE 8080

# Let runit start nginx & php-fpm
# Ensure /bin/docker-entrypoint.sh is always executed
ENTRYPOINT ["/sbin/tini", "--", "/bin/docker-entrypoint.sh"]

COPY --from=composer:2.8 /usr/bin/composer /usr/local/bin/composer
RUN composer run-script post-install-cmd
RUN composer dump-autoload

# Configure a healthcheck to validate that everything is up&running
HEALTHCHECK --timeout=10s CMD curl --silent --fail http://127.0.0.1:8080/fpm-ping || exit 1

ENV nginx_root_directory=/var/www/html/public \
    client_max_body_size=2M \
    clear_env=no \
    allow_url_fopen=On \
    allow_url_include=Off \
    display_errors=Off \
    file_uploads=On \
    max_execution_time=0 \
    max_input_time=-1 \
    max_input_vars=1000 \
    memory_limit=128M \
    post_max_size=8M \
    upload_max_filesize=2M \
    zlib_output_compression=On \
    date_timezone=UTC+3 \
    intl_default_locale=en_US
