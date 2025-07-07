#!/bin/sh

set -e

APP_ENV=local
RUN_SEEDERS=false
export TZ="Europe/Moscow"

echo "Container timezone set to: $TZ"
date

# Проверяем, смонтирован ли том /data
if [ ! -d "/data" ]; then
  echo "Ошибка: Директория /data не смонтирована!"
  exit 1
fi

# Путь к файлу базы данных
DB_PATH="/data/database.sqlite"

# Создаем SQLite базу, если ее нет
if [ ! -f "$DB_PATH" ]; then
  echo "Создание SQLite базы данных в $DB_PATH..."
  touch "$DB_PATH"
  chown nobody:nobody "$DB_PATH"
  chmod 664 "$DB_PATH"
  
  # Проверяем, что файл создан
  if [ ! -f "$DB_PATH" ]; then
    echo "Ошибка: Не удалось создать файл базы данных!"
    exit 1
  fi
fi

# Проверяем доступность базы данных
if [ ! -w "$DB_PATH" ]; then
  echo "Ошибка: Нет прав на запись в $DB_PATH!"
  exit 1
fi

# Выполняем миграции с обработкой ошибок
if [ "$APP_ENV" = "local" ]; then
    MAX_RETRIES=3
    RETRY_DELAY=5
    attempt=0

    while [ $attempt -lt $MAX_RETRIES ]; do
        if php artisan migrate --graceful --ansi --no-interaction; then
            echo "Миграции успешно выполнены."
            break
        else
            attempt=$((attempt+1))
            echo "Ошибка миграции (попытка $attempt из $MAX_RETRIES). Повтор через $RETRY_DELAY сек..."
            sleep $RETRY_DELAY
        fi
    done

    if [ $attempt -eq $MAX_RETRIES ]; then
        echo "Ошибка: Не удалось выполнить миграции после $MAX_RETRIES попыток!"
        exit 1
    fi

    # Запускаем сидеры, если нужно
    if [ -n "$RUN_SEEDERS" ] && [ "$RUN_SEEDERS" = "true" ]; then
        echo "Запуск сидеров базы данных..."
        php artisan db:seed --force
    fi
fi

# Очищаем кеш
php artisan optimize:clear

# Оптимизируем приложение для production
if [ "$APP_ENV" = "production" ]; then
    php artisan optimize
fi

# Запускаем основной процесс (переданный в CMD)
echo "Запуск основного процесса..."
exec "$@"
